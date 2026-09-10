-- Keep Gen1Recomp's existing machine item ids/save data, but reinterpret each
-- TM/HM by its displayed machine number using Pokemon Crystal's machine table.
-- The Kanto engine names TM item ids after their Gen I move (TM_MEGA_PUNCH,
-- etc.), so replacing ids would break scripts and existing inventories. Only
-- machine.move changes; names, prices, ids and story rewards stay intact.
local Catalog = require("mods.CRYSTAL_251.catalog")

local Machines = {}

-- The Kanto overworld keeps the original Red/Blue TM balls and rewards.  The
-- imported Crystal learnset table is still used for Gen 2 compatibility, but
-- machine contents at those Gen 1 locations must remain the Gen 1 contents.
Machines.GEN1_TM_MOVES = {
  "MEGA_PUNCH", "RAZOR_WIND", "SWORDS_DANCE", "WHIRLWIND", "MEGA_KICK",
  "TOXIC", "HORN_DRILL", "BODY_SLAM", "TAKE_DOWN", "DOUBLE_EDGE",
  "BUBBLEBEAM", "WATER_GUN", "ICE_BEAM", "BLIZZARD", "HYPER_BEAM",
  "PAY_DAY", "SUBMISSION", "COUNTER", "SEISMIC_TOSS", "RAGE",
  "MEGA_DRAIN", "SOLARBEAM", "DRAGON_RAGE", "THUNDERBOLT", "THUNDER",
  "EARTHQUAKE", "FISSURE", "DIG", "PSYCHIC_M", "TELEPORT", "MIMIC",
  "DOUBLE_TEAM", "REFLECT", "BIDE", "METRONOME", "SELFDESTRUCT",
  "EGG_BOMB", "FIRE_BLAST", "SWIFT", "SKULL_BASH", "SOFTBOILED",
  "DREAM_EATER", "SKY_ATTACK", "REST", "THUNDER_WAVE", "PSYWAVE",
  "EXPLOSION", "ROCK_SLIDE", "TRI_ATTACK", "SUBSTITUTE",
}

function Machines.moveFor(kind, number)
  number = tonumber(number)
  if not number or number % 1 ~= 0 then return nil end
  if kind == "TM" and number >= 1 and number <= 50 then
    return Catalog.tmItems[number]
  end
  if kind == "HM" and number >= 1 and number <= 7 then
    return Catalog.tmItems[50 + number]
  end
  return nil
end

function Machines.patchItems(mod)
  local pending = {}
  for id, def in mod.content.items:each() do
    local machine = type(def) == "table" and def.machine or nil
    local move = machine and Machines.moveFor(machine.kind, machine.number)
    if move and machine.move ~= move then
      pending[#pending + 1] = {
        id = id,
        machine = {
          kind = machine.kind,
          number = machine.number,
          move = move,
        },
      }
    end
  end
  -- Do not mutate the registry while iterating its folded view.
  for _, row in ipairs(pending) do
    mod.content.items:patch(row.id, { machine = row.machine })
  end
  return #pending
end

function Machines.restoreGen1Items(mod)
  local pending = {}
  for id, def in mod.content.items:each() do
    local machine = type(def) == "table" and def.machine or nil
    local move = machine and machine.kind == "TM"
      and Machines.GEN1_TM_MOVES[tonumber(machine.number)]
    if move and machine.move ~= move then
      pending[#pending + 1] = { id=id, machine={ kind="TM",
        number=machine.number, move=move } }
    end
  end
  for _, row in ipairs(pending) do mod.content.items:patch(row.id, {machine=row.machine}) end
  return #pending
end

return Machines
