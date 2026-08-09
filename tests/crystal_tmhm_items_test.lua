package.path = "./?.lua;./?/init.lua;" .. package.path

local Machines = require("mods.CRYSTAL_251.lib.crystal_machines")
local Catalog = require("mods.CRYSTAL_251.catalog")

local checks, passed = 0, 0
local function eq(actual, expected, message)
  checks = checks + 1
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 0)
  end
  passed = passed + 1
end

local items = { POTION = { id="POTION", name="POTION" } }
for n = 1, 50 do
  items[("GEN1_TM_%02d"):format(n)] = {
    id=("GEN1_TM_%02d"):format(n), name=("TM%02d"):format(n),
    machine={ kind="TM", number=n, move="GEN1_MOVE_"..n },
  }
end
for n = 1, 7 do
  items[("HM_%02d"):format(n)] = {
    id=("HM_%02d"):format(n), name=("HM%02d"):format(n),
    machine={ kind="HM", number=n, move="OLD_HM_"..n },
  }
end
items.UNKNOWN_MACHINE = {
  id="UNKNOWN_MACHINE", machine={ kind="TM", number=51, move="LEAVE_ME" },
}

local registry = {}
function registry:each() return pairs(items) end
function registry:patch(id, partial)
  local old = assert(items[id])
  for key, value in pairs(partial) do old[key] = value end
end

local changed = Machines.patchItems({ content={ items=registry } })
eq(changed, 57, "all synthetic TM/HM records are remapped")
for n = 1, 50 do
  eq(items[("GEN1_TM_%02d"):format(n)].machine.move, Catalog.tmItems[n],
    ("TM%02d mapping"):format(n))
end
for n = 1, 7 do
  eq(items[("HM_%02d"):format(n)].machine.move, Catalog.tmItems[50+n],
    ("HM%02d mapping"):format(n))
end
eq(items.GEN1_TM_01.machine.move, "DYNAMICPUNCH", "TM01 is DynamicPunch")
eq(items.GEN1_TM_02.machine.move, "HEADBUTT", "TM02 is Headbutt")
eq(items.GEN1_TM_03.machine.move, "CURSE", "TM03 is Curse")
eq(items.HM_06.machine.move, "WHIRLPOOL", "HM06 is Whirlpool")
eq(items.HM_07.machine.move, "WATERFALL", "HM07 is Waterfall")
eq(items.UNKNOWN_MACHINE.machine.move, "LEAVE_ME", "unknown machine numbers are untouched")
eq(items.POTION.machine, nil, "non-machine items are untouched")

print(("%d/%d checks passed (Crystal TM/HM item mapping)"):format(passed, checks))
