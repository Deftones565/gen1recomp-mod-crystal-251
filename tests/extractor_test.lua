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
local overworldPictures, daycarePictures, eggPictures, animationPictures, cries = 0, 0, 0, 0, 0
local data = require("mods.CRYSTAL_251.lib.extractor").extract(raw, revision, {
  writePicture=function(pathName, bytes, w, h, palette, layout, presentation)
    pictures = pictures + 1
    T.check(#bytes >= w*h*16, pathName .. " contains its resting frame")
    if pathName:match("/animations/front/") then
      animationPictures = animationPictures + 1
      T.eq(layout, "columns", pathName .. " preserves Crystal animation tile order")
      return
    end
    if presentation == "overworld" then
      overworldPictures = overworldPictures + 1
      T.eq(w, 2, pathName .. " is two tiles wide")
      T.eq(h, 4, pathName .. " contains two stacked 16px frames")
      T.eq(layout, "rows", pathName .. " preserves icon tile order")
      return
    elseif presentation == "daycare_icon" then
      daycarePictures = daycarePictures + 1
      T.eq(w, 2, pathName .. " is two tiles wide")
      T.eq(h, 12, pathName .. " expands two ROM frames into six NPC poses")
      T.eq(layout, "rows", pathName .. " preserves icon tile order")
      return
    elseif presentation == "egg" then
      eggPictures = eggPictures + 1
      T.eq(w, 5, "Egg front picture is five tiles wide")
      T.eq(h, 5, "Egg front picture exports only its resting frame")
      T.eq(layout, "columns", "Egg front picture preserves transposed tile order")
      return
    elseif presentation == "egg_icon" then
      eggPictures = eggPictures + 1
      T.eq(w, 2, "Egg icon is two tiles wide")
      T.eq(h, 8, "Egg icon repeats its two real frames for all engine frame slots")
      T.eq(layout, "rows", "Egg icon preserves row-major tile order")
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
  writeCry=function(pathName, definition)
    cries = cries + 1
    T.check(pathName:match("%.wav$") ~= nil, pathName .. " is a portable WAV path")
    T.check(definition.header.bank > 0, pathName .. " has a Crystal cry bank")
    T.check(definition.header.address >= 0x4000, pathName .. " has a Crystal cry address")
  end,
})
T.eq(#data.species, 251, "all 251 species are extracted")
T.eq(#data.moves, 251, "all 251 moves are extracted")
T.eq(#data.unownForms, 26, "all Unown letters are extracted")
T.eq(pictures - animationPictures, 251*6 + 26*6 + 2 + 2 + 38,
  "resting battle, Pokédex, legendary overworld, and Egg pictures are decoded")
T.check(animationPictures > 0, "Crystal front animation frames are decoded")
for _, form in ipairs(data.unownForms) do
  T.check(form.frontAnimation and #form.frontAnimation.frames > 0,
    "Unown " .. form.letter .. " has its form-specific Crystal animation")
end
T.eq(cries, 251, "all Crystal species cries are extracted")
T.eq(overworldPictures, 2, "Lugia and Ho-Oh get dedicated overworld sheets")
T.eq(daycarePictures, 38, "all Crystal menu icons get animated Day Care sheets")
T.eq(eggPictures, 2, "Egg front and party-icon graphics are decoded from the ROM")
T.eq(frontPictures, 251*4 + 26*4, "every front and Pokédex picture is column-major")
T.eq(backPictures, 251*2 + 26*2, "every normal and shiny back picture is column-major")
T.eq(dexPictures, 251*2 + 26*2, "every normal and shiny Pokédex picture requests centering")
T.eq(data.schema, 25, "compressed-bundle imports invalidate incompatible older writers")
T.eq(#data.species[1].shinyPaletteColors, 4,
  "Stadium 2 import retains Crystal's shiny palette")
T.eq(data.overworldSprites.lugia,
  "crystal_251/generated/overworld/lugia.png", "Lugia sprite path is portable")
T.eq(data.overworldSprites.hoOh,
  "crystal_251/generated/overworld/ho_oh.png", "Ho-Oh sprite path is portable")
T.eq(data.eggAssets.front,
  "crystal_251/generated/egg/front.png", "Egg front path is portable")
T.eq(data.eggAssets.icon,
  "crystal_251/generated/egg/icon.png", "Egg icon path is portable")
T.eq(#data.daycareIconAssets, 38, "all non-null Crystal menu icons are exported")
T.eq(data.daycareIconAssets[4],
  "crystal_251/generated/daycare_icons/04.png", "Pikachu icon path is portable")
T.eq(data.species[25].crystalMenuIcon, 4,
  "Pikachu uses Crystal's dedicated animated menu icon")
T.eq(data.species[249].crystalMenuIcon, 34,
  "Lugia uses Crystal's dedicated menu icon identity")
T.eq(data.species[129].battleScaleBack, 1,
  "Crystal's full-size Magikarp back sprite is not doubled like Gen I art")
T.eq(data.species[152].id, "CHIKORITA", "Johto National Dex order begins correctly")
T.eq(data.species[250].id, "HO_OH", "punctuated species ids are canonical")
T.eq(data.species[1].crystalGenderRatio, 31,
  "Bulbasaur keeps Crystal's one-eighth female ratio")
T.eq(data.species[25].crystalGenderRatio, 127,
  "Pikachu keeps Crystal's equal gender ratio")
T.eq(data.species[81].crystalGenderRatio, 255,
  "Magnemite keeps Crystal's genderless ratio")
T.eq(data.species[113].crystalGenderRatio, 254,
  "Chansey keeps Crystal's female-only ratio")
T.eq(data.species[128].crystalGenderRatio, 0,
  "Tauros keeps Crystal's male-only ratio")
T.eq(data.species[1].crystalHatchCycles, 20,
  "Bulbasaur keeps Crystal's hatch-cycle count")
T.eq(data.species[1].crystalEggGroups[1], 1,
  "Bulbasaur keeps its Monster egg group")
T.eq(data.species[1].crystalEggGroups[2], 7,
  "Bulbasaur keeps its Plant egg group")
T.check(#data.species[1].crystalEggMoves > 0,
  "Bulbasaur's explicit Crystal egg moves are extracted")
T.eq(data.species[81].crystalEggGroups[1], 10,
  "Magnemite keeps its Mineral egg group")
T.eq(data.species[150].crystalEggGroups[1], 15,
  "Mewtwo remains in the No Eggs group")
T.eq(data.moves[165].effect, "RECOIL_EFFECT", "Crystal effect bytes map correctly")
local eeveeEvos = {}
for _, evo in ipairs(data.species[133].evolutions) do eeveeEvos[evo.species]=evo.method end
T.eq(eeveeEvos.ESPEON, "EVOLVE_HAPPINESS_MORNDAY", "Espeon uses daytime friendship")
T.eq(eeveeEvos.UMBREON, "EVOLVE_HAPPINESS_NITE", "Umbreon uses nighttime friendship")
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
local levelTrades = { [64]=36, [67]=40, [75]=40, [93]=36 }
for dex, level in pairs(levelTrades) do
  local evo = data.species[dex].evolutions[1]
  T.eq(evo.method, "LEVEL", data.species[dex].id .. " evolves by level")
  T.eq(evo.level, level, data.species[dex].id .. " has its standalone level")
end
local itemTrades = {
  [61]="KINGS_ROCK", [79]="KINGS_ROCK", [95]="METAL_COAT",
  [123]="METAL_COAT", [117]="DRAGON_SCALE", [137]="UP_GRADE",
}
for dex, item in pairs(itemTrades) do
  local found
  for _, evo in ipairs(data.species[dex].evolutions) do
    if evo.item == item then found = evo break end
  end
  T.check(found ~= nil, data.species[dex].id .. " uses " .. item .. " directly")
  T.eq(found and found.method, "ITEM", data.species[dex].id .. " is an item evolution")
end
T.finish("crystal 251 extractor")
