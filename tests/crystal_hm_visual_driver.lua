-- Exhaustive in-game Crystal HM compatibility driver.
--
-- This deliberately exercises the real UI path for every compatible
-- (HM, Pokemon) pair:
--   Bag -> USE -> "Booted up an HM!" -> contained move -> PartyMenu
--   -> ABLE -> choose Pokemon -> "learned <move>!"
--
-- It also places one incompatible Pokemon beside the target whenever one
-- exists so the rendered PartyMenu visibly shows ABLE and NOT ABLE together.
-- The first successful pair for each HM is captured, plus a final PASS screen.
--
-- Run from the Gen1Recomp repository root:
--
--   SHOT_DIR=/tmp/crystal-hm-visual \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_hm_visual_driver.lua \
--   POKEPORT_TOUCH=0 \
--   POKEPORT_SPEED=20 \
--   love .
--
-- Crystal 251 must already be enabled/imported in the identity used to launch
-- the game. This driver never calls the game's save command.
--
-- Set CRYSTAL_HM_VISUAL_ALL_PAIRS=0 for a quick smoke run that still tests
-- all 7 HMs visually but teaches each HM to only one compatible Pokemon.
-- Set CRYSTAL_HM_VISUAL_SHOT_ALL=1 to save every successful pair rather than
-- only the first successful pair for each HM.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")
  local TextBox = require("src.render.TextBox")
  local ItemEffects = require("src.inventory.ItemEffects")
  local Catalog = require("mods.CRYSTAL_251.catalog")

  local DIR = os.getenv("SHOT_DIR") or "/tmp/crystal-hm-visual"
  local ALL_PAIRS = os.getenv("CRYSTAL_HM_VISUAL_ALL_PAIRS") ~= "0"
  local SHOT_ALL = os.getenv("CRYSTAL_HM_VISUAL_SHOT_ALL") == "1"

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
    local file = DIR .. "/FAIL_" .. safeName(name or "hm") .. ".png"
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

  -- Resolve the live HM item for each displayed HM number. The item ids remain
  -- Gen I ids for save/script compatibility; machine.move must be Crystal's
  -- move after lib/crystal_machines.lua patches them.
  local hms = {}
  for id, def in pairs(game.data.items) do
    local machine = type(def) == "table" and def.machine or nil
    if machine and machine.kind == "HM"
        and type(machine.number) == "number"
        and machine.number >= 1 and machine.number <= 7 then
      local n = machine.number
      check(hms[n] == nil,
        ("duplicate live HM%02d items: %s and %s"):format(n, hms[n] and hms[n].id or "?", id),
        ("hm%02d_duplicate"):format(n))
      hms[n] = {
        id = id,
        number = n,
        move = machine.move,
        name = def.name or ("HM%02d"):format(n),
      }
    end
  end

  for n = 1, 7 do
    check(hms[n] ~= nil, ("HM%02d is missing from live item data"):format(n),
      ("hm%02d_missing"):format(n))
    local expected = Catalog.tmItems[50 + n]
    check(hms[n].move == expected,
      ("HM%02d live item teaches %s, expected Crystal move %s")
        :format(n, tostring(hms[n].move), tostring(expected)),
      ("hm%02d_mapping"):format(n))
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

  local eligibleByHM, negativeByHM = {}, {}
  local expectedPairs = 0

  -- First pass: independently ask the real ItemEffects HM code about every
  -- Crystal-compatible pair before touching UI state. This catches a broken
  -- item mapping immediately and gives the visual pass an exact case count.
  for n = 1, 7 do
    local hm = hms[n]
    local eligible = {}
    local negative
    for _, row in ipairs(species) do
      if canLearn(row.def, hm.move) then
        eligible[#eligible + 1] = row
        expectedPairs = expectedPairs + 1

        local probe = { species = row.id, moves = {} }
        local result, payload = ItemEffects.use(
          game.data, game.save, hm.id, probe, nil, nil, game.overworld)
        check(result == "learnkept",
          ("HM%02d %s should be usable by #%03d %s, ItemEffects returned %s")
            :format(n, hm.move, row.dex, row.id, tostring(result)),
          ("hm%02d_%03d_runtime"):format(n, row.dex))
        check(payload == hm.move,
          ("HM%02d #%03d returned move %s instead of %s")
            :format(n, row.dex, tostring(payload), hm.move),
          ("hm%02d_%03d_payload"):format(n, row.dex))
      elseif not negative then
        negative = row
      end
    end
    check(#eligible > 0,
      ("HM%02d %s has no compatible Pokemon in the imported Crystal data")
        :format(n, hm.move),
      ("hm%02d_no_eligible"):format(n))
    eligibleByHM[n] = eligible
    negativeByHM[n] = negative
  end

  U.log("runtime compatibility precheck PASS:", expectedPairs,
    "Crystal-compatible HM/Pokemon pairs")
  U.log("visual mode:", ALL_PAIRS and "EVERY compatible pair" or "one pair per HM")

  U.teleport(game, "PALLET_TOWN", 5, 5, "down")

  local function containsMove(mon, move)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == move then return true end
    end
    return false
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

  local visualPairs = 0
  local screenshotCount = 0

  local function teachThroughUI(hm, ableRow, negativeRow, firstForHM)
    check(returnToOverworld(),
      ("HM%02d could not return to overworld before case #%03d")
        :format(hm.number, ableRow.dex),
      ("hm%02d_%03d_stack_before"):format(hm.number, ableRow.dex))

    local able = Pokemon.new(game.data, ableRow.id, 50)
    -- Keep the test on the direct successful-learning branch. We are auditing
    -- HM compatibility, not the four-move replacement menu.
    able.moves = {}
    local party = { able }

    if negativeRow then
      local negative = Pokemon.new(game.data, negativeRow.id, 50)
      negative.moves = {}
      party[#party + 1] = negative
    end
    game.save.party = party

    -- One-item bag means the real BagMenu cursor always starts on the HM under
    -- test; no direct call to BagMenu internals is used for the visual phase.
    game.save.inventory = {}
    game.save.bagOrder = {}
    check(Bag.add(game.save, hm.id, 1),
      ("could not add HM%02d to the test bag"):format(hm.number),
      ("hm%02d_bag_add"):format(hm.number))

    local bag = Screens.push(game, "BagMenu")
    U.wait(2)
    if bag and bag.gen2 then
      U.tap(game, "left")
      U.wait(2)
    end
    check(bag and bag.items and #bag.items == 1
        and bag.items[1].value == hm.id,
      ("HM%02d is not the only item in the visual test bag"):format(hm.number),
      ("hm%02d_bag_row"):format(hm.number))

    -- A on the HM -> USE/TOSS, A on USE -> the real HM boot/contained text.
    U.tap(game, "a")
    U.wait(2)
    U.tap(game, "a")
    U.wait(2)

    local menu = reachPartyMenu()
    check(menu ~= nil,
      ("HM%02d %s never reached the HM PartyMenu for #%03d %s")
        :format(hm.number, hm.move, ableRow.dex, ableRow.id),
      ("hm%02d_%03d_no_party"):format(hm.number, ableRow.dex))
    check(menu.tmhm ~= nil,
      ("HM%02d PartyMenu is not in HM mode"):format(hm.number),
      ("hm%02d_%03d_no_tmhm_mode"):format(hm.number, ableRow.dex))
    check(menu.tmhm.kind == "HM",
      ("HM%02d PartyMenu machine kind is %s instead of HM")
        :format(hm.number, tostring(menu.tmhm.kind)),
      ("hm%02d_%03d_party_kind"):format(hm.number, ableRow.dex))
    check(menu.tmhm.move == hm.move,
      ("HM%02d PartyMenu asks about %s instead of %s")
        :format(hm.number, tostring(menu.tmhm.move), hm.move),
      ("hm%02d_%03d_party_move"):format(hm.number, ableRow.dex))
    check(canLearn(game.data.pokemon[able.species], menu.tmhm.move),
      ("HM%02d PartyMenu should render #%03d %s as ABLE")
        :format(hm.number, ableRow.dex, ableRow.id),
      ("hm%02d_%03d_not_able"):format(hm.number, ableRow.dex))
    if negativeRow then
      check(not canLearn(game.data.pokemon[negativeRow.id], menu.tmhm.move),
        ("HM%02d negative control #%03d %s unexpectedly became compatible")
          :format(hm.number, negativeRow.dex, negativeRow.id),
        ("hm%02d_negative"):format(hm.number))
    end

    if firstForHM or SHOT_ALL then
      local base = ("hm%02d_%s_%03d_%s")
        :format(hm.number, safeName(hm.move), ableRow.dex, safeName(ableRow.id))
      U.wait(2)
      U.shot(game, DIR .. "/" .. base .. "_able.png")
      screenshotCount = screenshotCount + 1
    end

    -- The compatible Pokemon is deliberately first, so A selects it through
    -- PartyMenu's real pickOnly callback into BagMenu -> ItemEffects.use.
    U.tap(game, "a")
    U.wait(3)

    check(containsMove(able, hm.move),
      ("HM%02d %s did not actually teach #%03d %s through the UI")
        :format(hm.number, hm.move, ableRow.dex, ableRow.id),
      ("hm%02d_%03d_not_learned"):format(hm.number, ableRow.dex))
    check(#able.moves == 1 and able.moves[1].id == hm.move,
      ("HM%02d #%03d learned an unexpected move set")
        :format(hm.number, ableRow.dex),
      ("hm%02d_%03d_moveset"):format(hm.number, ableRow.dex))
    check(game.save.inventory[hm.id] == 1,
      ("HM%02d was consumed or its quantity changed after successful teaching")
        :format(hm.number),
      ("hm%02d_%03d_not_consumed"):format(hm.number, ableRow.dex))

    if firstForHM or SHOT_ALL then
      local top = game.stack:top()
      check(getmetatable(top) == TextBox,
        ("HM%02d successful teach did not show the learned-message TextBox")
          :format(hm.number),
        ("hm%02d_%03d_no_learn_text"):format(hm.number, ableRow.dex))
      local base = ("hm%02d_%s_%03d_%s")
        :format(hm.number, safeName(hm.move), ableRow.dex, safeName(ableRow.id))
      U.shot(game, DIR .. "/" .. base .. "_learned.png")
      screenshotCount = screenshotCount + 1
    end

    check(returnToOverworld(),
      ("HM%02d #%03d did not return to the overworld after learning")
        :format(hm.number, ableRow.dex),
      ("hm%02d_%03d_stack_after"):format(hm.number, ableRow.dex))

    visualPairs = visualPairs + 1
  end

  for n = 1, 7 do
    local hm = hms[n]
    local eligible = eligibleByHM[n]
    local limit = ALL_PAIRS and #eligible or 1
    U.log(("HM%02d %-14s compatible=%d visual=%d")
      :format(n, hm.move, #eligible, limit))

    for i = 1, limit do
      local ableRow = eligible[i]
      teachThroughUI(hm, ableRow, negativeByHM[n], i == 1)
    end
  end

  if ALL_PAIRS then
    check(visualPairs == expectedPairs,
      ("visual pair count mismatch: ran %d, expected %d")
        :format(visualPairs, expectedPairs),
      "pair_count")
  else
    check(visualPairs == 7,
      ("HM smoke visual ran %d cases instead of 7"):format(visualPairs),
      "hm_count")
  end

  check(returnToOverworld(), "could not reach overworld for final PASS screen", "final_stack")
  restoreTestSave()
  local summary = ALL_PAIRS
    and ("HM AUDIT PASS\n7 HMs / %d pairs"):format(visualPairs)
    or "HM AUDIT PASS\n7 HMs visual"
  game.stack:push(TextBox.new(game, summary))
  U.wait(3)
  U.shot(game, DIR .. "/HM_AUDIT_PASS.png")
  screenshotCount = screenshotCount + 1

  print(("[driver] PASS Crystal HM visual audit: 7 HMs, %d/%d compatible pairs exercised through UI, %d screenshots in %s")
    :format(visualPairs, expectedPairs, screenshotCount, DIR))
  love.event.quit()
end
