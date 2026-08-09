package.path = "./?.lua;./?/init.lua;" .. package.path

local Held = require("mods.CRYSTAL_251.held_item_management")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n")
      :format(label, tostring(got), tostring(want)))
  end
end
local function ok(value, label) eq(not not value, true, label) end

local function fixture(capacity)
  return {
    constants = { bagSize = capacity or 20 },
    pokemon = { PIKACHU = { name = "PIKACHU" } },
    items = {
      LEFTOVERS = { name = "LEFTOVERS" },
      BERRY = { name = "BERRY" },
      GOLD_BERRY = { name = "GOLD BERRY" },
      FLOWER_MAIL = { name = "FLOWER MAIL", isMail = true },
      BICYCLE = { name = "BICYCLE", keyItem = true },
      TM_TEST = { name = "TM01", machine = { kind = "TM", move = "TACKLE" } },
    },
  }
end

local data = fixture()
local save = { inventory = { LEFTOVERS = 1 }, bagOrder = { "LEFTOVERS" } }
local mon = { species = "PIKACHU" }
local success, result = Held.give(data, save, mon, "LEFTOVERS")
ok(success, "Give accepts an ordinary item")
eq(result, "given", "Give reports a new held item")
eq(mon.heldItem, "LEFTOVERS", "Give applies the item to the Pokemon")
eq(save.inventory.LEFTOVERS, nil, "Give removes one item from the bag")
eq(#save.bagOrder, 0, "Give removes an emptied bag slot from its order")

success, result = Held.take(data, save, mon)
ok(success, "Take accepts a held item")
eq(result, "taken", "Take reports success")
eq(mon.heldItem, nil, "Take clears the Pokemon held item")
eq(save.inventory.LEFTOVERS, 1, "Take returns the item to the bag")
eq(save.bagOrder[1], "LEFTOVERS", "Take restores bag order")

save = { inventory = { BERRY = 2 }, bagOrder = { "BERRY" } }
mon.heldItem = "LEFTOVERS"
success, result = Held.give(data, save, mon, "BERRY")
ok(success, "Give switches an existing held item")
eq(result, "swapped", "switch reports swapped")
eq(mon.heldItem, "BERRY", "switch applies the selected item")
eq(save.inventory.BERRY, 1, "switch spends one selected item")
eq(save.inventory.LEFTOVERS, 1, "switch returns the previous item")

for _, row in ipairs({
  { "FLOWER_MAIL", "mail" },
  { "BICYCLE", "key_item" },
  { "TM_TEST", "machine" },
}) do
  save.inventory[row[1]] = 1
  success, result = Held.give(data, save, mon, row[1])
  eq(success, false, row[1] .. " is rejected")
  eq(result, row[2], row[1] .. " rejection reason")
  eq(save.inventory[row[1]], 1, row[1] .. " remains in the bag")
  eq(mon.heldItem, "BERRY", row[1] .. " does not replace the held item")
end

local egg = { species = "EGG", isEgg = true }
success, result = Held.give(data, save, egg, "LEFTOVERS")
eq(success, false, "Egg rejects held items")
eq(result, "egg", "Egg rejection is explicit")

data = fixture(1)
save = { inventory = { BERRY = 2 }, bagOrder = { "BERRY" } }
mon = { species = "PIKACHU", heldItem = "LEFTOVERS" }
success, result = Held.give(data, save, mon, "BERRY")
eq(success, false, "full bag rejects a switch that needs another slot")
eq(result, "bag_full", "full bag switch reports capacity")
eq(mon.heldItem, "LEFTOVERS", "failed switch preserves held item")
eq(save.inventory.BERRY, 2, "failed switch preserves selected stack")
eq(#save.bagOrder, 1, "failed switch preserves bag order")

save = { inventory = { BERRY = 1 }, bagOrder = { "BERRY" } }
success, result = Held.give(data, save, mon, "BERRY")
ok(success, "switch can reuse the selected item's emptied slot")
eq(mon.heldItem, "BERRY", "slot-reusing switch equips selected item")
eq(save.inventory.LEFTOVERS, 1, "slot-reusing switch returns old item")
eq(save.bagOrder[1], "LEFTOVERS", "slot-reusing switch has correct order")

save = { inventory = { BERRY = 1 }, bagOrder = { "BERRY" } }
mon = { species = "PIKACHU", heldItem = "LEFTOVERS" }
success, result = Held.take(data, save, mon)
eq(success, false, "Take rejects a full bag")
eq(result, "bag_full", "Take reports full bag")
eq(mon.heldItem, "LEFTOVERS", "failed Take preserves held item")
eq(save.inventory.BERRY, 1, "failed Take preserves inventory")

local registered, partyHook
local mod = {
  content = { screens = { register = function(_, id, def)
    registered = { id = id, def = def }
  end } },
  hooks = { wrap = function(_, name, fn)
    if name == "ui.party.submenu" then partyHook = fn end
  end },
  ui = require("src.ui.ModUI"),
}
Held.install(mod)
eq(registered.id, "Crystal251HeldItemPicker", "picker is a mod-owned screen")
ok(type(registered.def.new) == "function", "picker screen has a factory")
ok(type(partyHook) == "function", "party submenu hook is installed")

local base = { { label = "STATS" }, { label = "SWITCH" } }
local fieldItems = partyHook(function(_, items) return items end, {}, base,
  { species = "PIKACHU" }, { battle = false })
eq(fieldItems[3].label, "ITEM", "ITEM is available from the field party menu")
local battleItems = { { label = "SWITCH" }, { label = "STATS" } }
battleItems = partyHook(function(_, items) return items end, {}, battleItems,
  { species = "PIKACHU" }, { battle = true })
eq(#battleItems, 2, "ITEM is absent from the battle party menu")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (held-item management)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (held-item management)"):format(checks, checks))
