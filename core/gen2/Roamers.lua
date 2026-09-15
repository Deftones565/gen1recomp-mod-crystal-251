-- Gen 2 roaming legendary state and movement rules.
-- The battle engine remains Gen 1; this module owns only the persistent
-- overworld/encounter behavior that is being backported.
local Roamers = {}

-- Kanto routes connected through their intervening towns/gates. Keep every
-- node encounter-capable; the movement algorithm remains the Crystal one.
Roamers.SPECIES = {
  {species="RAIKOU", level=40, map="ROUTE_10"},
  {species="ENTEI", level=40, map="ROUTE_7"},
  {species="SUICUNE", level=40, map="ROUTE_14"},
}
Roamers.MAPS = {
  {map="ROUTE_1",to={"ROUTE_2","ROUTE_22"}},
  {map="ROUTE_2",to={"ROUTE_1","ROUTE_3","ROUTE_22"}},
  {map="ROUTE_3",to={"ROUTE_2","ROUTE_4"}},
  {map="ROUTE_4",to={"ROUTE_3","ROUTE_5","ROUTE_9","ROUTE_24"}},
  {map="ROUTE_5",to={"ROUTE_4","ROUTE_6","ROUTE_7","ROUTE_8"}},
  {map="ROUTE_6",to={"ROUTE_5","ROUTE_7","ROUTE_8","ROUTE_11"}},
  {map="ROUTE_7",to={"ROUTE_5","ROUTE_6","ROUTE_8","ROUTE_16"}},
  {map="ROUTE_8",to={"ROUTE_5","ROUTE_7","ROUTE_10","ROUTE_12"}},
  {map="ROUTE_9",to={"ROUTE_4","ROUTE_10","ROUTE_24"}},
  {map="ROUTE_10",to={"ROUTE_9","ROUTE_8","ROUTE_12"}},
  {map="ROUTE_11",to={"ROUTE_6","ROUTE_12"}},
  {map="ROUTE_12",to={"ROUTE_8","ROUTE_10","ROUTE_11","ROUTE_13"}},
  {map="ROUTE_13",to={"ROUTE_12","ROUTE_14"}},
  {map="ROUTE_14",to={"ROUTE_13","ROUTE_15"}},
  {map="ROUTE_15",to={"ROUTE_14","ROUTE_18"}},
  {map="ROUTE_16",to={"ROUTE_7","ROUTE_17"}},
  {map="ROUTE_17",to={"ROUTE_16","ROUTE_18"}},
  {map="ROUTE_18",to={"ROUTE_17","ROUTE_15"}},
  {map="ROUTE_22",to={"ROUTE_1","ROUTE_2","ROUTE_23"}},
  {map="ROUTE_23",to={"ROUTE_22"}},
  {map="ROUTE_24",to={"ROUTE_4","ROUTE_9","ROUTE_25"}},
  {map="ROUTE_25",to={"ROUTE_24"}},
}

local function r(random, n)
  if random then return random(n) end
  return math.random(n)
end

local function mapEntry(mapId)
  for _, row in ipairs(Roamers.MAPS) do
    if row.map == mapId then return row end
  end
end

function Roamers.init(state)
  if not state.roamers then
    state.roamers = {}
    for _, row in ipairs(Roamers.SPECIES) do
      state.roamers[#state.roamers+1] = {
        species=row.species, level=row.level, map=row.map, hp=0,
      }
    end
  end
  -- Move old Johto locations without reviving caught/defeated slots or
  -- replacing persistent DVs and damage. This also repairs partial saves.
  for _, slot in ipairs(state.roamers) do
    if slot.species and slot.map and not mapEntry(slot.map) then
      for _, row in ipairs(Roamers.SPECIES) do
        if slot.species == row.species then slot.map = row.map; break end
      end
    end
  end
  state.roamerMaps = state.roamerMaps or {}
  state.roamerMapVersion = 2
  return state.roamers
end

function Roamers.active(slot)
  return type(slot) == "table" and slot.species and slot.map
end

local function jump(playerMap, random)
  for _ = 1, 32 do
    local row = Roamers.MAPS[r(random, #Roamers.MAPS)]
    if row.map ~= playerMap then return row.map end
  end
end

function Roamers.update(state, playerMap, random)
  local list = Roamers.init(state)
  local last = state.roamerMaps.last
  for _, slot in ipairs(list) do
    if Roamers.active(slot) then
      local entry = mapEntry(slot.map)
      if entry then
        for _ = 1, 64 do
          local value = r(random, 256) - 1
          local masked = value % 32
          if masked == 0 then
            slot.map = jump(playerMap, random) or slot.map
            break
          end
          local candidate = entry.to[(masked % 4) + 1]
          if candidate and candidate ~= last then
            slot.map = candidate
            break
          end
        end
      end
    end
  end
  state.roamerMaps.last, state.roamerMaps.current = state.roamerMaps.current, playerMap
end

function Roamers.jumpAll(state, playerMap, random)
  for _, slot in ipairs(Roamers.init(state)) do
    if Roamers.active(slot) then slot.map = jump(playerMap, random) or slot.map end
  end
  state.roamerMaps.last, state.roamerMaps.current = state.roamerMaps.current, playerMap
end

-- Gen 2 checks this before selecting a normal encounter: 100/256, then a
-- three-way slot selection. Surfing is explicitly excluded.
function Roamers.checkEncounter(state, mapId, onWater, random)
  if onWater then return nil end
  local list = Roamers.init(state)
  if r(random, 256) - 1 >= 100 then return nil end
  local index = ((r(random, 4) - 1) % 4)
  if index == 0 then return nil end
  local slot = list[index]
  if Roamers.active(slot) and slot.map == mapId then
    return index, slot
  end
end

function Roamers.endBattle(state, index, outcome, hp, playerMap, random)
  local slot = state.roamers and state.roamers[index]
  if not Roamers.active(slot) then return end
  if outcome == "win" or outcome == "caught" then
    slot.species, slot.map, slot.hp, slot.dvs = nil, nil, 0, nil
  else
    slot.hp = math.max(0, math.min(255, hp or 0))
    Roamers.update(state, playerMap, random)
  end
end

function Roamers.afterWildBattle(state, playerMap, random)
  if not state.roamers or r(random, 16) - 1 ~= 0 then return end
  Roamers.update(state, playerMap, random)
end

Roamers.ALWAYS_FLEE = {RAIKOU=true, ENTEI=true}
Roamers.OFTEN_FLEE = {CUBONE=true, QUAGSIRE=true, DELIBIRD=true, PHANPY=true, TEDDIURSA=true}
Roamers.SOMETIMES_FLEE = {MAGNEMITE=true, GRIMER=true, TANGELA=true, MR__MIME=true,
  EEVEE=true, PORYGON=true, DRATINI=true, DRAGONAIR=true, TOGETIC=true,
  UMBREON=true, UNOWN=true, SNUBBULL=true, HERACROSS=true}

return Roamers
