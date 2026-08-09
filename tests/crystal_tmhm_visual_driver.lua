-- Exhaustive in-game Crystal TM/HM compatibility driver.
--
-- This deliberately exercises the real UI path for every compatible
-- machine:
--   Bag -> USE -> boot text -> contained move -> PartyMenu
--   -> NOT ABLE rejection -> use again -> ABLE -> learned move
--
-- It also places one incompatible Pokemon beside the target whenever one
-- exists so the rendered PartyMenu visibly shows ABLE and NOT ABLE together.
-- Every machine captures its compatibility, rejection, and learned states,
-- plus a final PASS screen.
--
-- Run from the Gen1Recomp repository root:
--
--   SHOT_DIR=/tmp/crystal-tmhm-visual \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_tmhm_visual_driver.lua \
--   POKEPORT_TOUCH=0 \
--   POKEPORT_SPEED=20 \
--   love .
--
-- Crystal 251 must already be enabled/imported in the identity used to launch
-- the game. This driver never calls the game's save command.
--
-- Set CRYSTAL_TM_VISUAL_ALL_PAIRS=0 for a quick smoke run that tests all 57
-- machines visually but teaches each to only one compatible Pokemon.
-- Set CRYSTAL_TM_VISUAL_SHOT_ALL=1 to save every successful pair rather than
-- only the first successful pair for each TM.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")
  local TextBox = require("src.render.TextBox")
  local ItemEffects = require("src.inventory.ItemEffects")
  local Catalog = require("mods.CRYSTAL_251.catalog")

  local DIR = os.getenv("SHOT_DIR") or "/tmp/crystal-tmhm-visual"
  local ALL_PAIRS = os.getenv("CRYSTAL_TM_VISUAL_ALL_PAIRS") ~= "0"
  local SHOT_ALL = os.getenv("CRYSTAL_TM_VISUAL_SHOT_ALL") == "1"

  -- Keep the player's runtime party/bag intact even though the driver never
  -- invokes the game's save command. Restoring the original table references
  -- also makes an accidental outer save after the driver harmless.
  local originalParty = game.save.party
  local originalInventory = game.save.inventory
  local originalBagOrder = game.save.bagOrder
  local function restoreTestSave()
    game.save.party = originalParty
    game.save.inventory = originalInventory
    game.save.bagOrder = originalBagOrder
  end

  local function safeName(value)
    return tostring(value or "unknown"):lower():gsub("[^%w]+", "_")
  end

  local function fail(message, name)
    local file = DIR .. "/FAIL_" .. safeName(name or "tmhm") .. ".png"
    U.log("FAIL", message)
    U.shot(game, file)
    restoreTestSave()
    error(message, 0)
  end

  local function check(condition, message, name)
    if not condition then fail(message, name) end
  end

  check(game.data and game.data.pokemon and game.data.items,
    "game data is not initialized", "data")

  -- Resolve all 50 TMs and seven HMs. The inherited item ids remain
  -- Gen I ids for save/script compatibility; machine.move must be Crystal's
  -- move after lib/crystal_machines.lua patches them.
  local tms = {}
  for id, def in pairs(game.data.items) do
    local machine = type(def) == "table" and def.machine or nil
    local valid = machine and type(machine.number) == "number"
      and ((machine.kind == "TM" and machine.number >= 1 and machine.number <= 50)
        or (machine.kind == "HM" and machine.number >= 1 and machine.number <= 7))
    if valid then
      local n = machine.kind == "TM" and machine.number or 50 + machine.number
      check(tms[n] == nil,
        ("duplicate live machine slot %02d items: %s and %s")
          :format(n, tms[n] and tms[n].id or "?", id),
        ("machine%02d_duplicate"):format(n))
      tms[n] = {
        id = id,
        number = machine.number,
        kind = machine.kind,
        move = machine.move,
        name = def.name or (machine.kind .. ("%02d"):format(machine.number)),
      }
    end
  end

  local function machineLabel(machine)
    return machine.kind .. ("%02d"):format(machine.number)
  end

  for n = 1, 57 do
    check(tms[n] ~= nil, ("machine slot %02d is missing from live item data"):format(n),
      ("machine%02d_missing"):format(n))
    local expected = Catalog.tmItems[n]
    check(tms[n].move == expected,
      ("%s live item teaches %s, expected Crystal move %s")
        :format(machineLabel(tms[n]), tostring(tms[n].move), tostring(expected)),
      ("machine%02d_mapping"):format(n))
  end

  -- One canonical live species row per National Dex slot.
  local species = {}
  local seenDex = {}
  for id, def in pairs(game.data.pokemon) do
    local dex = type(def) == "table" and def.dex or nil
    if type(dex) == "number" and dex >= 1 and dex <= 251 and not seenDex[dex] then
      seenDex[dex] = true
      species[#species + 1] = { id = id, dex = dex, def = def }
    end
  end
  table.sort(species, function(a, b) return a.dex < b.dex end)
  check(#species == 251,
    ("expected 251 live Crystal species, found %d"):format(#species),
    "species_count")
  for dex = 1, 251 do
    check(seenDex[dex] == true, ("National Dex slot %d is missing"):format(dex),
      ("dex_%03d_missing"):format(dex))
  end

  local function canLearn(def, move)
    for _, m in ipairs((def and def.tmhm) or {}) do
      if m == move then return true end
    end
    return false
  end

  local eligibleByTM, negativeByTM = {}, {}
  local expectedPairs = 0

  -- First pass: independently ask the real ItemEffects TM code about every
  -- Crystal-compatible pair before touching UI state. This catches a broken
  -- item mapping immediately and gives the visual pass an exact case count.
  for n = 1, 57 do
    local tm = tms[n]
    local eligible = {}
    local negative
    for _, row in ipairs(species) do
      if canLearn(row.def, tm.move) then
        eligible[#eligible + 1] = row
        expectedPairs = expectedPairs + 1

        local probe = { species = row.id, moves = {} }
        local result, payload = ItemEffects.use(
          game.data, game.save, tm.id, probe, nil, nil, game.overworld)
        local expectedResult = tm.kind == "HM" and "learnkept" or "learn"
        check(result == expectedResult,
          ("%s %s should be usable by #%03d %s, ItemEffects returned %s")
            :format(machineLabel(tm), tm.move, row.dex, row.id, tostring(result)),
          ("machine%02d_%03d_runtime"):format(n, row.dex))
        check(payload == tm.move,
          ("TM%02d #%03d returned move %s instead of %s")
            :format(n, row.dex, tostring(payload), tm.move),
          ("tm%02d_%03d_payload"):format(n, row.dex))
      elseif not negative then
        negative = row
      end
    end
    check(#eligible > 0,
      ("%s %s has no compatible Pokemon in the imported Crystal data")
        :format(machineLabel(tm), tm.move),
      ("machine%02d_no_eligible"):format(n))
    eligibleByTM[n] = eligible
    negativeByTM[n] = negative
  end

  U.log("runtime compatibility precheck PASS:", expectedPairs,
    "Crystal-compatible machine/Pokemon pairs")
  U.log("visual mode:", ALL_PAIRS and "EVERY compatible pair" or "one pair per machine")

  U.teleport(game, "PALLET_TOWN", 5, 5, "down")

  local function containsMove(mon, move)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == move then return true end
    end
    return false
  end

  -- Hold A as state (not as repeated press events) until the current line is
  -- complete. This uses TextBox's real held-button fast path without closing
  -- the finished box, ensuring screenshots contain the complete message.
  local function finishTyping(box)
    game.input.state.a = true
    for _ = 1, 120 do
      if box.done or box.waiting then break end
      U.wait(1)
    end
    game.input.state.a = false
    U.wait(1)
  end

  local function returnToOverworld()
    for _ = 1, 80 do
      if game.stack:top() == game.overworld then return true end
      U.tap(game, "a")
      U.wait(1)
    end
    return false
  end

  local function reachPartyMenu()
    for _ = 1, 120 do
      local top = game.stack:top()
      if getmetatable(top) == PartyMenu then return top end
      U.tap(game, "a")
      U.wait(1)
    end
    return nil
  end

  local function returnToBag(bag)
    for _ = 1, 100 do
      if game.stack:top() == bag then return true end
      U.tap(game, "a")
      U.wait(1)
    end
    return false
  end

  local visualPairs = 0
  local screenshotCount = 0

  local function teachThroughUI(tm, ableRow, negativeRow, firstForTM)
    check(returnToOverworld(),
      ("TM%02d could not return to overworld before case #%03d")
        :format(tm.number, ableRow.dex),
      ("tm%02d_%03d_stack_before"):format(tm.number, ableRow.dex))

    local able = Pokemon.new(game.data, ableRow.id, 50)
    -- Keep the test on the direct successful-learning branch. We are auditing
    -- TM compatibility, not the four-move replacement menu.
    able.moves = {}
    local party = { able }
    local negative

    if negativeRow then
      negative = Pokemon.new(game.data, negativeRow.id, 50)
      negative.moves = {}
      party[#party + 1] = negative
    end
    game.save.party = party

    -- One-item bag means the real BagMenu cursor always starts on the TM under
    -- test; no direct call to BagMenu internals is used for the visual phase.
    game.save.inventory = {}
    game.save.bagOrder = {}
    check(Bag.add(game.save, tm.id, 1),
      ("could not add TM%02d to the test bag"):format(tm.number),
      ("tm%02d_bag_add"):format(tm.number))

    local bag = Screens.push(game, "BagMenu")
    U.wait(2)
    if bag and bag.gen2 then
      U.tap(game, "left")
      U.wait(2)
    end
    check(bag and bag.items and #bag.items == 1
        and bag.items[1].value == tm.id,
      ("TM%02d is not the only item in the visual test bag"):format(tm.number),
      ("tm%02d_bag_row"):format(tm.number))

    -- A on the TM -> USE/TOSS, A on USE -> the real TM boot/contained text.
    U.tap(game, "a")
    U.wait(2)
    U.tap(game, "a")
    U.wait(2)

    local menu = reachPartyMenu()
    check(menu ~= nil,
      ("TM%02d %s never reached the TM/HM PartyMenu for #%03d %s")
        :format(tm.number, tm.move, ableRow.dex, ableRow.id),
      ("tm%02d_%03d_no_party"):format(tm.number, ableRow.dex))
    check(menu.tmhm ~= nil,
      ("TM%02d PartyMenu is not in TM/HM mode"):format(tm.number),
      ("tm%02d_%03d_no_tmhm_mode"):format(tm.number, ableRow.dex))
    check(menu.tmhm.move == tm.move,
      ("TM%02d PartyMenu asks about %s instead of %s")
        :format(tm.number, tostring(menu.tmhm.move), tm.move),
      ("tm%02d_%03d_party_move"):format(tm.number, ableRow.dex))
    check(menu.tmhm.kind == tm.kind,
      ("%s PartyMenu kind is %s"):format(machineLabel(tm), tostring(menu.tmhm.kind)),
      ("machine_%s_party_kind"):format(machineLabel(tm):lower()))
    check(canLearn(game.data.pokemon[able.species], menu.tmhm.move),
      ("TM%02d PartyMenu should render #%03d %s as ABLE")
        :format(tm.number, ableRow.dex, ableRow.id),
      ("tm%02d_%03d_not_able"):format(tm.number, ableRow.dex))
    if negativeRow then
      check(not canLearn(game.data.pokemon[negativeRow.id], menu.tmhm.move),
        ("TM%02d negative control #%03d %s unexpectedly became compatible")
          :format(tm.number, negativeRow.dex, negativeRow.id),
        ("tm%02d_negative"):format(tm.number))
    end

    if firstForTM or SHOT_ALL then
      local base = ("%s_%s_%03d_%s")
        :format(machineLabel(tm):lower(), safeName(tm.move),
          ableRow.dex, safeName(ableRow.id))
      U.wait(2)
      U.shot(game, DIR .. "/" .. base .. "_able_not_able.png")
      screenshotCount = screenshotCount + 1
    end

    -- Select the incompatible second slot first. This must go through the real
    -- PartyMenu -> BagMenu -> ItemEffects rejection and retain the machine.
    if negative then
      menu.index = 2
      U.tap(game, "a")
      U.wait(3)
      check(not containsMove(negative, tm.move),
        ("%s incorrectly taught incompatible #%03d %s")
          :format(machineLabel(tm), negativeRow.dex, negativeRow.id),
        ("machine_%s_negative_learned"):format(machineLabel(tm):lower()))
      check(game.save.inventory[tm.id] == 1,
        ("%s was consumed by an incompatible attempt"):format(machineLabel(tm)),
        ("machine_%s_negative_consumed"):format(machineLabel(tm):lower()))
      local top = game.stack:top()
      check(getmetatable(top) == TextBox,
        ("%s rejection did not show a TextBox"):format(machineLabel(tm)),
        ("machine_%s_no_reject_text"):format(machineLabel(tm):lower()))
      if firstForTM or SHOT_ALL then
        finishTyping(top)
        local base = ("%s_%s_%03d_%s")
          :format(machineLabel(tm):lower(), safeName(tm.move),
            negativeRow.dex, safeName(negativeRow.id))
        U.shot(game, DIR .. "/" .. base .. "_rejected.png")
        screenshotCount = screenshotCount + 1
      end
      check(returnToBag(bag),
        ("%s rejection did not return to the same Bag"):format(machineLabel(tm)),
        ("machine_%s_reject_return"):format(machineLabel(tm):lower()))

      -- Reuse the still-owned machine and return to the compatible first slot.
      finishTyping(top)
      U.tap(game, "a")
      U.wait(2)
      menu = reachPartyMenu()
      check(menu and menu.tmhm and menu.tmhm.move == tm.move,
        ("%s second use did not return to its PartyMenu"):format(machineLabel(tm)),
        ("machine_%s_second_party"):format(machineLabel(tm):lower()))
      menu.index = 1
    end

    -- The compatible Pokemon is first; select it through PartyMenu's real
    -- pickOnly callback into BagMenu -> ItemEffects.use.
    U.tap(game, "a")
    U.wait(3)

    check(containsMove(able, tm.move),
      ("TM%02d %s did not actually teach #%03d %s through the UI")
        :format(tm.number, tm.move, ableRow.dex, ableRow.id),
      ("tm%02d_%03d_not_learned"):format(tm.number, ableRow.dex))
    check(#able.moves == 1 and able.moves[1].id == tm.move,
      ("TM%02d #%03d learned an unexpected move set")
        :format(tm.number, ableRow.dex),
      ("tm%02d_%03d_moveset"):format(tm.number, ableRow.dex))
    local remaining = game.save.inventory[tm.id]
    if tm.kind == "TM" then
      check(remaining == nil,
        ("%s was not consumed after successful teaching"):format(machineLabel(tm)),
        ("machine_%s_not_consumed"):format(machineLabel(tm):lower()))
    else
      check(remaining == 1,
        ("%s was consumed after successful teaching"):format(machineLabel(tm)),
        ("machine_%s_consumed"):format(machineLabel(tm):lower()))
    end

    if firstForTM or SHOT_ALL then
      local top = game.stack:top()
      check(getmetatable(top) == TextBox,
        ("TM%02d successful teach did not show the learned-message TextBox")
          :format(tm.number),
        ("tm%02d_%03d_no_learn_text"):format(tm.number, ableRow.dex))
      U.tap(game, "a")
      U.wait(2)
      local base = ("%s_%s_%03d_%s")
        :format(machineLabel(tm):lower(), safeName(tm.move),
          ableRow.dex, safeName(ableRow.id))
      U.shot(game, DIR .. "/" .. base .. "_learned.png")
      screenshotCount = screenshotCount + 1
    end

    check(returnToOverworld(),
      ("TM%02d #%03d did not return to the overworld after learning")
        :format(tm.number, ableRow.dex),
      ("tm%02d_%03d_stack_after"):format(tm.number, ableRow.dex))

    visualPairs = visualPairs + 1
  end

  for n = 1, 57 do
    local tm = tms[n]
    local eligible = eligibleByTM[n]
    local limit = ALL_PAIRS and #eligible or 1
    U.log(("%s %-14s compatible=%d visual=%d")
      :format(machineLabel(tm), tm.move, #eligible, limit))

    for i = 1, limit do
      local ableRow = eligible[i]
      teachThroughUI(tm, ableRow, negativeByTM[n], i == 1)
    end
  end

  if ALL_PAIRS then
    check(visualPairs == expectedPairs,
      ("visual pair count mismatch: ran %d, expected %d")
        :format(visualPairs, expectedPairs),
      "pair_count")
  else
    check(visualPairs == 57,
      ("machine smoke visual ran %d cases instead of 57"):format(visualPairs),
      "machine_count")
  end

  check(returnToOverworld(), "could not reach overworld for final PASS screen", "final_stack")
  restoreTestSave()
  local summary = ALL_PAIRS
    and ("TM/HM AUDIT PASS\n57 machines / %d pairs"):format(visualPairs)
    or "TM/HM AUDIT PASS\n57 machines visual"
  local passBox = TextBox.new(game, summary)
  game.stack:push(passBox)
  finishTyping(passBox)
  U.shot(game, DIR .. "/TMHM_AUDIT_PASS.png")
  screenshotCount = screenshotCount + 1

  print(("[driver] PASS Crystal TM/HM visual audit: 57 machines, %d/%d compatible pairs exercised through UI, %d screenshots in %s")
    :format(visualPairs, expectedPairs, screenshotCount, DIR))
  love.event.quit()
end
