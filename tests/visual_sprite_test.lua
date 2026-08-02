package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local path = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP Crystal 251 visual sprite goldens (set CRYSTAL_ROM)")
  os.exit(0)
end
local raw = file:read("*a"); file:close()
local revision = require("mods.CRYSTAL_251.addresses").revisions[
  "f2f52230b536214ef7c9924f483392993e226cfb"]
local Picture = require("mods.CRYSTAL_251.lib.picture")
local digest = require("src.link.Fingerprint").digest

-- Shade zero is both Crystal's paper/background and the white paint used
-- inside outlined artwork. Only paper connected to an image boundary should
-- become transparent; otherwise white eyes and markings disappear too.
local synthetic = string.char(
  0, 0, 0, 0, 0,
  0, 3, 3, 3, 0,
  0, 3, 0, 3, 0,
  0, 3, 3, 3, 0,
  0, 0, 0, 0, 0)
local syntheticAlpha = Picture.boundaryTransparency(synthetic, 5, 5)
T.check(syntheticAlpha[1] and syntheticAlpha[25],
  "boundary-connected Crystal paper becomes transparent")
T.check(not syntheticAlpha[13],
  "enclosed shade-zero sprite detail remains opaque")

-- Palette-independent raster hashes produced independently from the first
-- frame of pret/pokecrystal's canonical PNGs. They cover three sprite sizes,
-- both front/back packing paths, and a non-default Unown form without storing
-- or redistributing any artwork in the test suite.
local expected = {
  ["crystal_251/generated/front/charizard.png"] = "ed2b6507316114fb",
  ["crystal_251/generated/back/charizard.png"] = "24395c571bcb084b",
  ["crystal_251/generated/front/pikachu.png"] = "68233481a0bf0475",
  ["crystal_251/generated/back/pikachu.png"] = "1dda334e156bdf42",
  ["crystal_251/generated/front/magikarp.png"] = "196ebc9311006887",
  ["crystal_251/generated/back/magikarp.png"] = "d425eaddcbb796d1",
  ["crystal_251/generated/unown/z_front.png"] = "9b338960d3cf5954",
  ["crystal_251/generated/unown/z_back.png"] = "52760db34a07b9a7",
  ["crystal_251/generated/overworld/lugia.png"] = "ae3d71935c40ed87",
  ["crystal_251/generated/overworld/ho_oh.png"] = "0518c894b31c4488",
}
local seen, allNormalRasters, alphaMasks = {}, {}, {}
local data = require("mods.CRYSTAL_251.lib.extractor").extract(raw, revision, {
  writePicture = function(name, bytes, w, h, palette, layout)
    if not palette and not name:find("/dex/", 1, true)
        and not name:match("_dex%.png$") then
      local raster = Picture.shadeRaster(bytes, w, h, layout)
      allNormalRasters[#allNormalRasters + 1] = name .. "\0" .. w .. "x" .. h
        .. "\0" .. raster
      local transparent = Picture.boundaryTransparency(raster, w * 8, h * 8)
      local mask = {}
      for index = 1, #raster do mask[index] = transparent[index] and "1" or "0" end
      alphaMasks[#alphaMasks + 1] = name .. "\0" .. table.concat(mask)
    end
    local golden = expected[name]
    if golden and not palette then
      seen[name] = true
      T.eq(digest(Picture.shadeRaster(bytes, w, h, layout)), golden,
        name .. " matches the canonical Crystal resting-frame pixels")
    end
  end,
})
for name in pairs(expected) do T.check(seen[name], name .. " visual golden ran") end
table.sort(allNormalRasters)
T.eq(#allNormalRasters, 556,
  "visual sweep covers battle art, Unown forms, and both legendary map sprites")
T.eq(digest(table.concat(allNormalRasters, "\0")), "126d29c9f610001d",
  "all 556 normal Crystal sprite rasters match the audited visual snapshot")
T.eq(#alphaMasks, 556,
  "every normal Crystal sprite receives a decoded transparency mask")
for _, entry in ipairs(alphaMasks) do
  T.check(entry:find("1", 1, true) ~= nil,
    "Crystal sprite contains transparent boundary paper")
end

local BattleState = require("src.battle.BattleState")
local scale = BattleState.resolveBattleScale({ pokemon=data.species },
  "back", data.species[129].spriteBack, 129)
-- The registry is normally keyed by species id, so also pin the actual field
-- directly: the geometry assertion below is the final composed battle rule.
scale = data.species[129].battleScaleBack or scale
local x, y = BattleState.backPlacement(48, 48, 0, 0, scale)
T.eq(scale, 1, "Crystal's 48px player picture renders at native scale")
T.eq(x, 8, "Crystal's player picture remains anchored to battle column 1")
T.eq(y, 48, "Crystal's player picture occupies rows 48 through 95")
T.eq(y + 48 * scale, 96, "Crystal's player picture cannot overlap the text box")

T.finish("Crystal 251 visual sprite goldens")
