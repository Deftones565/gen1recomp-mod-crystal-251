-- Keep Gen1Recomp's existing machine item ids/save data, but reinterpret each
-- TM/HM by its displayed machine number using Pokemon Crystal's machine table.
-- The Kanto engine names TM item ids after their Gen I move (TM_MEGA_PUNCH,
-- etc.), so replacing ids would break scripts and existing inventories. Only
-- machine.move changes; names, prices, ids and story rewards stay intact.
local Catalog = require("mods.CRYSTAL_251.catalog")

local Machines = {}

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

return Machines
