package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end
local function ok(value, message)
  checks = checks + 1
  if not value then fail(message) end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    fail(("%s (got %s, want %s)"):format(message, tostring(got), tostring(want)))
  end
end
local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local value = file:read("*a")
  file:close()
  return value
end

local Bridge = require("mods.CRYSTAL_251.lib.stadium2_bridge")
local T = Bridge._test

eq(Bridge.COUNT, 251, "Stadium 2 bridge covers the full Crystal dex")
eq(Bridge.FORMAT, "C2DSM10",
  "Stadium 2 cache invalidates one-frame synthetic faint packs")
eq(Bridge.US_MD5, "1561c75d11cedf356a8ddb1a4a5f9d5d",
  "Stadium 2 importer identifies the supported US ROM")
-- Keep the title exactly twenty bytes, matching the N64 header field.
local z64Header = "\128\055\018\064" .. string.rep("\0", 0x1C)
  .. string.format("%-20s", "POKEMON STADIUM 2")
local v64Header = z64Header:gsub("(.)(.)", "%2%1")
local n64Header = z64Header:gsub("(.)(.)(.)(.)", "%4%3%2%1")
eq(T.n64Title(z64Header), "POKEMON STADIUM 2",
  "z64 Stadium 2 header is identified without loading the whole ROM")
eq(T.n64Title(v64Header), "POKEMON STADIUM 2",
  "v64 Stadium 2 header is identified")
eq(T.n64Title(n64Header), "POKEMON STADIUM 2",
  "n64 Stadium 2 header is identified")
ok(Bridge.NORMAL_DIR ~= Bridge.SHINY_DIR,
  "normal and shiny Stadium 2 packs use different directories")

local function be32(value)
  local d = value % 256
  value = math.floor(value / 256)
  local c = value % 256
  value = math.floor(value / 256)
  local b = value % 256
  value = math.floor(value / 256)
  local a = value % 256
  return string.char(a, b, c, d)
end

local count = 251
local tableEnd = 0x10 + count * 0x10
local archiveParts = { string.char(0, 0, 0, 1), be32(0),
  be32(tableEnd + count), be32(count) }
for index = 0, count - 1 do
  archiveParts[#archiveParts + 1] = be32(tableEnd + index)
  archiveParts[#archiveParts + 1] = be32(1)
  archiveParts[#archiveParts + 1] = be32(0)
  archiveParts[#archiveParts + 1] = be32(0)
end
archiveParts[#archiveParts + 1] = string.rep("X", count)
local archive = T.archiveAt(table.concat(archiveParts), 0)
eq(archive and archive.count, 251, "generic Stadium archive directory is decoded")
eq(archive and archive.records[251].size, 1,
  "last Stadium archive record remains in bounds")

local smallCount = 3
local smallTableEnd = 0x10 + smallCount * 0x10
local smallParts = { string.char(0, 0, 0, 2), be32(0),
  be32(smallTableEnd + smallCount), be32(smallCount) }
for index = 0, smallCount - 1 do
  smallParts[#smallParts + 1] = be32(smallTableEnd + index)
  smallParts[#smallParts + 1] = be32(1)
  smallParts[#smallParts + 1] = be32(0)
  smallParts[#smallParts + 1] = be32(0)
end
smallParts[#smallParts + 1] = "ABC"
local smallArchive = T.archiveAt(table.concat(smallParts), 0)
eq(smallArchive and smallArchive.count, 3,
  "small Stadium 2 motion archives are no longer discarded")

local function mutable(size)
  local bytes = {}
  for index = 1, size do bytes[index] = 0 end
  return bytes
end
local function put(bytes, offset, value)
  for index = 1, #value do bytes[offset + index] = value:byte(index) end
end
local function put16(bytes, offset, value)
  put(bytes, offset, string.char(math.floor(value / 256) % 256, value % 256))
end
local function put32(bytes, offset, value)
  put(bytes, offset, be32(value))
end
local function freeze(bytes)
  local out = {}
  for index = 1, #bytes do out[index] = string.char(bytes[index]) end
  return table.concat(out)
end

local sourceBase = 0x83500000
local rootOffset = 0x80
local rootAddress = sourceBase + rootOffset
local high = math.floor((rootAddress + 0x8000) / 0x10000) % 0x10000
local low = rootAddress % 0x10000
local fragmentBytes = mutable(0xC0)
put(fragmentBytes, 8, "FRAGMENT")
put32(fragmentBytes, 0x20, 0x3C080000 + high)
put32(fragmentBytes, 0x24, 0x25080000 + low)
put16(fragmentBytes, rootOffset, 152)
put32(fragmentBytes, rootOffset + 8, sourceBase + 0xA0)
local fragment = freeze(fragmentBytes)
local fragmentInfo = T.fragmentInfo(fragment)
ok(type(fragmentInfo) == "table",
  "Stadium 2 fragment link information is decoded")
eq(fragmentInfo and fragmentInfo.sourceBase, sourceBase,
  "fragment source base is inferred from its MIPS root stub")
eq(T.fragmentSpecies(fragment), 152,
  "prelinked Stadium 2 fragment retains its National Dex species")
eq(T.u32be(fragment, rootOffset + 8), sourceBase + 0xA0,
  "fragment bytes are not globally rewritten or allowed to corrupt texture data")

local normal = {
  { 248, 248, 248 }, { 240, 64, 32 }, { 128, 32, 16 }, { 0, 0, 0 },
}
local shiny = {
  { 248, 248, 248 }, { 48, 128, 240 }, { 24, 64, 144 }, { 0, 0, 0 },
}
local rgba = string.char(240, 64, 32, 255, 128, 32, 16, 200, 9, 8, 7, 0)
local recoloured = T.recolourRgba(rgba, normal, shiny)
eq(#recoloured, #rgba, "shiny recolouring preserves texture byte length")
ok(recoloured:sub(1, 3) ~= rgba:sub(1, 3),
  "opaque Stadium texture colours change for a shiny Pokemon")
eq(recoloured:byte(4), 255, "opaque texture alpha is preserved")
eq(recoloured:sub(9, 12), rgba:sub(9, 12),
  "fully transparent Stadium texels are untouched")

ok(T.isShiny({ dvs={ attack=10, defense=10, speed=10, special=10 } }),
  "Crystal shiny DVs select the shiny Stadium 2 pack")
ok(not T.isShiny({ dvs={ attack=9, defense=10, speed=10, special=10 } }),
  "non-shiny DVs select the normal Stadium 2 pack")

local fakeAnimations = { anims = { {}, {}, {}, {} } }
local fakeBuild = { CONTEXTS = {} }
for index = 1, 20 do fakeBuild.CONTEXTS[index] = "slot" .. index end
local rows, contexts = T.genericAnimationTable(fakeAnimations, fakeBuild)
eq(#rows, 165, "all move ids receive a safe Stadium 2 animation mapping")
eq(contexts[1], 0, "first Stadium 2 animation is the idle context")
eq(contexts[2], 1, "second Stadium 2 animation is the default attack")
eq(contexts[3], 2, "safe third Stadium 2 bank remains the real faint context")
eq(contexts[13], 2, "alternate faint context keeps the real faint animation")
eq(contexts[4], 3, "fourth Stadium 2 animation is the entrance context")
eq(fakeAnimations.anims[3].name, "faint",
  "third decoded Stadium 2 bank keeps its faint role when pose data is sane")
ok(not fakeAnimations.stadium2FaintRejected,
  "faint bank is not rejected without evidence of an explosive pose")

local geometryOnly = { anims = {} }
local staticRows, staticContexts = T.genericAnimationTable(geometryOnly, fakeBuild)
eq(#geometryOnly.anims, 1,
  "geometry-only Stadium 2 fragments receive one bind-pose animation")
eq(geometryOnly.anims[1].frames, 1,
  "synthetic Stadium 2 bind-pose animation is one frame")
ok(geometryOnly.anims[1].syntheticBindPose,
  "synthetic animation is identifiable as the Stadium 2 fallback")
eq(staticRows[1][1], 0,
  "moves safely resolve to the bind-pose fallback")
eq(staticContexts[1], 0,
  "idle context resolves to the bind-pose fallback")
eq(staticContexts[3], 0,
  "geometry-only faint context falls back to the only available pose")

-- The faint guard distinguishes legitimate whole-body travel from an actual
-- skeleton explosion. Translation shared by every bone must not be rejected;
-- one bone separating or scaling many times beyond the bind skeleton must.
local poseBuild = {}
function poseBuild.animSample(bones, animation, frame)
  return function(index)
    local row = animation.framesData and animation.framesData[frame + 1]
    local x = row and row[index] or bones[index].x or 0
    local scale = row and row.scale and row.scale[index] or 1
    return { x, 0, 0 }, { 0, 0, 0 }, { scale, scale, scale }
  end
end
function poseBuild.bindMatrices(bones, sample)
  local out = {}
  for index, bone in ipairs(bones) do
    local t, _, scale
    if sample then
      t, _, scale = sample(index)
    else
      t, scale = { bone.x or 0, 0, 0 }, { 1, 1, 1 }
    end
    out[index] = {
      { scale[1], 0, 0, t[1] },
      { 0, scale[2], 0, t[2] },
      { 0, 0, scale[3], t[3] },
    }
  end
  return out
end
local poseData = { bones={ {x=0}, {x=1} } }
local travellingFaint = {
  frames=2,
  framesData={ { [1]=0, [2]=1 }, { [1]=100, [2]=101 } },
}
ok(not T.animationLooksExplosive(poseData, travellingFaint, poseBuild),
  "whole-body faint travel does not look like a skeleton explosion")
local separatedFaint = {
  frames=2,
  framesData={ { [1]=0, [2]=1 }, { [1]=0, [2]=20 } },
}
ok(T.animationLooksExplosive(poseData, separatedFaint, poseBuild),
  "a faint that separates bones eightfold is rejected")
local scaledFaint = {
  frames=2,
  framesData={
    { [1]=0, [2]=1, scale={ [1]=1, [2]=1 } },
    { [1]=0, [2]=1, scale={ [1]=1, [2]=12 } },
  },
}
ok(T.animationLooksExplosive(poseData, scaledFaint, poseBuild),
  "a faint with pathological accumulated bone scale is rejected")

local rejectedAnimations = {
  bones=poseData.bones,
  anims={
    { frames=2, framesData=travellingFaint.framesData },
    {},
    separatedFaint,
    {},
  },
}
local rejectedBuild = { CONTEXTS=fakeBuild.CONTEXTS,
  bindMatrices=poseBuild.bindMatrices, animSample=poseBuild.animSample }
local _, rejectedContexts = T.genericAnimationTable(rejectedAnimations, rejectedBuild)
eq(rejectedContexts[3], 0,
  "only an actually explosive faint falls back to the stable idle bank")
ok(rejectedAnimations.stadium2FaintRejected,
  "rejected faint is recorded in Stadium 2 pack diagnostics")
eq(rejectedAnimations.anims[3].name, "faint_rejected",
  "rejected faint bank remains identifiable for diagnostics")

local untextured = {
  bones = { { parent=-1 } },
  prims = { { tex=-1, texAnim=3, texMap={ [0]=7 }, nverts=3, nidx=3 } },
  textures = {},
  fx = {},
}
local drawable, drawableInfo = T.normaliseDrawableModel(untextured, 219,
  { attach=function() return 0 end })
ok(drawable, "Stadium 2 geometry without a texture is retained")
eq(#untextured.textures, 1,
  "one generated material is added for an untextured Stadium 2 model")
eq(untextured.prims[1].tex, 0,
  "untextured primitive points at the generated zero-based texture")
eq(untextured.prims[1].texAnim, -1,
  "invalid texture animation is removed from the fallback material")
ok(untextured.textures[1].stadium2Fallback,
  "generated untextured material is identifiable in diagnostics")
eq(drawableInfo and drawableInfo.fallbackTexture, 0,
  "drawable normalisation reports the generated texture index")

local procedural = { bones={{ parent=-1 }}, prims={}, textures={}, fx={{ callback=1 }} }
local attachRan = false
local proceduralOk = T.normaliseDrawableModel(procedural, 92, {
  attach=function(model)
    attachRan = true
    model.textures[1] = { w=1, h=1, rgba=string.char(255,255,255,255) }
    model.prims[1] = { tex=0, nverts=3, nidx=3 }
    return 1
  end,
})
ok(attachRan and proceduralOk,
  "procedural Stadium effects attach before drawable validation")

local emptyOk, emptyErr = T.normaliseDrawableModel(
  { bones={{ parent=-1 }}, prims={}, textures={}, fx={{ callback=0x81234567 }} },
  219, { attach=function() return 0 end })
ok(not emptyOk and emptyErr:find("species 219", 1, true) ~= nil,
  "truly empty Stadium 2 models still fail with their species number")
ok(emptyErr:find("bones=1 prims=0 textures=0", 1, true) ~= nil,
  "drawable failure reports exact geometry counts")
ok(emptyErr:find("0x81234567", 1, true) ~= nil,
  "drawable failure reports unresolved effect callbacks")

-- Either mod supplies the same lib/StadiumPack.lua and lib/StadiumFragment.lua;
-- try DRAMATIC_SHAPE first and fall back to DRAMALESS_SHAPE. Users are
-- expected to have exactly one of the two installed.
local DRAMATIC_DIR = "mods/DRAMATIC_SHAPE"
local DRAMALESS_DIR = "mods/DRAMALESS_SHAPE"

local dramaticDir = DRAMATIC_DIR
local stadiumPackSource = read(DRAMATIC_DIR .. "/lib/StadiumPack.lua")
if not stadiumPackSource then
  dramaticDir = DRAMALESS_DIR
  stadiumPackSource = read(DRAMALESS_DIR .. "/lib/StadiumPack.lua")
end
assert(stadiumPackSource,
  "StadiumPack.lua not found under " .. DRAMATIC_DIR .. " or " .. DRAMALESS_DIR)

local stadiumFragmentSource = read(dramaticDir .. "/lib/StadiumFragment.lua")
assert(stadiumFragmentSource,
  "StadiumFragment.lua not found under " .. dramaticDir)
local modules = {
  StadiumPack = {
    SLOT = { idle=1, attack_default=2, faint=3, entrance=4 },
    NONE = 0xFFFF,
    keep = function() end,
    forget = function() end,
    invalidate = function() end,
  },
  Stadium = {
    update = function(_, battle)
      if battle and battle.testMon then
        battle.testMon:setSpecies(battle.testDex)
        battle._stadiumSawSendingOut = battle.sendingOut
        battle._stadiumSawEnemySendingOut = battle.enemySendingOut
      end
      return "updated"
    end,
  },
  StadiumMon = {
    FPS = 30,
    play = function(self, state, animIndex, auxIndex)
      self.state = state
      self.anim = animIndex or self.anim or 1
      self.aux = auxIndex or self.aux
      self.time = 0
      return true
    end,
    request = function(self, state, animIndex, auxIndex)
      self.baseRequestCalls = (self.baseRequestCalls or 0) + 1
      return self:play(state, animIndex, auxIndex)
    end,
    beginGrow = function(self)
      if self.grow then return false end
      self.grow = 0
      self.grewOwn = true
      self.beginGrowCalls = (self.beginGrowCalls or 0) + 1
      return true
    end,
    update = function(self, dt)
      self.baseUpdateCalls = (self.baseUpdateCalls or 0) + 1
      self.baseUpdateDt = dt
      return true
    end,
    finished = function(self) return self.done and true or false end,
    matrix = function(self, x, y, z)
      return { x=x, y=y, z=z, scale=self.scale }
    end,
    worldHeight = function() return 10 end,
    build = function(self)
      self.baseBuildCalls = (self.baseBuildCalls or 0) + 1
      self.baseBuildDt = self.dt
      return true
    end,
  },
  StadiumRig = { new = function() return nil end },
  StadiumInstall = {},
  StadiumRom = {
    normalise = function(value) return value end,
    decompress = function(value) return value end,
  },
  StadiumBuild = { CONTEXTS = fakeBuild.CONTEXTS, pack = function() return "DSM3" end },
  StadiumFragment = { extract = function() return nil, "unused" end },
  StadiumFx = { attach = function() end },
  StadiumRomPick = {},
  StadiumScreen = {
    new = function() return {} end,
    newNote = function() return {} end,
  },
}
local loggedError
local fakeLog = {
  info=function() end,
  warn=function() end,
  error=function(_, _, message) loggedError = message end,
}
local fakeDramaticMod = { log=fakeLog }
function fakeDramaticMod:read(path)
  if path == "lib/StadiumPack.lua" then return stadiumPackSource end
  if path == "lib/StadiumFragment.lua" then return stadiumFragmentSource end
  return nil
end
local fakeV = { mod=fakeDramaticMod, path=dramaticDir }
function fakeV.require(name) return assert(modules[name], name) end
local linkedParser = T.fragmentParser(fakeV, sourceBase)
ok(type(linkedParser) == "table" and type(linkedParser.extract) == "function",
  dramaticDir .. "'s fragment reader is cloned for Stadium 2's link base")
ok(type(linkedParser.inspect) == "function"
    and type(linkedParser.extractAnimations) == "function"
    and type(linkedParser.inspectAny) == "function"
    and type(linkedParser.extractAnimationsAny) == "function"
    and type(linkedParser.inspectRawAnimations) == "function"
    and type(linkedParser.extractRawAnimations) == "function",
  "cloned reader exposes FRAGMENT and raw pose-record decoding")

-- A minimal animation-only Stadium 2 FRAGMENT. It has no geometry pointer,
-- one skeletal-animation pointer, one frame, and one bone channel (three
-- component records). Translation constants 1/2/3 prove the separate bank is
-- sampled against the geometry fragment's already extracted skeleton.
local animBytes = mutable(0x120)
put(animBytes, 8, "FRAGMENT")
put32(animBytes, 0x20, 0x3C080000 + high)
put32(animBytes, 0x24, 0x25080000 + low)
put16(animBytes, rootOffset, 152)
put32(animBytes, rootOffset + 0x0C, sourceBase + 0xA0)
put32(animBytes, 0xA0, sourceBase + 0xB0)
put32(animBytes, 0xA4, 0)
put16(animBytes, 0xB0 + 4, 0)
put16(animBytes, 0xB0 + 6, 0)
put16(animBytes, 0xB0 + 8, 3)
put16(animBytes, 0xB0 + 0xA, 1)
put32(animBytes, 0xB0 + 0xC, sourceBase + 0xD0)
for axis = 0, 2 do
  local channel = 0xD0 + axis * 0xA
  put(animBytes, channel, string.char(1, 1, 1, 0))
  put16(animBytes, channel + 4, 1000)
  put16(animBytes, channel + 6, 0)
  put16(animBytes, channel + 8, axis + 1)
end
local animationFragment = freeze(animBytes)
local animationSummary, animationSummaryErr = linkedParser.inspect(
  animationFragment, "animation_only.bin")
ok(animationSummary ~= nil, animationSummaryErr or
  "animation-only Stadium 2 fragment is inspectable")
eq(animationSummary and animationSummary.geometry, 0,
  "animation-only fragment does not pretend to contain geometry")
eq(animationSummary and animationSummary.animations, 1,
  "animation-only fragment exposes its skeletal bank")
local animationBank, animationBankErr = linkedParser.extractAnimations(
  animationFragment, {
    { parent=-1, chan=0, t={0,0,0}, r={0,0,0}, s={1,1,1} },
  }, "animation_only.bin")
ok(animationBank ~= nil, animationBankErr or
  "separate Stadium 2 animation bank decodes")
eq(animationBank and #animationBank.anims, 1,
  "one real Stadium 2 animation is returned")
eq(animationBank and animationBank.anims[1].frames, 1,
  "decoded Stadium 2 animation retains its frame count")
eq(animationBank and animationBank.anims[1].tracks[1].t[1], 1,
  "separate animation bank drives bone X translation")
eq(animationBank and animationBank.anims[1].tracks[1].t[2], 2,
  "separate animation bank drives bone Y translation")
eq(animationBank and animationBank.anims[1].tracks[1].t[3], 3,
  "separate animation bank drives bone Z translation")
eq(T.mappedSpecies({ species=0, animations=1 }, 152, 251), 152,
  "full animation archives without a repeated species id use National Dex file order")
eq(T.mappedSpecies({ species=0, animations=1 }, 1, 3), nil,
  "small motion archives cannot accidentally map every file one to Bulbasaur")

-- Stadium 2 can point the FRAGMENT root directly at a skeletal animation
-- header instead of wrapping it in the Stadium 1 model root. This is the shape
-- that 0045g could not recognise in the real cartridge.
local rawAnimBytes = mutable(0xD0)
put(rawAnimBytes, 8, "FRAGMENT")
put32(rawAnimBytes, 0x20, 0x3C080000 + high)
put32(rawAnimBytes, 0x24, 0x25080000 + low)
put16(rawAnimBytes, rootOffset + 4, 0)
put16(rawAnimBytes, rootOffset + 6, 0)
put16(rawAnimBytes, rootOffset + 8, 3)
put16(rawAnimBytes, rootOffset + 0xA, 1)
put32(rawAnimBytes, rootOffset + 0xC, sourceBase + 0xA0)
for axis = 0, 2 do
  local channel = 0xA0 + axis * 0xA
  put(rawAnimBytes, channel, string.char(1, 1, 1, 0))
  put16(rawAnimBytes, channel + 4, 1000)
  put16(rawAnimBytes, channel + 6, 0)
  put16(rawAnimBytes, channel + 8, axis + 4)
end
local rawAnimationFragment = freeze(rawAnimBytes)
local rawSummary, rawSummaryErr = linkedParser.inspectAny(
  rawAnimationFragment, "raw_animation_root.bin")
ok(rawSummary ~= nil, rawSummaryErr or
  "raw-root Stadium 2 motion fragment is recognised")
eq(rawSummary and rawSummary.rootKind, "raw-motion",
  "raw animation header is not misclassified as a model root")
eq(rawSummary and rawSummary.animations, 1,
  "raw-root fragment reports one skeletal clip")
local rawBank, rawBankErr = linkedParser.extractAnimationsAny(
  rawAnimationFragment, {
    { parent=-1, chan=0, t={0,0,0}, r={0,0,0}, s={1,1,1} },
  }, "raw_animation_root.bin")
ok(rawBank ~= nil, rawBankErr or
  "raw-root Stadium 2 skeletal clip decodes")
eq(rawBank and #rawBank.anims, 1,
  "raw-root motion bank returns one animation")
eq(rawBank and rawBank.anims[1].tracks[1].t[1], 4,
  "raw-root motion bank drives the imported skeleton")

-- The real Stadium 2 pose-table children are not FRAGMENT modules. They are
-- relocatable raw animation blobs. Verify both direct file offsets and the
-- absolute prelinked pointer form used by the asset loader.
local rawPoseBytes = mutable(0x50)
put16(rawPoseBytes, 4, 0)
put16(rawPoseBytes, 6, 0)
put16(rawPoseBytes, 8, 3)
put16(rawPoseBytes, 0xA, 1)
put32(rawPoseBytes, 0xC, 0x20)
for axis = 0, 2 do
  local channel = 0x20 + axis * 0xA
  put(rawPoseBytes, channel, string.char(1, 1, 1, 0))
  put16(rawPoseBytes, channel + 4, 1000)
  put16(rawPoseBytes, channel + 6, 0)
  put16(rawPoseBytes, channel + 8, axis + 10)
end
local rawPose = freeze(rawPoseBytes)
local rawPoseSummary, rawPoseSummaryErr = linkedParser.inspectRawAnimations(
  rawPose, "raw_pose_direct.bin")
ok(rawPoseSummary ~= nil, rawPoseSummaryErr or
  "raw Stadium 2 pose record is recognised without a FRAGMENT wrapper")
eq(rawPoseSummary and rawPoseSummary.rootKind, "raw-pose",
  "raw pose record is classified separately from a model module")
eq(rawPoseSummary and rawPoseSummary.animations, 1,
  "one raw pose header is discovered")
local rawPoseBank, rawPoseErr = linkedParser.extractRawAnimations(rawPose, {
  { parent=-1, chan=0, t={0,0,0}, r={0,0,0}, s={1,1,1} },
}, "raw_pose_direct.bin")
ok(rawPoseBank ~= nil, rawPoseErr or
  "raw Stadium 2 pose record decodes against the imported skeleton")
eq(rawPoseBank and #rawPoseBank.anims, 1,
  "raw pose record returns one skeletal clip")
eq(rawPoseBank and rawPoseBank.anims[1].tracks[1].t[1], 10,
  "raw pose record drives bone translation")
ok(rawPoseBank and rawPoseBank.anims[1].rawPose,
  "raw pose animations retain their source kind")

-- Real Stadium 2 pose children put their animation header at the end of the
-- record and store its file-relative offset in word zero. The transform arrays
-- and channel table precede that footer. This is the layout observed in every
-- sampled Bulbasaur, Pikachu, Chikorita, Magcargo, and Celebi pose record.
local footerPoseBytes = mutable(0x6C)
put32(footerPoseBytes, 0, 0x50)
for valueIndex, value in ipairs({1000,1100,1000,1200,1000,1300}) do
  put16(footerPoseBytes, 2 + valueIndex * 2, value)
end
for axis = 0, 2 do
  local channel = 0x20 + axis * 0xA
  put(footerPoseBytes, channel, string.char(2, 1, 1, 0))
  put16(footerPoseBytes, channel + 4, axis * 2)
  put16(footerPoseBytes, channel + 6, 0)
  put16(footerPoseBytes, channel + 8, axis + 20)
end
put(footerPoseBytes, 0x50 + 1, string.char(2)) -- Stadium 2 clip class byte
put16(footerPoseBytes, 0x50 + 4, 0)
put16(footerPoseBytes, 0x50 + 6, 0)
put16(footerPoseBytes, 0x50 + 8, 3)
put16(footerPoseBytes, 0x50 + 0xA, 2)
put32(footerPoseBytes, 0x50 + 0xC, 0x20)
put32(footerPoseBytes, 0x50 + 0x10, 0x04)
put32(footerPoseBytes, 0x50 + 0x14, 0x08)
put32(footerPoseBytes, 0x50 + 0x18, 0x10)
local footerPose = freeze(footerPoseBytes)
local footerSummary, footerSummaryErr = linkedParser.inspectRawAnimations(
  footerPose, "raw_pose_footer.bin")
ok(footerSummary ~= nil, footerSummaryErr or
  "footer-addressed Stadium 2 pose record is recognised")
eq(footerSummary and footerSummary.animations, 1,
  "footer pointer selects exactly one animation instead of sample false positives")
local footerBank, footerErr = linkedParser.extractRawAnimations(footerPose, {
  { parent=-1, chan=0, t={0,0,0}, r={0,0,0}, s={1,1,1} },
}, "raw_pose_footer.bin")
ok(footerBank ~= nil, footerErr or
  "footer-addressed Stadium 2 pose record decodes")
eq(footerBank and footerBank.anims[1].frames, 2,
  "footer animation retains its real frame count")
eq(footerBank and footerBank.anims[1].tracks[1].t[1], 20,
  "footer animation drives the imported skeleton")
ok(type(footerBank and footerBank.anims[1].tracks[1].s[1]) == "table",
  "footer animation reads changing scale samples stored before the header")

local absolutePoseBytes = mutable(0x50)
put16(absolutePoseBytes, 4, 0)
put16(absolutePoseBytes, 6, 0)
put16(absolutePoseBytes, 8, 3)
put16(absolutePoseBytes, 0xA, 1)
put32(absolutePoseBytes, 0xC, 0x83500020)
for axis = 0, 2 do
  local channel = 0x20 + axis * 0xA
  put(absolutePoseBytes, channel, string.char(1, 1, 1, 0))
  put16(absolutePoseBytes, channel + 4, 1000)
  put16(absolutePoseBytes, channel + 6, 0)
  put16(absolutePoseBytes, channel + 8, axis + 13)
end
local absolutePose = freeze(absolutePoseBytes)
local absoluteBank, absoluteErr = linkedParser.extractRawAnimations(
  absolutePose, {
    { parent=-1, chan=0, t={0,0,0}, r={0,0,0}, s={1,1,1} },
  }, "raw_pose_absolute.bin")
ok(absoluteBank ~= nil, absoluteErr or
  "prelinked raw Stadium 2 pose pointers are rebased per file")
eq(absoluteBank and absoluteBank.anims[1].tracks[1].t[1], 13,
  "absolute raw pose pointer resolves to the channel table")


-- Stadium 2 bone channel ids are sparse. A one-bone model can legitimately
-- reference channel group 20, which requires 63 component rows even though the
-- skeleton contains only one bone. 0045h rejected this with a #bones-derived
-- upper bound and therefore decoded only a minority of the real pose banks.
local sparseBytes = mutable(0x390)
put(sparseBytes, 8, "FRAGMENT")
put32(sparseBytes, 0x20, 0x3C080000 + high)
put32(sparseBytes, 0x24, 0x25080000 + low)
put16(sparseBytes, rootOffset + 4, 0)
put16(sparseBytes, rootOffset + 6, 0)
put16(sparseBytes, rootOffset + 8, 63)
put16(sparseBytes, rootOffset + 0xA, 1)
put32(sparseBytes, rootOffset + 0xC, sourceBase + 0x100)
for axis = 0, 2 do
  local channel = 0x100 + (60 + axis) * 0xA
  put(sparseBytes, channel, string.char(1, 1, 1, 0))
  put16(sparseBytes, channel + 4, 1000)
  put16(sparseBytes, channel + 6, 0)
  put16(sparseBytes, channel + 8, axis + 7)
end
local sparseFragment = freeze(sparseBytes)
local sparseBank, sparseErr = linkedParser.extractAnimationsAny(sparseFragment, {
  { parent=-1, chan=20, t={0,0,0}, r={0,0,0}, s={1,1,1} },
}, "sparse_animation_root.bin")
ok(sparseBank ~= nil, sparseErr or
  "sparse Stadium 2 channel ids decode against a small skeleton")
eq(sparseBank and #sparseBank.anims, 1,
  "sparse channel bank returns one real animation")
eq(sparseBank and sparseBank.anims[1].tracks[1].t[1], 7,
  "sparse channel group drives the matching bone")

local function makeArchive(blobs, tag)
  local n = #blobs
  local headerSize = 0x10 + n * 0x10
  local total = headerSize
  for _, blob in ipairs(blobs) do total = total + #blob end
  local parts = { string.char(0, 0, 0, tag or 3), be32(0), be32(total), be32(n) }
  local relative = headerSize
  for _, blob in ipairs(blobs) do
    parts[#parts + 1] = be32(relative)
    parts[#parts + 1] = be32(#blob)
    parts[#parts + 1] = be32(0)
    parts[#parts + 1] = be32(0)
    relative = relative + #blob
  end
  for _, blob in ipairs(blobs) do parts[#parts + 1] = blob end
  return table.concat(parts)
end

-- The cartridge's Pokemon pose table is an archive of per-species bundles;
-- the files inside are raw relocatable pose records rather than FRAGMENT
-- modules. Verify that recursion retains and decodes those raw children.
local nestedPose = makeArchive({ rawPose }, 4)
local poseSources, poseErrors, poseStats = T.poseSourcesForRecord(nestedPose,
  { start=0, size=#nestedPose }, { V=fakeV, StadiumRom=modules.StadiumRom },
  "pose-table-test")
eq(#poseSources, 1,
  "nested Stadium 2 pose bundle exposes its raw animation record")
eq(poseStats and poseStats.archives, 1,
  "nested Stadium 2 pose archive is counted")
local nestedAnimations, _, nestedErrors = T.decodeAnimationSources("",
  poseSources, {
    { parent=-1, chan=0, t={0,0,0}, r={0,0,0}, s={1,1,1} },
  }, { V=fakeV, StadiumRom=modules.StadiumRom })
eq(#nestedAnimations, 1,
  "raw animation extracted from a nested pose bundle drives the model skeleton")
eq(#nestedErrors, 0,
  "valid nested pose bundle produces no decode errors")
local fakeCrystalMod = { log=fakeLog }
local cache = { species = {
  { dex=1, paletteColors=normal, shinyPaletteColors=shiny },
} }

-- Gen1Recomp's trainer AI switch path omits the normal enemy replacement
-- grow. Crystal supplies ONLY the engine's 12-frame grow state for both staged
-- modes. Stadium's skeletal entrance is then requested directly on the actual
-- incoming rig, rather than going through the globally wrapped startGrowIn
-- seam and risking contamination of later model/move animations.
local savedBattleStateModule = package.loaded["src.battle.BattleState"]
local fakeBattleState = {}
function fakeBattleState:sayNext(text)
  self.queue[#self.queue + 1] = { text=text }
end
function fakeBattleState:actNext(fn)
  self.queue[#self.queue + 1] = { fn=fn }
end
function fakeBattleState:startGrowIn(battler)
  self.growCalls = (self.growCalls or 0) + 1
  self.grownBattler = battler
end
function fakeBattleState:executeAction(_, _, action)
  if action and action.special == "aiSwitch" then
    self.enemy = assert(self.nextEnemy, "test incoming enemy")
    self:sayNext("trainer withdrew")
    self:sayNext("trainer sent out")
    return "switched"
  end
  return "ordinary"
end
package.loaded["src.battle.BattleState"] = fakeBattleState

local battleModelSetting = "stadium"
modules.OverworldBattle = {
  setting = {
    values = { true, "flatB", "stadium", "stadiumB", false },
    labels = { "2D-3D A", "2D-3D B", "STADIUM", "STADIUM B", "OFF" },
    get = function() return battleModelSetting end,
  },
}

ok(Bridge.install(fakeCrystalMod, cache, { exports={ lib=fakeV } }),
  "bridge installs through " .. dramaticDir .. "'s exported module namespace")

-- Stadium 2 models leave through a matching ball-in transition. A battler
-- identity change keeps the outgoing rig alive while it contracts, including
-- same-species replacements, and the engine's sendingOut flag is only hidden
-- from Stadium.update -- it is restored before the normal battle draw.
local recallOldBattler = { mon={ dvs={ attack=9, defense=8, speed=8, special=8 } } }
local recallNewBattler = { mon={ dvs={ attack=9, defense=8, speed=8, special=8 } } }
local recallRig = { releases=0 }
function recallRig:release() self.releases = self.releases + 1 end
local recallMon = setmetatable({
  side="player", species=1, _crystal251Variant="normal",
  _crystal251Battler=recallOldBattler,
  rig=recallRig, model={ anims={ { frames=2 } } }, scale=1,
}, { __index=modules.StadiumMon })
local recallBattle = {
  player=recallNewBattler, enemy={ mon={} }, sendingOut=true,
  testMon=recallMon, testDex=1,
}
eq(modules.Stadium.update(0, recallBattle, 0), "updated",
  "Stadium update preserves its wrapped return value during recall")
ok(recallMon._crystal251Recall ~= nil,
  "same-species battler replacement starts Stadium ball-in recall")
eq(recallMon.species, 1,
  "outgoing Stadium model stays loaded while recall is running")
ok(recallBattle._stadiumSawSendingOut == false,
  "Stadium sees outgoing player model while it is being recalled")
ok(recallBattle.sendingOut == true,
  "engine player sendingOut flag is restored after Stadium update")
recallMon:update(0.20)
ok(recallMon.scale > 0 and recallMon.scale < 1,
  "Stadium ball-in recall contracts smoothly instead of popping out")
local recallMatrix = recallMon:matrix(1, 2, 3)
ok(recallMatrix.y > 2,
  "recalling model converges upward toward its ball point")
recallMon:update(0.25)
eq(recallMon.scale, 0,
  "Stadium ball-in reaches zero scale after its recall duration")

-- Real 2D-3D A is stored as boolean true. It must bypass every Stadium-only
-- recall/model state while retaining the engine's own billboard animation.
battleModelSetting = true
local flatOldBattler = { mon={ dvs={ attack=9, defense=8, speed=8, special=8 } } }
local flatNewBattler = { mon={ dvs={ attack=9, defense=8, speed=8, special=8 } } }
local flatRig = { releases=0 }
function flatRig:release() self.releases = self.releases + 1 end
local flatMon = setmetatable({
  side="player", species=1, _crystal251Variant="normal",
  _crystal251Battler=flatOldBattler,
  rig=flatRig, model={ anims={ { frames=2 } } }, scale=1,
}, { __index=modules.StadiumMon })
local flatRecallBattle = {
  player=flatNewBattler, enemy={ mon={} }, sendingOut=true,
  testMon=flatMon, testDex=1,
}
eq(modules.Stadium.update(0, flatRecallBattle, 0), "updated",
  "2D-3D A update preserves the wrapped Stadium return value")
ok(flatRecallBattle._stadiumSawSendingOut == true,
  "2D-3D A sees the engine sendingOut flag without Stadium suppression")
ok(flatMon._crystal251Recall == nil,
  "2D-3D A same-species replacement never starts Stadium recall")
eq(flatMon.scale, 1,
  "2D-3D A replacement does not inherit Stadium shrink scale")
eq(flatMon._crystal251Battler, flatNewBattler,
  "2D-3D A keeps Stadium battler identity synchronized for later mode changes")
flatMon.done = true
ok(flatMon:finished(),
  "2D-3D A finished state is delegated directly to the original model helper")

battleModelSetting = "flatB"
flatMon._crystal251Battler = flatOldBattler
flatRecallBattle.player = flatNewBattler
eq(modules.Stadium.update(0, flatRecallBattle, 0), "updated",
  "2D-3D B update preserves the wrapped Stadium return value")
ok(flatMon._crystal251Recall == nil,
  "2D-3D B also bypasses Stadium recall state")

battleModelSetting = "stadium"

-- A faint gets its full collapse first. Only after StadiumMon reports that
-- held animation finished does the same ball-in run; onField therefore keeps
-- the model visible until the recall itself completes.
local faintMon = setmetatable({
  side="enemy", species=1, _crystal251Variant="normal",
  rig={}, model={ anims={ { frames=2 } } },
  state="faint", done=true, scale=1,
}, { __index=modules.StadiumMon })
ok(not faintMon:finished(),
  "finished Stadium faint starts recall instead of disappearing immediately")
eq(faintMon._crystal251Recall and faintMon._crystal251Recall.reason, "faint",
  "faint exit is identified as a Stadium recall")
faintMon:update(0.41)
ok(faintMon:finished(),
  "Stadium faint becomes removable only after ball-in finishes")
eq(faintMon.scale, 0,
  "completed faint recall has fully contracted the model")

local outgoingEnemy = { mon={ hp=20 } }
local incomingEnemy = { mon={ hp=30 } }
local switchBattle = setmetatable({
  crystal251Active=true, enemy=outgoingEnemy, nextEnemy=incomingEnemy, queue={},
}, { __index=fakeBattleState })
eq(switchBattle:executeAction(nil, nil, { special="aiSwitch" }), "switched",
  "Stadium AI switch preserves the engine action result")
ok(switchBattle.enemySendingOut,
  "Stadium AI switch hides the incoming enemy through its send-out text")
eq(#switchBattle.queue, 3,
  "Stadium AI switch queues one arrival action after the two engine messages")
eq(switchBattle.queue[1].text, "trainer withdrew",
  "withdraw text remains ahead of the Stadium arrival")
eq(switchBattle.queue[2].text, "trainer sent out",
  "send-out text remains ahead of the Stadium arrival")
local stadiumArrival = switchBattle.queue[3].fn
ok(type(stadiumArrival) == "function",
  "Stadium AI switch queues an isolated arrival action")
ok(not switchBattle.growCalls,
  "Stadium AI switch does not call the shared startGrowIn hook early")

-- Execute the queued action as BattleState.updateQueue does: the current fn is
-- already removed and nextInsert is reset to zero.
switchBattle.queue = {}
switchBattle.nextInsert = 0
stadiumArrival()
ok(not switchBattle.enemySendingOut,
  "Stadium enemy becomes visible when its arrival begins")
ok(not switchBattle.growCalls,
  "AI arrival never enters the globally wrapped startGrowIn hook")
eq(switchBattle.growIn and switchBattle.growIn.battler, incomingEnemy,
  "Stadium AI switch still installs the engine 12-frame grow state")
eq(switchBattle.queue[1] and switchBattle.queue[1].wait, 12,
  "Stadium AI switch keeps the engine grow hold")
eq(switchBattle._crystal251StadiumEntrancePending, incomingEnemy,
  "Stadium AI switch defers the skeletal entrance to the incoming rig")

-- The next Stadium update consumes that token on the ACTUAL replacement rig.
local arrivalRig = { release=function() end }
local arrivalMon = setmetatable({
  side="enemy", species=1, _crystal251Variant="normal",
  _crystal251Battler=incomingEnemy,
  rig=arrivalRig, model={ anims={ {}, {} } }, scale=1,
}, { __index=modules.StadiumMon })
switchBattle.testMon = arrivalMon
switchBattle.testDex = 1
eq(modules.Stadium.update(0, switchBattle, 0), "updated",
  "Stadium update consumes the queued model entrance on the replacement rig")
eq(arrivalMon.beginGrowCalls, 1,
  "replacement Stadium rig starts its smooth model grow")
eq(arrivalMon.state, "entrance",
  "replacement Stadium rig plays its entrance animation")
ok(switchBattle._crystal251StadiumEntrancePending == nil,
  "Stadium model entrance token is consumed exactly once")

-- A later attack must remain able to replace the entrance state. This guards
-- the regression where switch plumbing poisoned normal 3D battle animations.
ok(arrivalMon:request("attack", 2),
  "Stadium model still accepts battle animation requests after arrival")
eq(arrivalMon.state, "attack",
  "Stadium battle animation state is not stuck on entrance/recall")

-- 2D-3D A gets the same ENGINE grow, but never touches the Stadium model
-- entrance hook or pending model state.
battleModelSetting = true
local flatBattle = setmetatable({
  crystal251Active=true, enemy=outgoingEnemy, nextEnemy=incomingEnemy, queue={},
}, { __index=fakeBattleState })
flatBattle:executeAction(nil, nil, { special="aiSwitch" })
ok(flatBattle.enemySendingOut,
  "2D-3D A hides the incoming billboard through the send-out text")
eq(#flatBattle.queue, 3,
  "2D-3D A queues its arrival after the two switch messages")
local flatArrival = flatBattle.queue[3].fn
flatBattle.queue = {}
flatBattle.nextInsert = 0
flatArrival()
ok(not flatBattle.enemySendingOut,
  "2D-3D A reveals the incoming billboard for grow-in")
eq(flatBattle.growIn and flatBattle.growIn.battler, incomingEnemy,
  "2D-3D A receives the engine grow-in state")
eq(flatBattle.queue[1] and flatBattle.queue[1].wait, 12,
  "2D-3D A receives the normal 12-frame grow hold")
ok(not flatBattle.growCalls,
  "2D-3D A never calls the Stadium/shared startGrowIn hook")
ok(flatBattle._crystal251StadiumEntrancePending == nil,
  "2D-3D A never creates Stadium model entrance state")

battleModelSetting = "flatB"
local flatBBattle = setmetatable({
  crystal251Active=true, enemy=outgoingEnemy, nextEnemy=incomingEnemy, queue={},
}, { __index=fakeBattleState })
flatBBattle:executeAction(nil, nil, { special="aiSwitch" })
local flatBArrival = flatBBattle.queue[3].fn
flatBBattle.queue = {}
flatBBattle.nextInsert = 0
flatBArrival()
eq(flatBBattle.growIn and flatBBattle.growIn.battler, incomingEnemy,
  "2D-3D B receives the same isolated engine grow-in")

-- Ordinary actions must be byte-for-byte routing-wise: no send-out flags,
-- grow state, pending entrance, or extra queue rows.
battleModelSetting = "stadium"
local ordinaryBattle = setmetatable({
  crystal251Active=true, enemy=outgoingEnemy, queue={},
}, { __index=fakeBattleState })
eq(ordinaryBattle:executeAction(nil, nil, { special=nil }), "ordinary",
  "ordinary Crystal battle actions still pass straight through")
ok(ordinaryBattle.enemySendingOut == nil
   and ordinaryBattle.growIn == nil
   and ordinaryBattle._crystal251StadiumEntrancePending == nil
   and #ordinaryBattle.queue == 0,
  "AI switch compatibility never contaminates normal battle animations")
package.loaded["src.battle.BattleState"] = savedBattleStateModule
eq(modules.StadiumInstall.COUNT, 251,
  "installed bridge replaces the 151-model importer with Stadium 2's 251")
eq(modules.StadiumRomPick.LABEL, "STADIUM 2 ROM",
  "DRAMATIC_SHAPE/DRAMALESS_SHAPE options identify the Stadium 2 cartridge")
local savedRomPath = modules.StadiumInstall.romPath
local savedBegin = modules.StadiumInstall.begin
local savedCanDialog = modules.StadiumRomPick.canDialog
local savedChoose = modules.StadiumRomPick.choose
local pickerCalls = 0
modules.StadiumInstall.romPath = function() return "auto-stadium2.z64" end
modules.StadiumInstall.begin = function() return true end
modules.StadiumRomPick.canDialog = function() return true end
modules.StadiumRomPick.choose = function() pickerCalls = pickerCalls + 1 end
local pickerGame = { stack={ push=function() end } }
ok(modules.StadiumRomPick.import(pickerGame),
  "Stadium 2 manual import accepts automatic discovery first")
eq(pickerCalls, 0,
  "Stadium 2 file picker is skipped when automatic discovery succeeds")
modules.StadiumInstall.romPath = function() return nil end
ok(not modules.StadiumRomPick.import(pickerGame),
  "Stadium 2 manual import can fall through when no automatic ROM is found")
eq(pickerCalls, 1,
  "Stadium 2 file picker is the fallback after automatic discovery fails")

local savedLove = _G.love
local savedBeginFrom = modules.StadiumInstall.beginFrom
local androidPicked = {}
local androidPickCalls = 0
local androidBegin
_G.love = {
  system = {
    getOS = function() return "Android" end,
    pickFile = function(kind)
      androidPickCalls = androidPickCalls + 1
      eq(kind, "rom", "Stadium 2 Android picker requests a ROM")
      androidPicked[Bridge.ANDROID_PICKED] = "stadium2-rom-bytes"
      return true
    end,
  },
  filesystem = {
    getInfo = function(path)
      return androidPicked[path] and { type="file" } or nil
    end,
    read = function(path) return androidPicked[path] end,
    remove = function(path) androidPicked[path] = nil; return true end,
  },
}
modules.StadiumInstall.beginFrom = function(bytes, label)
  androidBegin = { bytes=bytes, label=label }
  return true
end
pickerCalls = 0
ok(modules.StadiumRomPick.import(pickerGame),
  "Stadium 2 opens Android's native picker when auto-detection fails")
eq(androidPickCalls, 1,
  "Stadium 2 invokes the Android native picker exactly once")
eq(pickerCalls, 0,
  "Android Stadium 2 import does not invoke a desktop picker")
ok(modules.StadiumRomPick.poll(pickerGame),
  "Stadium 2 consumes Android's picker handoff asynchronously")
eq(androidBegin and androidBegin.bytes, "stadium2-rom-bytes",
  "Stadium 2 passes Android-selected ROM bytes to its importer")
eq(androidBegin and androidBegin.label, Bridge.ANDROID_PICKED,
  "Stadium 2 identifies the Android picker handoff")
ok(androidPicked[Bridge.ANDROID_PICKED] == nil,
  "Stadium 2 removes the transient Android picker handoff")
modules.StadiumInstall.beginFrom = savedBeginFrom
_G.love = savedLove

modules.StadiumInstall.romPath = savedRomPath
modules.StadiumInstall.begin = savedBegin
modules.StadiumRomPick.canDialog = savedCanDialog
modules.StadiumRomPick.choose = savedChoose
ok(type(modules.StadiumMon.setSpecies) == "function",
  "Stadium model selection is patched without changing DRAMATIC_SHAPE/DRAMALESS_SHAPE files")
ok(type(modules.StadiumMon.attack) == "function",
  "Stadium model attack selection is extended for Crystal's 251 moves")
ok(type(modules.StadiumMon.build) == "function",
  "Stadium 2 installs the high-refresh skinning limiter")

local perfMon = {
  rig = {}, model = { anims={{ frames=40, loopStart=0 }} },
  anim = 1, aux = 1, time = 0,
  loop = true, yaw = 0, dt = 0,
}
modules.StadiumMon.build(perfMon)
eq(perfMon.baseBuildCalls, 1,
  "first visible Stadium 2 frame poses and uploads the mesh")
for frame = 1, 3 do
  perfMon.time = frame / 240
  perfMon.dt = 1 / 240
  modules.StadiumMon.build(perfMon)
end
eq(perfMon.baseBuildCalls, 1,
  "240 Hz rendering reuses the same 60 Hz skinned mesh sample")
perfMon.time = 4 / 240
perfMon.dt = 1 / 240
modules.StadiumMon.build(perfMon)
eq(perfMon.baseBuildCalls, 2,
  "the next 60 Hz presentation sample rebuilds the skinned mesh")
ok(math.abs((perfMon.baseBuildDt or 0) - 4 / 240) < 1e-9,
  "skipped high-refresh frame time is accumulated for the anchor filter")
local beforeRestart = perfMon.baseBuildCalls
modules.StadiumMon.play(perfMon, "idle", 1, 1)
modules.StadiumMon.build(perfMon)
eq(perfMon.baseBuildCalls, beforeRestart + 1,
  "restarting an animation invalidates the cached skinned frame")
local staticMon = {
  rig = {}, model = { anims={{ frames=1, loopStart=0 }} },
  anim = 1, time = 0, loop = true, yaw = 0, dt = 1 / 60,
}
modules.StadiumMon.build(staticMon)
staticMon.time = 30
modules.StadiumMon.build(staticMon)
eq(staticMon.baseBuildCalls, 1,
  "one-frame rest-pose fallbacks upload only once")
local requestedAttack
local gen2Mon = {
  model = { anims = { {}, {} } },
  slotAnim = function(_, slot)
    if slot == "attack_default" then return 2 end
  end,
  request = function(_, state, index)
    requestedAttack = { state=state, index=index }
    return true
  end,
}
ok(modules.StadiumMon.attack(gen2Mon, 200),
  "Generation II move ids play the Stadium 2 default attack animation")
eq(requestedAttack and requestedAttack.state, "attack",
  "Generation II move fallback requests an attack state")
eq(requestedAttack and requestedAttack.index, 2,
  "Generation II move fallback uses the imported default attack slot")
local failed, failureText = modules.StadiumInstall.fail(
  "extracting Stadium 2 models", "test parser reason", "archive=0x1234")
ok(not failed and failureText:find("test parser reason", 1, true) ~= nil,
  "Stadium 2 importer returns the exact parser failure")
ok(modules.StadiumInstall.status.errorFull:find("archive=0x1234", 1, true) ~= nil,
  "Stadium 2 failure keeps archive context for the error screen and log")
ok(type(loggedError) == "string"
   and loggedError:find("test parser reason", 1, true) ~= nil,
  "Stadium 2 failure is printed through the mod logger")
modules.StadiumInstall.cancel()

local stadium1Header = "\128\055\018\064" .. string.rep("\0", 0x1C)
  .. string.format("%-20s", "POKEMON STADIUM")
local romFiles = {
  ["baseroms/baserom.z64"] = stadium1Header,
  ["baseroms/renamed_game.z64"] = z64Header,
  ["Pokemon Stadium 2 (USA).z64"] = z64Header,
}
local missingPack = Bridge.SHINY_DIR .. "/125.dsm"
_G.love = { filesystem = {
  getDirectoryItems = function(path)
    if path == "baseroms" then return { "baserom.z64", "renamed_game.z64" } end
    if path == "" then return { "Pokemon Stadium 2 (USA).z64", "mods" } end
    return {}
  end,
  getInfo = function(path)
    if romFiles[path] or path == Bridge.MARKER then return { type="file" } end
    if path:match("%.dsm$") and path ~= missingPack then return { type="file" } end
    return nil
  end,
  read = function(path)
    if romFiles[path] then return romFiles[path] end
    if path == Bridge.MARKER then
      return Bridge.FORMAT .. " 251 2 testmd5\n"
    end
    return nil
  end,
  getSaveDirectory = function() return "/tmp/crystal251-test" end,
} }
eq(modules.StadiumInstall.romPath(), "baseroms/renamed_game.z64",
  "automatic scan ignores Stadium 1 and selects a renamed Stadium 2 ROM")
romFiles["baseroms/renamed_game.z64"] = nil
eq(modules.StadiumInstall.romPath(), "Pokemon Stadium 2 (USA).z64",
  "automatic Stadium 2 scan accepts an arbitrary filename beside the game")
romFiles["Pokemon Stadium 2 (USA).z64"] = nil
local realGetenv = os.getenv
local realOpen = io.open
local realHostShell = package.loaded["src.core.HostShell"]
local appImageRom = "/games/Pokemon Stadium 2 (USA).z64"
os.getenv = function(name)
  if name == "APPIMAGE" then return "/games/gen1recomp-x86_64.AppImage" end
  return realGetenv and realGetenv(name) or nil
end
io.open = function(path, mode)
  if path == appImageRom then
    return { read=function() return z64Header end, close=function() end }
  end
  return realOpen(path, mode)
end
package.loaded["src.core.HostShell"] = {
  popen = function(command)
    local value = command:find("/games", 1, true) and (appImageRom .. "\0") or ""
    return { read=function() return value end, close=function() end }
  end,
}
love.system = { getOS=function() return "Linux" end }
love.filesystem.getSourceBaseDirectory = function() return "/tmp/.mount_gen1/usr/bin" end
love.filesystem.getWorkingDirectory = function() return "/home/user" end
eq(modules.StadiumInstall.romPath(), appImageRom,
  "AppImage Stadium 2 auto-detection uses the directory containing the AppImage")
ok(modules.StadiumInstall.romHint():find("/games", 1, true) ~= nil,
  "AppImage Stadium 2 hint names the directory beside the AppImage")
os.getenv = realGetenv
io.open = realOpen
package.loaded["src.core.HostShell"] = realHostShell
love.system = nil
love.filesystem.getSourceBaseDirectory = nil
love.filesystem.getWorkingDirectory = nil
romFiles["Pokemon Stadium 2 (USA).z64"] = z64Header
romFiles["baseroms/renamed_game.z64"] = z64Header
modules.StadiumInstall.forget()
ok(not modules.StadiumInstall.ready(),
  "a missing Stadium 2 normal or shiny pack invalidates the cache")
missingPack = nil
modules.StadiumInstall.forget()
ok(modules.StadiumInstall.ready(),
  "all 251 normal and shiny packs satisfy the Stadium 2 cache")

local bridgeSource = read("mods/CRYSTAL_251/lib/stadium2_bridge.lua")
ok(bridgeSource:find('V.mod:read("lib/StadiumPack.lua")', 1, true) ~= nil,
  "bridge clones DRAMATIC_SHAPE/DRAMALESS_SHAPE's pack reader through its public mod object")
ok(bridgeSource:find('V.mod:read("lib/StadiumFragment.lua")', 1, true) ~= nil,
  "bridge clones DRAMATIC_SHAPE/DRAMALESS_SHAPE's parser for each Stadium 2 fragment link base")
ok(bridgeSource:find('source:gsub("species <= 151", "species <= 251"', 1, true) ~= nil,
  "only the cloned reader has its dex limit expanded")
ok(not bridgeSource:find("rebaseFragment", 1, true),
  "Stadium 2 fragments are parsed at their link bases instead of rewritten")
ok(bridgeSource:find('self.phase = "scan"', 1, true) ~= nil,
  "the importer continues scanning later model archives until all 251 are built")
ok(T.MODEL_TABLE_START == 0x27ED000
   and T.POSE_TABLE_START == 0x2D7D000
   and T.POSE_TABLE_END == 0x3FD5000,
  "supported US ROM uses separate authoritative model and pose tables")
ok(bridgeSource:find('archive.role = "model"', 1, true) ~= nil
   and bridgeSource:find('archive.role = "pose"', 1, true) ~= nil,
  "model geometry and nested pose bundles are indexed through separate paths")
ok(bridgeSource:find("nChannels > math.max", 1, true) == nil,
  "sparse animation channels are not capped by the model bone count")
ok(bridgeSource:find("inspectRawAnimations", 1, true) ~= nil
   and bridgeSource:find("extractRawAnimations", 1, true) ~= nil,
  "pose-table children are decoded without requiring a FRAGMENT marker")
ok(bridgeSource:find('rootKind = "raw-pose"', 1, true) ~= nil,
  "raw pose records retain a distinct diagnostic source kind")
ok(bridgeSource:find("crystal251RawU32(data, 0)", 1, true) ~= nil
   and bridgeSource:find("footer + 0x1C <= #data", 1, true) ~= nil,
  "raw pose word zero selects the standard animation footer")
ok(bridgeSource:find("prefixEnd + 4, #data - 0x1C", 1, true) == nil,
  "raw pose probing is bounded and cannot stall the import before progress")
ok(bridgeSource:find("if job.builtCount == Bridge.COUNT then", 1, true) ~= nil
   and bridgeSource:find("job.animatedBuilt == Bridge.COUNT", 1, true) == nil,
  "animation decoder coverage no longer blocks the 251-model import")
ok(bridgeSource:find("stadium2AnimationFallback", 1, true) ~= nil
   and bridgeSource:find("fallbackBuilt", 1, true) ~= nil,
  "missing pose records are packed with a reported bind-pose fallback")
ok(bridgeSource:find("local SKIN_FPS = 60", 1, true) ~= nil
   and bridgeSource:find("_crystal251SkinFrame", 1, true) ~= nil
   and bridgeSource:find("self.dt = elapsed", 1, true) ~= nil,
  "Stadium 2 CPU skinning is capped at 60 Hz with accumulated anchor time")
ok(bridgeSource:find("cache missing or outdated; starting automatic", 1, true) ~= nil
   and bridgeSource:find("local started, beginErr = Install.begin()", 1, true) ~= nil
   and bridgeSource:find("Screen.new(Game, true)", 1, true) ~= nil,
  "automatic Stadium 2 import starts directly before its progress screen")
ok(bridgeSource:find("function Install.romPath()", 1, true) ~= nil
   and bridgeSource:find("n64Title(header)", 1, true) ~= nil
   and bridgeSource:find("getSourceBaseDirectory", 1, true) ~= nil
   and bridgeSource:find('os.getenv("APPIMAGE")', 1, true) ~= nil
   and bridgeSource:find("getWorkingDirectory", 1, true) ~= nil
   and bridgeSource:find('addDirectory("", "")', 1, true) ~= nil,
  "Stadium 2 auto-detection covers packaged desktop and source layouts")
ok(bridgeSource:find("errorSamples", 1, true) ~= nil
   and bridgeSource:find("Rejected model samples", 1, true) ~= nil,
  "failed Stadium 2 scans retain the underlying parser errors")
ok(bridgeSource:find("FULL ERROR PRINTED", 1, true) ~= nil,
  "Stadium 2 failure screen remains visible with detailed diagnostics")
ok(not bridgeSource:find("git apply", 1, true),
  "runtime compatibility does not alter either dependency on disk")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal Stadium 2)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal Stadium 2)"):format(checks, checks))