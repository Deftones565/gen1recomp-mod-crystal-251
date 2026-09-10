-- Canonical evolution policy for Crystal species in Gen1Recomp's
-- single-player Kanto world. Keep this independent of the ROM cache so old
-- imports receive the same rules as newly extracted data.

local Evolutions = {}

-- Older Crystal caches were generated before the Gen 2 happiness method was
-- available and encoded these rows as level/stone evolutions. Normalize them
-- at load time so an existing cache receives the real Gen 2 trigger too.
local happinessTargets = {
  PIKACHU="ANYTIME", CLEFAIRY="ANYTIME", JIGGLYPUFF="ANYTIME",
  TOGETIC="ANYTIME", CROBAT="ANYTIME", BLISSEY="ANYTIME",
  ESPEON="MORNDAY", UMBREON="NITE",
}

Evolutions.levelTrades = {
  KADABRA = { species = "ALAKAZAM", level = 36 },
  MACHOKE = { species = "MACHAMP", level = 40 },
  GRAVELER = { species = "GOLEM", level = 40 },
  HAUNTER = { species = "GENGAR", level = 36 },
}

Evolutions.itemTrades = {
  POLIWHIRL = { species = "POLITOED", item = "KINGS_ROCK" },
  SLOWPOKE = { species = "SLOWKING", item = "KINGS_ROCK" },
  ONIX = { species = "STEELIX", item = "METAL_COAT" },
  SCYTHER = { species = "SCIZOR", item = "METAL_COAT" },
  SEADRA = { species = "KINGDRA", item = "DRAGON_SCALE" },
  PORYGON = { species = "PORYGON2", item = "UP_GRADE" },
}

Evolutions.requiredItems = {
  "KINGS_ROCK", "METAL_COAT", "DRAGON_SCALE", "UP_GRADE",
}

local function copy(row)
  local out = {}
  for key, value in pairs(row or {}) do out[key] = value end
  return out
end

function Evolutions.normalize(species, rows)
  local levelRule, itemRule = Evolutions.levelTrades[species],
    Evolutions.itemTrades[species]
  local out, found = {}, false
  for _, source in ipairs(rows or {}) do
    local row = copy(source)
    if row.method == "EVOLVE_HAPPINESS" then
      row = { method="EVOLVE_HAPPINESS_ANYTIME", species=row.species }
    elseif happinessTargets[row.species]
       and ((row.method == "LEVEL" and not levelRule)
         or (species == "EEVEE" and row.method == "ITEM")) then
      row = { method="EVOLVE_HAPPINESS_" .. happinessTargets[row.species],
        species=row.species }
    end
    if levelRule and row.species == levelRule.species then
      row = { method = "LEVEL", level = levelRule.level,
        species = levelRule.species }
      found = true
    elseif itemRule and row.species == itemRule.species then
      row = { method = "ITEM", item = itemRule.item,
        species = itemRule.species }
      found = true
    end
    out[#out + 1] = row
  end
  -- Retail Crystal always supplies these rows. The append makes the runtime
  -- policy resilient to an older or partially generated cache as well.
  local rule = levelRule or itemRule
  if rule and not found then
    if levelRule then
      out[#out + 1] = { method = "LEVEL", level = rule.level,
        species = rule.species }
    else
      out[#out + 1] = { method = "ITEM", item = rule.item,
        species = rule.species }
    end
  end
  return out
end

return Evolutions
