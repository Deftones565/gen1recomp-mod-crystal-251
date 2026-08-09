-- Crystal held-item management visual audit.
--
-- This first transaction-tests every live item definition, then drives the
-- real field PartyMenu ITEM command through Give, Switch, Take, and every
-- rejection class. It captures each visible state and restores the player's
-- original party/bag references without invoking Save.
--
-- Run from the repository root with Crystal 251 enabled and imported:
--
--   SHOT_DIR=/tmp/crystal-held-item-visual \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_held_item_visual_driver.lua \
--   POKEPORT_TOUCH=0 POKEPORT_SPEED=20 love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Bag = require("src.inventory.Bag")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")
  local ListMenu = require("src.ui.ListMenu")
  local Menu = require("src.ui.Menu")
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local Held = require("mods.CRYSTAL_251.held_item_management")

  local DIR = os.getenv("SHOT_DIR") or "/tmp/crystal-held-item-visual"
  local originalParty = game.save.party
  local originalInventory = game.save.inventory
  local originalBagOrder = game.save.bagOrder
  local originalOverworld = game.overworld

  local function restoreTestSave()
    game.save.party = originalParty
    game.save.inventory = originalInventory
    game.save.bagOrder = originalBagOrder
    game.overworld = originalOverworld
  end

  local function fail(message, name)
    U.log("FAIL", message)
    U.shot(game, DIR .. "/FAIL_" .. tostring(name or "held_item") .. ".png")
    restoreTestSave()
    error(message, 0)
  end

  local function check(condition, message, name)
    if not condition then fail(message, name) end
  end

  local function shot(name)
    check(U.shot(game, DIR .. "/" .. name .. ".png"),
      "screenshot did not reach disk: " .. name, name)
  end

  local function finishText(box)
    box = box or game.stack:top()
    check(getmetatable(box) == TextBox, "expected a TextBox", "expected_text")
    game.input.state.a = true
    for _ = 1, 160 do
      if box.done or box.waiting then break end
      U.wait(1)
    end
    game.input.state.a = false
    U.wait(2)
    check(box.done or box.waiting, "text did not finish typing", "unfinished_text")
    return box
  end

  local function dismissText()
    local box = game.stack:top()
    finishText(box)
    U.tap(game, "a")
    U.wait(2)
  end

  local function moveTo(menu, wanted)
    local function cursor()
      -- PartyMenu retains the selected Pokemon in .index while its command
      -- box uses .subIndex. Prefer the latter only while that box is open.
      if menu.submenu then return menu.subIndex or 1 end
      return menu.index or 1
    end
    local current = cursor()
    while current < wanted do
      U.tap(game, "down")
      U.wait(1)
      current = cursor()
    end
    while current > wanted do
      U.tap(game, "up")
      U.wait(1)
      current = cursor()
    end
  end

  local function rowWith(items, predicate)
    for i, row in ipairs(items or {}) do
      if predicate(row) then return i, row end
    end
    return nil
  end

  local function openItemMenu(party)
    check(game.stack:top() == party and getmetatable(party) == PartyMenu,
      "PartyMenu is not active", "party_not_active")
    U.tap(game, "a")
    U.wait(2)
    check(party.submenu and party.subItems, "Pokemon submenu did not open",
      "submenu_missing")
    local index = rowWith(party.subItems, function(row) return row.label == "ITEM" end)
    check(index, "field PartyMenu has no ITEM command", "item_command_missing")
    moveTo(party, index)
    U.tap(game, "a")
    U.wait(2)
    local menu = game.stack:top()
    check(getmetatable(menu) == Menu, "ITEM did not open Give/Take menu",
      "item_menu_missing")
    return menu
  end

  local function chooseMenuLabel(menu, label)
    local index = rowWith(menu.items, function(row) return row.label == label end)
    check(index, "menu has no " .. label .. " row", "missing_" .. label:lower())
    moveTo(menu, index)
    U.tap(game, "a")
    U.wait(2)
    return game.stack:top()
  end

  local function choosePickerItem(list, itemId)
    check(getmetatable(list) == ListMenu,
      "GIVE did not open the held-item picker", "picker_missing")
    local index = rowWith(list.items, function(row) return row.value == itemId end)
    check(index, itemId .. " is absent from the picker", "picker_" .. itemId)
    moveTo(list, index)
    U.tap(game, "a")
    U.wait(2)
    return game.stack:top()
  end

  check(game.data and game.data.items and game.data.pokemon.PIKACHU,
    "Crystal game data is not initialized", "data")
  check(game.data.items.LEFTOVERS and game.data.items.BERRY
      and game.data.items.FLOWER_MAIL and game.data.items.BICYCLE,
    "required held-item visual fixtures are missing", "fixtures")

  local machineId
  for id, def in pairs(game.data.items) do
    if def.machine and (not machineId
        or (def.machine.kind .. string.format("%02d", def.machine.number or 0))
          < (game.data.items[machineId].machine.kind
            .. string.format("%02d", game.data.items[machineId].machine.number or 0))) then
      machineId = id
    end
  end
  check(machineId, "no live TM/HM item found", "machine_fixture")

  -- Exhaustive transaction preflight. Every ordinary live item must survive a
  -- complete Give/Take round trip; every special pocket must be rejected with
  -- no mutation. This is deliberately independent of the representative
  -- screenshots below.
  local ids = {}
  for id in pairs(game.data.items) do ids[#ids + 1] = id end
  table.sort(ids)
  local holdable, rejected = 0, { mail = 0, key_item = 0, machine = 0 }
  for _, id in ipairs(ids) do
    local def = game.data.items[id]
    local expectedReason = (def.isMail or def.mail) and "mail"
      or (def.keyItem or Bag.isBadge(id)) and "key_item"
      or def.machine and "machine" or nil
    local probe = Pokemon.new(game.data, "PIKACHU", 20)
    local probeSave = { inventory = { [id] = 1 }, bagOrder = { id } }
    local success, reason = Held.give(game.data, probeSave, probe, id)
    if expectedReason then
      check(not success and reason == expectedReason,
        ("%s should reject as %s, got %s"):format(id, expectedReason, tostring(reason)),
        "classification_" .. id)
      check(probe.heldItem == nil and probeSave.inventory[id] == 1,
        id .. " rejection mutated state", "rejection_mutated_" .. id)
      rejected[expectedReason] = rejected[expectedReason] + 1
    else
      check(success and probe.heldItem == id and probeSave.inventory[id] == nil,
        id .. " could not be held", "give_" .. id)
      success, reason = Held.take(game.data, probeSave, probe)
      check(success and reason == "taken" and probe.heldItem == nil
          and probeSave.inventory[id] == 1,
        id .. " failed its Take round trip", "take_" .. id)
      holdable = holdable + 1
    end
  end
  U.log(("exhaustive preflight PASS: %d holdable; %d Mail, %d key, %d machine rejected")
    :format(holdable, rejected.mail, rejected.key_item, rejected.machine))

  -- PartyMenu is opaque, so it can sit over the boot screen without entering
  -- the overworld. Preserve that base stack: popping a boot state may request
  -- application shutdown as part of its normal lifecycle.
  local baseDepth = #game.stack.states
  game.overworld = nil
  local mon = Pokemon.new(game.data, "PIKACHU", 20)
  game.save.party = { mon }
  game.save.inventory = {}
  game.save.bagOrder = {}
  for _, id in ipairs({ "LEFTOVERS", "BERRY", "FLOWER_MAIL", "BICYCLE", machineId }) do
    check(Bag.add(game.save, id, 1, game.data), "could not stage " .. id,
      "stage_" .. id)
  end

  local party = Screens.push(game, "PartyMenu")
  U.wait(3)
  U.tap(game, "a")
  U.wait(2)
  local itemIndex = rowWith(party.subItems, function(row) return row.label == "ITEM" end)
  check(itemIndex, "ITEM command missing from Party submenu", "item_command")
  moveTo(party, itemIndex)
  shot("01_party_item_command")
  U.tap(game, "a")
  U.wait(2)

  local itemMenu = game.stack:top()
  check(getmetatable(itemMenu) == Menu and #itemMenu.items == 1
      and itemMenu.items[1].label == "GIVE",
    "empty-handed Pokemon should initially offer GIVE only", "give_only")
  local picker = chooseMenuLabel(itemMenu, "GIVE")
  shot("02_give_picker")
  choosePickerItem(picker, "LEFTOVERS")
  check(mon.heldItem == "LEFTOVERS" and not game.save.inventory.LEFTOVERS,
    "real UI did not give LEFTOVERS", "leftovers_not_given")
  finishText()
  shot("03_given_leftovers")
  dismissText()

  itemMenu = openItemMenu(party)
  check(rowWith(itemMenu.items, function(row) return row.label == "TAKE" end),
    "held Pokemon does not offer TAKE", "take_missing")
  shot("04_give_take_menu")
  picker = chooseMenuLabel(itemMenu, "GIVE")
  local prompt = choosePickerItem(picker, "BERRY")
  check(getmetatable(prompt) == TextBox, "swap did not ask for confirmation",
    "swap_prompt_missing")
  finishText(prompt)
  check(getmetatable(game.stack:top()) == ChoiceBox,
    "swap prompt has no YES/NO choice", "swap_choice_missing")
  shot("05_switch_prompt")
  U.tap(game, "a")
  U.wait(20)
  check(mon.heldItem == "BERRY" and game.save.inventory.LEFTOVERS == 1
      and not game.save.inventory.BERRY,
    "confirmed real-UI swap did not exchange held and bag items", "swap_failed")
  finishText()
  shot("06_swapped_berry")
  dismissText()

  -- The picker remains available after each refusal, proving that rejected
  -- items are not consumed and another choice can be made.
  itemMenu = openItemMenu(party)
  picker = chooseMenuLabel(itemMenu, "GIVE")
  choosePickerItem(picker, "FLOWER_MAIL")
  check(mon.heldItem == "BERRY" and game.save.inventory.FLOWER_MAIL == 1,
    "Mail rejection changed inventory", "mail_mutated")
  finishText()
  shot("07_mail_rejected")
  dismissText()

  choosePickerItem(picker, "BICYCLE")
  check(mon.heldItem == "BERRY" and game.save.inventory.BICYCLE == 1,
    "key-item rejection changed inventory", "key_mutated")
  finishText()
  shot("08_key_item_rejected")
  dismissText()

  choosePickerItem(picker, machineId)
  check(mon.heldItem == "BERRY" and game.save.inventory[machineId] == 1,
    "machine rejection changed inventory", "machine_mutated")
  finishText()
  shot("09_machine_rejected")
  dismissText()
  U.tap(game, "b")
  U.wait(2)

  itemMenu = openItemMenu(party)
  chooseMenuLabel(itemMenu, "TAKE")
  check(mon.heldItem == nil and game.save.inventory.BERRY == 1,
    "real UI TAKE did not return BERRY", "take_failed")
  finishText()
  shot("10_taken_berry")
  dismissText()

  -- Egg rejection through the same real picker.
  U.tap(game, "b")
  U.wait(2)
  local egg = Pokemon.new(game.data, "PIKACHU", 5)
  egg.isEgg, egg.nickname = true, "EGG"
  game.save.party = { egg }
  game.save.inventory = { LEFTOVERS = 1 }
  game.save.bagOrder = { "LEFTOVERS" }
  party = Screens.push(game, "PartyMenu")
  U.wait(2)
  itemMenu = openItemMenu(party)
  picker = chooseMenuLabel(itemMenu, "GIVE")
  choosePickerItem(picker, "LEFTOVERS")
  check(egg.heldItem == nil and game.save.inventory.LEFTOVERS == 1,
    "Egg rejection changed inventory", "egg_mutated")
  finishText()
  shot("11_egg_rejected")
  dismissText()
  U.tap(game, "b")
  U.wait(1)
  U.tap(game, "b")
  U.wait(2)

  -- Fill every bag slot and prove TAKE refuses without deleting the held item.
  mon = Pokemon.new(game.data, "PIKACHU", 20)
  mon.heldItem = "LEFTOVERS"
  game.save.party = { mon }
  game.save.inventory = {}
  game.save.bagOrder = {}
  local ballPocket = {
    MASTER_BALL = true, ULTRA_BALL = true, GREAT_BALL = true,
    POKE_BALL = true, SAFARI_BALL = true,
  }
  for _, id in ipairs(ids) do
    local def = game.data.items[id]
    -- Fill the ordinary item pocket specifically. This is also a full
    -- 20-slot vanilla bag, while Quality of Life's optional Gen II Pack sees
    -- the same fixture as a full item pocket rather than four partial pockets.
    if not Bag.isBadge(id) and id ~= "LEFTOVERS" and not def.keyItem
        and not def.machine and not ballPocket[id]
        and Bag.slots(game.save) < Bag.capacity(game.data) then
      game.save.inventory[id] = 1
      game.save.bagOrder[#game.save.bagOrder + 1] = id
    end
  end
  check(Bag.slots(game.save) == Bag.capacity(game.data),
    "could not stage a full bag", "full_bag_fixture")
  check(game.save.inventory.LEFTOVERS == nil,
    "full-bag fixture accidentally contains LEFTOVERS", "full_bag_has_held")
  U.log("full-bag preflight:", Bag.slots(game.save), "slots /",
    Bag.capacity(game.data), "capacity; held", mon.heldItem)
  party = Screens.push(game, "PartyMenu")
  U.wait(2)
  itemMenu = openItemMenu(party)
  chooseMenuLabel(itemMenu, "TAKE")
  check(mon.heldItem == "LEFTOVERS" and not game.save.inventory.LEFTOVERS,
    "full-bag TAKE lost or duplicated the held item", "full_bag_mutated")
  finishText()
  shot("12_full_bag_take_rejected")
  dismissText()

  while #game.stack.states > baseDepth do game.stack:pop() end
  game.save.party = { mon }
  Screens.push(game, "PartyMenu")
  local summary = ("HELD ITEM PASS\n%d held / %d rejected")
    :format(holdable, rejected.mail + rejected.key_item + rejected.machine)
  game.stack:push(TextBox.new(game, summary))
  finishText()
  shot("13_HELD_ITEM_AUDIT_PASS")
  restoreTestSave()

  print(("[driver] PASS Crystal held-item visual audit: %d live items held, "
    .. "%d rejected by Crystal pocket rules, 13 screenshots in %s")
    :format(holdable, rejected.mail + rejected.key_item + rejected.machine, DIR))
  love.event.quit()
end
