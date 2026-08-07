local Bridge = {}

Bridge.BASE_COUNT = 151
Bridge.MAX_COUNT = 251
Bridge.COUNT = 251
Bridge.OWNER_ID = "CRYSTAL_251"
Bridge.OWNER_NAME = "Crystal 251"
Bridge.FORMAT = "C2DSM8"
Bridge.VARIANTS = 2
Bridge.US_MD5 = "1561c75d11cedf356a8ddb1a4a5f9d5d"
Bridge.ROM_DIR = "baseroms"
Bridge.ROOT_DIR = "crystal_251/stadium2"
Bridge.NORMAL_DIR = Bridge.ROOT_DIR .. "/normal"
Bridge.SHINY_DIR = Bridge.ROOT_DIR .. "/shiny"
Bridge.MARKER = Bridge.ROOT_DIR .. "/pack.info"
Bridge.ERROR_LOG = Bridge.ROOT_DIR .. "/import_error.log"
Bridge.PICKED = "picked_stadium2.z64"
Bridge.ANDROID_PICKED = "picked_rom.gb"

local ASSET_START = 0x437610
-- The supported US Stadium 2 ROM has two authoritative Pokemon asset tables.
-- The first contains one model fragment per National Dex entry; the second
-- contains per-species pose bundles whose records expand into animation
-- fragments. Do not treat earlier archive-shaped tables as Pokemon models.
local MODEL_TABLE_START = 0x27ED000
local POSE_TABLE_START = 0x2D7D000
local POSE_TABLE_END = 0x3FD5000
local NONE16 = 0xFFFF

local installedFor = nil
local delegatedBridge = nil
local selectionV, selectionInstall, selectionPicker
local normalPack, shinyPack
local fragmentParsers = {}
local paletteByDex = {}
local wantedVariant = { player = "normal", enemy = "normal" }

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function u16be(data, offset)
  local a, b = data:byte(offset + 1, offset + 2)
  if not b then return nil end
  return a * 256 + b
end

local function s16be(data, offset)
  local value = u16be(data, offset)
  if not value then return nil end
  if value >= 0x8000 then value = value - 0x10000 end
  return value
end

local function u32be(data, offset)
  local a, b, c, d = data:byte(offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function isShiny(mon)
  local dvs = mon and mon.dvs
  if type(dvs) ~= "table" then return false end
  local attack = dvs.attack
  local attackOk = attack == 2 or attack == 3 or attack == 6 or attack == 7
    or attack == 10 or attack == 11 or attack == 14 or attack == 15
  return attackOk and dvs.defense == 10 and dvs.speed == 10
    and dvs.special == 10
end

local function variantFor(mon)
  return isShiny(mon) and "shiny" or "normal"
end

local function modelValue(V)
  local ok, battle = pcall(V.require, "OverworldBattle")
  if not (ok and battle and battle.setting and battle.setting.get) then return nil end
  return battle.setting:get()
end

local function modelsSelected(V)
  local value = modelValue(V)
  return value == "stadium" or value == "stadiumB"
end

local function selectModels(V, game, enabled)
  local ok, battle = pcall(V.require, "OverworldBattle")
  if not (ok and battle and battle.setting and battle.setting.setValue) then
    return false
  end
  local current = battle.setting:get()
  local discs = current == "flatB" or current == "stadiumB"
  local target
  if enabled then
    target = discs and "stadiumB" or "stadium"
  else
    target = discs and "flatB" or true
  end
  battle.setting:setValue(target, game)
  if enabled and battle.forceOG then pcall(battle.forceOG, game) end
  return true
end

local function labelStadium2(V)
  local ok, battle = pcall(V.require, "OverworldBattle")
  local setting = ok and battle and battle.setting
  if not (setting and type(setting.values) == "table"
      and type(setting.labels) == "table") then return false end
  for index, value in ipairs(setting.values) do
    if value == "stadium" then setting.labels[index] = "STADIUM 2 A"
    elseif value == "stadiumB" then setting.labels[index] = "STADIUM 2 B" end
  end
  return true
end

local function md5(data)
  local ok, value = pcall(function()
    local digest = love.data.hash("md5", data)
    if type(digest) == "userdata" and digest.getString then
      digest = digest:getString()
    end
    return love.data.encode("string", "hex", digest)
  end)
  return ok and value or nil
end

local function romTitle(data)
  if type(data) ~= "string" or #data < 0x34 then return "" end
  local title = data:sub(0x21, 0x34):gsub("%z", ""):gsub("%s+$", "")
  return title
end

-- Read the N64 header title without loading or byte-swapping an entire 64 MB
-- ROM. The title occupies bytes 0x20..0x33 in native .z64 order.
local function n64Title(header)
  if type(header) ~= "string" or #header < 0x34 then return "" end
  local magic = header:sub(1, 4)
  local mode
  if magic == "\128\055\018\064" then mode = "z64"
  elseif magic == "\055\128\064\018" then mode = "v64"
  elseif magic == "\064\018\055\128" then mode = "n64"
  else return "" end
  local out = {}
  for offset = 0x20, 0x33 do
    local source = offset
    if mode == "v64" then
      source = offset - offset % 2 + (1 - offset % 2)
    elseif mode == "n64" then
      source = offset - offset % 4 + (3 - offset % 4)
    end
    out[#out + 1] = header:sub(source + 1, source + 1)
  end
  return table.concat(out):gsub("%z", ""):gsub("%s+$", "")
end

local function archiveAt(data, offset)
  if type(data) ~= "string" or offset < 0 or offset + 0x10 > #data then
    return nil
  end
  local tag = u32be(data, offset)
  if not tag or tag - tag % 256 ~= 0 or u32be(data, offset + 4) ~= 0 then
    return nil
  end
  local total = u32be(data, offset + 8)
  local count = u32be(data, offset + 12)
  if not total or not count or count <= 0 or count >= 4096 then
    return nil
  end
  local tableEnd = 0x10 + count * 0x10
  if total < tableEnd or offset + total > #data then return nil end
  local records = {}
  for index = 0, count - 1 do
    local record = offset + 0x10 + index * 0x10
    local relative = u32be(data, record)
    local size = u32be(data, record + 4)
    if not relative or not size then return nil end
    if size == 0 then
      records[index + 1] = { start = offset, size = 0 }
    else
      if relative < tableEnd or relative + size > total then return nil end
      records[index + 1] = { start = offset + relative, size = size }
    end
  end
  return { offset = offset, total = total, count = count, records = records }
end

local function findRootPair(data)
  if type(data) ~= "string" or #data < 0x80 then return nil end
  for offset = 0x20, 0x7C, 4 do
    local first = u32be(data, offset)
    local second = u32be(data, offset + 4)
    if first and second and math.floor(first / 0x4000000) == 0x0F then
      local register = math.floor(first / 0x10000) % 0x20
      if math.floor(second / 0x4000000) == 0x09
          and math.floor(second / 0x200000) % 0x20 == register
          and math.floor(second / 0x10000) % 0x20 == register then
        local address = u16be(data, offset + 2) * 0x10000
          + s16be(data, offset + 6)
        return offset, address
      end
    end
  end
  return nil
end

local function fragmentInfo(data)
  if type(data) ~= "string" or #data < 0x80 then
    return nil, "fragment is too short"
  end
  if data:sub(9, 16) ~= "FRAGMENT" then
    return nil, "not a FRAGMENT module"
  end
  local pair, rootAddress = findRootPair(data)
  if not pair then return nil, "could not locate fragment root" end
  local sourceBase = math.floor(rootAddress / 0x100000) * 0x100000
  local rootOffset = rootAddress - sourceBase
  if rootOffset < 0 or rootOffset + 0x14 > #data then
    return nil, "fragment root is outside the module"
  end
  return {
    sourceBase = sourceBase,
    rootOffset = rootOffset,
    rootAddress = rootAddress,
    pair = pair,
  }
end

local function fragmentSpecies(data)
  local info = fragmentInfo(data)
  if not info then return nil end
  return u16be(data, info.rootOffset), info
end

local function fragmentParser(V, sourceBase)
  local cached = fragmentParsers[sourceBase]
  if cached then return cached end
  local source = assert(V.mod:read("lib/StadiumFragment.lua"),
    "DRAMATIC_SHAPE StadiumFragment.lua is unavailable")
  local changed
  source, changed = source:gsub("local BASE = 0x8FF00000",
    ("local BASE = 0x%08X"):format(sourceBase), 1)
  assert(changed == 1, "unsupported DRAMATIC_SHAPE StadiumFragment base")

  -- Stadium 2 keeps a Pokemon's geometry and motion banks in separate
  -- FRAGMENT entries. Inject two entry points into the private clone while
  -- all of StadiumFragment's local readers (newModel/newAnim/newAux/compress)
  -- are still in lexical scope. DRAMATIC_SHAPE's source and module object are
  -- never edited.
  local extension = [==[

local function crystal251Inside(frag, off, size)
  return type(off) == "number" and off >= 0
    and off + (size or 1) <= #frag.d
end

-- Stadium 2 motion-bank fragments do not always expose the Stadium 1 model
-- root ({species, geo list, animation list, aux list}). Identify a skeletal
-- animation from its own header and pointer graph instead. This is deliberately
-- strict enough not to classify arbitrary FRAGMENT code/data as motion.
local function crystal251LooksLikeAnim(frag, off, bones)
  if off % 4 ~= 0 or not crystal251Inside(frag, off, 0x1C) then return false end
  local flags = frag:u8(off)
  local startFrame = frag:u16(off + 4)
  local loopStart = frag:u16(off + 6)
  local nChannels = frag:u16(off + 8)
  local nFrames = frag:u16(off + 0xA)
  if flags > 0x0F or nChannels < 3 or nChannels > 0x600
      or nChannels % 3 ~= 0 or nFrames < 1 or nFrames > 0x1000
      or startFrame > 0x4000
      or (loopStart ~= 0xFFFF and loopStart > startFrame + nFrames) then
    return false
  end

  if type(bones) == "table" and #bones > 0 then
    local maxChan = -1
    for _, bone in ipairs(bones) do
      local chan = tonumber(bone.chan) or -1
      if chan > maxChan then maxChan = chan end
    end
    if maxChan >= 0 and nChannels < (maxChan + 1) * 3 then return false end
    -- Bone channel ids are sparse signed bytes, not a dense 0..#bones-1 list.
    -- Stadium 2 legitimately leaves holes, so an upper bound derived from the
    -- number of bones rejects valid pose banks. The file-wide 0x600 safety cap
    -- above and the pointer/table validation below remain authoritative.
  end

  local chanTable = frag:ptr(off + 0xC)
  local scaleData = frag:ptr(off + 0x10)
  local rotData = frag:ptr(off + 0x14)
  local transData = frag:ptr(off + 0x18)
  if not crystal251Inside(frag, chanTable, nChannels * 0xA) then return false end

  local active, changing = 0, 0
  local needsScale, needsRot, needsTrans = false, false, false
  for channel = 0, nChannels - 1 do
    local row = chanTable + channel * 0xA
    local ns, nr, nt = frag:u8(row), frag:u8(row + 1), frag:u8(row + 2)
    local interp = frag:u8(row + 3)
    if interp > 7 then return false end
    if ns > 0 or nr > 0 or nt > 0 then active = active + 1 end
    if ns > 1 then needsScale, changing = true, changing + 1 end
    if nr > 1 then needsRot, changing = true, changing + 1 end
    if nt > 1 then needsTrans, changing = true, changing + 1 end
  end
  if active == 0 then return false end
  if needsScale and not crystal251Inside(frag, scaleData, 2) then return false end
  if needsRot and not crystal251Inside(frag, rotData, 2) then return false end
  if needsTrans and not crystal251Inside(frag, transData, 2) then return false end
  -- A one-frame animation legitimately has constants only. Multi-frame banks
  -- need at least one changing stream or they are almost certainly a false hit.
  if nFrames > 1 and changing == 0 then return false end
  return true
end

local function crystal251RawAnimationOffsets(frag, bones)
  local found, seen = {}, {}
  local function add(off)
    if not seen[off] and crystal251LooksLikeAnim(frag, off, bones) then
      seen[off] = true
      found[#found + 1] = off
    end
  end

  local root = frag:root()
  if root then add(root) end
  -- Motion fragments normally expose either the animation header itself or a
  -- pointer/list close to the entry/root data. Follow every plausible pointer
  -- in that region first, then perform a full aligned scan only if necessary.
  local pointerEnd = math.min(#frag.d - 4, 0x1000)
  for o = 0x20, pointerEnd, 4 do
    local target = frag:ptr(o)
    if target and crystal251Inside(frag, target, 0x1C) then add(target) end
  end
  if #found == 0 then
    for off = 0x20, #frag.d - 0x1C, 4 do add(off) end
  end
  table.sort(found)
  return found
end

local function crystal251DecodeOne(frag, off, bones)
  local a = newAnim(frag, off)
  local nf = a.nFrames > 1 and a.nFrames or 1
  local tracks, trackCount = {}, 0
  for bi = 1, #bones do
    local b = bones[bi]
    local ch = tonumber(b.chan) or -1
    local bt = type(b.t) == "table" and b.t or { 0, 0, 0 }
    local br = type(b.r) == "table" and b.r or { 0, 0, 0 }
    local bs = type(b.s) == "table" and b.s or { 1, 1, 1 }
    if ch >= 0 and a:sampleTrs(ch, 0, bt, br, bs) ~= nil then
      local ts, rs, ss = {}, {}, {}
      for k = 1, 3 do ts[k], rs[k], ss[k] = {}, {}, {} end
      for fr = 0, nf - 1 do
        local t, r, sc = a:sampleTrs(ch, fr, bt, br, bs)
        for k = 1, 3 do
          ts[k][fr + 1], rs[k][fr + 1], ss[k][fr + 1] =
            t[k], r[k], sc[k]
        end
      end
      tracks[bi] = {
        t = { compress(ts[1], nf, 3), compress(ts[2], nf, 3),
              compress(ts[3], nf, 3) },
        r = { compress(rs[1], nf, 0), compress(rs[2], nf, 0),
              compress(rs[3], nf, 0) },
        s = { compress(ss[1], nf, 5), compress(ss[2], nf, 5),
              compress(ss[3], nf, 5) },
      }
      trackCount = trackCount + 1
    end
  end
  if #bones > 0 and trackCount == 0 then
    return nil, ("animation@0x%X has no channels used by this skeleton "
      .. "(file-channels=%d bones=%d)"):format(off, a.nChannels, #bones)
  end
  return {
    index = 0,
    frames = nf,
    flags = a.flags,
    channels = a.nChannels,
    loopStart = a.loopStart,
    tracks = tracks,
    sourceOffset = off,
  }
end

local function crystal251DecodeOffsets(frag, offsets, bones)
  bones = type(bones) == "table" and bones or {}
  local anims, errors = {}, {}
  for _, off in ipairs(offsets or {}) do
    local ok, animation, reason = pcall(crystal251DecodeOne, frag, off, bones)
    if ok and animation then
      animation.index = #anims
      anims[#anims + 1] = animation
    else
      errors[#errors + 1] = ("animation@0x%X: %s")
        :format(off, tostring(ok and reason or animation))
    end
  end
  return anims, errors
end

local function crystal251DecodeModelAnimations(frag, model, bones)
  local anims, errors = crystal251DecodeOffsets(frag, model.anims, bones)
  local aux = {}
  for i = 1, #model.auxAnims do
    local ok, a = pcall(newAux, frag, model.auxAnims[i])
    if ok and a then
      local channels = {}
      for c = 0, a.nChannels - 1 do
        local track, n = a:track(c)
        track.n = n
        channels[c + 1] = track
      end
      aux[#aux + 1] = {
        index = #aux,
        frames = a.nFrames > 1 and a.nFrames or 1,
        flags = a.flags,
        loopStart = a.loopStart,
        channels = channels,
      }
    end
  end
  return anims, aux, errors
end

function StadiumFragment.inspect(data, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model, modelErr = pcall(newModel, frag)
  if ok and model then
    return {
      species = model.species,
      geometry = #model.geoLayouts,
      animations = #model.anims,
      auxiliary = #model.auxAnims,
      rootKind = "model",
    }
  end
  return nil, ok and modelErr or model
end

function StadiumFragment.inspectAny(data, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model = pcall(newModel, frag)
  if ok and model then
    local raw = #model.anims == 0 and crystal251RawAnimationOffsets(frag) or {}
    return {
      species = model.species,
      geometry = #model.geoLayouts,
      animations = math.max(#model.anims, #raw),
      auxiliary = #model.auxAnims,
      rootKind = #model.anims > 0 and "model" or (#raw > 0 and "raw-motion" or "model"),
      rawAnimationOffsets = raw,
    }
  end
  local raw = crystal251RawAnimationOffsets(frag)
  if #raw == 0 then return nil, tostring(model or "unrecognised FRAGMENT root") end
  local root = frag:root()
  local species = root and crystal251Inside(frag, root, 2) and frag:u16(root) or 0
  return {
    species = species,
    geometry = 0,
    animations = #raw,
    auxiliary = 0,
    rootKind = "raw-motion",
    rawAnimationOffsets = raw,
  }
end

function StadiumFragment.extractAnimations(data, bones, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local model, modelErr = newModel(frag)
  if not model then return nil, modelErr end
  local anims, aux, errors = crystal251DecodeModelAnimations(frag, model, bones)
  return {
    species = model.species,
    anims = anims,
    auxAnims = aux,
    errors = errors,
  }
end

function StadiumFragment.extractAnimationsAny(data, bones, name)
  local frag, err = StadiumFragment.open(data, name)
  if not frag then return nil, err end
  local ok, model = pcall(newModel, frag)
  if ok and model and (#model.anims > 0 or #model.auxAnims > 0) then
    local anims, aux, errors = crystal251DecodeModelAnimations(frag, model, bones)
    return { species=model.species, anims=anims, auxAnims=aux, errors=errors }
  end
  local offsets = crystal251RawAnimationOffsets(frag, bones)
  if #offsets == 0 then return nil, tostring(model or "no skeletal animation headers") end
  local anims, errors = crystal251DecodeOffsets(frag, offsets, bones)
  if #anims == 0 then return nil, table.concat(errors, " | ") end
  local root = frag:root()
  local species = root and crystal251Inside(frag, root, 2) and frag:u16(root) or 0
  return { species=species, anims=anims, auxAnims={}, errors=errors }
end


-- Stadium 2's pose table does not store its individual clips as executable
-- FRAGMENT modules. Each nested file is a relocatable animation blob: the
-- same animation/channel structures used by Stadium 1, but without a MIPS
-- entry stub or the literal "FRAGMENT" marker. Pointers in different entries
-- are found in one of the forms used by the asset loader: file offsets,
-- offsets relative to the animation header, low-24-bit segmented offsets, or
-- absolute addresses against an aligned load base.
local RawFrag = {}
RawFrag.__index = RawFrag
setmetatable(RawFrag, { __index = Frag })

function RawFrag:off(ptr)
  if ptr == 0 then return nil end
  if self.pointerMode == "file" then return ptr end
  if self.pointerMode == "header" then return self.headerOffset + ptr end
  if self.pointerMode == "low24" then return ptr % 0x1000000 end
  return ptr - (self.pointerBase or 0)
end

function RawFrag:ptr(o)
  return self:off(self:u32(o))
end

local function crystal251HexPrefix(data, count)
  local out = {}
  for i = 1, math.min(#data, count or 32) do
    out[#out + 1] = ("%02X"):format(data:byte(i))
  end
  return table.concat(out)
end

local function crystal251RawModes(data, headerOffset)
  local modes, seen = {}, {}
  local function add(mode, base, label)
    local key = mode .. ":" .. tostring(base or 0)
    if seen[key] then return end
    seen[key] = true
    modes[#modes + 1] = { mode=mode, base=base or 0, label=label or key }
  end
  add("file", 0, "file-offset")
  add("header", 0, "header-relative")
  add("low24", 0, "low24")

  local pointers = {}
  for o = 0xC, 0x18, 4 do
    local at = headerOffset + o
    if at + 4 <= #data then
      local a,b,c,d = data:byte(at + 1, at + 4)
      local value = ((a * 256 + b) * 256 + c) * 256 + d
      if value ~= 0 then pointers[#pointers + 1] = value end
    end
  end
  for pointerIndex, ptr in ipairs(pointers) do
    -- Prelinked N64 asset bases are normally page, 64K, or 1M aligned. Try
    -- each without assuming one global base for all species.
    for _, align in ipairs({ 0x1000, 0x10000, 0x100000 }) do
      local base = math.floor(ptr / align) * align
      add("base", base, ("base-0x%X"):format(base))
    end
    -- Some pose records are relocated at a non-page-aligned arena address.
    -- The first pointer is the channel table, which normally follows the
    -- 0x1C-byte animation header. Derive those common placements directly
    -- instead of requiring the arena base itself to be aligned.
    if pointerIndex == 1 then
      local alignedHeaderEnd = math.floor((headerOffset + 0x1F) / 4) * 4
      for _, target in ipairs({
          alignedHeaderEnd, headerOffset + 0x20,
          0x20, 0x30, 0x40, 0x80, 0x100,
        }) do
        if target >= 0 and target < #data then
          local base = ptr - target
          add("base", base, ("derived-0x%X"):format(base))
        end
      end
    end
  end
  return modes
end

local function crystal251RawU32(data, offset)
  local a, b, c, d = byte(data, offset + 1, offset + 4)
  if not d then return nil end
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function crystal251RawCandidates(data, bones)
  local found, seen = {}, {}
  if type(data) ~= "string" or #data < 0x1C then return found end
  local function probe(off)
    for _, mode in ipairs(crystal251RawModes(data, off)) do
      local frag = setmetatable({
        d=data, name="<raw Stadium 2 pose>", headerOffset=off,
        pointerMode=mode.mode, pointerBase=mode.base,
      }, RawFrag)
      if crystal251LooksLikeAnim(frag, off, bones) then
        local key = off .. ":" .. mode.label
        if not seen[key] then
          seen[key] = true
          found[#found + 1] = {
            frag=frag, off=off, mode=mode.label,
          }
        end
      end
    end
  end

  -- Stadium 2 pose children are laid out backwards from the model fragments:
  -- word 0 is a file-relative offset to the standard 0x1C-byte skeletal
  -- animation header at the END of the record. The sample streams in front of
  -- it are the scale/rotation/translation arrays and channel table named by
  -- that footer. Probe this authoritative pointer first and, when it validates,
  -- do not count coincidental header-shaped sample bytes as extra clips.
  local footer = crystal251RawU32(data, 0)
  if footer and footer % 4 == 0 and footer >= 0
      and footer + 0x1C <= #data then
    probe(footer)
    if #found > 0 then return found end
  end

  -- Retain the bounded prefix probe for older direct-header fixtures and for
  -- any exceptional records that omit the footer pointer. Never scan an entire
  -- pose stream synchronously: large species records contain tens of kilobytes
  -- of packed samples and previously stalled the import screen.
  local prefixEnd = math.min(#data - 0x1C, 0x80)
  for off = 0, prefixEnd, 4 do probe(off) end
  return found
end

function StadiumFragment.inspectRawAnimations(data, name)
  local candidates = crystal251RawCandidates(data)
  if #candidates == 0 then
    return nil, ("raw pose has no animation header (bytes=%d head=%s)")
      :format(type(data) == "string" and #data or 0,
        type(data) == "string" and crystal251HexPrefix(data, 32) or "")
  end
  local offsets, modes = {}, {}
  for _, candidate in ipairs(candidates) do
    offsets[candidate.off] = true
    modes[candidate.mode] = true
  end
  local nOffsets, nModes = 0, 0
  for _ in pairs(offsets) do nOffsets = nOffsets + 1 end
  for _ in pairs(modes) do nModes = nModes + 1 end
  return {
    species = 0,
    geometry = 0,
    animations = nOffsets,
    auxiliary = 0,
    rootKind = "raw-pose",
    pointerModes = nModes,
  }
end

function StadiumFragment.extractRawAnimations(data, bones, name)
  local candidates = crystal251RawCandidates(data, bones)
  if #candidates == 0 then
    return nil, ("raw pose has no skeleton-compatible animation header "
      .. "(bytes=%d head=%s)"):format(type(data) == "string" and #data or 0,
        type(data) == "string" and crystal251HexPrefix(data, 32) or "")
  end
  local anims, errors, usedOffsets = {}, {}, {}
  for _, candidate in ipairs(candidates) do
    -- The same header can validate under multiple equivalent pointer modes.
    -- Keep the first mode that actually decodes against this skeleton.
    if not usedOffsets[candidate.off] then
      local ok, animation, reason = pcall(crystal251DecodeOne,
        candidate.frag, candidate.off, bones or {})
      if ok and animation then
        usedOffsets[candidate.off] = true
        animation.index = #anims
        animation.rawPose = true
        animation.pointerMode = candidate.mode
        anims[#anims + 1] = animation
      else
        errors[#errors + 1] = ("raw-animation@0x%X[%s]: %s")
          :format(candidate.off, candidate.mode,
            tostring(ok and reason or animation))
      end
    end
  end
  if #anims == 0 then return nil, table.concat(errors, " | ") end
  return { species=0, anims=anims, auxAnims={}, errors=errors }
end
]==]
  local injected
  source, injected = source:gsub("\nreturn StadiumFragment%s*$",
    function() return extension .. "\nreturn StadiumFragment\n" end, 1)
  assert(injected == 1, "unsupported DRAMATIC_SHAPE StadiumFragment footer")

  local compile = loadstring or load
  local chunk, err = compile(source,
    ("@STADIUM2_SHARED/StadiumFragment_%08X.lua"):format(sourceBase))
  assert(chunk, err)
  local proxy = { mod = V.mod, require = V.require, data = V.data, path = V.path }
  local parser = assert(chunk(proxy), "could not clone DRAMATIC_SHAPE StadiumFragment")
  fragmentParsers[sourceBase] = parser
  return parser
end

local function rgbToHsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local maxValue = math.max(r, g, b)
  local minValue = math.min(r, g, b)
  local delta = maxValue - minValue
  local hue = 0
  if delta > 0 then
    if maxValue == r then
      hue = ((g - b) / delta) % 6
    elseif maxValue == g then
      hue = (b - r) / delta + 2
    else
      hue = (r - g) / delta + 4
    end
    hue = hue / 6
  end
  local saturation = maxValue == 0 and 0 or delta / maxValue
  return hue, saturation, maxValue
end

local function hsvToRgb(h, s, v)
  h = h % 1
  s, v = clamp(s, 0, 1), clamp(v, 0, 1)
  local sector = math.floor(h * 6)
  local fraction = h * 6 - sector
  local p = v * (1 - s)
  local q = v * (1 - fraction * s)
  local t = v * (1 - (1 - fraction) * s)
  local r, g, b
  sector = sector % 6
  if sector == 0 then r, g, b = v, t, p
  elseif sector == 1 then r, g, b = q, v, p
  elseif sector == 2 then r, g, b = p, v, t
  elseif sector == 3 then r, g, b = p, q, v
  elseif sector == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5)
end

local function paletteColour(palette, index)
  local value = palette and palette[index]
  if type(value) ~= "table" then return nil end
  return tonumber(value[1]), tonumber(value[2]), tonumber(value[3])
end

local function recolourRgba(rgba, normalPalette, shinyPalette)
  if type(rgba) ~= "string" or type(normalPalette) ~= "table"
      or type(shinyPalette) ~= "table" then
    return rgba
  end
  local transforms = {}
  for index = 2, 4 do
    local nr, ng, nb = paletteColour(normalPalette, index)
    local sr, sg, sb = paletteColour(shinyPalette, index)
    if nr and sr then
      local nh, ns, nv = rgbToHsv(nr, ng, nb)
      local sh, ss, sv = rgbToHsv(sr, sg, sb)
      local hueDelta = sh - nh
      if hueDelta > 0.5 then hueDelta = hueDelta - 1 end
      if hueDelta < -0.5 then hueDelta = hueDelta + 1 end
      transforms[#transforms + 1] = {
        r = nr, g = ng, b = nb,
        hue = hueDelta,
        saturation = ns > 0.05 and ss / ns or 1,
        value = nv > 0.05 and sv / nv or 1,
        addR = sr - nr, addG = sg - ng, addB = sb - nb,
        colourful = ns > 0.08 or ss > 0.08,
      }
    end
  end
  if #transforms == 0 then return rgba end

  local output = {}
  for offset = 1, #rgba, 4 do
    local r, g, b, a = rgba:byte(offset, offset + 3)
    if not a then break end
    if a == 0 then
      output[#output + 1] = rgba:sub(offset, offset + 3)
    else
      local best, distance
      for _, transform in ipairs(transforms) do
        local dr, dg, db = r - transform.r, g - transform.g, b - transform.b
        local current = dr * dr + dg * dg + db * db
        if not distance or current < distance then
          best, distance = transform, current
        end
      end
      local rr, gg, bb
      if best.colourful then
        local h, s, v = rgbToHsv(r, g, b)
        rr, gg, bb = hsvToRgb(h + best.hue,
          clamp(s * best.saturation, 0, 1), clamp(v * best.value, 0, 1))
      else
        rr = clamp(r + best.addR, 0, 255)
        gg = clamp(g + best.addG, 0, 255)
        bb = clamp(b + best.addB, 0, 255)
      end
      output[#output + 1] = string.char(
        math.floor(rr + 0.5), math.floor(gg + 0.5),
        math.floor(bb + 0.5), a)
    end
  end
  return table.concat(output)
end

local function clonePack(V, cacheDir, label)
  local source = assert(V.mod:read("lib/StadiumPack.lua"),
    "DRAMATIC_SHAPE StadiumPack.lua is unavailable")
  local changed
  source, changed = source:gsub("species <= 151", "species <= 251", 1)
  assert(changed == 1, "unsupported DRAMATIC_SHAPE StadiumPack limit")
  local compile = loadstring or load
  local chunk, err = compile(source,
    "@STADIUM2_SHARED/" .. tostring(label) .. "/StadiumPack.lua")
  assert(chunk, err)
  local proxy = { mod = V.mod, require = V.require, data = V.data, path = V.path }
  local pack = chunk(proxy)
  pack.CACHE_DIR = cacheDir
  pack.DIR = "__stadium2_shared_no_shipped_assets__"
  return pack
end

local function configurePalettes(cache)
  local species = cache and cache.species
  if type(species) ~= "table" or #species == 0 then return false end
  paletteByDex = {}
  for _, row in ipairs(species) do
    if row.dex and row.paletteColors and row.shinyPaletteColors then
      paletteByDex[row.dex] = {
        normal = row.paletteColors,
        shiny = row.shinyPaletteColors,
      }
    end
  end
  return true
end

function Bridge.configure(options)
  options = type(options) == "table" and options or {}
  local requested = tonumber(options.count) or Bridge.COUNT
  requested = math.floor(requested)
  if requested < Bridge.BASE_COUNT then requested = Bridge.BASE_COUNT end
  if requested > Bridge.MAX_COUNT then requested = Bridge.MAX_COUNT end

  local previous = Bridge.COUNT
  if requested > Bridge.COUNT then Bridge.COUNT = requested end
  if options.ownerId and (requested >= previous or not Bridge.OWNER_ID) then
    Bridge.OWNER_ID = tostring(options.ownerId)
  end
  if options.ownerName and (requested >= previous or not Bridge.OWNER_NAME) then
    Bridge.OWNER_NAME = tostring(options.ownerName)
  end
  configurePalettes(options.cache)

  if selectionInstall then
    selectionInstall.COUNT = Bridge.COUNT
    if selectionInstall.status then selectionInstall.status.total = Bridge.COUNT end
    if Bridge.COUNT > previous and selectionInstall.forget then
      selectionInstall.forget()
    end
  end
  if selectionPicker then
    selectionPicker.ID = tostring(Bridge.OWNER_ID) .. ":stadium2Rom"
  end
  return Bridge
end

local function fallbackTexture(species)
  local palettes = paletteByDex[species]
  local colours = palettes and palettes.normal
  local colour = colours and (colours[2] or colours[3] or colours[1])
  local r, g, b = 255, 255, 255
  if type(colour) == "table" then
    r = clamp(math.floor((tonumber(colour[1]) or r) + 0.5), 0, 255)
    g = clamp(math.floor((tonumber(colour[2]) or g) + 0.5), 0, 255)
    b = clamp(math.floor((tonumber(colour[3]) or b) + 0.5), 0, 255)
  end
  return {
    index = -1,
    w = 1,
    h = 1,
    generated = true,
    stadium2Fallback = true,
    rgba = string.char(r, g, b, 255),
  }
end

local function fxCallbacks(model)
  local values, seen = {}, {}
  for _, effect in ipairs((model and model.fx) or {}) do
    local callback = tonumber(effect.callback or effect.cb or effect.address)
    local label = callback and ("0x%08X"):format(callback) or tostring(
      effect.callback or effect.cb or effect.address or "?")
    if not seen[label] then
      seen[label] = true
      values[#values + 1] = label
    end
  end
  return #values > 0 and table.concat(values, ",") or "none"
end

-- Stadium 2 has a small number of display-list groups that deliberately draw
-- without a texture. The Stadium 1 pack format always expects a texture index,
-- so retaining DRAMATIC_SHAPE's old "textures > 0" gate drops otherwise valid
-- geometry (Magcargo in the US ROM is the known case). Attach supported
-- procedural effects first, then give every still-untextured primitive a 1x1
-- owner-supplied palette material. This changes only the cloned shared
-- import path; DRAMATIC_SHAPE's own importer and files remain untouched.
local function normaliseDrawableModel(model, species, Fx)
  model.bones = type(model.bones) == "table" and model.bones or {}
  model.prims = type(model.prims) == "table" and model.prims or {}
  model.textures = type(model.textures) == "table" and model.textures or {}

  local attached, attachError = 0, nil
  if Fx and type(Fx.attach) == "function" then
    local ok, value = pcall(Fx.attach, model, species)
    if ok then
      attached = tonumber(value) or 0
    else
      attachError = tostring(value)
    end
  end

  local fallbackIndex = nil
  local function ensureFallback()
    if fallbackIndex == nil then
      fallbackIndex = #model.textures -- primitive texture indexes are 0-based
      model.textures[#model.textures + 1] = fallbackTexture(species)
    end
    return fallbackIndex
  end

  for _, prim in ipairs(model.prims) do
    local texture = tonumber(prim.tex)
    if not texture or texture < 0 or texture >= #model.textures then
      prim.tex = ensureFallback()
      -- An untextured source material cannot safely retain an animation stream
      -- that swaps to indexes from a texture bank it does not have.
      prim.texAnim = -1
      prim.texMap = nil
    elseif type(prim.texMap) == "table" then
      for key, mapped in pairs(prim.texMap) do
        mapped = tonumber(mapped)
        if not mapped or mapped < 0 or mapped >= #model.textures then
          prim.texMap[key] = ensureFallback()
        end
      end
    end
    if type(prim.fxFrames) == "table" then
      for index, mapped in ipairs(prim.fxFrames) do
        mapped = tonumber(mapped)
        if not mapped or mapped < 0 or mapped >= #model.textures then
          prim.fxFrames[index] = ensureFallback()
        end
      end
    end
  end

  local bones, prims, textures = #model.bones, #model.prims, #model.textures
  if bones == 0 or prims == 0 or textures == 0 then
    local extra = attachError and ("; effect attach error=" .. attachError) or ""
    return nil, ("species %d has no drawable geometry "
      .. "(bones=%d prims=%d textures=%d effects-added=%d callbacks=%s)%s")
      :format(species, bones, prims, textures, attached, fxCallbacks(model), extra)
  end
  return true, {
    bones = bones,
    prims = prims,
    textures = textures,
    effectsAdded = attached,
    fallbackTexture = fallbackIndex,
  }
end

local function genericAnimationTable(data, Build)
  local animations = data.anims or {}
  if #animations == 0 then
    -- Stadium 2 stores the Pokemon mesh/skeleton and its animation banks in
    -- separate archives. DRAMATIC_SHAPE's Stadium 1 parser can already read
    -- the mesh fragment, but naturally finds no embedded animations there.
    -- Keep the model usable while the separate Stadium 2 animation format is
    -- not yet decoded by giving it one one-frame bind-pose loop. A track-less
    -- animation means "use every bone's rest transform" to StadiumBuild.
    animations[1] = {
      index = 0,
      frames = 1,
      flags = 0,
      channels = 0,
      loopStart = 0,
      tracks = {},
      syntheticBindPose = true,
    }
    data.anims = animations
  end
  local names = { "idle", "attack_default", "faint", "entrance" }
  local auxiliary = data.auxAnims or {}
  for index, animation in ipairs(animations) do
    animation.name = names[index] or ("anim" .. tostring(index - 1))
    -- Stadium 2 keeps eye/material streams beside the skeletal banks. Without
    -- its still-undecoded battle lookup table, matching by bank order is the
    -- safest faithful default and is strictly better than discarding every
    -- blink stream as the bind-pose implementation did.
    animation.aux = #auxiliary > 0 and math.min(index - 1, #auxiliary - 1) or -1
  end
  local idle = 0
  local attack = #animations > 1 and 1 or idle
  local faint = #animations > 2 and 2 or attack
  local entrance = #animations > 3 and 3 or idle
  local rows = {}
  local attackAux = animations[attack + 1] and animations[attack + 1].aux or -1
  for move = 1, 165 do rows[move] = { attack, attackAux } end
  local contexts = {}
  for index = 1, #Build.CONTEXTS do contexts[index] = NONE16 end
  contexts[1], contexts[2], contexts[3], contexts[4] = idle, attack, faint, entrance
  contexts[12], contexts[13], contexts[19], contexts[20] = idle, faint, entrance, idle
  return rows, contexts
end

local function decompressedFragment(data, record, StadiumRom)
  local blob = data:sub(record.start + 1, record.start + record.size)
  local ok, decoded, err = pcall(StadiumRom.decompress, blob)
  if not ok then return nil, tostring(decoded) end
  if type(decoded) ~= "string" then return nil, tostring(err or "decompression failed") end
  local info, infoErr = fragmentInfo(decoded)
  if not info then return nil, infoErr end
  return decoded, info
end

local function inspectFragment(data, record, StadiumRom, V, name)
  local decoded, infoOrErr = decompressedFragment(data, record, StadiumRom)
  if not decoded then return nil, infoOrErr end
  local parser = fragmentParser(V, infoOrErr.sourceBase)
  local inspect = parser.inspectAny or parser.inspect
  local ok, summary, summaryErr = pcall(inspect, decoded, name)
  if not ok then return nil, tostring(summary) end
  if not summary then return nil, summaryErr end
  return summary, {
    record = record,
    sourceBase = infoOrErr.sourceBase,
  }
end

local function inspectModelFragment(data, record, StadiumRom, V, name)
  local decoded, infoOrErr = decompressedFragment(data, record, StadiumRom)
  if not decoded then return nil, infoOrErr end
  local parser = fragmentParser(V, infoOrErr.sourceBase)
  local ok, summary, summaryErr = pcall(parser.inspect, decoded, name)
  if not ok then return nil, tostring(summary) end
  if not summary then return nil, summaryErr end
  return summary, {
    record = record,
    sourceBase = infoOrErr.sourceBase,
  }
end

local function mappedSpecies(summary, fileIndex, archiveCount)
  local species = tonumber(summary and summary.species)
  if species and species >= 1 and species <= Bridge.COUNT then return species end
  -- Only a full National-Dex archive may use its record number as the species.
  -- Small motion archives need an explicit species id; otherwise file 1 in
  -- every archive would all be incorrectly attached to Bulbasaur.
  if archiveCount and archiveCount >= Bridge.COUNT
      and fileIndex and fileIndex >= 1 and fileIndex <= Bridge.COUNT then
    return fileIndex
  end
  return nil
end

local function candidateLooksLikeSpeciesArchive(data, archive, StadiumRom, V)
  local found = {}
  local geometryMatches, animationMatches = 0, 0
  local limit = math.min(archive.count, archive.count <= 128 and archive.count or 96)
  for index = 1, limit do
    local fileIndex = index - 1
    local summary = inspectFragment(data, archive.records[index], StadiumRom, V,
      ("stadium2_probe_%d_%d.bin"):format(archive.offset, fileIndex))
    if summary then
      local species = mappedSpecies(summary, fileIndex, archive.count)
      if (summary.animations or 0) > 0 then
        animationMatches = animationMatches + 1
        if species or summary.rootKind == "raw-motion" then return true end
      end
      if species and (summary.geometry or 0) > 0 and not found[species] then
        found[species] = true
        geometryMatches = geometryMatches + 1
        if geometryMatches >= 3 then return true end
      end
    end
  end
  return animationMatches > 0
end

local function archiveNear(data, expected, limit)
  local direct = archiveAt(data, expected)
  if direct then return direct end
  local finish = math.min(#data - 0x10, expected + (limit or 0x1000))
  for offset = expected + 0x10, finish, 0x10 do
    local archive = archiveAt(data, offset)
    if archive then return archive end
  end
  return nil
end

-- The bridge accepts one exact Stadium 2 revision, so use its documented
-- Pokemon model and pose table locations. The old heuristic also accepted the
-- unrelated archive at 0x2000000 and then paired those skeletons with false
-- animation headers found inside the actual model table.
local function nextArchive(data, cursor)
  cursor = cursor or ASSET_START
  if cursor <= MODEL_TABLE_START then
    local archive = archiveNear(data, MODEL_TABLE_START, 0x1000)
    if archive then
      archive.role = "model"
      return archive, MODEL_TABLE_START + 1, false
    end
    return nil, MODEL_TABLE_START + 1, false,
      ("Pokemon model table was not found near 0x%X"):format(MODEL_TABLE_START)
  end
  if cursor <= POSE_TABLE_START then
    local archive = archiveNear(data, POSE_TABLE_START, 0x1000)
    if archive and archive.offset < POSE_TABLE_END then
      archive.role = "pose"
      return archive, POSE_TABLE_START + 1, false
    end
    return nil, POSE_TABLE_END, true,
      ("Pokemon pose table was not found near 0x%X"):format(POSE_TABLE_START)
  end
  return nil, #data + 1, true
end


local function recordBytes(container, record)
  if type(container) ~= "string" or not record or (record.size or 0) <= 0 then
    return nil, "empty archive record"
  end
  local last = record.start + record.size
  if record.start < 0 or last > #container then return nil, "archive record is out of bounds" end
  return container:sub(record.start + 1, last)
end

local function decodedPayload(container, record, StadiumRom)
  local blob, blobErr = recordBytes(container, record)
  if not blob then return nil, blobErr end
  local ok, decoded, err = pcall(StadiumRom.decompress, blob)
  if ok and type(decoded) == "string" then return decoded end
  -- Nested pose directories are sometimes stored raw. Preserve the original
  -- bytes when decompression says this is not a compressed member.
  if archiveAt(blob, 0) or fragmentInfo(blob) then return blob end
  return nil, tostring(ok and err or decoded or "decompression failed")
end

local function archivesInPayload(payload)
  local archives, seen = {}, {}
  local function add(offset)
    if seen[offset] then return end
    local archive = archiveAt(payload, offset)
    if archive then
      seen[offset] = true
      archives[#archives + 1] = archive
      return archive
    end
  end
  local root = add(0)
  if root then return archives end
  -- Some pose bundles have a small metadata prefix before their nested
  -- archive. Search aligned offsets but do not walk inside an archive once it
  -- has been accepted; recursion handles its records.
  local offset = 0x10
  while offset <= #payload - 0x10 do
    local archive = add(offset)
    if archive then offset = offset + archive.total else offset = offset + 0x10 end
  end
  return archives
end

local function inspectDecodedMotion(decoded, V, name)
  local info, infoErr = fragmentInfo(decoded)
  local parser
  if info then
    parser = fragmentParser(V, info.sourceBase)
    local inspect = parser.inspectAny or parser.inspect
    local ok, summary, summaryErr = pcall(inspect, decoded, name)
    if not ok then return nil, tostring(summary) end
    if not summary then return nil, summaryErr end
    if (summary.animations or 0) <= 0 and (summary.auxiliary or 0) <= 0 then
      return nil, "FRAGMENT contains no animation banks"
    end
    return {
      decoded = decoded,
      sourceBase = info.sourceBase,
      animations = summary.animations or 0,
      auxiliary = summary.auxiliary or 0,
      rootKind = summary.rootKind,
      explicitSpecies = tonumber(summary.species),
    }
  end

  -- Individual files inside the Stadium 2 pose bundle are raw relocatable
  -- animation records, not FRAGMENT modules. Decode their header/pointer graph
  -- directly through the private parser clone.
  parser = fragmentParser(V, 0x8FF00000)
  local inspectRaw = parser.inspectRawAnimations
  if not inspectRaw then return nil, infoErr end
  local ok, summary, rawErr = pcall(inspectRaw, decoded, name)
  if not ok then return nil, tostring(summary) end
  if not summary then return nil, tostring(rawErr or infoErr) end
  return {
    decoded = decoded,
    sourceBase = 0x8FF00000,
    animations = summary.animations or 0,
    auxiliary = summary.auxiliary or 0,
    rootKind = summary.rootKind or "raw-pose",
    rawPose = true,
  }
end

local function collectPosePayload(payload, dependencies, label, depth, out, errors, stats)
  depth = depth or 0
  out, errors = out or {}, errors or {}
  stats = stats or { archives = 0, fragments = 0 }

  -- A species pose bundle is itself an archive and its directory bytes can
  -- accidentally resemble a raw animation header. Executable FRAGMENT files
  -- are unambiguous, but for everything else archive structure takes priority
  -- over raw-pose probing.
  local isFragment = fragmentInfo(payload) ~= nil
  if isFragment then
    local motion, motionErr = inspectDecodedMotion(payload, dependencies.V, label)
    if motion then
      motion.path = label
      out[#out + 1] = motion
      stats.fragments = stats.fragments + 1
      return out, errors, stats
    end
    if #errors < 24 then errors[#errors + 1] = label .. ": " .. tostring(motionErr) end
    return out, errors, stats
  end

  if depth < 4 then
    local archives = archivesInPayload(payload)
    if #archives > 0 then
      for archiveIndex, archive in ipairs(archives) do
        stats.archives = stats.archives + 1
        for recordIndex, record in ipairs(archive.records) do
          if record.size > 0 then
            local child, childErr = decodedPayload(payload, record, dependencies.StadiumRom)
            local childLabel = ("%s/archive%d/file%d"):format(label, archiveIndex,
              recordIndex - 1)
            if child then
              collectPosePayload(child, dependencies, childLabel, depth + 1,
                out, errors, stats)
            elseif #errors < 24 then
              errors[#errors + 1] = childLabel .. ": " .. tostring(childErr)
            end
          end
        end
      end
      return out, errors, stats
    end
  end

  local motion, motionErr = inspectDecodedMotion(payload, dependencies.V, label)
  if motion then
    motion.path = label
    out[#out + 1] = motion
    stats.fragments = stats.fragments + 1
    return out, errors, stats
  end
  if #errors < 24 then
    errors[#errors + 1] = label .. ": "
      .. tostring(motionErr or (depth >= 4 and "nesting limit" or "no nested archive"))
  end
  return out, errors, stats
end

local function poseSourcesForRecord(data, record, dependencies, label)
  local payload, payloadErr = decodedPayload(data, record, dependencies.StadiumRom)
  if not payload then return {}, { label .. ": " .. tostring(payloadErr) },
    { archives = 0, fragments = 0 } end
  return collectPosePayload(payload, dependencies, label, 0)
end

local function appendSource(bucket, species, source)
  local list = bucket[species]
  if not list then list = {}; bucket[species] = list end
  list[#list + 1] = source
end

local function sourceLabel(source)
  if source.path then return source.path end
  return ("archive=0x%X file=%s"):format(source.archiveOffset or 0,
    tostring(source.fileIndex or "?"))
end

local function decodeAnimationSources(data, sources, bones, dependencies)
  local anims, aux = {}, {}
  local errors = {}
  for _, source in ipairs(sources or {}) do
    local decoded, infoOrErr
    if type(source.decoded) == "string" then
      decoded = source.decoded
      infoOrErr = { sourceBase = source.sourceBase }
    else
      decoded, infoOrErr = decompressedFragment(data, source.record,
        dependencies.StadiumRom)
    end
    if decoded then
      local parser = fragmentParser(dependencies.V, infoOrErr.sourceBase)
      local extract
      if source.rawPose then
        extract = parser.extractRawAnimations
      else
        extract = parser.extractAnimationsAny or parser.extractAnimations
      end
      local debugName = source.path or ("stadium2_anim_%s_%s.bin")
        :format(tostring(source.archiveOffset or 0), tostring(source.fileIndex or 0))
      local ok, bank, bankErr = pcall(extract, decoded, bones, debugName)
      if ok and bank then
        for _, animation in ipairs(bank.anims or {}) do
          animation.index = #anims
          animation.source = sourceLabel(source)
          anims[#anims + 1] = animation
        end
        for _, animation in ipairs(bank.auxAnims or {}) do
          animation.index = #aux
          animation.source = sourceLabel(source)
          aux[#aux + 1] = animation
        end
      else
        errors[#errors + 1] = sourceLabel(source) .. ": "
          .. tostring(ok and bankErr or bank)
      end
    else
      errors[#errors + 1] = sourceLabel(source) .. ": " .. tostring(infoOrErr)
    end
  end
  return anims, aux, errors
end

local function newBuildJob(data, dependencies, writePack)
  local StadiumRom = dependencies.StadiumRom
  local Build = dependencies.Build
  local Fx = dependencies.Fx
  local job = {
    phase = "scan", cursor = ASSET_START,
    total = Bridge.COUNT, done = 0, species = nil,
    built = {}, builtCount = 0, failed = {}, bytes = 0,
    errorSamples = {}, modelSources = {}, animationSources = {},
    modelSpecies = 0, animatedSpecies = 0, animationClips = 0,
    motionFiles = 0, emptyPoseBundles = 0,
    nestedPoseArchives = 0, modelTableCount = 0, poseTableCount = 0,
  }

  local function countSource(bucket, species)
    if not bucket[species] then return true end
    return false
  end

  local function finish()
    -- Model availability and animation coverage are separate concerns. A pose
    -- decoder regression must not make the already-working 251 model import
    -- disappear. Models without a decoded motion bank are packed with the
    -- existing one-frame rest pose and reported separately.
    if job.builtCount == Bridge.COUNT then
      job.success = true
      job.animationIncomplete = (job.animatedBuilt or 0) < Bridge.COUNT
    else
      local detail = job.lastError and ("; last error: " .. job.lastError) or ""
      if job.lastScanError then detail = detail .. "; scan: " .. job.lastScanError end
      job.error = ("built %d/%d models; real animation banks=%d/%d; "
        .. "model-table-records=%d pose-table-records=%d "
        .. "indexed geometry=%d animation-species=%d motion-files=%d "
        .. "nested-pose-archives=%d empty-pose-bundles=%d%s")
        :format(job.builtCount, Bridge.COUNT, job.animatedBuilt or 0,
          Bridge.COUNT, job.modelTableCount or 0, job.poseTableCount or 0,
          job.modelSpecies or 0, job.animatedSpecies or 0,
          job.motionFiles or 0, job.nestedPoseArchives or 0,
          job.emptyPoseBundles or 0, detail)
    end
    job.phase = "done"
    return false
  end

  function job:step()
    if self.phase == "done" then return false end

    if self.phase == "scan" then
      local archive, cursor, exhausted, scanErr = nextArchive(data, self.cursor)
      self.cursor = cursor
      if archive then
        self.archive = archive
        self.archiveRole = archive.role
        self.archiveOffset = archive.offset
        if archive.role == "model" then self.modelTableCount = archive.count
        elseif archive.role == "pose" then self.poseTableCount = archive.count end
        self.phase = "index"
        self.index = 1
        self.archives = (self.archives or 0) + 1
        return true
      end
      if scanErr then self.lastScanError = scanErr end
      if exhausted then
        self.phase = "build"
        self.speciesIndex = 1
        self.animatedBuilt = 0
        return true
      end
      return true
    end

    if self.phase == "index" then
      local record = self.archive.records[self.index]
      if not record then
        self.archive = nil
        self.archiveRole = nil
        self.index = nil
        self.phase = "scan"
        return true
      end
      local fileIndex = self.index - 1
      self.fileIndex = fileIndex
      self.index = self.index + 1
      if self.archiveRole == "model" then
        local summary, sourceOrErr = inspectModelFragment(data, record, StadiumRom,
          dependencies.V, ("stadium2_model_index_%d.bin"):format(fileIndex))
        if summary then
          local species = mappedSpecies(summary, fileIndex, self.archive.count)
          if species and (summary.geometry or 0) > 0 then
            local source = sourceOrErr
            source.archiveOffset = self.archiveOffset
            source.fileIndex = fileIndex
            source.geometry = summary.geometry or 0
            if countSource(self.modelSources, species) then
              self.modelSpecies = self.modelSpecies + 1
            end
            appendSource(self.modelSources, species, source)
          end
        elseif #self.errorSamples < 12 then
          self.errorSamples[#self.errorSamples + 1] = {
            archive = self.archiveOffset, file = fileIndex,
            reason = tostring(sourceOrErr),
          }
        end
      elseif self.archiveRole == "pose" and fileIndex >= 1
          and fileIndex <= Bridge.COUNT then
        local species = fileIndex
        local label = ("pose-table=0x%X species=%d file=%d")
          :format(self.archiveOffset, species, fileIndex)
        local sources, poseErrors, poseStats = poseSourcesForRecord(data, record,
          dependencies, label)
        self.nestedPoseArchives = self.nestedPoseArchives
          + (poseStats.archives or 0)
        if #sources > 0 then
          if countSource(self.animationSources, species) then
            self.animatedSpecies = self.animatedSpecies + 1
          end
          for _, source in ipairs(sources) do
            source.archiveOffset = self.archiveOffset
            source.fileIndex = fileIndex
            appendSource(self.animationSources, species, source)
            self.motionFiles = self.motionFiles + 1
            self.animationClips = self.animationClips + (source.animations or 0)
          end
        else
          self.emptyPoseBundles = self.emptyPoseBundles + 1
          if #self.errorSamples < 12 then
            self.errorSamples[#self.errorSamples + 1] = {
              archive = self.archiveOffset, file = fileIndex,
              reason = table.concat(poseErrors or {}, " | "),
            }
          end
        end
      end
      return true
    end

    local species = self.speciesIndex
    if species > Bridge.COUNT then return finish() end
    self.speciesIndex = species + 1
    self.species = species

    local modelSource = self.modelSources[species]
      and self.modelSources[species][1]
    if not modelSource then
      self.lastError = ("species %d has no geometry source"):format(species)
      self.failed[#self.failed + 1] = species
      return true
    end

    local ok, result, reason = pcall(function()
      local decoded, infoOrErr = decompressedFragment(data, modelSource.record,
        StadiumRom)
      if not decoded then return nil, infoOrErr end
      local parser = fragmentParser(dependencies.V, infoOrErr.sourceBase)
      local model, extractErr = parser.extract(decoded,
        ("stadium2_model_%d.bin"):format(species))
      if not model then return nil, extractErr end
      model.species = species
      local drawable, drawableErr = normaliseDrawableModel(model, species, Fx)
      if not drawable then return nil, drawableErr end

      local animations, auxiliary, animationErrors = decodeAnimationSources(data,
        self.animationSources[species], model.bones, dependencies)
      local realAnimationCount = #animations
      model.anims = animations
      if #auxiliary > 0 then model.auxAnims = auxiliary end
      if realAnimationCount == 0 then
        model.stadium2AnimationFallback = true
        model.stadium2AnimationError = #animationErrors > 0
          and table.concat(animationErrors, " | ")
          or "no decodable Stadium 2 skeletal animation record"
      end

      local rows, contexts, animationErr = genericAnimationTable(model, Build)
      if not rows then return nil, animationErr end
      local normalBytes = Build.pack(model, species, rows, contexts)
      local palettes = paletteByDex[species]
      if palettes then
        for _, texture in ipairs(model.textures) do
          texture.rgba = recolourRgba(texture.rgba,
            palettes.normal, palettes.shiny)
        end
      end
      local shinyBytes = Build.pack(model, species, rows, contexts)
      local wrote, writeErr = writePack(species, normalBytes, shinyBytes)
      if not wrote then return nil, writeErr end
      return {
        species = species,
        bytes = #normalBytes + #shinyBytes,
        animations = realAnimationCount,
        fallback = realAnimationCount == 0,
        animationError = model.stadium2AnimationError,
      }
    end)

    if not ok then reason, result = result, nil end
    if result then
      self.built[result.species] = true
      self.builtCount = self.builtCount + 1
      if (result.animations or 0) > 0 then
        self.animatedBuilt = self.animatedBuilt + 1
      else
        self.fallbackBuilt = (self.fallbackBuilt or 0) + 1
        if result.animationError then self.lastAnimationError = result.animationError end
      end
      self.done = self.builtCount
      self.bytes = self.bytes + result.bytes
      self.lastAnimationCount = result.animations
    else
      self.failed[#self.failed + 1] = species
      self.lastError = tostring(reason or "unknown Stadium 2 build error")
      if #self.errorSamples < 12 then
        self.errorSamples[#self.errorSamples + 1] = {
          archive = modelSource.archiveOffset,
          file = modelSource.fileIndex,
          reason = self.lastError,
        }
      end
    end
    return true
  end

  function job:progress()
    if self.phase == "scan" then
      local position = self.cursor or ASSET_START
      local span = math.max(1, POSE_TABLE_START - MODEL_TABLE_START)
      return 0.25 * math.min(1,
        math.max(0, position - MODEL_TABLE_START) / span)
    elseif self.phase == "index" then
      local indexed = (self.index or 1) - 1
      local count = self.archive and self.archive.count or 1
      return 0.25 + 0.10 * math.min(1, indexed / math.max(1, count))
    elseif self.phase == "build" then
      return 0.35 + 0.65 * (self.done / self.total)
    end
    return self.success and 1 or (self.done / self.total)
  end

  return job
end

local function patchPack(V)
  local Pack = V.require("StadiumPack")
  normalPack = clonePack(V, Bridge.NORMAL_DIR, "normal")
  shinyPack = clonePack(V, Bridge.SHINY_DIR, "shiny")

  Pack.CACHE_DIR = Bridge.ROOT_DIR
  Pack.DIR = "__stadium2_shared_no_stadium1__"
  Pack.load = function(species, variant)
    local selected = variant == "shiny" and shinyPack or normalPack
    return selected.load(species)
  end
  Pack.available = function(species, variant)
    local selected = variant == "shiny" and shinyPack or normalPack
    return selected.available(species)
  end
  Pack.keep = function(species)
    normalPack.keep(species)
    shinyPack.keep(species)
  end
  Pack.invalidate = function()
    normalPack.invalidate()
    shinyPack.invalidate()
  end
  Pack.forget = function()
    normalPack.forget()
    shinyPack.forget()
  end
  return Pack
end

local function patchModels(V, Pack)
  local Stadium = V.require("Stadium")
  local StadiumMon = V.require("StadiumMon")
  local StadiumRig = V.require("StadiumRig")

  local oldUpdate = Stadium.update
  Stadium.update = function(dt, battle, groundY)
    wantedVariant.player = variantFor(battle and battle.player and battle.player.mon)
    wantedVariant.enemy = variantFor(battle and battle.enemy and battle.enemy.mon)
    return oldUpdate(dt, battle, groundY)
  end

  local oldAttack = StadiumMon.attack
  local oldBuild = StadiumMon.build
  local oldPlay = StadiumMon.play

  -- LOVE normally renders at the monitor refresh rate. On a 120/144/240 Hz
  -- display the original Stadium path therefore posed, CPU-skinned, and
  -- uploaded both Pokemon that many times per second even though its smooth
  -- interpolation was authored around a 60 Hz presentation. Stadium 2 models
  -- are larger and carry more bones, so that redundant work is noticeable.
  --
  -- Keep the animation clock fully real-time, but only rebuild the dynamic
  -- mesh when the next 60 Hz presentation sample is reached. At 60 Hz this is
  -- bit-for-bit the old cadence; at 240 Hz it removes three out of every four
  -- complete pose/skin/upload passes. Matrix-only changes such as the send-out
  -- grow still happen every rendered frame because Stadium computes those
  -- outside StadiumMon:build().
  local SKIN_FPS = 60

  if type(oldPlay) == "function" then
    StadiumMon.play = function(self, ...)
      local played = oldPlay(self, ...)
      if played then
        self._crystal251PoseSerial = (self._crystal251PoseSerial or 0) + 1
        self._crystal251SkinFrame = nil
        self._crystal251SkinDt = 0
      end
      return played
    end
  end

  if type(oldBuild) == "function" then
    StadiumMon.build = function(self)
      if not (self.rig and self.model) then
        self._crystal251SkinFrame = nil
        self._crystal251SkinDt = 0
        return oldBuild(self)
      end

      local time = tonumber(self.time) or 0
      if time < 0 then time = 0 end
      local anim = self.anim or 0
      local loop = self.loop and true or false
      local frame = math.floor(time * SKIN_FPS + 1e-7)
      local record = self.model.anims and self.model.anims[anim] or nil
      local sourceFrames = record and tonumber(record.frames) or 1
      if not (sourceFrames > 1) then
        -- Bind-pose fallbacks and genuinely one-frame clips are immutable.
        frame = 0
      else
        local sourceFps = tonumber(StadiumMon.FPS) or 30
        if not (sourceFps > 0) then sourceFps = 30 end
        local total = math.max(1,
          math.floor(sourceFrames * SKIN_FPS / sourceFps + 0.5))
        if loop then
          local loopStart = tonumber(record.loopStart) or 0
          if not (loopStart > 0 and loopStart < sourceFrames) then
            loopStart = 0
          end
          local first = math.floor(loopStart * SKIN_FPS / sourceFps + 0.5)
          if first < 0 or first >= total then first = 0 end
          if frame >= total then
            frame = first + (frame - first) % math.max(1, total - first)
          end
        elseif frame >= total then
          frame = total - 1
        end
      end
      local serial = self._crystal251PoseSerial or 0
      local aux = self.aux or 0
      local yaw = self.yaw or 0
      local elapsed = (self._crystal251SkinDt or 0) + (self.dt or 0)

      if self._crystal251SkinFrame == frame
          and self._crystal251SkinSerial == serial
          and self._crystal251SkinAnim == anim
          and self._crystal251SkinAux == aux
          and self._crystal251SkinYaw == yaw
          and self._crystal251SkinLoop == loop then
        self._crystal251SkinDt = elapsed
        return true
      end

      -- anchor() is time-filtered. Feed it the complete elapsed time since the
      -- previous mesh upload rather than only the final high-refresh frame.
      local savedDt = self.dt
      self.dt = elapsed
      local built = oldBuild(self)
      self.dt = savedDt
      if built then
        self._crystal251SkinFrame = frame
        self._crystal251SkinSerial = serial
        self._crystal251SkinAnim = anim
        self._crystal251SkinAux = aux
        self._crystal251SkinYaw = yaw
        self._crystal251SkinLoop = loop
        self._crystal251SkinDt = 0
      else
        self._crystal251SkinFrame = nil
        self._crystal251SkinDt = elapsed
      end
      return built
    end
  end

  StadiumMon.setSpecies = function(self, dex)
    local variant = wantedVariant[self.side] or "normal"
    if dex == self.species and variant == self._crystal251Variant then
      return self.rig ~= nil
    end
    if self.rig then self.rig:release() end
    self.rig, self.model, self.species = nil, nil, dex
    self._crystal251Variant = variant
    self._crystal251PoseSerial = (self._crystal251PoseSerial or 0) + 1
    self._crystal251SkinFrame = nil
    self._crystal251SkinDt = 0
    self.grow, self.grewOwn = nil, nil
    if not dex then return false end
    local model = Pack.load(dex, variant)
    if not model or model.staticPose then return false end
    local rig = StadiumRig.new(model)
    if not rig then return false end
    self.model, self.rig = model, rig
    self.state, self.anim, self.time = nil, nil, 0
    self:play("idle")
    return true
  end

  -- DRAMATIC_SHAPE's original pack has 165 move rows because it targets Red
  -- and Blue. Crystal has 251 move ids. Keep its exact table lookup for the
  -- original range, then route Generation II moves through the imported
  -- Stadium 2 default attack slot instead of leaving the model motionless.
  StadiumMon.attack = function(self, moveIndex)
    if oldAttack and moveIndex and moveIndex >= 1 and moveIndex <= 165 then
      local ok, played = pcall(oldAttack, self, moveIndex)
      if ok and played then return played end
    end
    if not (self.model and moveIndex and moveIndex >= 1
        and moveIndex <= Bridge.COUNT) then return false end
    local index = self.slotAnim and self:slotAnim("attack_default") or nil
    if not index and self.slotAnim then index = self:slotAnim("idle") end
    if not index then index = (#(self.model.anims or {}) > 1) and 2 or 1 end
    if not (self.request and self.model.anims and self.model.anims[index]) then
      return false
    end
    return self:request("attack", index, nil)
  end
end

local function filesystem()
  return love and love.filesystem
end

local function isFile(path)
  local fs = filesystem()
  if not (fs and fs.getInfo) then return false end
  local ok, info = pcall(fs.getInfo, path, "file")
  return ok and info and true or false
end

local function oneLine(value)
  return tostring(value or "unknown error")
    :gsub("\r", "")
    :gsub("\n+", " | ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
end

local function writeStadiumFailure(V, text)
  text = tostring(text or "unknown error")
  if V and V.mod and V.mod.log then
    pcall(function() V.mod.log:error("stadium2 import failed: %s", text) end)
  end
  pcall(function()
    if io and io.stderr then
      io.stderr:write("[" .. tostring(Bridge.OWNER_ID)
        .. "] Stadium 2 import failed:\n" .. text .. "\n")
      if io.stderr.flush then io.stderr:flush() end
    end
  end)
  local fs = filesystem()
  if fs and fs.createDirectory then pcall(fs.createDirectory, Bridge.ROOT_DIR) end
  if fs and fs.write then pcall(fs.write, Bridge.ERROR_LOG, text .. "\n") end
end

local function patchInstall(V, Pack)
  local Install = V.require("StadiumInstall")
  local StadiumRom = V.require("StadiumRom")
  local Build = V.require("StadiumBuild")
  local Fx = V.require("StadiumFx")
  local readyCache, job
  local status = { state = "idle", done = 0, total = Bridge.COUNT }

  Install.ROM_DIR = Bridge.ROM_DIR
  Install.DIR = Bridge.ROOT_DIR
  Install.MARKER = Bridge.MARKER
  Install.FORMAT = Bridge.FORMAT
  Install.COUNT = Bridge.COUNT
  Install.status = status

  local function fail(stage, reason, context)
    local short = oneLine(reason)
    local full = ("Stage: %s\nReason: %s%s")
      :format(oneLine(stage), short,
        context and ("\n" .. tostring(context)) or "")
    status.state = "failed"
    status.error = oneLine(stage) .. ": " .. short
    status.errorFull = full
    status.errorLog = Bridge.ERROR_LOG
    writeStadiumFailure(V, full)
    return false, status.error
  end
  Install.fail = fail

  local preferred = {
    Bridge.ROM_DIR .. "/pokemon_stadium_2.z64",
    Bridge.ROM_DIR .. "/pokemon_stadium_2.n64",
    Bridge.ROM_DIR .. "/pokemon_stadium_2.v64",
    Bridge.ROM_DIR .. "/pokemonstadium2.z64",
    Bridge.ROM_DIR .. "/stadium2.z64",
  }
  local externalRomPath = nil

  local function sourceBaseDirectory()
    local fs = filesystem()
    if not (fs and fs.getSourceBaseDirectory) then return nil end
    local ok, base = pcall(fs.getSourceBaseDirectory)
    return ok and type(base) == "string" and base ~= "" and base or nil
  end

  local function cleanDirectory(path)
    if type(path) ~= "string" then return nil end
    path = path:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[/\\]+$", "")
    return path ~= "" and path or nil
  end

  local function parentDirectory(path)
    path = cleanDirectory(path)
    return path and cleanDirectory(path:match("^(.*)[/\\][^/\\]+$")) or nil
  end

  local function macBundleParent(path)
    path = cleanDirectory(path)
    if not path then return nil end
    local normalized = path:gsub("\\", "/")
    return cleanDirectory(normalized:match("^(.*)/[^/]+%.app/")
      or normalized:match("^(.*)/[^/]+%.app$"))
  end

  local function hostDirectories()
    local fs = filesystem()
    local platform = love and love.system and love.system.getOS
      and love.system.getOS() or nil
    if platform == "Android" or platform == "iOS" then return {} end
    local dirs, seen = {}, {}
    local function add(path)
      path = cleanDirectory(path)
      if path and not seen[path] then
        seen[path] = true
        dirs[#dirs + 1] = path
      end
    end
    if platform == "Linux" and os and os.getenv then
      add(parentDirectory(os.getenv("APPIMAGE")))
    end
    if platform == "OS X" then
      add(macBundleParent(sourceBaseDirectory()))
      if type(arg) == "table" then add(macBundleParent(arg[0])) end
    end
    add(sourceBaseDirectory())
    if type(arg) == "table" then add(parentDirectory(arg[0])) end
    if fs and fs.getWorkingDirectory then
      local ok, cwd = pcall(fs.getWorkingDirectory)
      if ok then add(cwd) end
    end
    return dirs
  end

  local function autoCommandOutput(command)
    local okHost, HostShell = pcall(require, "src.core.HostShell")
    local pipe
    if okHost and HostShell and type(HostShell.popen) == "function" then
      pipe = HostShell.popen(command, "r")
    elseif io and io.popen then
      local ok, opened = pcall(io.popen, command, "r")
      pipe = ok and opened or nil
    end
    if not pipe then return nil end
    local okRead, output = pcall(pipe.read, pipe, "*a")
    pcall(pipe.close, pipe)
    return okRead and type(output) == "string" and output or nil
  end

  local function externalCandidatePaths()
    local platform = love and love.system and love.system.getOS
      and love.system.getOS() or nil
    if platform ~= "Windows" and platform ~= "Linux" and platform ~= "OS X" then
      return {}
    end
    if platform == "Windows" and os and os.getenv
        and os.getenv("APPX_PACKAGE_FAMILY_NAME") then
      return {}
    end
    local paths, seen = {}, {}
    local function append(path)
      if path ~= "" and not seen[path] then
        seen[path] = true
        paths[#paths + 1] = path
      end
    end
    for _, base in ipairs(hostDirectories()) do
      local output
      local found = {}
      if platform == "Windows" then
        local quoted = base:gsub("'", "''")
        output = autoCommandOutput("powershell -NoProfile -Command \"$p='" .. quoted
          .. "'; Get-ChildItem -LiteralPath $p -File | Where-Object { @('.z64','.n64','.v64') -contains $_.Extension.ToLowerInvariant() } | ForEach-Object {$_.FullName}\"")
        for path in tostring(output or ""):gmatch("[^\r\n]+") do
          found[#found + 1] = path
        end
      else
        local quoted = "'" .. base:gsub("'", "'\\''") .. "'"
        output = autoCommandOutput("find " .. quoted
          .. " -maxdepth 1 -type f \\( -iname '*.z64' -o -iname '*.n64' -o -iname '*.v64' \\) -print0 2>/dev/null")
        for path in tostring(output or ""):gmatch("([^%z]+)%z") do
          found[#found + 1] = path
        end
      end
      table.sort(found)
      for _, path in ipairs(found) do append(path) end
    end
    return paths
  end

  local function candidatePaths()
    local fs = filesystem()
    if not fs then return {} end
    local paths, seen = {}, {}
    local function add(path)
      if not seen[path] and isFile(path) then
        seen[path] = true
        paths[#paths + 1] = path
      end
    end
    local function addDirectory(path, prefix)
      local ok, items = pcall(fs.getDirectoryItems, path)
      if not (ok and items) then return end
      table.sort(items)
      for _, name in ipairs(items) do
        if name:lower():match("%.[nvz]64$") then
          add(prefix .. name)
        end
      end
    end
    for _, path in ipairs(preferred) do add(path) end
    addDirectory(Bridge.ROM_DIR, Bridge.ROM_DIR .. "/")
    addDirectory("", "")
    return paths
  end

  local function stadium2Path(path)
    local fs = filesystem()
    if not (fs and fs.read) then return false end
    local ok, header = pcall(fs.read, path, 0x40)
    if not (ok and type(header) == "string") then return false end
    return n64Title(header):upper():find("POKEMON STADIUM 2", 1, true) ~= nil
  end

  local function externalStadium2Path(path)
    if not (io and io.open) then return false end
    local ok, file = pcall(io.open, path, "rb")
    if not (ok and file) then return false end
    local okRead, header = pcall(file.read, file, 0x40)
    pcall(file.close, file)
    if not (okRead and type(header) == "string") then return false end
    return n64Title(header):upper():find("POKEMON STADIUM 2", 1, true) ~= nil
  end

  function Install.romPath()
    externalRomPath = nil
    for _, path in ipairs(candidatePaths()) do
      if stadium2Path(path) then return path end
    end
    for _, path in ipairs(externalCandidatePaths()) do
      if externalStadium2Path(path) then
        externalRomPath = path
        return path
      end
    end
    return nil
  end

  function Install.romPresent()
    return Install.romPath() ~= nil
  end

  function Install.romHint()
    local fs = filesystem()
    local save = fs and fs.getSaveDirectory
      and select(2, pcall(fs.getSaveDirectory)) or nil
    local dirs = hostDirectories()
    local base = dirs[1]
    local fallback = type(save) == "string" and save .. "/" .. Bridge.ROM_DIR
      or "the game folder/" .. Bridge.ROM_DIR
    return base and base .. " OR " .. fallback or fallback
  end

  function Install.romHintFile()
    return Install.romHint()
  end

  local function readMarker()
    local fs = filesystem()
    if not (fs and isFile(Bridge.MARKER)) then return nil end
    local ok, text = pcall(fs.read, Bridge.MARKER)
    if not (ok and type(text) == "string") then return nil end
    local format, count, variants, hash = text:match(
      "^(%S+)%s+(%d+)%s+(%d+)%s*(%S*)")
    if not format then return nil end
    return {
      format = format,
      count = tonumber(count),
      variants = tonumber(variants),
      md5 = hash,
    }
  end

  function Install.ready()
    if readyCache ~= nil then return readyCache end
    local marker = readMarker()
    if not (marker ~= nil and marker.format == Bridge.FORMAT
        and marker.count >= Bridge.COUNT and marker.variants == Bridge.VARIANTS) then
      readyCache = false
      return false
    end
    for species = 1, Bridge.COUNT do
      if not isFile(("%s/%03d.dsm"):format(Bridge.NORMAL_DIR, species))
          or not isFile(("%s/%03d.dsm"):format(Bridge.SHINY_DIR, species)) then
        readyCache = false
        return false
      end
    end
    readyCache = true
    return true
  end

  function Install.available()
    return Install.ready()
  end

  function Install.pending()
    return not Install.available() and Install.romPresent()
  end

  function Install.forget()
    readyCache = nil
    Pack.forget()
  end

  local function writePack(species, normalBytes, shinyBytes)
    local fs = filesystem()
    if not fs then return false, "no filesystem" end
    local normalPath = ("%s/%03d.dsm"):format(Bridge.NORMAL_DIR, species)
    local shinyPath = ("%s/%03d.dsm"):format(Bridge.SHINY_DIR, species)
    local ok, err = fs.write(normalPath, normalBytes)
    if not ok then return false, tostring(err) end
    ok, err = fs.write(shinyPath, shinyBytes)
    if not ok then return false, tostring(err) end
    return true
  end

  function Install.begin()
    local fs = filesystem()
    if not fs then return fail("opening filesystem", "love.filesystem is unavailable") end
    local path = Install.romPath()
    if not path then
      return fail("finding Stadium 2 ROM",
        "no Pokemon Stadium 2 ROM beside the game or in " .. Bridge.ROM_DIR)
    end
    local ok, bytes
    if externalRomPath == path then
      local file
      ok, file = pcall(io.open, path, "rb")
      if ok and file then
        ok, bytes = pcall(file.read, file, "*a")
        pcall(file.close, file)
      else
        bytes = file
      end
    else
      ok, bytes = pcall(fs.read, path)
    end
    if not ok then
      return fail("reading Stadium 2 ROM", bytes, "ROM: " .. tostring(path))
    end
    if type(bytes) ~= "string" then
      return fail("reading Stadium 2 ROM", "filesystem returned no ROM bytes",
        "ROM: " .. tostring(path))
    end
    return Install.beginFrom(bytes, path)
  end

  function Install.beginFrom(bytes, label)
    local fs = filesystem()
    if not fs then return fail("opening filesystem", "love.filesystem is unavailable") end
    if type(bytes) ~= "string" or #bytes == 0 then
      return fail("reading Stadium 2 ROM", "ROM file is empty",
        "ROM: " .. tostring(label or "unknown"))
    end
    local okNormalise, normalised = pcall(StadiumRom.normalise, bytes)
    if not okNormalise then
      return fail("normalising N64 ROM", normalised,
        "ROM: " .. tostring(label or "unknown"))
    end
    if not normalised then
      return fail("normalising N64 ROM", "bad N64 byte-order magic",
        "ROM: " .. tostring(label or "unknown"))
    end
    local okTitle, title = pcall(romTitle, normalised)
    if not okTitle then
      return fail("reading N64 title", title, "ROM: " .. tostring(label or "unknown"))
    end
    title = tostring(title or ""):upper()
    local okHash, hash = pcall(md5, normalised)
    if not okHash then
      return fail("hashing Stadium 2 ROM", hash,
        "ROM: " .. tostring(label or "unknown"))
    end
    status.wrongVersion = false
    if not title:find("POKEMON STADIUM 2", 1, true)
        and hash ~= Bridge.US_MD5 then
      return fail("validating Stadium 2 ROM", "needs Pokemon Stadium 2 (US)",
        ("ROM: %s\nN64 title: %s\nMD5: %s\nExpected MD5: %s")
          :format(tostring(label or "unknown"), title, tostring(hash), Bridge.US_MD5))
    end
    if hash and hash ~= Bridge.US_MD5 then
      status.wrongVersion = true
      if V.mod and V.mod.log then
        V.mod.log:warn("stadium2: %s is md5 %s; expected US ROM md5 %s. "
          .. "Scanning its model archive anyway.", tostring(label or "ROM"),
          tostring(hash), Bridge.US_MD5)
      end
    end
    for _, directory in ipairs({ Bridge.ROOT_DIR, Bridge.NORMAL_DIR, Bridge.SHINY_DIR }) do
      local okDir, made, dirErr = pcall(fs.createDirectory, directory)
      if not okDir or made == false then
        return fail("creating Stadium 2 cache directory", dirErr or made,
          "Directory: " .. directory)
      end
    end
    if fs.remove then pcall(fs.remove, Bridge.ERROR_LOG) end
    local okJob, newJob = pcall(newBuildJob, normalised, {
      StadiumRom = StadiumRom,
      Build = Build,
      Fx = Fx,
      V = V,
    }, writePack)
    if not okJob then
      return fail("starting Stadium 2 model scan", newJob,
        "ROM: " .. tostring(label or "unknown"))
    end
    job = newJob
    job.md5 = hash
    job.label = label
    status.state = "building"
    status.done = 0
    status.total = Bridge.COUNT
    status.species = nil
    status.error = nil
    status.errorFull = nil
    status.errorLog = nil
    status.rom = label
    return true
  end

  function Install.step()
    if not job then return false end
    local active = job
    local okStep, more = pcall(active.step, active)
    if not okStep then
      job = nil
      fail("processing Stadium 2 archive", more,
        ("ROM: %s\nArchive offset: %s\nFile index: %s\nBuilt: %d/%d")
          :format(tostring(active.label or status.rom or "unknown"),
            active.archiveOffset and ("0x%X"):format(active.archiveOffset) or "unknown",
            tostring(active.fileIndex or "unknown"), active.builtCount or 0, Bridge.COUNT))
      return false
    end
    status.done = active.done
    status.total = active.total
    status.species = active.species
    status.phase = active.phase
    status.archives = active.archives or 0
    status.modelSpecies = active.modelSpecies or 0
    status.animatedSpecies = active.animatedSpecies or 0
    status.animationClips = active.animationClips or 0
    status.nestedPoseArchives = active.nestedPoseArchives or 0
    if active.error then
      local samples = {}
      for _, sample in ipairs(active.errorSamples or {}) do
        samples[#samples + 1] = ("archive=0x%X file=%s: %s")
          :format(sample.archive or 0, tostring(sample.file), tostring(sample.reason))
      end
      job = nil
      fail("extracting Stadium 2 models and animations", active.error,
        ("ROM: %s\nTop-level tables: %s\nModel records: %s\n"
          .. "Pose records: %s\nNested pose archives: %s\nBuilt: %d/%d\n"
          .. "Rejected model samples:\n%s")
          :format(tostring(active.label or status.rom or "unknown"),
            tostring(active.archives or 0), tostring(active.modelTableCount or 0),
            tostring(active.poseTableCount or 0),
            tostring(active.nestedPoseArchives or 0),
            active.builtCount or 0, Bridge.COUNT,
            #samples > 0 and table.concat(samples, "\n") or "none recorded"))
      return false
    end
    if not more then
      local fs = filesystem()
      if active.success and fs then
        local marker = ("%s %d %d %s\n"):format(Bridge.FORMAT,
          Bridge.COUNT, Bridge.VARIANTS, tostring(active.md5 or ""))
        local okWrite, wrote, err = pcall(fs.write, Bridge.MARKER, marker)
        if not okWrite or wrote == false then
          job = nil
          fail("writing Stadium 2 completion marker", err or wrote,
            "File: " .. Bridge.MARKER)
          return false
        end
        readyCache = nil
        Pack.forget()
        if V.mod and V.mod.log then
          V.mod.log:info("stadium2: built %d Pokemon from %d tables and %d nested "
            .. "pose archives; real-animation species=%d fallback species=%d "
            .. "discovered clips=%d",
            active.builtCount or 0, active.archives or 0,
            active.nestedPoseArchives or 0, active.animatedBuilt or 0,
            active.fallbackBuilt or 0, active.animationClips or 0)
          if active.animationIncomplete then
            V.mod.log:warn("stadium2: model import completed, but %d Pokemon use "
              .. "the one-frame rest-pose fallback; last animation error: %s",
              active.fallbackBuilt or 0,
              tostring(active.lastAnimationError or "no decoded pose records"))
          end
        end
        status.done = Bridge.COUNT
        status.total = Bridge.COUNT
        status.state = "done"
      else
        job = nil
        fail("finishing Stadium 2 model build",
          active.error or "model build ended without a complete pack set")
        return false
      end
      job = nil
      return false
    end
    return true
  end

  function Install.cancel()
    job = nil
    status.state = "idle"
    status.done = 0
    status.species = nil
    status.error = nil
    status.errorFull = nil
  end

  Install._crystal251 = {
    readMarker = readMarker,
    newBuildJob = newBuildJob,
  }
  return Install
end

local function patchPicker(V, Install)
  local Picker = V.require("StadiumRomPick")
  local Screen = V.require("StadiumScreen")
  Picker.LABEL = "STADIUM 2 ROM"
  Picker.ID = tostring(Bridge.OWNER_ID) .. ":stadium2Rom"
  Picker.PICKED = Bridge.PICKED

  if not Screen._crystal251FailureUi then
    Screen._crystal251FailureUi = true
    local oldUpdate, oldDraw = Screen.update, Screen.draw
    local dismiss = { "a", "b", "start", "select" }
    local function wrap(text, width, limit)
      local lines, line = {}, ""
      local function push(value)
        if value ~= "" and #lines < limit then lines[#lines + 1] = value end
      end
      for word in tostring(text or "unknown error"):gmatch("%S+") do
        while #word > width and #lines < limit do
          if line ~= "" then push(line); line = "" end
          push(word:sub(1, width))
          word = word:sub(width + 1)
        end
        if #lines >= limit then break end
        if line == "" then line = word
        elseif #line + #word + 1 <= width then line = line .. " " .. word
        else push(line); line = word end
      end
      push(line)
      return lines
    end
    Screen.update = function(self, ...)
      if Install.status.state == "failed" and not self.note then
        local input = self.game and self.game.input
        if input and input.wasPressed then
          for _, button in ipairs(dismiss) do
            if input:wasPressed(button) then
              if self.game.stack and self.game.stack:top() == self then
                self.game.stack:pop()
              end
              return
            end
          end
        end
        return
      end
      return oldUpdate(self, ...)
    end
    Screen.draw = function(self, ...)
      if Install.status.state ~= "failed" or self.note then
        return oldDraw(self, ...)
      end
      local Font = require("src.render.Font")
      love.graphics.setColor(0.93, 0.94, 0.90, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw("STADIUM 2 FAILED", 8, 8)
      local lines = wrap(Install.status.errorFull or Install.status.error, 18, 9)
      for index, line in ipairs(lines) do
        Font.draw(line, 8, 24 + (index - 1) * 10)
      end
      Font.draw("FULL ERROR PRINTED", 8, 120)
      Font.draw("A/B: CLOSE", 8, 132)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local function haveShell()
    local ok, popen = pcall(function() return io and io.popen end)
    return ok and popen and true or false
  end

  local function haveFiles()
    local ok, open = pcall(function() return io and io.open end)
    return ok and open and true or false
  end

  local function osName()
    local ok, name = pcall(function() return love.system.getOS() end)
    return ok and name or nil
  end

  local androidPickPending = false
  local androidPickGame = nil

  local function canAndroidPick()
    return osName() == "Android" and love and love.system
      and type(love.system.pickFile) == "function"
  end

  local function beginAndroidPick(game)
    if not canAndroidPick() then return false end
    local fs = filesystem()
    if fs and fs.remove then pcall(fs.remove, Bridge.ANDROID_PICKED) end
    local ok, opened = pcall(love.system.pickFile, "rom")
    if not (ok and opened) then return false end
    androidPickPending = true
    androidPickGame = game or true
    return true
  end

  -- Host tools launched from an AppImage must not inherit the bundled
  -- LD_LIBRARY_PATH. Otherwise system kdialog/zenity can load the AppImage's
  -- incompatible Qt/GTK libraries, exit before drawing a window, and look
  -- exactly like a cancelled picker. The engine's HostShell owns that fix.
  local okHostShell, HostShell = pcall(require, "src.core.HostShell")

  local function hostPopen(command)
    if okHostShell and HostShell and type(HostShell.popen) == "function" then
      return HostShell.popen(command, "r")
    end
    if not haveShell() then return nil end
    local prefix = ""
    if os and os.getenv and os.getenv("APPIMAGE") then
      prefix = "env -u LD_LIBRARY_PATH "
    end
    local ok, pipe = pcall(io.popen, prefix .. command, "r")
    return ok and pipe or nil
  end

  local function commandOutput(command)
    local pipe = hostPopen(command)
    if not pipe then return nil end
    local okRead, output = pcall(pipe.read, pipe, "*a")
    pcall(pipe.close, pipe)
    if not (okRead and type(output) == "string") then return nil end
    output = output:gsub("^%s+", ""):gsub("%s+$", "")
    return output ~= "" and output or nil
  end

  local dialogBackend = false
  local function linuxCommand(name)
    return commandOutput("sh -c 'command -v " .. name .. " 2>/dev/null'")
      and true or false
  end

  local function backend()
    if dialogBackend ~= false then return dialogBackend end
    local platform = osName()
    if platform == "Windows" then dialogBackend = "powershell"
    elseif platform == "OS X" then dialogBackend = "osascript"
    elseif platform == "Linux" then
      if linuxCommand("zenity") then dialogBackend = "zenity"
      elseif linuxCommand("kdialog") then dialogBackend = "kdialog"
      elseif linuxCommand("yad") then dialogBackend = "yad"
      else dialogBackend = nil end
    else dialogBackend = nil end
    return dialogBackend
  end

  function Picker.canDialog()
    return canAndroidPick() or (haveFiles() and backend() ~= nil)
  end
  Picker.available = Picker.canDialog

  function Picker.choose()
    local prompt = "Choose your Pokemon Stadium 2 (US) ROM"
    local selected = backend()
    if selected == "osascript" then
      return commandOutput(([[osascript -e 'POSIX path of (choose file with prompt "%s" of type ]]
        .. [[{"z64", "n64", "v64"})' 2>/dev/null]]):format(prompt))
    elseif selected == "powershell" then
      local script = table.concat({
        "Add-Type -AssemblyName System.Windows.Forms;",
        "$d=New-Object System.Windows.Forms.OpenFileDialog;",
        "$d.Title='" .. prompt .. "';",
        "$d.Filter='Nintendo 64 ROM (*.z64;*.n64;*.v64)|*.z64;*.n64;*.v64"
          .. "|All files (*.*)|*.*';",
        "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding="
          .. "[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
      })
      return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
    elseif selected == "zenity" then
      return commandOutput(([[zenity --file-selection --title="%s" ]]
        .. [[--file-filter="Nintendo 64 ROM | *.z64 *.n64 *.v64" 2>/dev/null]])
          :format(prompt))
    elseif selected == "kdialog" then
      return commandOutput([[kdialog --getopenfilename "$HOME" "*.z64 *.n64 *.v64|]]
        .. [[Nintendo 64 ROM" 2>/dev/null]])
    elseif selected == "yad" then
      return commandOutput(([[yad --file --title="%s" ]]
        .. [[--file-filter="Nintendo 64 ROM | *.z64 *.n64 *.v64" 2>/dev/null]])
          :format(prompt))
    end
    return nil
  end

  function Picker.read(path)
    if not haveFiles() then return nil, "no file access" end
    local ok, file = pcall(io.open, path, "rb")
    if not (ok and file) then return nil, "could not open that file" end
    local okRead, bytes = pcall(file.read, file, "*a")
    pcall(file.close, file)
    if not (okRead and type(bytes) == "string") then
      return nil, "could not read that file"
    end
    return bytes
  end

  function Picker.import(game)
    if Install.status.state == "building" then return false end
    local automatic = Install.romPath()
    if automatic then
      local started, beginErr = Install.begin()
      if not started then
        if Install.status.state ~= "failed" then
          Install.fail("starting automatic Stadium 2 import", beginErr,
            "ROM: " .. tostring(automatic))
        end
        if game and game.stack then game.stack:push(Screen.new(game, true)) end
        return false
      end
      if game and game.stack then game.stack:push(Screen.new(game, true)) end
      return true
    end
    if beginAndroidPick(game) then
      return true
    end
    if not Picker.canDialog() then
      if V.mod and V.mod.log then
        V.mod.log:warn("stadium2: no file-dialog backend; install kdialog, "
          .. "zenity, or yad, or place the ROM at %s", Install.romHintFile())
      end
      if game and game.stack then
        game.stack:push(Screen.newNote(game, "STADIUM 2 ROM",
          "INSTALL KDIALOG/ZENITY", Install.romHintFile()))
      end
      return false
    end
    local path = Picker.choose()
    if not path then return false end
    local function pickerFail(stage, reason, context)
      Install.fail(stage, reason, context)
      if game and game.stack then game.stack:push(Screen.new(game, true)) end
      return false
    end
    local bytes, readErr = Picker.read(path)
    if not bytes then
      return pickerFail("reading selected Stadium 2 ROM",
        readErr or "could not read that file", "ROM: " .. tostring(path))
    end
    local started, beginErr = Install.beginFrom(bytes, path)
    if not started then
      if Install.status.state ~= "failed" then
        return pickerFail("starting selected Stadium 2 import", beginErr,
          "ROM: " .. tostring(path))
      end
      if game and game.stack then game.stack:push(Screen.new(game, true)) end
      return false
    end
    if game and game.stack then game.stack:push(Screen.new(game, true)) end
    return true
  end

  -- A native picker is modal and blocks inside io.popen. Do not open it
  -- directly from the options input callback: SDL may still own pointer
  -- capture until the matching mouse-up event is pumped, leaving the dialog
  -- behind an unresponsive captured cursor. Queue it for the next released
  -- frame; DRAMATIC_SHAPE already polls this module every update.
  local pendingDialogGame = nil
  local pendingDialogArmed = false

  local function mouseHeld()
    if not (love and love.mouse and love.mouse.isDown) then return false end
    local ok, held = pcall(love.mouse.isDown, 1, 2, 3)
    return ok and held and true or false
  end

  function Picker.request(game)
    if Install.status.state == "building" then return false end
    pendingDialogGame = game or true
    pendingDialogArmed = false
    return true
  end

  function Picker.row()
    return {
      id = Picker.ID,
      label = Picker.LABEL,
      value = function()
        if Install.status.state == "building" then return "BUILDING" end
        if Install.available() then return "READY" end
        return Picker.canDialog() and "IMPORT" or "WHERE?"
      end,
      step = function(game)
        Picker.request(game)
        return true
      end,
    }
  end

  function Picker.poll(game)
    if pendingDialogGame ~= nil then
      -- Always yield at least one update, then wait for pointer release.
      if not pendingDialogArmed then
        pendingDialogArmed = true
        return false
      end
      if mouseHeld() then return false end
      local target = pendingDialogGame == true and game or pendingDialogGame
      pendingDialogGame = nil
      pendingDialogArmed = false
      local okImport, result = pcall(Picker.import, target)
      if not okImport then
        Install.fail("opening Stadium 2 importer", result)
        if target and target.stack then target.stack:push(Screen.new(target, true)) end
      end
      return true
    end

    if androidPickPending then
      local fs = filesystem()
      if not (fs and fs.getInfo and fs.read) or Install.status.state == "building" then
        return false
      end
      local okInfo, info = pcall(fs.getInfo, Bridge.ANDROID_PICKED, "file")
      if not (okInfo and info) then return false end
      local okRead, bytes = pcall(fs.read, Bridge.ANDROID_PICKED)
      if fs.remove then pcall(fs.remove, Bridge.ANDROID_PICKED) end
      local target = androidPickGame == true and game or androidPickGame
      androidPickPending = false
      androidPickGame = nil
      if not okRead then
        Install.fail("reading Android Stadium 2 ROM", bytes,
          "File: " .. Bridge.ANDROID_PICKED)
      elseif type(bytes) ~= "string" then
        Install.fail("reading Android Stadium 2 ROM", "selected file contained no ROM bytes",
          "File: " .. Bridge.ANDROID_PICKED)
      else
        local started, err = Install.beginFrom(bytes, Bridge.ANDROID_PICKED)
        if not started and Install.status.state ~= "failed" then
          Install.fail("starting Android Stadium 2 import", err,
            "File: " .. Bridge.ANDROID_PICKED)
        end
      end
      if target and target.stack then target.stack:push(Screen.new(target, true)) end
      return true
    end

    local fs = filesystem()
    if not (fs and fs.getInfo) or Install.status.state == "building" then
      return false
    end
    local ok, info = pcall(fs.getInfo, Picker.PICKED, "file")
    if not (ok and info) then return false end
    local okRead, bytes = pcall(fs.read, Picker.PICKED)
    pcall(fs.remove, Picker.PICKED)
    if not okRead then
      Install.fail("reading queued Stadium 2 ROM", bytes,
        "File: " .. Picker.PICKED)
    elseif type(bytes) ~= "string" then
      Install.fail("reading queued Stadium 2 ROM", "queued file contained no ROM bytes",
        "File: " .. Picker.PICKED)
    else
      local started, err = Install.beginFrom(bytes, Picker.PICKED)
      if not started and Install.status.state ~= "failed" then
        Install.fail("starting queued Stadium 2 import", err,
          "File: " .. Picker.PICKED)
      end
    end
    if game and game.stack then game.stack:push(Screen.new(game, true)) end
    return true
  end

  local asked = false
  function Screen.maybePush()
    if asked then return false end
    local ok, Game = pcall(require, "src.core.Game")
    if not (ok and Game and Game.stack and Game.overworld) then return false end
    if Game.stack:top() ~= Game.overworld then return false end
    asked = true
    if Install.pending() then
      local rom = Install.romPath()
      if V.mod and V.mod.log then
        V.mod.log:info("stadium2: cache missing or outdated; starting automatic "
          .. "import from %s", tostring(rom or Bridge.ROM_DIR))
      end
      -- Start the job here, before pushing the UI. This removes a fragile
      -- dependency on the stack calling StadiumScreen:enter() and guarantees
      -- that an automatic import either enters BUILDING or prints a failure.
      local started, beginErr = Install.begin()
      if not started and Install.status.state ~= "failed" then
        Install.fail("starting automatic Stadium 2 import", beginErr,
          "ROM: " .. tostring(rom or "unknown"))
      end
      Game.stack:push(Screen.new(Game, true))
      return true
    end
    if not Install.available() and V.mod and V.mod.log then
      V.mod.log:info("stadium2: no Pokemon Stadium 2 (US) ROM found. "
        .. "OPTIONS -> %s imports one; the folder is %s",
        Picker.LABEL, Install.romHint())
    end
    return false
  end
  function Screen._reset() asked = false end
  return Picker
end

function Bridge.modelRow()
  if delegatedBridge and delegatedBridge ~= Bridge then
    return delegatedBridge.modelRow()
  end
  local V, Install, Picker = selectionV, selectionInstall, selectionPicker
  if not (V and Install) then return nil end
  return {
    id = tostring(Bridge.OWNER_ID) .. ":stadium2Models",
    stadium2Shared = true,
    label = "STADIUM 2 MODELS",
    value = function()
      if Install.status and Install.status.state == "building" then return "BUILDING" end
      if not Install.available() then return "IMPORT" end
      return modelsSelected(V) and "ON" or "OFF"
    end,
    step = function(game)
      if not Install.available() then
        if Picker and Picker.request then Picker.request(game)
        elseif Picker and Picker.import then
          local ok, result = pcall(Picker.import, game)
          if not ok and Install.fail then
            Install.fail("opening Stadium 2 importer", result)
          end
        end
        return true
      end
      selectModels(V, game, not modelsSelected(V))
      return true
    end,
  }
end

function Bridge.appendModelRow(rows)
  if delegatedBridge and delegatedBridge ~= Bridge then
    return delegatedBridge.appendModelRow(rows)
  end
  if type(rows) ~= "table" then return rows end
  for _, row in ipairs(rows) do
    if type(row) == "table" and (row.stadium2Shared == true
        or row.label == "STADIUM 2 MODELS") then
      return rows
    end
  end
  local row = Bridge.modelRow()
  if row then rows[#rows + 1] = row end
  return rows
end

function Bridge.install(mod, cache, dramatic, options)
  options = type(options) == "table" and options or {}
  if options.count == nil then options.count = Bridge.COUNT end
  if options.ownerId == nil then options.ownerId = Bridge.OWNER_ID end
  if options.ownerName == nil then options.ownerName = Bridge.OWNER_NAME end
  if options.cache == nil then options.cache = cache end
  Bridge.configure(options)

  local exports = dramatic and dramatic.exports
  local V = exports and exports.lib
  if not (V and V.require and V.mod) then return false end

  local shared = V._pokemonStadium2Bridge
  if shared and shared ~= Bridge then
    delegatedBridge = shared
    shared.configure(options)
    local active = shared.install(mod, cache, dramatic, options)
    return active or shared
  end

  if installedFor == V then return Bridge end
  V._pokemonStadium2Bridge = Bridge
  local ok, result = pcall(function()
    local Pack = patchPack(V)
    patchModels(V, Pack)
    local Install = patchInstall(V, Pack)
    local Picker = patchPicker(V, Install)
    labelStadium2(V)
    selectionV, selectionInstall, selectionPicker = V, Install, Picker
    Picker.ID = tostring(Bridge.OWNER_ID) .. ":stadium2Rom"
    return true
  end)
  if not ok then
    if V._pokemonStadium2Bridge == Bridge then V._pokemonStadium2Bridge = nil end
    if mod and mod.log then
      mod.log:warn("Stadium 2 compatibility was not installed by %s: %s",
        tostring(Bridge.OWNER_NAME), tostring(result))
    end
    return false
  end
  installedFor = V
  if mod and mod.log then
    mod.log:info("DRAMATIC_SHAPE will use Pokemon Stadium 2 models for Pokemon 1-%d (%s)",
      Bridge.COUNT, tostring(Bridge.OWNER_NAME))
  end
  return Bridge
end

Bridge._test = {
  u16be = u16be,
  u32be = u32be,
  archiveAt = archiveAt,
  archiveNear = archiveNear,
  archivesInPayload = archivesInPayload,
  decodedPayload = decodedPayload,
  collectPosePayload = collectPosePayload,
  poseSourcesForRecord = poseSourcesForRecord,
  MODEL_TABLE_START = MODEL_TABLE_START,
  POSE_TABLE_START = POSE_TABLE_START,
  POSE_TABLE_END = POSE_TABLE_END,
  findRootPair = findRootPair,
  fragmentInfo = fragmentInfo,
  fragmentSpecies = fragmentSpecies,
  fragmentParser = fragmentParser,
  mappedSpecies = mappedSpecies,
  candidateLooksLikeSpeciesArchive = candidateLooksLikeSpeciesArchive,
  decodeAnimationSources = decodeAnimationSources,
  recolourRgba = recolourRgba,
  isShiny = isShiny,
  romTitle = romTitle,
  n64Title = n64Title,
  genericAnimationTable = genericAnimationTable,
  fallbackTexture = fallbackTexture,
  normaliseDrawableModel = normaliseDrawableModel,
  modelValue = modelValue,
  modelsSelected = modelsSelected,
  selectModels = selectModels,
  labelStadium2 = labelStadium2,
}

return Bridge
