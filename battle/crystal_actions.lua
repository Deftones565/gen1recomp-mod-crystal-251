-- Pokemon Crystal action legality, obedience, PP and trainer-item behavior.
--
-- The live engine is Generation-I-shaped, so this module keeps every change
-- behind battle.crystal251Active and installs only runtime wrappers.  The
-- behavioral source is pret/pokecrystal's CheckObedience, DoTurn and
-- AI_TryItem routines.

local Actions = {}

local HEAL_AMOUNT = {
  POTION=20, SUPER_POTION=50, HYPER_POTION=200,
}

local X_STAT = {
  X_ATTACK="attack", X_DEFEND="defense", X_SPEED="speed",
  X_SPECIAL="specialAttack",
}

local TRAINER_ITEMS = {
  FULL_RESTORE=true, MAX_POTION=true, HYPER_POTION=true,
  SUPER_POTION=true, POTION=true, X_ACCURACY=true,
  FULL_HEAL=true, GUARD_SPEC=true, DIRE_HIT=true,
  X_ATTACK=true, X_DEFEND=true, X_SPEED=true, X_SPECIAL=true,
}
Actions.TRAINER_ITEMS = TRAINER_ITEMS

local function displayName(battler)
  if not battler then return "POKEMON" end
  return battler.isPlayer and tostring(battler.name)
    or ("Enemy " .. tostring(battler.name))
end

local function swapNibbles(value)
  value = math.floor(value or 0) % 256
  return (value % 16) * 16 + math.floor(value / 16)
end
Actions.swapNibbles = swapNibbles

local function battleTower(battle)
  return battle and (battle.battleTower or battle.inBattleTowerBattle
    or battle.kind == "battle_tower")
end

function Actions.badgeCount(battle)
  if not battle then return 0 end
  if battle.crystalBadgeCount ~= nil then
    return math.max(0, math.floor(battle.crystalBadgeCount))
  end
  local save = battle.game and battle.game.save
  local inventory = save and save.inventory
  if not inventory then return 0 end
  local list = battle.data and battle.data.constants
    and battle.data.constants.badges
  if type(list) ~= "table" or #list == 0 then
    list = {
      {id="BOULDERBADGE"},{id="CASCADEBADGE"},{id="THUNDERBADGE"},
      {id="RAINBOWBADGE"},{id="SOULBADGE"},{id="MARSHBADGE"},
      {id="VOLCANOBADGE"},{id="EARTHBADGE"},
    }
  end
  local count = 0
  for _, row in ipairs(list) do
    local key = row.item or row.id
    if key and inventory[key] then count = count + 1 end
  end
  return count
end

-- Crystal badge thresholds are 10 / 30 / 50 / 70 / all levels.  The mod's
-- world still exposes the eight Kanto badge slots, so positions 2/4/6/8 are
-- used as the equivalent progression gates.
local function badgeAt(battle, position)
  if battle and battle.crystalBadgeCount ~= nil then
    return battle.crystalBadgeCount >= position
  end
  local save = battle and battle.game and battle.game.save
  local inventory = save and save.inventory
  if not inventory then return false end
  local list = battle.data and battle.data.constants
    and battle.data.constants.badges
  if type(list) ~= "table" or #list == 0 then
    list = {
      {id="BOULDERBADGE"},{id="CASCADEBADGE"},{id="THUNDERBADGE"},
      {id="RAINBOWBADGE"},{id="SOULBADGE"},{id="MARSHBADGE"},
      {id="VOLCANOBADGE"},{id="EARTHBADGE"},
    }
  end
  local row = list[position]
  local key = row and (row.item or row.id)
  return key ~= nil and inventory[key] == true
end

function Actions.obedienceLevel(battle)
  if badgeAt(battle, 8) then return 101 end
  if badgeAt(battle, 6) then return 70 end
  if badgeAt(battle, 4) then return 50 end
  if badgeAt(battle, 2) then return 30 end
  return 10
end

function Actions.isOutsider(battle, battler)
  local player = battle and battle.game and battle.game.save
    and battle.game.save.player
  local playerId = player and player.id
  local otId = battler and battler.mon and battler.mon.otId
  return playerId ~= nil and otId ~= nil and playerId ~= otId
end

local function isChargeRelease(user, moveInst)
  return user and user.charging == moveInst and user.chargeReady
end

function Actions.isContinuation(user, moveInst)
  if not (user and moveInst) then return false end
  if isChargeRelease(user, moveInst) then return true end
  if user.thrashTurns and user.thrashTurns > 0
     and moveInst == user.thrashMove then return true end
  if user.forcedMove and moveInst == user.forcedMove
     and ((user.rolloutCount or 0) > 0 or (user.forcedMoveTurns or 0) > 0) then
    return true
  end
  return false
end

local function rollBelow(rng, limit, swapped)
  limit = math.max(1, math.min(255, math.floor(limit or 1)))
  for _ = 1, 1024 do
    local value = rng(0, 255)
    if swapped then value = swapNibbles(value) end
    if value < limit then return value end
  end
  return 0
end

local function napTurns(rng)
  for _ = 1, 1024 do
    local value = (rng(0, 255) * 2) % 256
    value = swapNibbles(value) % 8
    if value ~= 0 then return value end
  end
  return 1
end

function Actions.usableMoves(battler, omitIndex)
  local usable = {}
  for index, moveInst in ipairs((battler and battler.curMoves) or {}) do
    if index ~= omitIndex and battler.disabledSlot ~= index
       and (moveInst.pp or 0) > 0 then
      usable[#usable + 1] = { index=index, move=moveInst }
    end
  end
  return usable
end

local function moveIndex(battler, action)
  for index, moveInst in ipairs((battler and battler.curMoves) or {}) do
    if moveInst == action then return index end
  end
  if action and action.id then
    for index, moveInst in ipairs((battler and battler.curMoves) or {}) do
      if moveInst.id == action.id then return index end
    end
  end
  return nil
end

local function alternateMove(battle, battler, selected)
  local selectedIndex = moveIndex(battler, selected)
  if not selectedIndex or battler.disabledMove or battler.disabledTurns
     or battler.disabledSlot then
    return nil
  end
  local usable = Actions.usableMoves(battler, selectedIndex)
  if #usable == 0 then return nil end

  -- The ROM repeatedly samples a move slot and rejects the selected slot,
  -- undefined slots and zero-PP slots. Sampling the compact legal set is
  -- distribution-equivalent when all four slots are equally likely.
  local pick = usable[battle.rng(1, #usable)]
  return pick and pick.move or nil
end

function Actions.checkObedience(battle, user, action)
  if not (battle and battle.crystal251Active and user and user.isPlayer)
     or not action or not action.id or action.struggle
     or battle.kind == "link" or battleTower(battle)
     or Actions.isContinuation(user, action)
     or not Actions.isOutsider(battle, user) then
    return { obey=true }
  end

  local level = math.max(1, math.floor((user.mon and user.mon.level) or 1))
  local obeyLevel = Actions.obedienceLevel(battle)
  if level <= obeyLevel then return { obey=true } end

  local total = math.min(255, level + obeyLevel)
  local first = rollBelow(battle.rng, total, true)
  if first < obeyLevel then return { obey=true } end

  if user.mon.status == "SLP"
     and (action.id == "SNORE" or action.id == "SLEEP_TALK") then
    return { interrupted=true, kind="ignored_sleep",
      message=displayName(user) .. " ignored orders...sleeping!" }
  end

  local second = rollBelow(battle.rng, total, false)
  if second < obeyLevel then
    local replacement = alternateMove(battle, user, action)
    if replacement then
      return { interrupted=true, kind="alternate", action=replacement,
        message=displayName(user) .. " ignored orders!" }
    end
  end

  local delta = level - obeyLevel
  local third = swapNibbles(battle.rng(0, 255))
  if third < delta then
    return { interrupted=true, kind="nap", turns=napTurns(battle.rng),
      message=displayName(user) .. " began to nap!" }
  elseif third < delta * 2 then
    return { interrupted=true, kind="self_hit",
      message=displayName(user) .. " won't obey!" }
  end

  local lines = {
    displayName(user) .. " is loafing around!",
    displayName(user) .. " won't obey!",
    displayName(user) .. " turned away!",
    displayName(user) .. " ignored orders!",
  }
  return { interrupted=true, kind="nothing",
    message=lines[(battle.rng(0, 255) % 4) + 1] }
end

function Actions.applyDisobedience(battle, user, target, result)
  if not (result and result.interrupted) then return false end
  if result.message and battle.sayNext then battle:sayNext(result.message) end

  if result.kind == "alternate" and result.action then
    -- CheckObedience recursively enters DoMove with wAlreadyDisobeyed set;
    -- direct performMove re-entry has the same effect and consumes the
    -- replacement move's PP through this module's wrapper.
    battle:performMove(user, target, result.action, false)
  elseif result.kind == "nap" then
    user.mon.status = "SLP"
    user.sleepTurns = result.turns or 1
    user.nightmare = nil
  elseif result.kind == "self_hit" then
    if battle.computeDamage and battle.applyDamage then
      local damage = battle:computeDamage(user, user,
        { id="DISOBEY", power=40, type="NORMAL", accuracy=100 },
        { rng=battle.rng, forceCrit=false, typeless=true, screens=target })
      if battle.sayNext then
        battle:sayNext("It hurt itself in its confusion!")
      end
      battle:applyDamage(user, damage)
      if user.mon.hp <= 0 and battle.onFaint then battle:onFaint(user) end
    end
  end

  -- EndDisobedience clears the remembered/counter move and breaks Encore,
  -- but (unlike the ordinary confusion gate) does not call CantMove and
  -- therefore does not erase charge/rampage/Rollout state.
  if result.kind ~= "alternate" then
    user.lastMove, user.lastCounterMove = nil, nil
    user.encoreTurns, user.encoreMove = nil, nil
  end
  return true
end


function Actions.onSelectedAction(user, action)
  if not (user and action and action.id) then return end
  local id = action.id
  if id ~= "FURY_CUTTER" then user.furyCutterCount = nil end
  if id ~= "PROTECT" and id ~= "DETECT" and id ~= "ENDURE" then
    user.protectChain, user.protectLastTurn = nil, nil
  end
  if id ~= "RAGE" then
    user.rageMove, user.crystalRageMove, user.crystalRageCounter = nil, nil, nil
  end
  -- EndUserDestinyBond runs before every attempted move. Selecting Destiny
  -- Bond again simply reapplies it later in that move's command stream.
  user.destinyBond = nil
end

function Actions.consumePP(battle, user, moveInst, isCalled)
  if not moveInst or moveInst.struggle or isCalled
     or Actions.isContinuation(user, moveInst) then
    return true, false
  end
  local pp = math.floor(moveInst.pp or 0)
  if pp <= 0 then return false, false end
  moveInst.pp = pp - 1
  return true, true
end

function Actions.legalizeEnemyAction(battle, battler, action)
  if not (battle and battle.crystal251Active and battler and action)
     or action.special or not action.id or action.struggle
     or Actions.isContinuation(battler, action) then
    return action
  end
  local index = moveIndex(battler, action)
  local stored = index and battler.curMoves[index] or nil
  if stored and battler.disabledSlot ~= index and (stored.pp or 0) > 0 then
    return stored
  end
  local usable = Actions.usableMoves(battler)
  if #usable == 0 then return { id="STRUGGLE", pp=1, struggle=true } end
  return usable[battle.rng(1, #usable)].move
end

local function highestLevelEnemy(battle)
  local active = battle and battle.enemy and battle.enemy.mon
  if not active then return false end
  local highest = 0
  for _, mon in ipairs(battle.enemyParty or {}) do
    if (mon.level or 0) > highest then highest = mon.level or 0 end
  end
  return (active.level or 0) >= highest
end
Actions.highestLevelEnemy = highestLevelEnemy

function Actions.trainerItemEligible(battle, item)
  return battle and battle.crystal251Active and battle.kind == "trainer"
    and battle.kind ~= "link" and not battleTower(battle)
    and (battle.aiUses or 0) > 0 and TRAINER_ITEMS[item] == true
    and highestLevelEnemy(battle)
end

function Actions.trainerItemUseful(battle, item)
  local enemy = battle and battle.enemy
  if not (enemy and enemy.mon) then return false end
  local mon = enemy.mon
  if item == "FULL_HEAL" then return mon.status ~= nil end
  if item == "FULL_RESTORE" then
    return mon.hp < mon.stats.hp or mon.status ~= nil or enemy.confusedTurns ~= nil
  end
  if item == "MAX_POTION" or HEAL_AMOUNT[item] then
    return mon.hp < mon.stats.hp
  end
  if item == "X_ACCURACY" then return not enemy.xAccuracy end
  if item == "GUARD_SPEC" then return not enemy.mist end
  if item == "DIRE_HIT" then return not enemy.focusEnergy end
  local stat = X_STAT[item]
  if stat then return (enemy.stages[stat] or 0) < 6 end
  return false
end

local function clearMajorStatus(enemy)
  enemy.mon.status = nil
  enemy.sleepTurns = nil
  enemy.toxicCounter = nil
  enemy.nightmare = nil
end

function Actions.resetAfterTrainerItem(enemy)
  enemy.bideTurns, enemy.bideDamage, enemy.crystalBide = nil, nil, nil
  enemy.furyCutterCount = nil
  enemy.protectChain, enemy.protectLastTurn = nil, nil
  enemy.rageMove, enemy.crystalRageMove, enemy.crystalRageCounter = nil, nil, nil
  enemy.lastCounterMove = nil
end

function Actions.useTrainerItem(battle, item)
  local enemy = battle.enemy
  local def = battle.data and battle.data.items and battle.data.items[item]
  local itemName = def and def.name or item
  local trainerName = battle.trainer and battle.trainer.name or "Trainer"
  local messages = { trainerName .. " used " .. tostring(itemName) .. "!" }

  if item == "FULL_HEAL" then
    -- Crystal bug: enemy Full Heal does not clear confusion.
    clearMajorStatus(enemy)
  elseif item == "FULL_RESTORE" then
    clearMajorStatus(enemy)
    enemy.confusedTurns = nil
    enemy.mon.hp = enemy.mon.stats.hp
  elseif item == "MAX_POTION" then
    enemy.mon.hp = enemy.mon.stats.hp
  elseif HEAL_AMOUNT[item] then
    enemy.mon.hp = math.min(enemy.mon.stats.hp,
      enemy.mon.hp + HEAL_AMOUNT[item])
  elseif item == "X_ACCURACY" then
    enemy.xAccuracy = true
  elseif item == "GUARD_SPEC" then
    enemy.mist = true
  elseif item == "DIRE_HIT" then
    enemy.focusEnergy = true
  elseif X_STAT[item] then
    local stat = X_STAT[item]
    enemy.stages[stat] = math.min(6, (enemy.stages[stat] or 0) + 1)
    messages[#messages + 1] = tostring(enemy.name) .. "'s " .. stat:upper() .. " rose!"
  end

  Actions.resetAfterTrainerItem(enemy)
  return messages
end

function Actions.installRuntime()
  local BattleState = require("src.battle.BattleState")
  local TrainerAI = require("src.battle.TrainerAI")
  if BattleState._crystal251ActionsBridge then return end
  BattleState._crystal251ActionsBridge = true

  local originalMenuLockedAction = BattleState.menuLockedAction
  BattleState.menuLockedAction = function(self, battler)
    if not self.crystal251Active then
      return originalMenuLockedAction(self, battler)
    end
    if battler.mustRecharge then return { special="recharge" } end
    if battler.charging then return battler.charging end
    if battler.encoreTurns and battler.encoreTurns > 0 and battler.encoreMove then
      for _, moveInst in ipairs(battler.curMoves or {}) do
        if moveInst.id == battler.encoreMove and (moveInst.pp or 0) > 0 then
          return moveInst
        end
      end
      battler.encoreTurns, battler.encoreMove = nil, nil
    end
    if battler.forcedMove and (battler.forcedMoveTurns or 0) > 0 then
      return battler.forcedMove
    end
    if battler.thrashTurns and battler.thrashTurns > 0 then
      return battler.thrashMove
    end
    -- Crystal Rage remains active as a damage counter, but does not skip the
    -- move menu and therefore is not returned as a forced action.
    return nil
  end

  local originalEnemyAction = BattleState.enemyAction
  BattleState.enemyAction = function(self)
    local action = originalEnemyAction(self)
    if self.crystal251Active then
      return Actions.legalizeEnemyAction(self, self.enemy, action)
    end
    return action
  end

  local originalStatusInterrupt = BattleState.statusInterrupt
  BattleState.statusInterrupt = function(self, user, target, action)
    if self.crystal251Active then Actions.onSelectedAction(user, action) end
    local interrupted = originalStatusInterrupt(self, user, target, action)
    if interrupted or not self.crystal251Active then return interrupted end
    local result = Actions.checkObedience(self, user, action)
    if result and result.interrupted then
      Actions.applyDisobedience(self, user, target, result)
      return true
    end
    return false
  end

  local originalPerformMove = BattleState.performMove
  BattleState.performMove = function(self, user, target, moveInst, isCalled)
    if not moveInst or not self.crystal251Active then
      return originalPerformMove(self, user, target, moveInst, isCalled)
    end
    local selectedId = moveInst.id
    local usable, consumed = Actions.consumePP(self, user, moveInst, isCalled)
    if not usable then
      if self.sayNext then self:sayNext("But no PP is left for the move!") end
      return
    end
    local crystalPP = consumed and moveInst.pp or nil
    if consumed then moveInst.pp = crystalPP + 1 end
    local ok, a, b, c = pcall(originalPerformMove,
      self, user, target, moveInst, isCalled)
    if consumed and moveInst.id == selectedId then moveInst.pp = crystalPP end
    if not ok then error(a, 0) end
    return a, b, c
  end

  local originalPlayerHasPP = BattleState.playerHasPP
  BattleState.playerHasPP = function(self)
    if not self.crystal251Active then return originalPlayerHasPP(self) end
    return #Actions.usableMoves(self.player) > 0
  end

  local originalClassAction = TrainerAI.classAction
  TrainerAI.classAction = function(battle)
    local action = originalClassAction(battle)
    if not (battle and battle.crystal251Active) then return action end
    if action and action.special == "aiItem" then
      if Actions.trainerItemEligible(battle, action.item)
         and Actions.trainerItemUseful(battle, action.item) then
        return action
      end
      return nil
    end
    return action
  end

  local originalUseItem = TrainerAI.useItem
  TrainerAI.useItem = function(battle, item)
    if battle and battle.crystal251Active and TRAINER_ITEMS[item] then
      return Actions.useTrainerItem(battle, item)
    end
    return originalUseItem(battle, item)
  end
end

return Actions
