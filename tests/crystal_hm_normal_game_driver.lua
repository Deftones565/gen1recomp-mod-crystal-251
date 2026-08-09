-- End-to-end Crystal HM test using the normal Gen I story reward path.
--
-- Flow:
--   S.S. Anne captain -> receive HM01 normally -> Bag -> HM01
--   -> incompatible Pokemon (must reject) -> HM01 again
--   -> compatible Pokemon (must learn CUT) -> HM01 remains owned.
--
-- Run from the Gen1Recomp repository root:
--
--   SHOT_DIR=/tmp/crystal-hm-normal \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_hm_normal_game_driver.lua \
--   POKEPORT_TOUCH=0 \
--   POKEPORT_SPEED=20 \
--   love .
--
-- Crystal 251 must already be enabled/imported. The driver never saves.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")

  local DIR = os.getenv("SHOT_DIR") or "/tmp/crystal-hm-normal"
  local HM = "HM_CUT"
  local MAP = "SS_ANNE_CAPTAINS_ROOM"
  local FLAG = "EVENT_GOT_HM01"

  local originalParty = game.save.party
  local originalInventory = game.save.inventory
  local originalBagOrder = game.save.bagOrder
  local originalFlag = game.save.flags and game.save.flags[FLAG]
  local originalSavedIndex = game.partyMenuSavedIndex

  local function restore()
    game.save.party = originalParty
    game.save.inventory = originalInventory
    game.save.bagOrder = originalBagOrder
    game.partyMenuSavedIndex = originalSavedIndex
    if game.save.flags then game.save.flags[FLAG] = originalFlag end
  end

  local function safeName(value)
    return tostring(value or "unknown"):lower():gsub("[^%w]+", "_")
  end

  local function fail(message, name)
    U.log("FAIL", message)
    U.shot(game, DIR .. "/FAIL_" .. safeName(name or "hm01") .. ".png")
    restore()
    error(message, 0)
  end

  local function check(value, message, name)
    if not value then fail(message, name) end
  end

  local function hasMove(mon, move)
    for _, mv in ipairs(mon.moves or {}) do
      if mv.id == move then return true end
    end
    return false
  end

  local function canLearn(def, move)
    for _, id in ipairs((def and def.tmhm) or {}) do
      if id == move then return true end
    end
    return false
  end

  local hmDef = game.data.items and game.data.items[HM]
  check(hmDef and hmDef.machine, "HM_CUT is missing from live item data", "hm_missing")
  check(hmDef.machine.kind == "HM" and hmDef.machine.number == 1,
    "HM_CUT is not live HM01", "hm_number")
  check(hmDef.machine.move == "CUT",
    "live HM01 teaches " .. tostring(hmDef.machine.move) .. " instead of CUT",
    "hm_move")

  local compatible, incompatible
  for id, def in pairs(game.data.pokemon or {}) do
    local dex = type(def) == "table" and def.dex or nil
    if type(dex) == "number" and dex >= 1 and dex <= 251 then
      if canLearn(def, "CUT") then
        if not compatible or dex < compatible.dex then
          compatible = { id = id, dex = dex, def = def }
        end
      elseif not incompatible or dex < incompatible.dex then
        incompatible = { id = id, dex = dex, def = def }
      end
    end
  end
  check(compatible ~= nil, "no Crystal Pokemon can learn CUT", "no_compatible")
  check(incompatible ~= nil, "no Crystal Pokemon rejects CUT", "no_incompatible")

  local bad = Pokemon.new(game.data, incompatible.id, 30)
  local good = Pokemon.new(game.data, compatible.id, 30)
  bad.moves = {}
  good.moves = {}

  game.save.party = { bad, good }
  game.save.inventory = {}
  game.save.bagOrder = {}
  game.save.flags = game.save.flags or {}
  game.save.flags[FLAG] = nil
  game.partyMenuSavedIndex = 1

  U.log("HM01 normal-game test:",
    "incompatible=#" .. incompatible.dex .. " " .. incompatible.id,
    "compatible=#" .. compatible.dex .. " " .. compatible.id)

  -- Get HM01 from the actual S.S. Anne captain talk script. No Bag.add(),
  -- no give_item call and no EVENT_GOT_HM01 shortcut is used here.
  U.teleport(game, MAP, 0, 0, "down")
  local ow = game.overworld
  check(ow and ow.map and ow.map.id == MAP,
    "could not enter the S.S. Anne captain's room", "captain_room")

  local captain
  for _, npc in ipairs(ow.npcs or {}) do
    local name = npc.def and npc.def.name or ""
    if tostring(name):find("CAPTAIN", 1, true) then
      captain = npc
      break
    end
  end
  check(captain ~= nil, "could not find the S.S. Anne captain NPC", "captain_npc")

  local spots = {
    { 0,  1, "up" },
    { 0, -1, "down" },
    { 1,  0, "left" },
    {-1,  0, "right" },
  }
  local stand
  for _, s in ipairs(spots) do
    local x, y = captain.cellX + s[1], captain.cellY + s[2]
    if ow.map:inBounds(x, y) and ow.map:isWalkableCell(x, y) then
      stand = { x = x, y = y, facing = s[3] }
      break
    end
  end
  check(stand ~= nil, "no walkable cell beside the S.S. Anne captain", "captain_adjacent")

  U.teleport(game, MAP, stand.x, stand.y, stand.facing)
  U.wait(2)

  -- Use the overworld's real interaction path while standing in front of
  -- the captain. HM01 is still awarded only by the captain's normal NPC
  -- script; the test never inserts HM_CUT or sets EVENT_GOT_HM01 itself.
  ow = game.overworld
  check(type(ow.interact) == "function",
    "overworld interaction function is unavailable", "captain_interact")
  ow:interact()
  U.wait(2)

  -- The captain's real reward script runs:
  --   dialogue -> Music_PkmnHealed -> dialogue -> give_item HM_CUT.
  -- play_once deliberately blocks until the real audio channel finishes.
  -- POKEPORT_SPEED accelerates logic, not the duration of that one-shot,
  -- so a fixed frame timeout can expire long before the jingle ends.
  -- Use wall-clock time here so this remains a real end-to-end test at
  -- both normal speed and accelerated driver speed.
  local gotHM = false
  local rewardDeadline = love.timer.getTime() + 15
  local waitingLogged = false
  while love.timer.getTime() < rewardDeadline do
    if game.save.flags[FLAG]
        and (game.save.inventory[HM] or 0) == 1
        and game.stack:top() == game.overworld then
      gotHM = true
      break
    end
    local Music = require("src.core.Music")
    if Music.oneShotPlaying and Music.oneShotPlaying() and not waitingLogged then
      U.log("waiting for captain reward jingle to finish")
      waitingLogged = true
    end
    U.tap(game, "a")
    U.wait(1)
    -- Avoid spinning thousands of accelerated logic frames while the
    -- real-time one-shot is still playing.
    if Music.oneShotPlaying and Music.oneShotPlaying() and love.timer.sleep then
      love.timer.sleep(0.01)
    end
  end
  check(gotHM,
    "captain interaction did not award HM01 through the normal story script",
    "captain_reward")
  check((game.save.inventory[HM] or 0) == 1,
    "normal HM01 reward is not in the bag", "reward_inventory")
  U.log("PASS obtained HM01 from S.S. Anne captain")
  U.shot(game, DIR .. "/01_hm01_obtained.png")

  local function reachPartyMenu()
    for _ = 1, 160 do
      local top = game.stack:top()
      if getmetatable(top) == PartyMenu then return top end
      U.tap(game, "a")
      U.wait(1)
    end
    return nil
  end

  local function openHM()
    local bag = Screens.push(game, "BagMenu")
    U.wait(2)
    if bag and bag.gen2 then
      U.tap(game, "left")
      U.wait(2)
    end
    check(bag and bag.items and #bag.items == 1 and bag.items[1].value == HM,
      "HM01 is not the selectable item in the real Bag UI", "bag_hm01")
    U.tap(game, "a")
    U.wait(2)
    U.tap(game, "a")
    U.wait(2)
    local party = reachPartyMenu()
    check(party ~= nil, "HM01 did not open the real PartyMenu", "party_open")
    check(party.tmhm and party.tmhm.kind == "HM" and party.tmhm.move == "CUT",
      "PartyMenu did not enter HM01/CUT compatibility mode", "party_hm_mode")
    return party, bag
  end

  -- First attempt the incompatible Pokemon. This must take the normal
  -- PartyMenu selection path and reject it without learning or consuming HM01.
  local party, bag = openHM()
  game.partyMenuSavedIndex = 1
  party.index = 1
  U.shot(game, DIR .. "/02_able_not_able.png")
  U.tap(game, "a")
  U.wait(3)
  check(not hasMove(bad, "CUT"),
    incompatible.id .. " incorrectly learned CUT", "incompatible_learned")
  check((game.save.inventory[HM] or 0) == 1,
    "HM01 was consumed by the incompatible attempt", "incompatible_consumed")
  U.shot(game, DIR .. "/03_incompatible_rejected.png")
  U.log("PASS incompatible Pokemon rejected HM01:", incompatible.id)

  -- Dismiss the rejection text back to the same BagMenu.
  for _ = 1, 80 do
    if game.stack:top() == bag then break end
    U.tap(game, "a")
    U.wait(1)
  end
  check(game.stack:top() == bag,
    "incompatible HM01 attempt did not return to the bag", "reject_return")

  -- Use the still-owned HM01 again, then choose the compatible Pokemon.
  game.partyMenuSavedIndex = 1
  U.tap(game, "a")
  U.wait(2)
  U.tap(game, "a")
  U.wait(2)
  party = reachPartyMenu()
  check(party ~= nil, "second HM01 use did not reach PartyMenu", "party_second")
  check(party.tmhm and party.tmhm.move == "CUT",
    "second HM01 use lost CUT compatibility mode", "party_second_mode")
  party.index = 1
  U.tap(game, "down")
  U.wait(2)
  check(party.index == 2, "could not select the compatible Pokemon", "compatible_select")
  U.tap(game, "a")
  U.wait(3)

  check(hasMove(good, "CUT"),
    compatible.id .. " did not learn CUT from normally obtained HM01",
    "compatible_not_learned")
  check((game.save.inventory[HM] or 0) == 1,
    "HM01 was consumed after teaching CUT", "compatible_consumed")
  U.shot(game, DIR .. "/04_compatible_learned.png")

  U.log("PASS compatible Pokemon learned CUT:", compatible.id)
  U.log("PASS HM01 remained in the bag after teaching")
  U.log("PASS Crystal normal-game HM01 audit")

  restore()
  love.event.quit()
end
