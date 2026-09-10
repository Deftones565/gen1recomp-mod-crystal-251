-- Pokemon Crystal turn-resolution and between-turn scheduler.
--
-- Gen 2 resolves the shared end-of-turn pipeline in battler order:
-- weather, status damage, Leech Seed/Curse/Nightmare, partial trapping,
-- held recovery, Future Sight, Perish Song, defrost, Safeguard, screens,
-- Encore, and lock-on counters.

local Runtime = require("src.mods.Runtime")
local CrystalItems = require("mods.CRYSTAL_251.battle.crystal_items")
local CrystalStatus = require("mods.CRYSTAL_251.battle.crystal_status")
local SpecialDamage = require("mods.CRYSTAL_251.battle.special_damage")

local Scheduler = {}

local function sideKey(battler)
  return battler and battler.isPlayer and "player" or "enemy"
end

local function trace(battle, phase, battler)
  local out = battle and battle.crystalSchedulerTrace
  if out then
    out[#out + 1] = battler and (phase .. ":" .. sideKey(battler)) or phase
  end
end

local function displayName(battler)
  if not battler then return "Pokemon" end
  return battler.isPlayer and tostring(battler.name)
    or ("Enemy " .. tostring(battler.name))
end

local function endOrder(battle)
  -- hSerialConnectionStatus == USING_EXTERNAL_CLOCK reverses every paired
  -- between-turn routine.  In the runtime that is the guest's perspective.
  if battle and battle.kind == "link" and battle.linkRole == "guest" then
    return { battle.enemy, battle.player }
  end
  return { battle.player, battle.enemy }
end
Scheduler.endOrder = endOrder

local function opponentOf(battle, battler)
  return battler == battle.player and battle.enemy or battle.player
end

local function alive(battler)
  return battler and battler.mon and battler.mon.hp > 0
end

local function queueMessages(battle, battler, messages)
  for _, message in ipairs(messages or {}) do
    if battle.sayNext then battle:sayNext(message) end
  end
  if messages and #messages > 0 and battle.drainNext then battle:drainNext() end
end

local function faintIfNeeded(battle, battler)
  if battler and battler.mon and battler.mon.hp <= 0 and battle.onFaint then
    battle:onFaint(battler)
    return true
  end
  return false
end

function Scheduler.beginTurn(battle)
  if not battle then return end
  battle.crystalResidualTurns = {}
  battle.crystalActionOrder = {}
end

function Scheduler.afterAction(battle, battler, opponent)
  if not (battle and battle.crystal251Active and battler and opponent)
     or battle.result or not alive(battler) or not alive(opponent) then
    return false
  end
  battle.crystalResidualTurns = battle.crystalResidualTurns or {}
  battle.crystalActionOrder = battle.crystalActionOrder or {}
  battle.crystalActionOrder[#battle.crystalActionOrder + 1] = sideKey(battler)
  -- Gen 2 applies residuals in HandleBetweenTurnEffects, after weather and
  -- in battler order. The action hook only records that the action happened.
  return true
end

local function ensureActionResiduals(battle)
  -- Direct test probes and a few nonstandard battle drivers emit turn_ended
  -- without going through executeAction.  Preserve exact live behavior while
  -- giving those callers the same result once per side.
  return battle
end

local function checkFaints(battle)
  local fainted = false
  for _, battler in ipairs(endOrder(battle)) do
    if battler and battler.mon and battler.mon.hp <= 0 then
      fainted = faintIfNeeded(battle, battler) or fainted
    end
  end
  return fainted
end

local function weatherDamage(battle, battler)
  if battle.weather ~= "sandstorm" or not alive(battler)
      or battler.invulnerableMove == "DIG" then return 0 end
  for _, typeId in ipairs(battler.curTypes or {}) do
    if typeId == "ROCK" or typeId == "GROUND" or typeId == "STEEL" then
      return 0
    end
  end
  local damage = math.max(1, math.floor(battler.mon.stats.hp / 8))
  if battle.animNext then battle:animNext("IN_SANDSTORM", not battler.isPlayer) end
  if battle.sayNext then
    battle:sayNext(displayName(battler) .. " is buffeted by the sandstorm!")
  end
  local dealt = battle:applyDamage(battler, damage)
  if dealt > 0 and battle.drainNext then battle:drainNext() end
  return dealt
end

function Scheduler.handleWeather(battle)
  if not battle.weatherTurns then return end
  if battle.animNext then
    local animation = ({ rain="CRYSTAL_RAIN", sun="CRYSTAL_SUN",
      sandstorm="CRYSTAL_SANDSTORM" })[battle.weather]
    if animation then battle:animNext(animation, true) end
  end
  battle.weatherTurns = battle.weatherTurns - 1
  if battle.weatherTurns <= 0 then
    local ended = battle.weather
    battle.weather, battle.weatherTurns = nil, nil
    if battle.sayNext then
      if ended == "sandstorm" then battle:sayNext("The sandstorm subsided.")
      elseif ended == "rain" then battle:sayNext("The rain stopped.")
      elseif ended == "sun" then battle:sayNext("The sunlight faded.") end
    end
    return
  end
  if battle.sayNext then
    local text = ({sandstorm="The sandstorm rages.",
      rain="The rain continues to fall.", sun="The sunlight is strong."})[battle.weather]
    if text then battle:sayNext(text) end
  end
  for _, battler in ipairs(endOrder(battle)) do weatherDamage(battle, battler) end
end

function Scheduler.handleWrap(battle)
  for _, battler in ipairs(endOrder(battle)) do
    if alive(battler) then
      local messages = CrystalStatus.wrapResidual(battler, battle)
      queueMessages(battle, battler, messages)
    end
  end
end

local function tickScreenSide(battle, side, battler)
  for _, row in ipairs({
    { field="reflectTurns", flag="reflect", ended="REFLECT wore off!" },
    { field="lightScreenTurns", flag="lightScreen", ended="LIGHT SCREEN wore off!" },
  }) do
    if side[row.field] then
      side[row.field] = side[row.field] - 1
      if side[row.field] <= 0 then
        side[row.field] = nil
        if battle.sayNext then
          battle:sayNext(displayName(battler) .. "'s " .. row.ended)
        end
      end
    end
  end
end

local function syncScreenBattler(side, battler)
  if not battler then return end
  battler.reflectTurns = side.reflectTurns
  battler.lightScreenTurns = side.lightScreenTurns
  battler.reflect = side.reflectTurns and side.reflectTurns > 0 or nil
  battler.lightScreen = side.lightScreenTurns and side.lightScreenTurns > 0 or nil
end

function Scheduler.handleScreens(battle, order)
  battle.crystalScreens = battle.crystalScreens or { player={}, enemy={} }
  order = order or { battle.player, battle.enemy }
  for _, battler in ipairs(order) do
    if battler then
      local side = battler.isPlayer and battle.crystalScreens.player
        or battle.crystalScreens.enemy
      tickScreenSide(battle, side, battler)
    end
  end
  syncScreenBattler(battle.crystalScreens.player, battle.player)
  syncScreenBattler(battle.crystalScreens.enemy, battle.enemy)
end

local function tickLockOn(battle)
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler and battler.lockOnTurns then
      battler.lockOnTurns = battler.lockOnTurns - 1
      if battler.lockOnTurns <= 0 then
        battler.lockOnTurns, battler.lockedTarget = nil, nil
      end
    end
  end
end

function Scheduler.endTurn(battle)
  if not (battle and battle.crystal251Active) then return false end
  if battle._crystalSchedulerRunning then return true end
  battle._crystalSchedulerRunning = true

  if not battle.result then
    ensureActionResiduals(battle)

    trace(battle, "weather")
    Scheduler.handleWeather(battle)
    checkFaints(battle)

    if not battle.result then
      for _, battler in ipairs(endOrder(battle)) do
        if alive(battler) then
          trace(battle, "status", battler)
          queueMessages(battle, battler,
            CrystalStatus.statusResidual(battler, battle))
          trace(battle, "seed_curse", battler)
          queueMessages(battle, battler,
            CrystalStatus.seedCurseResidual(battler, opponentOf(battle, battler), battle))
        end
      end
      checkFaints(battle)
    end
    if not battle.result then
      trace(battle, "wrap")
      Scheduler.handleWrap(battle)
      checkFaints(battle)
    end
    if not battle.result then trace(battle, "leftovers"); CrystalItems.handleLeftovers(battle, endOrder(battle)) end
    if not battle.result then trace(battle, "mysteryberry"); CrystalItems.handleMysteryBerry(battle, endOrder(battle)) end
    if not battle.result then trace(battle, "healing"); CrystalItems.handleHealingItems(battle, endOrder(battle)) end

    if not battle.result then
      trace(battle, "future_sight")
      SpecialDamage.tickFutureSight(battle, endOrder(battle))
      checkFaints(battle)
    end
    if not battle.result then
      trace(battle, "perish")
      CrystalStatus.tickPerish(battle, endOrder(battle))
      checkFaints(battle)
    end
    if not battle.result then trace(battle, "defrost"); CrystalStatus.handleDefrost(battle, endOrder(battle)) end
    if not battle.result then trace(battle, "safeguard"); CrystalStatus.tickSafeguard(battle, endOrder(battle)) end
    if not battle.result then trace(battle, "screens"); Scheduler.handleScreens(battle, endOrder(battle)) end
    if not battle.result then trace(battle, "encore"); CrystalStatus.tickEncore(battle, endOrder(battle)) end
    if not battle.result then trace(battle, "lockon"); tickLockOn(battle) end
  end

  battle.crystalResidualTurns = {}
  battle.crystalActionOrder = {}
  battle._crystalSchedulerRunning = nil
  return true
end

function Scheduler.onTurnEnded(ev)
  local battle = ev and ev.battle
  if not (battle and battle.crystal251Active) or ev.crystalScheduled then return end
  Scheduler.endTurn(battle)
end

function Scheduler.installRuntime()
  local BattleState = require("src.battle.BattleState")
  if BattleState._crystal251SchedulerBridge then return end
  BattleState._crystal251SchedulerBridge = true

  local originalExecuteAction = BattleState.executeAction
  BattleState.executeAction = function(self, user, target, action)
    local result = originalExecuteAction(self, user, target, action)
    if self.crystal251Active and user and target then
      local activeUser = user.isPlayer and self.player or self.enemy
      local activeTarget = user.isPlayer and self.enemy or self.player
      Scheduler.afterAction(self, activeUser, activeTarget)
    end
    return result
  end

  local originalResolveSwitch = BattleState.resolveSwitch
  BattleState.resolveSwitch = function(self, newMon)
    local before = #self.queue
    local result = originalResolveSwitch(self, newMon)
    if self.crystal251Active and #self.queue >= before + 4 then
      -- Original queue: interception, switch, enemy action, end turn.
      table.insert(self.queue, before + 3, { fn=function()
        Scheduler.afterAction(self, self.player, self.enemy)
      end })
    end
    return result
  end

  local function insertBeforeFirstNewFn(self, before, fn)
    local fnCount = 0
    for index = before + 1, #self.queue do
      if self.queue[index].fn then
        fnCount = fnCount + 1
        if fnCount == 1 then
          table.insert(self.queue, index, { fn=fn })
          return true
        end
      end
    end
    return false
  end

  local originalItemUsed = BattleState.itemUsed
  BattleState.itemUsed = function(self, messages)
    local before = #self.queue
    local result = originalItemUsed(self, messages)
    if self.crystal251Active then
      insertBeforeFirstNewFn(self, before, function()
        Scheduler.afterAction(self, self.player, self.enemy)
      end)
    end
    return result
  end

  local originalTryRun = BattleState.tryRun
  BattleState.tryRun = function(self)
    local before = #self.queue
    local result = originalTryRun(self)
    if self.crystal251Active and not self.result then
      local count = 0
      for index = before + 1, #self.queue do
        if self.queue[index].fn then count = count + 1 end
      end
      if count >= 2 then
        insertBeforeFirstNewFn(self, before, function()
          Scheduler.afterAction(self, self.player, self.enemy)
        end)
      end
    end
    return result
  end

  local originalEndOfTurn = BattleState.endOfTurn
  BattleState.endOfTurn = function(self)
    if not self.crystal251Active then return originalEndOfTurn(self) end
    Scheduler.endTurn(self)
    Runtime.emit("battle.turn_ended", {
      battle=self, turn=self.turnCount or 0, crystalScheduled=true,
    })
  end
end

return Scheduler
