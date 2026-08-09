-- End-to-end normal-acquisition audit for Crystal 251 HMs.
--
-- HM01-HM05 are obtained from their real Gen I overworld/story rewards:
--   HM01 CUT      - S.S. Anne captain
--   HM02 FLY      - Route 16 hidden-house girl
--   HM03 SURF     - Safari Zone Secret House
--   HM04 STRENGTH - Fuchsia Warden after returning GOLD TEETH
--   HM05 FLASH    - Oak's aide after 10 owned Pokemon
--
-- For every normally obtainable HM the driver then exercises:
--   real Bag -> HM boot text -> real PartyMenu
--   -> incompatible Pokemon must reject
--   -> use the SAME HM again
--   -> compatible Pokemon must learn the Crystal move
--   -> HM must remain in the bag.
--
-- Crystal's two additional HMs use progression-equivalent Kanto paths:
--   HM06 WHIRLPOOL - Lance after the Rocket Hideout Giovanni victory
--   HM07 WATERFALL - item-ball pickup in Seafoam Islands B4F
--
-- Run:
--   SHOT_DIR=/tmp/crystal-hm-normal-audit \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_hm_normal_game_audit_driver.lua \
--   POKEPORT_TOUCH=0 \
--   POKEPORT_SPEED=20 \
--   love .
--
-- The driver never saves.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")
  local Bag = require("src.inventory.Bag")
  local Catalog = require("mods.CRYSTAL_251.catalog")

  local DIR = os.getenv("SHOT_DIR") or "/tmp/crystal-hm-normal-audit"

  local original = {
    party = game.save.party,
    inventory = game.save.inventory,
    bagOrder = game.save.bagOrder,
    flags = game.save.flags,
    pokedex = game.save.pokedex,
    objectToggles = game.save.objectToggles,
    itemsTaken = game.save.itemsTaken,
    partyMenuSavedIndex = game.partyMenuSavedIndex,
  }

  local function restore()
    game.save.party = original.party
    game.save.inventory = original.inventory
    game.save.bagOrder = original.bagOrder
    game.save.flags = original.flags
    game.save.pokedex = original.pokedex
    game.save.objectToggles = original.objectToggles
    game.save.itemsTaken = original.itemsTaken
    game.partyMenuSavedIndex = original.partyMenuSavedIndex
  end

  local function safeName(v)
    return tostring(v or "unknown"):lower():gsub("[^%w]+", "_")
  end

  local function fail(message, name)
    U.log("FAIL", message)
    U.shot(game, DIR .. "/FAIL_" .. safeName(name or "hm_audit") .. ".png")
    restore()
    error(message, 0)
  end

  local function check(ok, message, name)
    if not ok then fail(message, name) end
  end

  local function hasMove(mon, move)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == move then return true end
    end
    return false
  end

  local function canLearn(def, move)
    for _, moveId in ipairs((def and def.tmhm) or {}) do
      if moveId == move then return true end
    end
    return false
  end

  local species = {}
  for id, def in pairs(game.data.pokemon or {}) do
    local dex = type(def) == "table" and def.dex or nil
    if type(dex) == "number" and dex >= 1 and dex <= 251 then
      species[#species + 1] = { id = id, dex = dex, def = def }
    end
  end
  table.sort(species, function(a, b) return a.dex < b.dex end)
  check(#species >= 251, "Crystal species data is not loaded", "species")

  local function controlsFor(move)
    local good, bad
    for _, row in ipairs(species) do
      if canLearn(row.def, move) then
        if not good then good = row end
      elseif not bad then
        bad = row
      end
      if good and bad then break end
    end
    return good, bad
  end

  -- Keep only the event flags needed by each reward isolated from the user's
  -- live inventory/party while retaining unrelated progression flags.
  local flags = {}
  for k, v in pairs(original.flags or {}) do flags[k] = v end
  game.save.flags = flags
  game.save.objectToggles = {}

  local acquisitions = {
    {
      number = 1,
      item = "HM_CUT",
      move = "CUT",
      flag = "EVENT_GOT_HM01",
      map = "SS_ANNE_CAPTAINS_ROOM",
      text = "TEXT_SSANNECAPTAINSROOM_CAPTAIN",
      npcNeedle = "CAPTAIN",
      label = "S.S. Anne captain",
      clearFlags = {},
    },
    {
      number = 2,
      item = "HM_FLY",
      move = "FLY",
      flag = "EVENT_GOT_HM02",
      map = "ROUTE_16_FLY_HOUSE",
      text = "TEXT_ROUTE16FLYHOUSE_BRUNETTE_GIRL",
      npcNeedle = "BRUNETTE",
      label = "Route 16 hidden-house girl",
      clearFlags = {},
    },
    {
      number = 3,
      item = "HM_SURF",
      move = "SURF",
      flag = "EVENT_GOT_HM03",
      map = "SAFARI_ZONE_SECRET_HOUSE",
      text = "TEXT_SAFARIZONESECRETHOUSE_FISHING_GURU",
      npcNeedle = "FISHING",
      label = "Safari Zone Secret House",
      clearFlags = {},
    },
    {
      number = 4,
      item = "HM_STRENGTH",
      move = "STRENGTH",
      flag = "EVENT_GOT_HM04",
      map = "WARDENS_HOUSE",
      text = "TEXT_WARDENSHOUSE_WARDEN",
      npcNeedle = "WARDEN",
      label = "Fuchsia Warden",
      clearFlags = { "EVENT_GAVE_GOLD_TEETH" },
      setup = function()
        check(Bag.add(game.save, "GOLD_TEETH", 1),
          "could not place GOLD TEETH prerequisite in the test bag",
          "hm04_gold_teeth")
      end,
    },
    {
      number = 5,
      item = "HM_FLASH",
      move = "FLASH",
      -- story4.lua's oaksAide helper keys the reward flag from the item id.
      flag = "EVENT_GOT_HM_FLASH",
      map = "ROUTE_2_GATE",
      text = "TEXT_ROUTE2GATE_OAKS_AIDE",
      npcNeedle = "AIDE",
      label = "Oak's aide (10 owned)",
      clearFlags = {},
      setup = function()
        local owned, seen = {}, {}
        for i = 1, math.min(10, #species) do
          owned[species[i].id] = true
          seen[species[i].id] = true
        end
        game.save.pokedex = { owned = owned, seen = seen }
      end,
    },
    {
      number = 6,
      item = "HM_06",
      move = "WHIRLPOOL",
      flag = "MOD_CRYSTAL251_GOT_HM06",
      map = "ROCKET_HIDEOUT_B4F",
      text = "TEXT_CRYSTAL251_ROCKET_HIDEOUT_LANCE",
      npcNeedle = "CRYSTAL251_ROCKET_HIDEOUT_LANCE",
      label = "Lance after the Rocket Hideout operation",
      clearFlags = {},
      setup = function()
        game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI = true
      end,
    },
    {
      number = 7,
      item = "HM_07",
      move = "WATERFALL",
      map = "SEAFOAM_ISLANDS_B4F",
      text = "TEXT_CRYSTAL251_SEAFOAM_HM07",
      npcNeedle = "CRYSTAL251_SEAFOAM_HM07",
      label = "Seafoam Islands ice-cave item ball",
      clearFlags = {},
      setup = function()
        game.save.itemsTaken = game.save.itemsTaken or {}
        game.save.itemsTaken.SEAFOAM_ISLANDS_B4F_obj_4 = nil
      end,
    },
  }

  local liveHM = {}
  for id, def in pairs(game.data.items or {}) do
    local m = type(def) == "table" and def.machine or nil
    if m and m.kind == "HM" and type(m.number) == "number"
        and m.number >= 1 and m.number <= 7 then
      liveHM[m.number] = { id = id, move = m.move, def = def }
    end
  end

  for n = 1, 7 do
    local hm = liveHM[n]
    check(hm ~= nil, ("live HM%02d is missing"):format(n),
      ("hm%02d_missing"):format(n))
    local expected = Catalog.tmItems[50 + n]
    check(hm.move == expected,
      ("live HM%02d teaches %s instead of Crystal %s")
        :format(n, tostring(hm.move), tostring(expected)),
      ("hm%02d_mapping"):format(n))
  end

  local function findRewardNpc(ow, row)
    local fallback
    for _, npc in ipairs(ow.npcs or {}) do
      local def = npc.def or {}
      if def.text == row.text then return npc end
      local name = tostring(def.name or "")
      if row.npcNeedle and name:find(row.npcNeedle, 1, true) then
        fallback = fallback or npc
      end
    end
    return fallback
  end

  local adjacent = {
    { dx = 0, dy = 1, facing = "up" },
    { dx = 0, dy = -1, facing = "down" },
    { dx = 1, dy = 0, facing = "left" },
    { dx = -1, dy = 0, facing = "right" },
  }

  local function standFor(ow, npc)
    for _, s in ipairs(adjacent) do
      local x, y = npc.cellX + s.dx, npc.cellY + s.dy
      if ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y) then
        local occupied = ow:npcAtCell(x, y)
        if not occupied then
          return { x = x, y = y, facing = s.facing }
        end
      end
    end
  end

  local function waitForReward(row)
    local deadline = love.timer.getTime() + 20
    local waitingLogged = false
    while love.timer.getTime() < deadline do
      if (not row.flag or game.save.flags[row.flag])
          and (game.save.inventory[row.item] or 0) == 1
          and game.stack:top() == game.overworld then
        return true
      end

      local Music = require("src.core.Music")
      if Music.oneShotPlaying and Music.oneShotPlaying() and not waitingLogged then
        U.log(("HM%02d waiting for real-time reward jingle"):format(row.number))
        waitingLogged = true
      end

      -- Advances dialogue and chooses YES on the Oak's-aide prompt.
      U.tap(game, "a")
      U.wait(1)

      if Music.oneShotPlaying and Music.oneShotPlaying() and love.timer.sleep then
        love.timer.sleep(0.01)
      end
    end
    return false
  end

  local function obtainNormally(row)
    game.save.inventory = {}
    game.save.bagOrder = {}
    if row.flag then game.save.flags[row.flag] = nil end
    for _, flag in ipairs(row.clearFlags or {}) do
      game.save.flags[flag] = nil
    end
    game.save.pokedex = original.pokedex

    if row.setup then row.setup() end

    check((game.save.inventory[row.item] or 0) == 0,
      ("HM%02d was already present before its normal reward"):format(row.number),
      ("hm%02d_preowned"):format(row.number))

    U.teleport(game, row.map, 0, 0, "down")
    local ow = game.overworld
    check(ow and ow.map and ow.map.id == row.map,
      ("could not load %s for HM%02d"):format(row.map, row.number),
      ("hm%02d_map"):format(row.number))

    local npc = findRewardNpc(ow, row)
    check(npc ~= nil,
      ("could not find HM%02d reward NPC in %s"):format(row.number, row.map),
      ("hm%02d_npc"):format(row.number))

    local stand = standFor(ow, npc)
    check(stand ~= nil,
      ("no walkable interaction cell for HM%02d reward NPC"):format(row.number),
      ("hm%02d_adjacent"):format(row.number))

    U.teleport(game, row.map, stand.x, stand.y, stand.facing)
    U.wait(2)
    ow = game.overworld

    local fx, fy = ow.player:facingCell()
    local faced = ow:npcAtCell(fx, fy)
    check(faced ~= nil,
      ("HM%02d player is not facing a reward NPC after positioning")
        :format(row.number),
      ("hm%02d_facing"):format(row.number))

    local facedDef = faced.def or {}
    check(facedDef.text == row.text
          or tostring(facedDef.name or ""):find(row.npcNeedle, 1, true) ~= nil,
      ("HM%02d is facing the wrong NPC (%s / %s)")
        :format(row.number, tostring(facedDef.name), tostring(facedDef.text)),
      ("hm%02d_wrong_npc"):format(row.number))

    check(type(ow.interact) == "function",
      "overworld interaction function is unavailable",
      ("hm%02d_interact"):format(row.number))

    -- Same interaction dispatch as pressing A in the overworld. The HM itself
    -- is awarded only by the map's real reward script.
    ow:interact()
    U.wait(2)

    check(waitForReward(row),
      ("HM%02d was not awarded through %s's normal story interaction")
        :format(row.number, row.label),
      ("hm%02d_reward"):format(row.number))

    check((game.save.inventory[row.item] or 0) == 1,
      ("HM%02d reward did not leave exactly one HM in inventory"):format(row.number),
      ("hm%02d_inventory"):format(row.number))

    U.log(("PASS obtained HM%02d %s normally from %s")
      :format(row.number, row.move, row.label))
    U.shot(game, ("%s/%02d_hm%02d_%s_obtained.png")
      :format(DIR, row.number, row.number, safeName(row.move)))
  end

  local function reachPartyMenu()
    for _ = 1, 180 do
      local top = game.stack:top()
      if getmetatable(top) == PartyMenu then return top end
      U.tap(game, "a")
      U.wait(1)
    end
    return nil
  end

  local function openHMThroughBag(row)
    local bag = Screens.push(game, "BagMenu")
    U.wait(2)

    -- QUALITY_OF_LIFE's Gen II Pack opens on ITEM and wraps LEFT to TM/HM.
    if bag and bag.gen2 then
      U.tap(game, "left")
      U.wait(2)
    end

    check(bag and bag.items and #bag.items == 1
        and bag.items[1].value == row.item,
      ("HM%02d is not the selectable machine in the real Bag UI")
        :format(row.number),
      ("hm%02d_bag"):format(row.number))

    U.tap(game, "a") -- HM -> USE/TOSS
    U.wait(2)
    U.tap(game, "a") -- USE
    U.wait(2)

    local party = reachPartyMenu()
    check(party ~= nil,
      ("HM%02d did not reach the real PartyMenu"):format(row.number),
      ("hm%02d_party"):format(row.number))

    check(party.tmhm and party.tmhm.kind == "HM"
          and party.tmhm.move == row.move,
      ("HM%02d PartyMenu is not auditing %s")
        :format(row.number, row.move),
      ("hm%02d_party_mode"):format(row.number))
    return party, bag
  end

  local function returnToBag(bag, row)
    for _ = 1, 100 do
      if game.stack:top() == bag then return true end
      U.tap(game, "a")
      U.wait(1)
    end
    return false
  end

  local function teachAudit(row)
    local goodRow, badRow = controlsFor(row.move)
    check(goodRow ~= nil,
      ("no Crystal Pokemon is compatible with HM%02d %s")
        :format(row.number, row.move),
      ("hm%02d_no_good"):format(row.number))
    check(badRow ~= nil,
      ("no Crystal Pokemon is incompatible with HM%02d %s")
        :format(row.number, row.move),
      ("hm%02d_no_bad"):format(row.number))

    local bad = Pokemon.new(game.data, badRow.id, 30)
    local good = Pokemon.new(game.data, goodRow.id, 30)
    bad.moves = {}
    good.moves = {}
    game.save.party = { bad, good }
    game.partyMenuSavedIndex = 1

    U.log(("HM%02d %s controls: incompatible=#%d %s compatible=#%d %s")
      :format(row.number, row.move, badRow.dex, badRow.id, goodRow.dex, goodRow.id))

    local party, bag = openHMThroughBag(row)
    party.index = 1
    game.partyMenuSavedIndex = 1

    check(not canLearn(game.data.pokemon[bad.species], row.move),
      ("HM%02d negative control unexpectedly reports compatible")
        :format(row.number),
      ("hm%02d_bad_control"):format(row.number))
    check(canLearn(game.data.pokemon[good.species], row.move),
      ("HM%02d positive control unexpectedly reports incompatible")
        :format(row.number),
      ("hm%02d_good_control"):format(row.number))

    U.shot(game, ("%s/%02d_hm%02d_%s_able_not_able.png")
      :format(DIR, row.number, row.number, safeName(row.move)))

    -- Select incompatible first.
    U.tap(game, "a")
    U.wait(3)

    check(not hasMove(bad, row.move),
      ("%s incorrectly learned HM%02d %s")
        :format(badRow.id, row.number, row.move),
      ("hm%02d_bad_learned"):format(row.number))
    check((game.save.inventory[row.item] or 0) == 1,
      ("HM%02d was consumed by the incompatible attempt"):format(row.number),
      ("hm%02d_bad_consumed"):format(row.number))

    U.shot(game, ("%s/%02d_hm%02d_%s_incompatible_rejected.png")
      :format(DIR, row.number, row.number, safeName(row.move)))
    U.log(("PASS HM%02d incompatible Pokemon rejected: %s")
      :format(row.number, badRow.id))

    check(returnToBag(bag, row),
      ("HM%02d incompatible attempt did not return to the same Bag")
        :format(row.number),
      ("hm%02d_reject_return"):format(row.number))

    -- Use the same, still-owned HM again and select compatible slot 2.
    U.tap(game, "a")
    U.wait(2)
    U.tap(game, "a")
    U.wait(2)
    party = reachPartyMenu()

    check(party ~= nil and party.tmhm and party.tmhm.move == row.move,
      ("second HM%02d use did not return to %s PartyMenu mode")
        :format(row.number, row.move),
      ("hm%02d_second_party"):format(row.number))

    party.index = 1
    game.partyMenuSavedIndex = 1
    U.tap(game, "down")
    U.wait(2)
    check(party.index == 2,
      ("could not select HM%02d compatible Pokemon"):format(row.number),
      ("hm%02d_good_select"):format(row.number))

    U.tap(game, "a")
    U.wait(3)

    check(hasMove(good, row.move),
      ("%s did not learn HM%02d %s from the normally obtained HM")
        :format(goodRow.id, row.number, row.move),
      ("hm%02d_good_not_learned"):format(row.number))
    check(#good.moves == 1 and good.moves[1].id == row.move,
      ("HM%02d taught an unexpected move set"):format(row.number),
      ("hm%02d_good_moveset"):format(row.number))
    check((game.save.inventory[row.item] or 0) == 1,
      ("HM%02d was consumed after successful teaching"):format(row.number),
      ("hm%02d_good_consumed"):format(row.number))

    U.shot(game, ("%s/%02d_hm%02d_%s_compatible_learned.png")
      :format(DIR, row.number, row.number, safeName(row.move)))

    U.log(("PASS HM%02d compatible Pokemon learned %s: %s")
      :format(row.number, row.move, goodRow.id))
    U.log(("PASS HM%02d remained in the bag after teaching")
      :format(row.number))
  end

  local passedNormal = 0

  for _, row in ipairs(acquisitions) do
    -- Reset the stack before every independent acquisition case.
    while game.stack:top() do game.stack:pop() end

    obtainNormally(row)
    teachAudit(row)
    passedNormal = passedNormal + 1
  end

  U.log(("PASS Crystal normal-acquisition HM audit: %d/7 HM rewards obtained and tested end-to-end")
    :format(passedNormal))
  U.log("No HM was injected by this audit.")

  restore()
  love.event.quit()
end
