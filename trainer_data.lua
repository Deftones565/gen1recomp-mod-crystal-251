-- Curated Generation II additions for Kanto trainer archetypes.  The table is
-- deliberately about trainer identity, not merely a Pokemon's primary type:
-- e.g. Bird Keepers get actual birds, while Crobat and Jumpluff stay with
-- trainers whose themes fit them.  `min` is the earliest ordinary trainer
-- level; one candidate up to four levels early is an intentional ace preview.

local function rows(...)
  local out = {}
  for _, value in ipairs({...}) do
    if type(value) == "string" then out[#out+1] = { id=value, min=1 }
    else out[#out+1] = value end
  end
  return out
end

return {
  classThemes = {
    OPP_BIRD_KEEPER={ name="BIRDS", pool=rows(
      {id="HOOTHOOT",min=10},{id="NATU",min=14},{id="MURKROW",min=20},
      {id="NOCTOWL",min=22},{id="XATU",min=27},{id="DELIBIRD",min=28},
      {id="SKARMORY",min=30}) },
    OPP_BUG_CATCHER={ name="BUGS", pool=rows(
      {id="LEDYBA",min=7},{id="SPINARAK",min=7},{id="PINECO",min=12},
      {id="YANMA",min=16},{id="LEDIAN",min=18},{id="ARIADOS",min=22},
      {id="HERACROSS",min=25},{id="SCIZOR",min=35}) },
    OPP_BLACKBELT={ name="MARTIAL", pool=rows(
      {id="TYROGUE",min=18},{id="HITMONTOP",min=28}) },
    OPP_CHANNELER={ name="OCCULT", pool=rows(
      {id="MISDREAVUS",min=22},{id="UNOWN",min=24}) },
    OPP_FISHER={ name="FISHING", pool=rows(
      {id="CHINCHOU",min=18},{id="QWILFISH",min=20},{id="REMORAID",min=20},
      {id="CORSOLA",min=22}) },
    OPP_SWIMMER={ name="AQUATIC", pool=rows(
      {id="MARILL",min=14},{id="WOOPER",min=14},{id="CHINCHOU",min=18},
      {id="QWILFISH",min=20},{id="CORSOLA",min=22},{id="MANTINE",min=28},
      {id="OCTILLERY",min=30}) },
    OPP_SAILOR={ name="SEAFARING", pool=rows(
      {id="MARILL",min=15},{id="WOOPER",min=15},{id="CHINCHOU",min=18},
      {id="CORSOLA",min=22},{id="MANTINE",min=28}) },
    OPP_HIKER={ name="MOUNTAIN", pool=rows(
      {id="SUDOWOODO",min=18},{id="SHUCKLE",min=18},{id="GLIGAR",min=24},
      {id="PHANPY",min=22},{id="DONPHAN",min=32},{id="LARVITAR",min=35}) },
    OPP_ENGINEER={ name="MACHINES", pool=rows(
      {id="MAREEP",min=16},{id="FLAAFFY",min=20},{id="ELEKID",min=20}) },
    OPP_ROCKER={ name="ELECTRIC", pool=rows(
      {id="MAREEP",min=16},{id="FLAAFFY",min=20},{id="ELEKID",min=20},
      {id="AMPHAROS",min=32}) },
    OPP_PSYCHIC_TR={ name="PSYCHIC", pool=rows(
      {id="NATU",min=16},{id="UNOWN",min=18},{id="GIRAFARIG",min=25},
      {id="XATU",min=28},{id="ESPEON",min=32}) },
    OPP_BURGLAR={ name="FIRE", pool=rows(
      {id="SLUGMA",min=22},{id="HOUNDOUR",min=25},{id="MAGBY",min=25},
      {id="HOUNDOOM",min=36}) },
    OPP_SCIENTIST={ name="LAB", pool=rows(
      {id="PORYGON2",min=32},{id="SMOOCHUM",min=22},{id="ELEKID",min=22},
      {id="MAGBY",min=22}) },
    OPP_BIKER={ name="URBAN TOUGH", pool=rows(
      {id="MURKROW",min=22},{id="SNEASEL",min=28},{id="HOUNDOUR",min=25}) },
    OPP_CUE_BALL={ name="URBAN TOUGH", pool=rows(
      {id="MURKROW",min=22},{id="SNEASEL",min=28},{id="HOUNDOUR",min=25}) },
    OPP_TAMER={ name="FIERCE", pool=rows(
      {id="URSARING",min=32},{id="DONPHAN",min=32},{id="HOUNDOOM",min=36}) },
    OPP_POKEMANIAC={ name="RARE MONSTERS", pool=rows(
      {id="AIPOM",min=20},{id="DUNSPARCE",min=20},{id="STANTLER",min=26},
      {id="SMEARGLE",min=28},{id="URSARING",min=34}) },
    OPP_ROCKET={ name="ROCKET", pool=rows(
      {id="MURKROW",min=22},{id="SNEASEL",min=28},{id="HOUNDOUR",min=26},
      {id="ARIADOS",min=24}) },
  },

  gymThemes = {
    PEWTER_GYM={ name="ROCK GYM", pool=rows({id="SUDOWOODO",min=12},{id="SHUCKLE",min=16}) },
    CERULEAN_GYM={ name="WATER GYM", pool=rows({id="MARILL",min=16},{id="WOOPER",min=16},{id="CHINCHOU",min=20}) },
    VERMILION_GYM={ name="ELECTRIC GYM", pool=rows({id="MAREEP",min=18},{id="FLAAFFY",min=22},{id="ELEKID",min=22}) },
    CELADON_GYM={ name="GRASS GYM", pool=rows({id="HOPPIP",min=18},{id="SUNKERN",min=18},{id="BELLOSSOM",min=30}) },
    FUCHSIA_GYM={ name="POISON GYM", pool=rows({id="SPINARAK",min=20},{id="ARIADOS",min=26},{id="QWILFISH",min=28}) },
    SAFFRON_GYM={ name="PSYCHIC GYM", pool=rows({id="NATU",min=24},{id="GIRAFARIG",min=28},{id="XATU",min=30},{id="ESPEON",min=34}) },
    CINNABAR_GYM={ name="FIRE GYM", pool=rows({id="SLUGMA",min=28},{id="HOUNDOUR",min=30},{id="MAGBY",min=30},{id="HOUNDOOM",min=38}) },
    VIRIDIAN_GYM={ name="GROUND GYM", pool=rows({id="WOOPER",min=24},{id="GLIGAR",min=30},{id="PHANPY",min=28},{id="DONPHAN",min=38},{id="STEELIX",min=40}) },
  },

  -- Original signature aces stay in the final slot. These additions replace
  -- a non-ace slot only, so the battles remain recognizable.
  bosses = {
    OPP_BROCK={species="SUDOWOODO",slot=1}, OPP_MISTY={species="AZUMARILL",slot=1},
    OPP_LT_SURGE={species="AMPHAROS",slot=1}, OPP_ERIKA={species="BELLOSSOM",slot=1},
    OPP_KOGA={species="ARIADOS",slot=1}, OPP_SABRINA={species="ESPEON",slot=1},
    OPP_BLAINE={species="HOUNDOOM",slot=1}, OPP_GIOVANNI={species="STEELIX",slot=1},
    OPP_LORELEI={species="PILOSWINE",slot=2}, OPP_BRUNO={species="HITMONTOP",slot=2},
    OPP_AGATHA={species="MISDREAVUS",slot=3}, OPP_LANCE={species="KINGDRA",slot=3},
  },

  reviewedUnchanged = {
    OPP_RIVAL1=true, OPP_RIVAL2=true, OPP_RIVAL3=true,
    OPP_PROF_OAK=true, OPP_CHIEF=true, OPP_UNUSED_JUGGLER=true,
  },
}
