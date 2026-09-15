-- Exhaustive ROM-backed acquisition and compatibility audit for Crystal 251.
--
-- Verifies every live TM01-TM50 and HM01-HM07 has an ordinary gameplay
-- source, then applies that machine to one genuinely compatible and one
-- genuinely incompatible Pokemon from the imported Crystal data.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local romPath = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(romPath, "rb")
if not file then
  print("SKIP Crystal machine full audit (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local addresses = require("mods.CRYSTAL_251.addresses")
local run, cache = require("mods.CRYSTAL_251.tests._real_rom_mod").load(T, raw)
local Data = run.data
T.eq(#run.errors, 0, "Crystal 251 loads for the full machine audit")

local SCRIPT_FILES = {
  "data/scripts/story.lua",
  "data/scripts/story3.lua",
  "data/scripts/story4.lua",
  "data/scripts/story5.lua",
  "data/scripts/victories.lua",
}
local scriptText = {}
for _, path in ipairs(SCRIPT_FILES) do
  local source = assert(io.open(path, "rb"), "missing acquisition source " .. path)
  scriptText[path] = source:read("*a")
  source:close()
end

local function containsId(text, id)
  return text:find("%f[%w_]" .. id .. "%f[^%w_]", 1) ~= nil
end

local sources = {}
local function record(itemId, description)
  sources[itemId] = sources[itemId] or {}
  sources[itemId][#sources[itemId] + 1] = description
end

-- Visible item balls, including HM07 in Seafoam Islands.
for mapId, map in pairs(run.data.maps or {}) do
  for _, object in ipairs(map.objects or {}) do
    if object.item then record(object.item, "item ball:" .. mapId) end
  end
end

-- Pokemart machine inventories.
for mapLabel, pointers in pairs(run.data.text_pointers or {}) do
  for _, pointer in pairs(pointers) do
    if type(pointer) == "table" then
      for _, itemId in ipairs(pointer.mart or {}) do
        record(itemId, "mart:" .. mapLabel)
      end
    end
  end
end

-- Scripted gifts, Gym rewards, drink trades, Game Corner prizes, and the
-- five native HM rewards. Restrict the scan to the actual acquisition modules
-- above so incidental dialogue checks cannot masquerade as an item source.
for itemId in pairs(run.data.items) do
  for path, text in pairs(scriptText) do
    if containsId(text, itemId) then record(itemId, "script:" .. path) end
  end
end

-- HM06 is a mod-composed declarative gift rather than a base source file.
local progression = assert(run.loader.exports.CRYSTAL_251.machineProgression,
  "Crystal machine progression metadata is exported")
T.eq(progression.hm06.method, "gift", "HM06 keeps Crystal's gift method")
T.eq(progression.hm06.map, "ROCKET_HIDEOUT_B4F",
  "HM06 gift follows the Rocket operation")
record("HM_06", "gift:" .. progression.hm06.map)
T.eq(progression.hm07.method, "item_ball", "HM07 keeps Crystal's pickup method")
T.eq(progression.hm07.map, "SEAFOAM_ISLANDS_B4F",
  "HM07 pickup is in the ice-cave equivalent")

local machines = {}
local seenSlots = {}
for itemId, def in pairs(run.data.items) do
  local machine = type(def) == "table" and def.machine or nil
  if machine and ((machine.kind == "TM" and machine.number <= 50)
      or (machine.kind == "HM" and machine.number <= 7)) then
    local slot = machine.kind .. string.format("%02d", machine.number)
    T.check(not seenSlots[slot], slot .. " has exactly one live item definition")
    seenSlots[slot] = itemId
    machines[#machines + 1] = {
      slot=slot, itemId=itemId, def=def, move=machine.move,
      kind=machine.kind, number=machine.number,
    }
  end
end
table.sort(machines, function(a, b)
  if a.kind ~= b.kind then return a.kind < b.kind end
  return a.number < b.number
end)

T.eq(#machines, 57, "all 50 TMs and seven HMs are live")
for n = 1, 50 do T.check(seenSlots[("TM%02d"):format(n)],
  ("TM%02d exists"):format(n)) end
for n = 1, 7 do T.check(seenSlots[("HM%02d"):format(n)],
  ("HM%02d exists"):format(n)) end

local ItemEffects = require("src.inventory.ItemEffects")
local accepted, rejected = 0, 0
for _, row in ipairs(machines) do
  local good, bad
  for speciesId, pokemon in pairs(run.data.pokemon) do
    if pokemon.dex and pokemon.dex <= 251 then
      local compatible = false
      for _, moveId in ipairs(pokemon.tmhm or {}) do
        if moveId == row.move then compatible = true break end
      end
      if compatible and not good then good = speciesId end
      if not compatible and not bad then bad = speciesId end
      if good and bad then break end
    end
  end

  T.check(sources[row.itemId] and #sources[row.itemId] > 0,
    row.slot .. " has an ordinary acquisition source")
  T.check(good ~= nil, row.slot .. " has a compatible Pokemon")
  T.check(bad ~= nil, row.slot .. " has an incompatible Pokemon")

  local goodMon = { species=good, moves={} }
  local result, moveId = ItemEffects.use(run.data,
    { player={name="RED"}, inventory={ [row.itemId]=1 } },
    row.itemId, goodMon, nil)
  local expected = row.kind == "HM" and "learnkept" or "learn"
  T.eq(result, expected,
    row.slot .. " accepts a Crystal-compatible Pokemon with correct consumption")
  T.eq(moveId, row.move, row.slot .. " applies the mapped Crystal move")
  accepted = accepted + 1

  local badMon = { species=bad, moves={} }
  local denied, messages = ItemEffects.use(run.data,
    { player={name="RED"}, inventory={ [row.itemId]=1 } },
    row.itemId, badMon, nil)
  T.eq(denied, "failed", row.slot .. " rejects an incompatible Pokemon")
  T.check(type(messages) == "table" and #messages > 0,
    row.slot .. " returns a rejection message")
  T.eq(#badMon.moves, 0, row.slot .. " does not alter the rejected Pokemon")
  rejected = rejected + 1
end

T.eq(accepted, 57, "every machine accepts a positive compatibility control")
T.eq(rejected, 57, "every machine rejects a negative compatibility control")

print(("PASS Crystal machine full audit: %d/57 obtainable, accepted, and rejected")
  :format(#machines))
