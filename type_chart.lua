-- Generation II type chart differences and the two added types. Multipliers
-- use the engine's x10 representation.
return {
  types = {
    STEEL = { name = "STEEL", category = "physical", index = 9 },
    DARK = { name = "DARK", category = "special", index = 27 },
    CURSE_TYPE = { name = "???", category = "special", index = 19 },
  },
  rows = {
    ["NORMAL>STEEL"]=5, ["FIRE>STEEL"]=20, ["WATER>STEEL"]=10,
    ["ELECTRIC>STEEL"]=10, ["GRASS>STEEL"]=5, ["ICE>STEEL"]=5,
    ["FIGHTING>STEEL"]=20, ["POISON>STEEL"]=0, ["GROUND>STEEL"]=20,
    ["FLYING>STEEL"]=5, ["PSYCHIC_TYPE>STEEL"]=5, ["BUG>STEEL"]=5,
    ["ROCK>STEEL"]=5, ["GHOST>STEEL"]=5, ["DRAGON>STEEL"]=5,
    ["DARK>STEEL"]=5, ["STEEL>STEEL"]=5, ["STEEL>FIRE"]=5,
    ["STEEL>WATER"]=5, ["STEEL>ELECTRIC"]=5, ["STEEL>ICE"]=20,
    ["STEEL>ROCK"]=20, ["DARK>PSYCHIC_TYPE"]=20, ["DARK>GHOST"]=20,
    ["DARK>FIGHTING"]=5, ["DARK>DARK"]=5, ["DARK>STEEL"]=5,
    ["FIGHTING>DARK"]=20, ["BUG>DARK"]=20, ["GHOST>DARK"]=5,
    ["PSYCHIC_TYPE>DARK"]=0,
  },
  -- Gen I bugs corrected by Crystal.
  corrections = { ["GHOST>PSYCHIC_TYPE"]=20, ["BUG>POISON"]=5,
    ["POISON>BUG"]=10, ["ICE>FIRE"]=5 },
}
