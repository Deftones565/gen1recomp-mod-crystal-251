package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local path = os.getenv("CRYSTAL_ROM") or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP crystal 251 extractor (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a"); file:close()
local manifest = require("mods.CRYSTAL_251.addresses")
local revision = manifest.revisions["f2f52230b536214ef7c9924f483392993e226cfb"]
T.eq(#raw, 2*1024*1024, "fixture has the retail Crystal ROM size")

local pictures, frontPictures, backPictures, dexPictures = 0, 0, 0, 0
local overworldPictures = 0
local data = require("mods.CRYSTAL_251.lib.extractor").extract(raw, revision, {
  writePicture=function(pathName, bytes, w, h, palette, layout, presentation)
    pictures = pictures + 1
    T.check(#bytes >= w*h*16, pathName .. " contains its resting frame")
    if presentation == "overworld" then
      overworldPictures = overworldPictures + 1
      T.eq(w, 2, pathName .. " is two tiles wide")
      T.eq(h, 4, pathName .. " contains two stacked 16px frames")
      T.eq(layout, "rows", pathName .. " preserves icon tile order")
      return
    end
    if presentation == "dex" then dexPictures = dexPictures + 1 end
    if pathName:match("_back%.png$") or pathName:match("/back/") then
      backPictures = backPictures + 1
      T.eq(layout, "columns", pathName .. " preserves Crystal's column layout metadata")
    else
      frontPictures = frontPictures + 1
      T.eq(layout, "columns", pathName .. " preserves animation-packer transpose metadata")
    end
  end,
})
T.eq(#data.species, 251, "all 251 species are extracted")
T.eq(#data.moves, 251, "all 251 moves are extracted")
T.eq(#data.unownForms, 26, "all Unown letters are extracted")
T.eq(pictures, 251*6 + 26*6 + 2,
  "battle, Pokédex, and legendary overworld pictures are decoded")
T.eq(overworldPictures, 2, "Lugia and Ho-Oh get dedicated overworld sheets")
T.eq(frontPictures, 251*4 + 26*4, "every front and Pokédex picture is column-major")
T.eq(backPictures, 251*2 + 26*2, "every normal and shiny back picture is column-major")
T.eq(dexPictures, 251*2 + 26*2, "every normal and shiny Pokédex picture requests centering")
T.eq(data.schema, 12, "alpha-safe edge bleed invalidates older generated caches")
T.eq(data.overworldSprites.lugia,
  "crystal_251/generated/overworld/lugia.png", "Lugia sprite path is portable")
T.eq(data.overworldSprites.hoOh,
  "crystal_251/generated/overworld/ho_oh.png", "Ho-Oh sprite path is portable")
T.eq(data.species[129].battleScaleBack, 1,
  "Crystal's full-size Magikarp back sprite is not doubled like Gen I art")
T.eq(data.species[152].id, "CHIKORITA", "Johto National Dex order begins correctly")
T.eq(data.species[250].id, "HO_OH", "punctuated species ids are canonical")
T.eq(data.moves[165].effect, "RECOIL_EFFECT", "Crystal effect bytes map correctly")
local eeveeEvos = {}
for _, evo in ipairs(data.species[133].evolutions) do eeveeEvos[evo.species]=evo.item end
T.eq(eeveeEvos.ESPEON, "SUN_STONE", "Espeon uses the timeless day substitute")
T.eq(eeveeEvos.UMBREON, "MOON_STONE", "Umbreon uses the timeless night substitute")
local expectedStones = {
  [25] = "THUNDER_STONE", [37] = "FIRE_STONE", [44] = "LEAF_STONE",
  [61] = "WATER_STONE", [90] = "WATER_STONE", [102] = "LEAF_STONE",
}
for dex, item in pairs(expectedStones) do
  T.eq(data.species[dex].evolutions[1].item, item,
    data.species[dex].id .. " keeps its canonical evolution stone")
end
local tyrogue = {}
for _, evo in ipairs(data.species[236].evolutions) do tyrogue[evo.method] = true end
T.check(tyrogue.CRYSTAL_STAT_GT and tyrogue.CRYSTAL_STAT_LT and tyrogue.CRYSTAL_STAT_EQ,
  "Tyrogue's three stat branches remain explicit")
T.finish("crystal 251 extractor")
