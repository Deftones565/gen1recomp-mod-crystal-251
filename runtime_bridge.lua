-- Crystal-only runtime adaptation layer.
--
-- This module deliberately patches engine functions only at runtime while the
-- CRYSTAL_251 mod is loaded.  No source file outside mods/CRYSTAL_251 is
-- modified, and every behavioral branch is restricted to Crystal-owned data.

local CrystalItems = require("mods.CRYSTAL_251.battle.crystal_items")

local Bridge = {
  heldItems = {},
}

local function defaultRng(a, b)
  if love and love.math and love.math.random then
    return love.math.random(a, b)
  end
  return math.random(a, b)
end

local function rollWildHeldItem(species, rng)
  local held = Bridge.heldItems and Bridge.heldItems[species]
  return CrystalItems.rollWildHeldItem(held, rng or defaultRng)
end

Bridge.rollWildHeldItem = rollWildHeldItem

-- Mark HP loss that came from a move command. Crystal Rage builds only after
-- applydamage/buildopponentrage, not from poison, weather or other residuals.
function Bridge.applyMoveDamage(battle, target, damage)
  if not battle then return 0 end
  battle._crystalMoveDamageDepth = (battle._crystalMoveDamageDepth or 0) + 1
  local ok, dealt = pcall(battle.applyDamage, battle, target, damage)
  battle._crystalMoveDamageDepth = math.max(0,
    (battle._crystalMoveDamageDepth or 1) - 1)
  if not ok then error(dealt, 0) end
  return dealt
end

function Bridge.setHeldItems(items)
  Bridge.heldItems = items or {}
end

local function installPokemonBridge()
  local Pokemon = require("src.pokemon.Pokemon")
  if Pokemon._crystal251RuntimeBridge then return end
  Pokemon._crystal251RuntimeBridge = true

  local originalNew = Pokemon.new
  Pokemon.new = function(data, species, level, rng, opts)
    local mon = originalNew(data, species, level, rng)
    if opts and opts.wildHeldItem then
      mon.heldItem = rollWildHeldItem(species, rng)
    end
    return mon
  end
  Pokemon.rollCrystal251WildHeldItem = rollWildHeldItem
end

local function installWildBattleBridge()
  local BattleState = require("src.battle.BattleState")
  local CrystalStatus = require("mods.CRYSTAL_251.battle.crystal_status")
  if BattleState._crystal251WildItemBridge then return end
  BattleState._crystal251WildItemBridge = true

  local function activate(battle)
    CrystalStatus.beginBattle(battle)
    CrystalItems.beginBattle(battle)
    return battle
  end

  local originalNewWild = BattleState.newWild
  BattleState.newWild = function(game, species, level, opts)
    local battle = originalNewWild(game, species, level, opts)
    if battle and battle.enemy and battle.enemy.mon then
      battle.enemy.mon.heldItem = rollWildHeldItem(species, battle.rng)
    end
    return activate(battle)
  end

  local originalNewTrainer = BattleState.newTrainer
  BattleState.newTrainer = function(game, oppClass, partyIndex)
    return activate(originalNewTrainer(game, oppClass, partyIndex))
  end
end

local function installSecondarySubstituteBridge()
  local EffectRegistry = require("src.battle.EffectRegistry")
  if EffectRegistry._crystal251SubstituteBridge then return end
  EffectRegistry._crystal251SubstituteBridge = true

  local originalRunDamaging = EffectRegistry.runDamaging
  EffectRegistry.runDamaging = function(battle, ctx, record)
    local move = ctx and ctx.move
    local startedWithSub = ctx and ctx.target and ctx.target.substituteHP ~= nil
    local crystalMove = move and (move.index or 0) >= 166
    local activeRecord = record

    if startedWithSub and crystalMove and record and record.run
       and record.kind ~= "primary" then
      activeRecord = {}
      for key, value in pairs(record) do activeRecord[key] = value end
      local originalRun = record.run
      activeRecord.run = function(runCtx)
        if move.effect == "CRYSTAL_EFFECT_45"
           and runCtx.target.substituteHP == nil then
          return originalRun(runCtx)
        end
        return {}
      end
    end

    battle._crystalMoveDamageDepth = (battle._crystalMoveDamageDepth or 0) + 1
    local ok, a, b, c = pcall(originalRunDamaging, battle, ctx, activeRecord)
    if ok and battle.crystal251Active then
      CrystalItems.afterDamagingMove(ctx)
    end
    battle._crystalMoveDamageDepth = math.max(0,
      (battle._crystalMoveDamageDepth or 1) - 1)
    if not ok then error(a, 0) end
    return a, b, c
  end
end

local function installRageBridge()
  local BattleState = require("src.battle.BattleState")
  if BattleState._crystal251RageBridge then return end
  BattleState._crystal251RageBridge = true

  local originalApplyDamage = BattleState.applyDamage
  BattleState.applyDamage = function(self, target, damage)
    if self.crystal251Active and (self._crystalMoveDamageDepth or 0) > 0 then
      damage = CrystalItems.focusBandDamage(self, target, damage)
    end
    if not (target and target.crystalRageMove) then
      return originalApplyDamage(self, target, damage)
    end

    -- The base engine represents Generation I Rage as Attack-stage boosts.
    -- Hide its lock marker for every source of HP loss. Only move-command
    -- damage then increments Crystal's dedicated byte counter; poison,
    -- weather and other residuals neither build Rage nor raise Attack.
    local lock = target.rageMove
    target.rageMove = nil
    local ok, dealt = pcall(originalApplyDamage, self, target, damage)
    target.rageMove = lock
    if not ok then error(dealt, 0) end

    if dealt > 0 and (self._crystalMoveDamageDepth or 0) > 0 then
      target.crystalRageCounter = math.min(255,
        (target.crystalRageCounter or 0) + 1)
      self:sayNext((target.isPlayer and target.name
        or ("Enemy " .. tostring(target.name))) .. "'s RAGE is building!")
    end
    return dealt
  end
end


local function installStatusBridge()
  local Status = require("src.battle.Status")
  local StatusRegistry = require("src.battle.StatusRegistry")
  local BattleState = require("src.battle.BattleState")
  local CrystalStatus = require("mods.CRYSTAL_251.battle.crystal_status")
  if Status._crystal251StatusBridge then return end
  Status._crystal251StatusBridge = true

  local originalBeforeMove = Status.beforeMove
  Status.beforeMove = function(battler, rng, battle)
    if battle and battle.crystal251Active then
      return CrystalStatus.beforeMove(
        battler, rng, battle, battle._crystal251CurrentAction)
    end
    return originalBeforeMove(battler, rng, battle)
  end

  local originalResidual = Status.residual
  Status.residual = function(battler, opponent, battle)
    if battle and battle.crystal251Active then
      return CrystalStatus.residual(battler, opponent, battle)
    end
    return originalResidual(battler, opponent, battle)
  end

  local originalInflict = StatusRegistry.inflict
  StatusRegistry.inflict = function(battle, target, status, opts)
    if battle and battle.crystal251Active then
      return CrystalStatus.inflict(battle, target, status, opts)
    end
    return originalInflict(battle, target, status, opts)
  end

  -- Status.beforeMove does not receive the selected action in the base API.
  -- Expose it only for the duration of this check so Crystal Disable can
  -- reject the disabled move without changing the engine signature.
  local originalStatusInterrupt = BattleState.statusInterrupt
  BattleState.statusInterrupt = function(self, user, target, action)
    if not self.crystal251Active then
      return originalStatusInterrupt(self, user, target, action)
    end
    local previous = self._crystal251CurrentAction
    self._crystal251CurrentAction = action
    local ok, interrupted = pcall(
      originalStatusInterrupt, self, user, target, action)
    self._crystal251CurrentAction = previous
    if not ok then error(interrupted, 0) end
    return interrupted
  end
end

local function installConsecutiveInterruptBridge()
  local BattleState = require("src.battle.BattleState")
  if BattleState._crystal251ConsecutiveInterruptBridge then return end
  BattleState._crystal251ConsecutiveInterruptBridge = true

  local originalStatusInterrupt = BattleState.statusInterrupt
  BattleState.statusInterrupt = function(self, user, target, action)
    local interrupted = originalStatusInterrupt(self, user, target, action)
    if interrupted and user then
      -- Crystal's CantMove clears Rollout, rampage and Fury Cutter for every
      -- interruption, not only the full-paralysis/self-hit cases inherited
      -- from the Generation I engine. Rage deliberately remains locked.
      user.furyCutterCount = nil
      user.rolloutCount = nil
      if user.forcedMove and user.forcedMove.id == "ROLLOUT" then
        user.forcedMove, user.forcedMoveTurns = nil, nil
      end
      user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
    end
    return interrupted
  end
end

local function installPursuitBridge()
  require("mods.CRYSTAL_251.battle.crystal_switching").installRuntime()
end

local function installActionsBridge()
  require("mods.CRYSTAL_251.battle.crystal_actions").installRuntime()
end

local function installSchedulerBridge()
  require("mods.CRYSTAL_251.battle.crystal_scheduler").installRuntime()
end

local function installAIBridge()
  require("mods.CRYSTAL_251.battle.crystal_ai").installRuntime()
end

local function installModesBridge()
  require("mods.CRYSTAL_251.battle.crystal_modes").installRuntime()
end

local function installProgressionBridge()
  require("mods.CRYSTAL_251.battle.crystal_progression").installRuntime()
end

local function installSummaryBridge()
  require("mods.CRYSTAL_251.battle.crystal_summary").installRuntime()
end

local function installGenderBridge()
  require("mods.CRYSTAL_251.battle.crystal_gender").installRuntime()
end

local installers = {
  installPokemonBridge,
  installWildBattleBridge,
  installSecondarySubstituteBridge,
  installRageBridge,
  installStatusBridge,
  installConsecutiveInterruptBridge,
  installPursuitBridge,
  installActionsBridge,
  installSchedulerBridge,
  installAIBridge,
  installModesBridge,
  installProgressionBridge,
  installSummaryBridge,
  installGenderBridge,
}

function Bridge.install()
  if Bridge._installed then return false end
  Bridge._installed = true
  local ok, err = pcall(function()
    for index = 1, #installers do installers[index]() end
  end)
  if not ok then
    Bridge._installed = false
    error(err, 0)
  end
  return true
end

return Bridge
