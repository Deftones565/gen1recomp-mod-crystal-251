-- Addresses reproduced from pret/pokecrystal builds whose SHA-1 values match
-- the supported retail UE dumps. Crystal's content layout is identical in
-- v1.0 and v1.1; keeping two records makes validation and future changes safe.
local common = {
  pokemonPalettes = { bank = 0x02, address = 0x68ce },
  -- EggPic is gfx/pokemon/egg/front.animated.2bpp.lz. EggIcon is the
  -- ordinary two-frame 16x32 party icon sheet. Both are copied from the
  -- user's Crystal ROM during import; no Nintendo artwork ships with the mod.
  eggPic = { bank = 0x54, address = 0x5caf },
  eggIcon = { bank = 0x23, address = 0x798d },
  eggMovePointers = { bank = 0x08, address = 0x7b11 },
  tmhmMoves = { bank = 0x04, address = 0x567a },
  moves = { bank = 0x10, address = 0x5afb },
  evosAttacksPointers = { bank = 0x10, address = 0x65b1 },
  pokedexEntryPointers = { bank = 0x11, address = 0x4378 },
  baseData = { bank = 0x14, address = 0x5424 },
  pokemonNames = { bank = 0x14, address = 0x7384 },
  iconPointers = { bank = 0x23, address = 0x6bbf },
  battleAnimations = { bank = 0x32, address = 0x506f },
  animationPointers = { bank = 0x34, address = 0x4695 },
  unownAnimationPointers = { bank = 0x34, address = 0x6229 },
  bitmasksPointers = { bank = 0x34, address = 0x64ef },
  unownBitmasksPointers = { bank = 0x34, address = 0x7ad3 },
  framesPointers = { bank = 0x35, address = 0x4000 },
  kantoFrames = { bank = 0x35, address = 0x41f6 },
  johtoFrames = { bank = 0x36, address = 0x4400 },
  unownFramesPointers = { bank = 0x36, address = 0x59a9 },
  cryPointers = { bank = 0x3a, address = 0x51b0 },
  pokemonCries = { bank = 0x3c, address = 0x6787 },
  pokemonPicPointers = { bank = 0x48, address = 0x4000 },
  unownPicPointers = { bank = 0x49, address = 0x4000 },
  pokedexEntries1 = { bank = 0x60, address = 0x5695 },
  pokedexEntries2 = { bank = 0x6e, address = 0x4000 },
  moveNames = { bank = 0x72, address = 0x5f29 },
  pokedexEntries3 = { bank = 0x73, address = 0x4000 },
  pokedexEntries4 = { bank = 0x74, address = 0x4000 },
}

local function copy()
  local out = {}
  for key, value in pairs(common) do
    out[key] = { bank = value.bank, address = value.address }
  end
  return out
end

return {
  schema = 1,
  revisions = {
    ["f4cd194bdee0d04ca4eac29e09b8e4e9d818c133"] = {
      id = "crystal-ue-1.0", title = "Pokemon Crystal UE v1.0", addresses = copy(),
    },
    ["f2f52230b536214ef7c9924f483392993e226cfb"] = {
      id = "crystal-ue-1.1", title = "Pokemon Crystal UE v1.1", addresses = copy(),
    },
  },
}
