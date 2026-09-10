-- Gen 2 roaming legendary state and movement rules.
-- The battle engine remains Gen 1; this module owns only the persistent
-- overworld/encounter behavior that is being backported.
local Roamers = {}

Roamers.SPECIES = {
  {species="RAIKOU", level=40, map="ROUTE_42"},
  {species="ENTEI", level=40, map="ROUTE_37"},
  {species="SUICUNE", level=40, map="ROUTE_38"},
}

Roamers.MAPS = {
  {map="ROUTE_29",to={"ROUTE_30","ROUTE_46"}},
  {map="ROUTE_30",to={"ROUTE_29","ROUTE_31"}},
  {map="ROUTE_31",to={"ROUTE_30","ROUTE_32","ROUTE_36"}},
  {map="ROUTE_32",to={"ROUTE_36","ROUTE_31","ROUTE_33"}},
  {map="ROUTE_33",to={"ROUTE_32","ROUTE_34"}},
  {map="ROUTE_34",to={"ROUTE_33","ROUTE_35"}},
  {map="ROUTE_35",to={"ROUTE_34","ROUTE_36"}},
  {map="ROUTE_36",to={"ROUTE_35","ROUTE_31","ROUTE_32","ROUTE_37"}},
  {map="ROUTE_37",to={"ROUTE_36","ROUTE_38","ROUTE_42"}},
  {map="ROUTE_38",to={"ROUTE_37","ROUTE_39","ROUTE_42"}},
  {map="ROUTE_39",to={"ROUTE_38"}},
  {map="ROUTE_42",to={"ROUTE_43","ROUTE_44","ROUTE_37","ROUTE_38"}},
  {map="ROUTE_43",to={"ROUTE_42","ROUTE_44"}},
  {map="ROUTE_44",to={"ROUTE_42","ROUTE_43","ROUTE_45"}},
  {map="ROUTE_45",to={"ROUTE_44","ROUTE_46"}},
  {map="ROUTE_46",to={"ROUTE_45","ROUTE_29"}},
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
  if state.roamers then return state.roamers end
  state.roamers = {}
  for _, row in ipairs(Roamers.SPECIES) do
    state.roamers[#state.roamers+1] = {
      species=row.species, level=row.level, map=row.map, hp=0,
    }
  end
  state.roamerMaps = {}
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
