local Ecology = {}

local LEGENDARY = {
  ARTICUNO=true, ZAPDOS=true, MOLTRES=true, MEWTWO=true, MEW=true,
  RAIKOU=true, ENTEI=true, SUICUNE=true, LUGIA=true, HO_OH=true, CELEBI=true,
}

local PERIOD = {
  MORNING="morning", DAY="day", EVENING="night", NIGHT="night",
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for key, child in pairs(value) do out[key] = copy(child) end
  return out
end

local function speciesOf(entry)
  return type(entry) == "table" and entry[1] or entry
end

local function levelOf(entry, fallback)
  return type(entry) == "table" and entry[2] or fallback
end

local function buildGroup(source, entries, pokemon, mapId, terrain, period)
  assert(source and source.slots and #source.slots == 10,
    ("Crystal ecology needs a ten-slot source at %s/%s"):format(mapId, terrain))
  assert(type(entries) == "table" and #entries == 10,
    ("Crystal ecology %s/%s/%s must define exactly ten slots")
      :format(mapId, terrain, period))
  local slots = {}
  for index, entry in ipairs(entries) do
    local species = speciesOf(entry)
    assert(pokemon[species], ("Crystal ecology %s/%s/%s references unknown %s")
      :format(mapId, terrain, period, tostring(species)))
    local level = levelOf(entry, source.slots[index].level)
    assert(type(level) == "number" and level >= 2 and level <= 100,
      ("Crystal ecology %s/%s/%s slot %d has invalid level")
        :format(mapId, terrain, period, index))
    slots[index] = { species=species, level=level }
  end
  return { rate=source.rate, slots=slots }
end

function Ecology.install(mod, cache)
  local definitions = require("mods.CRYSTAL_251.ecology_data")
  local original, pokemon = {}, {}
  for id, encounter in mod.content.encounters:each() do original[id] = copy(encounter) end
  for id, species in mod.content.pokemon:each() do pokemon[id] = species end

  local groups, direct, mapCount, groupCount = {}, {}, 0, 0
  for mapId, mapDef in pairs(definitions.maps) do
    local source = assert(original[mapId], "Crystal ecology map is unavailable: " .. mapId)
    groups[mapId] = { tier=mapDef.tier }
    mapCount = mapCount + 1
    local patch = {}
    for terrain, periods in pairs(mapDef) do
      if terrain ~= "tier" then
        local sourceGroup = assert(source[terrain],
          ("Crystal ecology terrain is unavailable: %s/%s"):format(mapId, terrain))
        local compiled = {}
        for _, period in ipairs({ "morning", "day", "night", "combined" }) do
          compiled[period] = buildGroup(sourceGroup, assert(periods[period]), pokemon,
            mapId, terrain, period)
          for _, slot in ipairs(compiled[period].slots) do direct[slot.species] = true end
        end
        groups[mapId][terrain] = compiled
        patch[terrain] = copy(compiled.combined)
        groupCount = groupCount + 1
      end
    end
    mod.content.encounters:patch(mapId, patch)
  end

  -- Every existing wild map is curated. Failing here is preferable to a new
  -- imported version silently retaining the old arbitrary encounter table.
  for mapId, encounter in pairs(original) do
    if (encounter.grass or encounter.water) and not groups[mapId] then
      error("Crystal ecology has no curated template for " .. mapId)
    end
  end

  local currentTod, providerObserved = "DAY", false
  mod.hooks:wrap("world.tod", function(next, tod, ctx)
    local out = next(tod, ctx)
    if type(out) == "string" and out ~= "" then
      currentTod = out:upper()
      if out ~= tod then providerObserved = true end
    end
    return out
  end, 100)

  local dramatic = mod.find("DRAMATIC_SHAPE")
  if dramatic then providerObserved = true end

  local function activePeriod()
    if mod.options:get("time_spawns") == "off" or not providerObserved then
      return "combined"
    end
    return PERIOD[currentTod] or "day"
  end

  -- Roaming Events (120) and Crystal legendaries (70) remain outside this
  -- link. Their ordinary roll therefore comes from the correct time table,
  -- and their replacement probabilities and persistent state are unchanged.
  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    local map = ctx and groups[ctx.mapId]
    local terrain = ctx and ctx.terrain == "water" and "water" or "grass"
    local variants = map and map[terrain]
    if not variants then return next(encDef, ctx) end
    local selected = variants[activePeriod()] or variants.combined
    local replacement = copy(encDef)
    replacement[terrain] = selected
    return next(replacement, ctx)
  end, 20)

  local function list()
    local out = {}
    for mapId, map in pairs(groups) do
      for _, terrain in ipairs({ "grass", "water" }) do
        local variants = map[terrain]
        if variants then
          for _, period in ipairs({ "morning", "day", "night", "combined" }) do
            out[#out + 1] = { mapId=mapId, terrain=terrain, period=period,
              tier=map.tier, group=copy(variants[period]) }
          end
        end
      end
    end
    table.sort(out, function(a,b)
      local ak, bk = a.mapId .. a.terrain .. a.period, b.mapId .. b.terrain .. b.period
      return ak < bk
    end)
    return out
  end

  local ordinary = 0
  for _, species in ipairs(cache.species) do
    if not LEGENDARY[species.id] and direct[species.id] then ordinary = ordinary + 1 end
  end
  return {
    version=2, maps=mapCount, groups=groupCount, direct=direct,
    directlyWild=ordinary, list=list, period=activePeriod,
    providerActive=function() return providerObserved end,
    usesTime=function()
      return mod.options:get("time_spawns") ~= "off" and providerObserved
    end,
  }
end

return Ecology
