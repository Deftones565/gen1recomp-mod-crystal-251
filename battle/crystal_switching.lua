local Runtime = require("src.mods.Runtime")

local Switching = {}

local PASS_FIELDS = {
  "substituteHP", "confusedTurns", "focusEnergy", "leechSeeded",
  "cursed", "perishTurns", "foresight", "defenseCurl", "mist",
  "cantEscape", "cantEscapeFrom", "protect", "endure",
  "protectChain", "protectLastTurn", "lockedTarget", "lockOnTurns",
  "toxicCounter", "rageMove", "crystalRageMove", "crystalRageCounter",
  "thrashTurns", "thrashMove", "thrashAnnounced", "bideTurns",
  "bideDamage", "mustRecharge", "charging", "chargeReady",
  "invulnerable", "invulnerableMove",
}

local RESET_FIELDS = {
  "disabledTurns", "disabledSlot", "disabledMove", "disableTurns",
  "encoreTurns", "encoreMove", "encoreSetTurn", "infatuatedWith",
  "transformed", "lastMove", "trappingTurns", "trapMove", "trapDamage",
  "boundTurns", "crystalTrapTurns", "crystalTrapSource", "crystalTrapMove",
}

local BLOCKED_BATTLE_TYPES = {
  forceshiny=true, force_shiny=true, trap=true, celebi=true, suicune=true,
  BATTLETYPE_FORCESHINY=true, BATTLETYPE_TRAP=true,
  BATTLETYPE_CELEBI=true, BATTLETYPE_SUICUNE=true,
}

local function displayName(battler)
  if not battler then return "Pokemon" end
  return battler.isPlayer and tostring(battler.name)
    or ("Enemy " .. tostring(battler.name))
end

local function hasType(battler, wanted)
  for _, typeId in ipairs((battler and battler.curTypes) or {}) do
    if typeId == wanted then return true end
  end
  return false
end

local function partyFor(battle, battler)
  if battler.isPlayer then
    local save = battle.game and battle.game.save
    return save and save.party or {}
  end
  if battle.kind == "wild" then return {} end
  return battle.enemyParty or {}
end

local function currentIndex(battle, battler, party)
  if not battler.isPlayer and battle.enemyIndex then return battle.enemyIndex end
  for index, mon in ipairs(party or {}) do
    if mon == battler.mon then return index end
  end
end

function Switching.healthyIndexes(battle, battler)
  local party = partyFor(battle, battler)
  local active = currentIndex(battle, battler, party)
  local indexes = {}
  for index, mon in ipairs(party) do
    if index ~= active and (mon.hp or 0) > 0 then indexes[#indexes + 1] = index end
  end
  return indexes, party, active
end

function Switching.pickForcedIndex(battle, battler, rng)
  local indexes, party, active = Switching.healthyIndexes(battle, battler)
  if #indexes == 0 then return nil end
  local valid = {}
  for _, index in ipairs(indexes) do valid[index] = true end
  rng = rng or battle.rng
  for _ = 1, 1024 do
    local raw = rng(0, 255)
    local index = (raw % 8) + 1
    if index ~= active and party[index] and valid[index] then return index end
  end
  return indexes[1]
end

function Switching.wildForceSucceeds(userLevel, targetLevel, rng)
  userLevel = math.max(1, math.floor(userLevel or 1))
  targetLevel = math.max(1, math.floor(targetLevel or 1))
  if userLevel >= targetLevel then return true end
  local limit = userLevel + targetLevel
  local roll
  repeat roll = rng(0, 255) until roll <= limit
  return roll >= math.floor(targetLevel / 4)
end

local function makeBattler(battle, mon, isPlayer)
  local BattleState = require("src.battle.BattleState")
  local save = isPlayer and battle.game and battle.game.save or nil
  return BattleState.makeBattler(battle.data, mon, isPlayer, save)
end

function Switching.transferBatonState(previous, incoming)
  local wasPartiallyTrapped = (tonumber(previous.crystalTrapTurns) or 0) > 0
  incoming.stages = {}
  for stat, value in pairs(previous.stages or {}) do incoming.stages[stat] = value end
  for _, field in ipairs(PASS_FIELDS) do incoming[field] = previous[field] end
  for _, field in ipairs(RESET_FIELDS) do incoming[field] = nil end
  if wasPartiallyTrapped then
    incoming.cantEscape = nil
    incoming.cantEscapeFrom = nil
  end
  incoming.nightmare = incoming.mon.status == "SLP" and previous.nightmare or nil
  return incoming
end

function Switching.replaceActive(battle, previous, mon, index, opts)
  opts = opts or {}
  local incoming = makeBattler(battle, mon, previous.isPlayer)
  if opts.batonPass then Switching.transferBatonState(previous, incoming) end
  if previous.isPlayer then
    battle.player = incoming
  else
    battle.enemy = incoming
    battle.enemyIndex = index
    if battle.aiUsesFor then battle.aiUses = battle:aiUsesFor() end
  end
  battle:syncSides()
  Runtime.emit("battle.battler_switched", {
    battle=battle,
    side=battle:sideOf(incoming),
    battler=incoming,
    previous=previous,
    batonPass=opts.batonPass or false,
    forced=opts.forced or false,
    faintReplacement=opts.faintReplacement or false,
  })
  return incoming
end

function Switching.spikes(ctx)
  local field = ctx.user.isPlayer and "enemySpikes" or "playerSpikes"
  if ctx.battle[field] then return { "But, it failed!" } end
  ctx.battle[field] = true
  return { "SPIKES scattered all around!" }
end

function Switching.applySpikes(battle, battler)
  if not (battle and battler and battler.mon) then return 0 end
  local active = battler.isPlayer and battle.playerSpikes or battle.enemySpikes
  if not active or battler.mon.hp <= 0 or hasType(battler, "FLYING") then return 0 end
  local maxHP = battler.mon.stats and battler.mon.stats.hp or battler.mon.hp
  local damage = math.max(1, math.floor(maxHP / 8))
  damage = math.min(damage, battler.mon.hp)
  battler.mon.hp = battler.mon.hp - damage
  if battle.drainNext then battle:drainNext(battler, battler.mon.hp) end
  if battle.sayNext then battle:sayNext("SPIKES hurt " .. displayName(battler) .. "!") end
  return damage
end

local function failForce(ctx)
  ctx.battle:cancelMoveAnim()
  return { "It didn't affect " .. displayName(ctx.target) .. "!" }
end

local function targetActedFirst(battle, target)
  local key = target.isPlayer and "player" or "enemy"
  return battle.crystalActedSides
    and battle.crystalActedSides[key] == (battle.turnCount or 0)
end

function Switching.forceSwitch(ctx)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  if BLOCKED_BATTLE_TYPES[battle.battleType] then return failForce(ctx) end
  if battle.kind == "wild" then
    if not Switching.wildForceSucceeds(user.mon.level, target.mon.level, ctx.rng) then
      return failForce(ctx)
    end
    battle.result = "run"
    battle.afterQueue = "finish"
    if ctx.move.id == "WHIRLWIND" then
      return { displayName(target) .. " was blown away!" }
    end
    return { displayName(target) .. " ran away scared!" }
  end
  if not targetActedFirst(battle, target) then return failForce(ctx) end
  local index = Switching.pickForcedIndex(battle, target, ctx.rng)
  if not index then return failForce(ctx) end
  local party = partyFor(battle, target)
  local previous = target
  local incoming = Switching.replaceActive(battle, previous, party[index], index, {
    forced=true,
  })
  return { displayName(incoming) .. " was dragged out!" }
end

function Switching.batonPass(ctx)
  local indexes, party = Switching.healthyIndexes(ctx.battle, ctx.user)
  if #indexes == 0 then
    ctx.battle:cancelMoveAnim()
    ctx.say("But, it failed!")
    return false
  end
  local index
  if ctx.battle.batonPassChoice then
    local picked = ctx.battle.batonPassChoice(ctx.user, party)
    for _, candidate in ipairs(indexes) do
      if candidate == picked then index = picked break end
    end
  end
  index = index or indexes[1]
  local previous = ctx.user
  local incoming = Switching.replaceActive(ctx.battle, previous, party[index], index, {
    batonPass=true,
  })
  ctx.say(displayName(incoming) .. " was passed the battle!")
  return true
end

function Switching.patchMoves(mod, crystalMoves)
  local count = 0
  for _, id in ipairs({ "WHIRLWIND", "ROAR" }) do
    local row = crystalMoves and crystalMoves[id]
    if row then
      row.effect = "CRYSTAL_EFFECT_1C"
      row.priority = -1
      if mod.content.moves:get(id) then
        mod.content.moves:patch(id, { effect="CRYSTAL_EFFECT_1C", priority=-1 })
      end
      count = count + 1
    end
  end
  return count
end

local function isMove(action, id)
  return action and action.id == id
end

function Switching.installRuntime()
  local BattleState = require("src.battle.BattleState")
  if BattleState._crystal251SwitchingBridge then return end
  BattleState._crystal251SwitchingBridge = true

  local originalEnemyAction = BattleState.enemyAction
  BattleState.enemyAction = function(self)
    local action = originalEnemyAction(self)
    if self.crystal251Active and action and action.special == "aiSwitch"
       and self.enemy and self.enemy.cantEscape then
      local TrainerAI = require("src.battle.TrainerAI")
      return TrainerAI.chooseMove(self.enemy, self.rng, self)
    end
    return action
  end

  local originalExecuteAction = BattleState.executeAction
  BattleState.executeAction = function(self, user, target, action)
    if self.crystal251Active and user then
      self.crystalActedSides = self.crystalActedSides or {}
      self.crystalActedSides[user.isPlayer and "player" or "enemy"] = self.turnCount or 0
    end
    return originalExecuteAction(self, user, target, action)
  end

  local originalResolveSwitch = BattleState.resolveSwitch
  BattleState.resolveSwitch = function(self, newMon)
    local player = self.player
    local partialTrap = self.crystal251Active and player
      and (tonumber(player.crystalTrapTurns) or 0) > 0
      and player.crystalTrapSource == self.enemy
    local trapped = self.crystal251Active and player
      and (player.cantEscape or partialTrap)
    if trapped then
      self.phase = "messages"
      self.afterQueue = "menu"
      self.nextInsert = 0
      self:say(self:romText("_MonCantBeRecalledText",
        "%s\ncan't be recalled!", tostring(player.name)))
      return false
    end
    if self.crystal251Active and player and player.mon and player.mon.hp > 0
        and type(self.enemyAction) == "function" then
      local enemyAction = self:enemyAction()
      if isMove(enemyAction, "PURSUIT") then
        self.phase = "messages"
        self.afterQueue = "menu"
        self.crystalSwitchingTarget = player
        self:executeAction(self.enemy, player, enemyAction)
        self.crystalSwitchingTarget = nil
        if player.mon.hp <= 0 then return false end
        -- The enemy has already spent this turn intercepting the recall.
        -- Suppress only originalResolveSwitch's queued free action; restore
        -- the caller's selector as soon as that one lookup is consumed.
        local choose = self.enemyAction
        self.enemyAction = function(battle)
          battle.enemyAction = choose
          return nil
        end
      end
    end
    return originalResolveSwitch(self, newMon)
  end

  local originalResolveTurn = BattleState.resolveTurn
  local function cachedResolve(self, playerAction, enemyAction)
    local own = rawget(self, "enemyAction")
    self.enemyAction = function() return enemyAction end
    local ok, result = pcall(originalResolveTurn, self, playerAction)
    self.enemyAction = own
    if not ok then error(result, 0) end
    return result
  end

  local function customTurn(self, playerAction, enemyAction, first, second)
    self.turnCount = (self.turnCount or 0) + 1
    Runtime.emit("battle.turn_started", {
      battle=self,
      turn=self.turnCount,
      playerAction=playerAction,
      enemyAction=enemyAction,
    })
    self.phase = "messages"
    self.afterQueue = "menu"
    self:act(first)
    self:act(second)
    self:act(function() self:endOfTurn() end)
  end

  BattleState.resolveTurn = function(self, playerAction)
    local enemyAction = self:enemyAction()
    if not self.crystal251Active then
      return cachedResolve(self, playerAction, enemyAction)
    end
    if enemyAction and enemyAction.special == "aiSwitch" then
      if isMove(playerAction, "PURSUIT") then
        local outgoing = self.enemy
        return customTurn(self, playerAction, enemyAction,
          function()
            if outgoing.mon.hp > 0 then
              self.crystalSwitchingTarget = outgoing
              self:executeAction(self.player, outgoing, playerAction)
              self.crystalSwitchingTarget = nil
            end
          end,
          function()
            if outgoing.mon.hp > 0 then
              self:executeAction(outgoing, self.player, enemyAction)
            end
          end)
      end
      return customTurn(self, playerAction, enemyAction,
        function()
          self:executeAction(self.enemy, self.player, enemyAction)
        end,
        function()
          if self.player.mon.hp > 0 and self.enemy.mon.hp > 0 then
            self:executeAction(self.player, self.enemy, playerAction)
          end
        end)
    end
    if isMove(playerAction, "BATON_PASS") or isMove(enemyAction, "BATON_PASS") then
      local TurnOrder = require("src.battle.TurnOrder")
      local pMove = playerAction and playerAction.id and self.data.moves[playerAction.id] or nil
      local eMove = enemyAction and enemyAction.id and self.data.moves[enemyAction.id] or nil
      local pFirst
      if Runtime.wantsHook("battle.turn_order") then
        pFirst = Runtime.call("battle.turn_order", function(a, aMove, b, bMove, c)
          return TurnOrder.firstMover(a, aMove, b, bMove, c.rng, c.invertTie)
        end, self.player, pMove, self.enemy, eMove, { rng=self.rng })
      else
        pFirst = TurnOrder.firstMover(self.player, pMove, self.enemy, eMove, self.rng)
      end
      if pFirst then
        return customTurn(self, playerAction, enemyAction,
          function()
            if self.player.mon.hp > 0 then
              self:executeAction(self.player, self.enemy, playerAction)
            end
          end,
          function()
            if self.enemy.mon.hp > 0 then
              self:executeAction(self.enemy, self.player, enemyAction)
            end
          end)
      end
      return customTurn(self, playerAction, enemyAction,
        function()
          if self.enemy.mon.hp > 0 then
            self:executeAction(self.enemy, self.player, enemyAction)
          end
        end,
        function()
          if self.player.mon.hp > 0 then
            self:executeAction(self.player, self.enemy, playerAction)
          end
        end)
    end
    return cachedResolve(self, playerAction, enemyAction)
  end
end

return Switching
