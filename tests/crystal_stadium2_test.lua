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
  local file = assert(io.open(path, "rb"))
  local value = file:read("*a")
  file:close()
  return value
end

local Bridge = require("mods.CRYSTAL_251.lib.stadium2_bridge")
local T = Bridge._test

eq(Bridge.COUNT, 251, "Stadium 2 bridge covers the full Crystal dex")
eq(Bridge.FORMAT, "C2DSM8",
  "Stadium 2 cache invalidates pose records packed before the footer-header fix")
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
eq(contexts[3], 2, "third Stadium 2 animation is the faint context")
eq(contexts[4], 3, "fourth Stadium 2 animation is the entrance context")

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

local stadiumPackSource = read("mods/DRAMATIC_SHAPE/lib/StadiumPack.lua")
local stadiumFragmentSource = read("mods/DRAMATIC_SHAPE/lib/StadiumFragment.lua")
local modules = {
  StadiumPack = {
    SLOT = { idle=1, attack_default=2, faint=3, entrance=4 },
    NONE = 0xFFFF,
    keep = function() end,
    forget = function() end,
    invalidate = function() end,
  },
  Stadium = { update = function() return "updated" end },
  StadiumMon = {},
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
local fakeV = { mod=fakeDramaticMod, path="mods/DRAMATIC_SHAPE" }
function fakeV.require(name) return assert(modules[name], name) end
local linkedParser = T.fragmentParser(fakeV, sourceBase)
ok(type(linkedParser) == "table" and type(linkedParser.extract) == "function",
  "DRAMATIC_SHAPE's fragment reader is cloned for Stadium 2's link base")
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
ok(Bridge.install(fakeCrystalMod, cache, { exports={ lib=fakeV } }),
  "bridge installs through DRAMATIC_SHAPE's exported module namespace")
eq(modules.StadiumInstall.COUNT, 251,
  "installed bridge replaces the 151-model importer with Stadium 2's 251")
eq(modules.StadiumRomPick.LABEL, "STADIUM 2 ROM",
  "DRAMATIC_SHAPE options identify the Stadium 2 cartridge")
ok(type(modules.StadiumMon.setSpecies) == "function",
  "Stadium model selection is patched without changing DRAMATIC_SHAPE files")
ok(type(modules.StadiumMon.attack) == "function",
  "Stadium model attack selection is extended for Crystal's 251 moves")
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
}
local missingPack = Bridge.SHINY_DIR .. "/125.dsm"
_G.love = { filesystem = {
  getDirectoryItems = function(path)
    if path == "baseroms" then return { "baserom.z64", "renamed_game.z64" } end
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
modules.StadiumInstall.forget()
ok(not modules.StadiumInstall.ready(),
  "a missing Stadium 2 normal or shiny pack invalidates the cache")
missingPack = nil
modules.StadiumInstall.forget()
ok(modules.StadiumInstall.ready(),
  "all 251 normal and shiny packs satisfy the Stadium 2 cache")

local bridgeSource = read("mods/CRYSTAL_251/lib/stadium2_bridge.lua")
ok(bridgeSource:find('V.mod:read("lib/StadiumPack.lua")', 1, true) ~= nil,
  "bridge clones DRAMATIC_SHAPE's pack reader through its public mod object")
ok(bridgeSource:find('V.mod:read("lib/StadiumFragment.lua")', 1, true) ~= nil,
  "bridge clones DRAMATIC_SHAPE's parser for each Stadium 2 fragment link base")
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
ok(bridgeSource:find("cache missing or outdated; starting automatic", 1, true) ~= nil
   and bridgeSource:find("local started, beginErr = Install.begin()", 1, true) ~= nil
   and bridgeSource:find("Screen.new(Game, true)", 1, true) ~= nil,
  "automatic Stadium 2 import starts directly before its progress screen")
ok(bridgeSource:find("function Install.romPath()", 1, true) ~= nil
   and bridgeSource:find("n64Title(header)", 1, true) ~= nil,
  "baseroms auto-detection identifies Stadium 2 by its N64 header")
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
