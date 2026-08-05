-- Pokemon Crystal multi-hit and consecutive-move command families.
--
-- These effects need more than the engine's Generation I multi-hit record:
-- Crystal recalculates critical hits and damage for every strike, lets later
-- strikes continue after Substitute breaks, applies Rollout/Fury Cutter/Rage
-- multipliers after the ordinary damage formula, and uses a 2-3 turn rampage.

local MultiTurn = {}

local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local Runtime = require("src.mods.Runtime")
local Bridge = require("mods.CRYSTAL_251.runtime_bridge")

local configured = {
  moves = {},
  scripts = {},
  interpreter = nil,
}

local MOVE_IDS = {
  THRASH=true, PETAL_DANCE=true, OUTRAGE=true,
  DOUBLESLAP=true, COMET_PUNCH=true, FURY_ATTACK=true, PIN_MISSILE=true,
  SPIKE_CANNON=true, BARRAGE=true, FURY_SWIPES=true, BONE_RUSH=true,
  DOUBLE_KICK=true, BONEMERANG=true, TWINEEDLE=true, TRIPLE_KICK=true,
  RAGE=true, ROLLOUT=true, FURY_CUTTER=true,
}
MultiTurn.MOVE_IDS = MOVE_IDS

local EFFECT_OVERRIDES = {
  THRASH="CRYSTAL_EFFECT_1B", PETAL_DANCE="CRYSTAL_EFFECT_1B",
  DOUBLESLAP="CRYSTAL_EFFECT_1D", COMET_PUNCH="CRYSTAL_EFFECT_1D",
  FURY_ATTACK="CRYSTAL_EFFECT_1D", PIN_MISSILE="CRYSTAL_EFFECT_1D",
  SPIKE_CANNON="CRYSTAL_EFFECT_1D", BARRAGE="CRYSTAL_EFFECT_1D",
  FURY_SWIPES="CRYSTAL_EFFECT_1D",
  DOUBLE_KICK="CRYSTAL_EFFECT_2C", BONEMERANG="CRYSTAL_EFFECT_2C",
  TWINEEDLE="CRYSTAL_EFFECT_4D", RAGE="CRYSTAL_EFFECT_51",
}
MultiTurn.EFFECT_OVERRIDES = EFFECT_OVERRIDES

local function displayName(battler)
  if not battler then return "the target" end
  return battler.isPlayer and battler.name or ("Enemy " .. tostring(battler.name))
end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

-- BattleCommand_EndLoop: 3/8 two hits, 3/8 three, 1/8 four, 1/8 five.
-- Crystal reaches those weights with one conditional second RNG call.
function MultiTurn.twoToFiveCount(rng)
  rng = rng or function(_, high) return high end
  local first = clamp(rng(0, 3), 0, 3)
  if first < 2 then return first + 2 end
  return clamp(rng(0, 3), 0, 3) + 2
end

function MultiTurn.rolloutMultiplier(count, curled)
  count = clamp(count or 1, 1, 5)
  local mult = 2 ^ (count - 1)
  if curled then mult = mult * 2 end
  return mult
end

function MultiTurn.furyCutterMultiplier(count)
  count = clamp(count or 1, 1, 5)
  return 2 ^ (count - 1)
end

function MultiTurn.rageMultiplier(counter)
  return clamp((counter or 0) + 1, 1, 256)
end

function MultiTurn.rampageRemaining(rng)
  rng = rng or function(_, high) return high end
  -- The initial use is turn one; Crystal stores one or two future forced uses.
  return clamp(rng(1, 2), 1, 2)
end

local function emitDamage(ctx, dealt, info)
  if Runtime.wants("battle.damage_dealt") then
    Runtime.emit("battle.damage_dealt", {
      battle=ctx.battle, user=ctx.user, target=ctx.target, move=ctx.move,
      damage=dealt, crit=info and info.crit or false,
      typeMult=info and info.typeMult or 10,
    })
  end
end

local function cancelAndSay(ctx, text)
  if ctx.battle and ctx.battle.cancelMoveAnim then ctx.battle:cancelMoveAnim() end
  if text and ctx.say then ctx.say(text) end
end

local function miss(ctx)
  cancelAndSay(ctx, displayName(ctx.user) .. "'s attack missed!")
end

local function immune(ctx)
  cancelAndSay(ctx, "It doesn't affect " .. displayName(ctx.target) .. "!")
end

local function accuracy(ctx)
  if ctx.target.protect or ctx.target.invulnerable then return false end
  return ctx.battle:accuracyRoll(ctx.move, ctx.user, ctx.target)
end

local function formula(ctx, commands, opts)
  opts = opts or {}
  opts.crystalSequence = true
  opts.script = {
    id=ctx.move.id,
    index=ctx.move.index or 0,
    effect=ctx.move.effect,
    effectName="ConsecutiveDamage",
    mode="sequence",
    commands=commands,
  }
  return ctx.battle:computeDamage(ctx.user, ctx.target, ctx.move, opts)
end

local function queueLaterHit(ctx)
  local battle = ctx.battle
  battle.nextInsert = (battle.nextInsert or 0) + 1
  local row = { anim=ctx.move.id, attackerIsPlayer=ctx.user.isPlayer }
  table.insert(battle.queue, battle.nextInsert, row)
  return row
end

local function applyHit(ctx, damage, info, hit)
  info = info or { crit=false, typeMult=10 }
  if info.typeMult == 0 then return false, "immune" end
  if info.missed then return false, "miss" end
  damage = math.max(0, math.min(65535, math.floor(damage or 0)))
  if ctx.target.endure and damage >= ctx.target.mon.hp then
    damage = math.max(0, ctx.target.mon.hp - 1)
  end
  ctx.battle.lastDamage = damage
  if hit and hit > 1 then queueLaterHit(ctx) end
  local dealt = Bridge.applyMoveDamage(ctx.battle, ctx.target, damage)
  emitDamage(ctx, dealt, info)
  if info.crit then ctx.say("Critical hit!") end
  if info.typeMult > 10 then ctx.say("It's super effective!")
  elseif info.typeMult < 10 and info.typeMult > 0 then
    ctx.say("It's not very effective...")
  end
  return true, dealt
end

local function finishPostStab(ctx, damage, info, multiplier)
  multiplier = multiplier or 1
  damage = math.min(65535, math.max(0, math.floor(damage or 0)) * multiplier)
  if info and info.crystal251 then
    damage = CrystalDamage.applyVariation(damage, ctx.rng)
  end
  return damage, info
end

local function finishTripleKick(ctx, damage, info, hit)
  if not (info and info.crystal251) then
    -- Preserve the public battle.computeDamage seam used by integration tests
    -- and other mods; a non-Crystal result is already fully modified.
    return math.min(65535, math.max(0, math.floor(damage or 0)) * hit), info
  end
  damage = math.min(65535, math.max(0, math.floor(damage or 0)) * hit)
  local typeMult, immuneFlag
  damage, typeMult, immuneFlag = CrystalDamage.applyStabType({
    battle=ctx.battle, user=ctx.user, target=ctx.target, move=ctx.move,
  }, damage)
  info.typeMult = typeMult
  if immuneFlag then return 0, info end
  return CrystalDamage.applyVariation(damage, ctx.rng), info
end

local function reportHits(ctx, hits)
  if hits <= 1 then return end
  if ctx.user.isPlayer then
    ctx.say("Hit the enemy\n" .. hits .. " times!")
  else
    ctx.say("Hit " .. hits .. " times!")
  end
end

local function resolveOrdinaryMulti(state)
  local ctx = state.ctx
  local family = state.script.effectName
  local hits = family == "MultiHit" and MultiTurn.twoToFiveCount(ctx.rng) or 2
  if not accuracy(ctx) then miss(ctx); state.stop=true; state.failed=true; return end

  local poison = family == "PoisonMultiHit"
    and not ctx.target.substituteHP
    and (ctx.move.effectChance or 0) > 0
    and ctx.rng(0, 255) < (ctx.move.effectChance or 0)

  local landed = 0
  for hit = 1, hits do
    if ctx.target.mon.hp <= 0 then break end
    local damage, info = formula(ctx, {
      "critical", "damagestats", "damagecalc", "stab",
      "damagevariation", "endmove",
    })
    if info and info.typeMult == 0 then
      if hit == 1 then immune(ctx) end
      break
    end
    local ok = applyHit(ctx, damage, info, hit)
    if not ok then
      if hit == 1 then miss(ctx) end
      break
    end
    landed = hit
  end

  reportHits(ctx, landed)
  if poison and landed > 0 and ctx.target.mon.hp > 0
     and not ctx.target.substituteHP and ctx.inflict then
    for _, message in ipairs(ctx.inflict(ctx.target, "PSN", {
      secondary=true, moveType=ctx.move.type, source=ctx.move.id,
    }) or {}) do ctx.say(message) end
  end
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits, state.stop = landed, true
end

local function resolveTripleKick(state)
  local ctx = state.ctx
  local landed = 0
  for hit = 1, 3 do
    if ctx.target.mon.hp <= 0 then break end
    if not accuracy(ctx) then
      if hit == 1 then miss(ctx) end
      break
    end
    local damage, info = formula(ctx, {
      "critical", "damagestats", "damagecalc", "endmove",
    })
    damage, info = finishTripleKick(ctx, damage, info, hit)
    if info and info.typeMult == 0 then
      if hit == 1 then immune(ctx) end
      break
    end
    local ok = applyHit(ctx, damage, info, hit)
    if not ok then break end
    landed = hit
  end
  reportHits(ctx, landed)
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits, state.stop = landed, true
end

local function resolveRollout(state)
  local ctx, user = state.ctx, state.ctx.user
  local sleepTalk = ctx.isCalled and user.mon.status == "SLP"

  -- Crystal calculates critical/base damage and STAB before checkhit for
  -- Rollout. Keep that RNG order even though a miss discards the result.
  local damage, info = formula(ctx, {
    "critical", "damagestats", "damagecalc", "stab", "endmove",
  })
  if not accuracy(ctx) then
    user.rolloutCount, user.forcedMove, user.forcedMoveTurns = nil, nil, nil
    miss(ctx); state.failed=true; state.stop=true; return
  end
  if info and info.typeMult == 0 then
    user.rolloutCount, user.forcedMove, user.forcedMoveTurns = nil, nil, nil
    immune(ctx); state.failed=true; state.stop=true; return
  end

  local count = sleepTalk and 1 or math.min(5, (user.rolloutCount or 0) + 1)
  damage, info = finishPostStab(ctx, damage, info,
    MultiTurn.rolloutMultiplier(count, user.defenseCurl))

  if not sleepTalk then
    if count < 5 then
      user.rolloutCount = count
      user.forcedMove, user.forcedMoveTurns = ctx.moveInst, 5 - count
    else
      user.rolloutCount, user.forcedMove, user.forcedMoveTurns = nil, nil, nil
    end
  end
  applyHit(ctx, damage, info, 1)
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits, state.stop = 1, true
end

local function resolveFuryCutter(state)
  local ctx, user = state.ctx, state.ctx.user

  -- As in Crystal's script, critical/base damage and STAB precede checkhit.
  local damage, info = formula(ctx, {
    "critical", "damagestats", "damagecalc", "stab", "endmove",
  })
  if not accuracy(ctx) then
    user.furyCutterCount = nil
    miss(ctx); state.failed=true; state.stop=true; return
  end
  if info and info.typeMult == 0 then
    user.furyCutterCount = nil
    immune(ctx); state.failed=true; state.stop=true; return
  end
  local count = math.min(5, (user.furyCutterCount or 0) + 1)
  damage, info = finishPostStab(ctx, damage, info,
    MultiTurn.furyCutterMultiplier(count))
  user.furyCutterCount = count
  applyHit(ctx, damage, info, 1)
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits, state.stop = 1, true
end

local function finishRampage(ctx, user)
  if user.safeguardTurns and user.safeguardTurns > 0 then return end
  if user.confusedTurns then return end
  user.confusedTurns = ctx.rng(2, 3)
  ctx.say(displayName(user) .. " became confused!")
end

local function resolveRampage(state)
  local ctx, user = state.ctx, state.ctx.user
  local sleepingCall = ctx.isCalled and user.mon.status == "SLP"
  local confuseAfter = false
  if not sleepingCall then
    if user.thrashMove == ctx.moveInst and (user.thrashTurns or 0) > 0 then
      user.thrashTurns = user.thrashTurns - 1
      if user.thrashTurns <= 0 then
        user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
        confuseAfter = true
      end
    else
      user.thrashTurns = MultiTurn.rampageRemaining(ctx.rng)
      user.thrashMove, user.thrashAnnounced = ctx.moveInst, true
    end
  end

  local landed = 0
  if not accuracy(ctx) then
    miss(ctx)
  else
    local damage, info = formula(ctx, {
      "critical", "damagestats", "damagecalc", "stab",
      "damagevariation", "endmove",
    })
    if info and info.typeMult == 0 then immune(ctx)
    else
      local ok = applyHit(ctx, damage, info, 1)
      if ok then landed = 1 end
    end
  end
  if confuseAfter then finishRampage(ctx, user) end
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits, state.stop = landed, true
end

local function resolveRage(state)
  local ctx, user = state.ctx, state.ctx.user

  -- Rage also calculates through STAB before checkhit. A failed first use
  -- never reaches BattleCommand_Rage, so it must not create the lock.
  local damage, info = formula(ctx, {
    "critical", "damagestats", "damagecalc", "stab", "endmove",
  })
  if not accuracy(ctx) then miss(ctx); state.failed=true; state.stop=true; return end
  if info and info.typeMult == 0 then
    immune(ctx); state.failed=true; state.stop=true; return
  end

  user.rageMove = ctx.moveInst
  user.crystalRageMove = ctx.moveInst
  user.crystalRageCounter = user.crystalRageCounter or 0
  damage, info = finishPostStab(ctx, damage, info,
    MultiTurn.rageMultiplier(user.crystalRageCounter))
  applyHit(ctx, damage, info, 1)
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits, state.stop = 1, true
end

local function handlersFor(effectName)
  if effectName == "MultiHit" or effectName == "PoisonMultiHit" then
    return { startloop=resolveOrdinaryMulti }
  end
  if effectName == "TripleKick" then return { startloop=resolveTripleKick } end
  if effectName == "Rollout" then return { checkrollout=resolveRollout } end
  if effectName == "FuryCutter" then return { furycutter=resolveFuryCutter } end
  if effectName == "Rampage" then return { checkrampage=resolveRampage } end
  if effectName == "Rage" then return { ragedamage=resolveRage } end
  error("unsupported Crystal consecutive family " .. tostring(effectName))
end

function MultiTurn.perform(ctx)
  local script = configured.scripts[ctx.move.id]
    or MoveScripts.forMove(configured.moves[ctx.move.id] or ctx.move)
  local interpreter = assert(configured.interpreter,
    "Crystal consecutive-move interpreter is not configured")
  local state = { ctx=ctx, user=ctx.user, target=ctx.target, move=ctx.move }
  interpreter:run(script, { state=state, handlers=handlersFor(script.effectName) }, "all")
  return state
end

function MultiTurn.record()
  return { perform=function(ctx) return MultiTurn.perform(ctx) end }
end

function MultiTurn.patchMoves(mod, crystalMoves)
  for id, effect in pairs(EFFECT_OVERRIDES) do
    local crystal = assert(crystalMoves[id], "missing Crystal move record for " .. id)
    crystal.effect = effect
    mod.content.moves:patch(id, {
      effect=effect,
      effectChance=crystal.effectChance,
      multiHit=nil,
    })
  end
end

function MultiTurn.configure(opts)
  opts = opts or {}
  configured.moves = opts.moves or {}
  configured.scripts = opts.scripts or {}
  configured.interpreter = opts.interpreter
end

return MultiTurn
