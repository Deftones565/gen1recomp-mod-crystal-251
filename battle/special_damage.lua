-- Command-specific Pokemon Crystal damage families.
--
-- These moves do not share the ordinary critical/stats/STAB/random pipeline.
-- They are executed through the mod-local command interpreter while the base
-- engine remains untouched when CRYSTAL_251 is absent.

local SpecialDamage = {}

local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local Runtime = require("src.mods.Runtime")
local TypeChart = require("src.battle.TypeChart")
local Bridge = require("mods.CRYSTAL_251.runtime_bridge")

local configured = {
  moves = {},
  scripts = {},
  interpreter = nil,
}

local MOVE_IDS = {
  BIDE=true,
  GUILLOTINE=true, HORN_DRILL=true, FISSURE=true,
  SUPER_FANG=true,
  SONICBOOM=true, DRAGON_RAGE=true, SEISMIC_TOSS=true, NIGHT_SHADE=true,
  PSYWAVE=true,
  COUNTER=true,
  FLAIL=true, REVERSAL=true,
  PRESENT=true,
  MIRROR_COAT=true,
  FUTURE_SIGHT=true,
  BEAT_UP=true,
}
SpecialDamage.MOVE_IDS = MOVE_IDS

local EFFECT_CODES = {
  0x1a, -- Bide
  0x26, -- OHKO
  0x28, -- Super Fang
  0x29, -- static damage (SonicBoom / Dragon Rage)
  0x57, -- level damage (Seismic Toss / Night Shade)
  0x58, -- Psywave
  0x59, -- Counter
  0x63, -- Reversal / Flail
  0x7a, -- Present
  0x90, -- Mirror Coat
  0x94, -- Future Sight
  0x9a, -- Beat Up
}
SpecialDamage.EFFECT_CODES = EFFECT_CODES

local function displayName(battler)
  if not battler then return "the target" end
  return battler.isPlayer and battler.name or ("Enemy " .. tostring(battler.name))
end

local function matchupTypes(move, target)
  local out = {}
  for _, typeId in ipairs(target and target.curTypes or {}) do
    local ignoredGhost = target.foresight and typeId == "GHOST"
      and (move.type == "NORMAL" or move.type == "FIGHTING")
    if not ignoredGhost then out[#out + 1] = typeId end
  end
  return out
end

local function typeMultiplier(move, target)
  return TypeChart.effectiveness(move.type, matchupTypes(move, target))
end

local function cancelAndSay(state, text)
  local battle = state.ctx.battle
  if battle and battle.cancelMoveAnim then battle:cancelMoveAnim() end
  if text and state.ctx.say then state.ctx.say(text) end
  state.failed = true
  state.stop = true
end

local function miss(state)
  cancelAndSay(state, displayName(state.ctx.user) .. "'s attack missed!")
end

local function immune(state)
  cancelAndSay(state, "It doesn't affect " .. displayName(state.ctx.target) .. "!")
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

local function applyDamage(state)
  if state.failed or not state.damage or state.damage <= 0 then return end
  local ctx = state.ctx
  local damage = math.min(65535, math.max(0, math.floor(state.damage)))
  if ctx.target.endure and damage >= ctx.target.mon.hp then
    damage = math.max(0, ctx.target.mon.hp - 1)
  end
  ctx.battle.lastDamage = damage
  local dealt = Bridge.applyMoveDamage(ctx.battle, ctx.target, damage)
  emitDamage(ctx, dealt, state.info)
  state.dealt = dealt
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
end

local function withMovePower(ctx, power, fn)
  local oldPower = ctx.move.power
  ctx.move.power = power
  local ok, a, b = pcall(fn)
  ctx.move.power = oldPower
  if not ok then error(a, 0) end
  return a, b
end

function SpecialDamage.reversalPower(hp, maxHP)
  hp = math.max(0, hp or 0)
  maxHP = math.max(1, maxHP or 1)
  local pixels = math.floor(48 * hp / maxHP)
  if pixels <= 1 then return 200 end
  if pixels <= 4 then return 150 end
  if pixels <= 9 then return 100 end
  if pixels <= 16 then return 80 end
  if pixels <= 32 then return 40 end
  return 20
end

function SpecialDamage.presentOutcome(roll)
  roll = math.max(0, math.min(255, roll or 0))
  -- PresentPower: 0..102 => 40, 103..179 => 80,
  -- 180..204 => 120, 205..255 => heal.
  if roll <= 102 then return 40 end
  if roll <= 179 then return 80 end
  if roll <= 204 then return 120 end
  return "heal"
end

function SpecialDamage.psywaveDamage(level, rng)
  level = math.max(1, level or 1)
  local limit = level + math.floor(level / 2)
  if limit <= 1 then return 1 end
  rng = rng or function(_, high) return high end
  for _ = 1, 1024 do
    local value = rng(0, 255)
    if value > 0 and value < limit then return value end
  end
  return math.max(1, limit - 1)
end

function SpecialDamage.fixedDamage(moveId, userLevel, targetHP, rng, movePower)
  if moveId == "SEISMIC_TOSS" or moveId == "NIGHT_SHADE" then
    return math.max(1, userLevel or 1)
  end
  if moveId == "PSYWAVE" then
    return SpecialDamage.psywaveDamage(userLevel, rng)
  end
  if moveId == "SUPER_FANG" then
    return math.max(1, math.floor(math.max(1, targetHP or 1) / 2))
  end
  return math.max(1, movePower or 1)
end

function SpecialDamage.ohkoAccuracyByte(baseAccuracy, userLevel, targetLevel)
  local base = math.floor((baseAccuracy or 0) * 255 / 100)
  return math.min(255, math.max(0,
    base + 2 * ((userLevel or 1) - (targetLevel or 1))))
end

function SpecialDamage.counterDamage(last, wantedCategory, moveId, target)
  if not last or not last.from or not last.damage or last.damage <= 0 then return nil end
  if last.category ~= wantedCategory then return nil end
  if (last.power or 0) <= 0 then return nil end
  if last.moveId == moveId then return nil end
  if target and last.from ~= target then return nil end
  return math.min(65535, last.damage * 2)
end

function SpecialDamage.beatUpDamage(level, power, attack, defense, roll, crit)
  local damage = math.floor(2 * math.max(1, level or 1) / 5) + 2
  damage = math.floor(damage * math.max(1, power or 1)
    * math.max(1, attack or 1) / math.max(1, defense or 1))
  damage = math.floor(damage / 50)
  if crit then damage = math.min(65535, damage * 2) end
  damage = math.min(997, damage) + 2
  damage = math.floor(damage * math.max(217, math.min(255, roll or 255)) / 255)
  return math.max(1, math.min(999, damage))
end

local function formula(ctx, commands, opts)
  return CrystalDamage.computeWithCommands({
    battle=ctx.battle, user=ctx.user, target=ctx.target,
    move=ctx.move, rng=ctx.rng,
  }, commands, opts or {})
end

local function checkHit(state)
  if state.failed then return end
  local ctx = state.ctx
  if ctx.target.protect or ctx.target.invulnerable then
    miss(state)
    return
  end
  if not ctx.battle:accuracyRoll(ctx.move, ctx.user, ctx.target) then
    miss(state)
  end
end

local function checkNeutralizedImmunity(state)
  if state.failed then return end
  if typeMultiplier(state.ctx.move, state.ctx.target) == 0 then immune(state) end
end

local function handleConstantDamage(state)
  local ctx = state.ctx
  local moveId = ctx.move.id
  if moveId == "FLAIL" or moveId == "REVERSAL" then
    local power = SpecialDamage.reversalPower(ctx.user.mon.hp, ctx.user.mon.stats.hp)
    local damage, info = withMovePower(ctx, power, function()
      -- Reversal/Flail run DamageCalc and STAB but deliberately skip both the
      -- critical command and damage variation in Crystal.
      return formula(ctx, { "damagestats", "damagecalc", "stab", "endmove" }, {
        forceCrit=false,
      })
    end)
    state.damage, state.info = damage, info
    state.precomputed = true
    return
  end
  state.damage = SpecialDamage.fixedDamage(moveId,
    ctx.user.mon.level, ctx.target.mon.hp, ctx.rng, ctx.move.power)
  state.info = { crit=false, typeMult=10, crystal251=true }
  state.precomputed = true
end

local function handleOHKO(state)
  if state.failed then return end
  local ctx = state.ctx
  if typeMultiplier(ctx.move, ctx.target) == 0 then
    immune(state)
    return
  end
  local userLevel = ctx.user.mon.level or 1
  local targetLevel = ctx.target.mon.level or 1
  if userLevel < targetLevel then
    cancelAndSay(state, "It doesn't affect " .. displayName(ctx.target) .. "!")
    return
  end
  if ctx.target.protect or ctx.target.invulnerable then
    miss(state)
    return
  end
  local byte = SpecialDamage.ohkoAccuracyByte(ctx.move.accuracy,
    userLevel, targetLevel)
  local oldAccuracy = ctx.move.accuracy
  ctx.move.accuracy = byte * 100 / 255
  local ok, hit = pcall(function()
    return ctx.battle:accuracyRoll(ctx.move, ctx.user, ctx.target)
  end)
  ctx.move.accuracy = oldAccuracy
  if not ok then error(hit, 0) end
  if not hit then
    miss(state)
    return
  end
  state.damage = 65535
  state.info = { crit=false, typeMult=10, ohko=true, crystal251=true }
end

local function handleCounter(state, category)
  local ctx = state.ctx
  if typeMultiplier(ctx.move, ctx.target) == 0 then
    immune(state)
    return
  end
  local last = ctx.user.crystalLastDamageTaken
  if not last or last.turn ~= (ctx.battle.turnCount or 0) then
    cancelAndSay(state, "But, it failed!")
    return
  end
  local damage = SpecialDamage.counterDamage(last, category, ctx.move.id, ctx.target)
  if not damage then
    cancelAndSay(state, "But, it failed!")
    return
  end
  state.damage = damage
  state.info = { crit=false, typeMult=10, crystal251=true }
end

local function handlePresent(state)
  local ctx = state.ctx
  -- Present calls STAB once before choosing the damage/heal branch. The only
  -- mechanically relevant result before the roll is a type immunity.
  if typeMultiplier(ctx.move, ctx.target) == 0 then
    immune(state)
    return
  end
  local outcome = SpecialDamage.presentOutcome(ctx.rng(0, 255))
  if outcome == "heal" then
    local mon = ctx.target.mon
    if mon.hp >= mon.stats.hp then
      cancelAndSay(state, "But, it failed!")
      return
    end
    mon.hp = math.min(mon.stats.hp,
      mon.hp + math.max(1, math.floor(mon.stats.hp / 4)))
    if ctx.drain then ctx.drain() end
    ctx.say(displayName(ctx.target) .. " regained health!")
    state.healed = true
    state.stop = true
    return
  end
  local damage, info = withMovePower(ctx, outcome, function()
    return formula(ctx, {
      "critical", "damagestats", "damagecalc", "stab",
      "damagevariation", "endmove",
    }, { forceCrit=state.crit })
  end)
  state.damage, state.info = damage, info
  state.precomputed = true
end

local function partyFor(ctx, battler)
  if battler.isPlayer then
    local save = ctx.battle.game and ctx.battle.game.save
    return save and save.party or { battler.mon }
  end
  return ctx.battle.enemyParty or { battler.mon }
end

local function handleBeatUp(state)
  local ctx = state.ctx
  local eligible = {}
  for _, mon in ipairs(partyFor(ctx, ctx.user)) do
    if (mon.hp or 0) > 0 and mon.status == nil then
      eligible[#eligible + 1] = mon
    end
  end
  if #eligible == 0 then
    cancelAndSay(state, "But, it failed!")
    return
  end

  local defender = ctx.target.def or ctx.data.pokemon[ctx.target.mon.species]
  local defense = defender and defender.baseStats and defender.baseStats.defense or 1
  local landed = 0
  for _, mon in ipairs(eligible) do
    if ctx.target.mon.hp <= 0 then break end
    local attacker = ctx.data.pokemon[mon.species]
    local attack = attacker and attacker.baseStats and attacker.baseStats.attack or 1
    local crit = CrystalDamage.rollCritical(ctx.user, ctx.move, ctx.rng)
    local damage = SpecialDamage.beatUpDamage(mon.level, ctx.move.power,
      attack, defense, ctx.rng(217, 255), crit)
    if ctx.target.endure and damage >= ctx.target.mon.hp then
      damage = math.max(0, ctx.target.mon.hp - 1)
    end
    ctx.battle.lastDamage = damage
    local dealt = Bridge.applyMoveDamage(ctx.battle, ctx.target, damage)
    emitDamage(ctx, dealt, { crit=crit, typeMult=10 })
    landed = landed + 1
    if crit then ctx.say("Critical hit!") end
  end
  if landed == 0 then
    cancelAndSay(state, "But, it failed!")
    return
  end
  if landed > 1 then
    ctx.say(ctx.user.isPlayer and ("Hit the enemy\n" .. landed .. " times!")
      or ("Hit " .. landed .. " times!"))
  end
  if ctx.target.mon.hp <= 0 then ctx.battle:onFaint(ctx.target) end
  state.hits = landed
  state.stop = true
end

local function handleFutureSight(state)
  local ctx = state.ctx
  local key = ctx.target.isPlayer and "player" or "enemy"
  ctx.battle.crystalFutureSight = ctx.battle.crystalFutureSight or {}
  if ctx.battle.crystalFutureSight[key] then
    cancelAndSay(state, "But, it failed!")
    return
  end
  local damage, info = formula(ctx,
    { "damagestats", "damagecalc", "endmove" }, { forceCrit=false })
  local storedDamage = math.max(1, damage or 1)
  ctx.battle.crystalFutureSight[key] = {
    turns=4,
    baseDamage=storedDamage,
    damage=storedDamage,
    source=ctx.user,
    moveId=ctx.move.id,
    category=info and info.category or "special",
  }
  ctx.battle:cancelMoveAnim()
  ctx.say(displayName(ctx.user) .. " foresaw an attack!")
  state.scheduled = true
  state.stop = true
end

local function handleBideStart(state)
  local ctx = state.ctx
  ctx.user.bideTurns = ctx.rng(2, 3)
  ctx.user.bideDamage = 0
  ctx.user.crystalBide = true
  ctx.battle:cancelMoveAnim()
  if ctx.anim then
    ctx.anim(ctx.user.isPlayer and "XSTATITEM_ANIM" or "XSTATITEM_DUPLICATE_ANIM")
  end
  ctx.say(displayName(ctx.user) .. " is storing energy!")
  state.stop = true
end

local function commandHandlers()
  return {
    checkhit = checkHit,
    resettypematchup = checkNeutralizedImmunity,
    constantdamage = handleConstantDamage,
    ohko = handleOHKO,
    counter = function(state) handleCounter(state, "physical") end,
    mirrorcoat = function(state) handleCounter(state, "special") end,
    present = handlePresent,
    beatup = handleBeatUp,
    futuresight = handleFutureSight,
    storeenergy = handleBideStart,
    critical = function(state)
      if state.script.effectName ~= "BeatUp" then
        state.crit = CrystalDamage.rollCritical(
          state.ctx.user, state.ctx.move, state.ctx.rng)
      end
    end,
    stab = function(state)
      if state.info and state.info.typeMult == 0 then immune(state) end
    end,
    applydamage = applyDamage,
    criticaltext = function(state)
      if state.info and state.info.crit and not state.failed then
        state.ctx.say("Critical hit!")
      elseif state.info and state.info.ohko and not state.failed then
        state.ctx.say("One-hit KO!")
      end
    end,
    supereffectivetext = function(state)
      local mult = state.info and state.info.typeMult or 10
      if mult > 10 then state.ctx.say("It's super effective!")
      elseif mult < 10 and mult > 0 then state.ctx.say("It's not very effective...") end
    end,
  }
end

function SpecialDamage.perform(ctx)
  local script = configured.scripts[ctx.move.id]
    or MoveScripts.forMove(configured.moves[ctx.move.id] or ctx.move)
  local interpreter = assert(configured.interpreter,
    "Crystal special damage interpreter is not configured")
  local state = {
    ctx=ctx,
    user=ctx.user,
    target=ctx.target,
    move=ctx.move,
  }
  interpreter:run(script, {
    state=state,
    handlers=commandHandlers(),
  }, "all")
  return state
end

function SpecialDamage.tickFutureSight(battle, order)
  local pending = battle and battle.crystalFutureSight
  if not pending then return end
  -- HandleFutureSight runs the player-owned pending attack first locally and
  -- reverses that paired order for the external-clock/link guest. Records are
  -- stored by target side for switch-slot persistence, so map each source side
  -- to its opposite target slot here.
  order = order or { battle.player, battle.enemy }
  for _, sourceSide in ipairs(order) do
    local key = sourceSide and (sourceSide.isPlayer and "enemy" or "player")
    local attack = key and pending[key]
    if attack then
      attack.turns = attack.turns - 1
      -- Crystal stores 4 and triggers when the end-phase decrement reaches 1.
      if attack.turns == 1 then
        pending[key] = nil
        local target = key == "player" and battle.player or battle.enemy
        if target and target.mon.hp > 0 then
          local move = battle.data.moves[attack.moveId or "FUTURE_SIGHT"]
          -- The pending counter belongs to a side, not the original battler;
          -- after a switch Crystal uses the current active battler on that side
          -- for the due-turn hit/accuracy context.
          local source = sourceSide
            or (key == "player" and battle.enemy or battle.player)
          -- The initial turn stores damage before damagevariation. On the due
          -- turn the script resumes at damagevariation, then checkhit, Protect,
          -- animation, failure text, and applydamage.
          local hit = source and move and not target.invulnerable
            and not target.protect and battle:accuracyRoll(move, source, target)
          if not hit then
            battle:sayNext("But, it failed!")
          else
            local damage = math.max(1,
              math.floor((attack.baseDamage or attack.damage or 1)
                * battle.rng(217, 255) / 255))
            if target.endure and damage >= target.mon.hp then
              damage = math.max(0, target.mon.hp - 1)
            end
            battle:sayNext("The future attack struck " .. displayName(target) .. "!")
            battle:animNext("FUTURE_SIGHT", source.isPlayer)
            battle.lastDamage = damage
            local dealt = Bridge.applyMoveDamage(battle, target, damage)
            emitDamage({ battle=battle, user=source, target=target, move=move },
              dealt, { crit=false, typeMult=10 })
          end
        end
      end
    end
  end
  if next(pending) == nil then battle.crystalFutureSight = nil end
end

function SpecialDamage.continueBide(battle, user, target)
  user.bideTurns = user.bideTurns - 1
  if user.bideTurns > 0 then
    battle:sayNext(displayName(user) .. " is storing energy!")
    return
  end
  battle:sayNext(displayName(user) .. " unleashed energy!")
  local damage = math.min(65535, math.max(0, (user.bideDamage or 0) * 2))
  user.bideTurns, user.bideDamage, user.crystalBide = nil, nil, nil
  if damage <= 0 then
    battle:cancelMoveAnim()
    battle:sayNext("But, it failed!")
    return
  end
  local move = battle.data.moves.BIDE
  if typeMultiplier(move, target) == 0 then
    battle:cancelMoveAnim()
    battle:sayNext("It doesn't affect " .. displayName(target) .. "!")
    return
  end
  if target.protect or target.invulnerable
     or not battle:accuracyRoll(move, user, target) then
    battle:cancelMoveAnim()
    battle:sayNext(displayName(user) .. "'s attack missed!")
    return
  end
  battle:animNext("BIDE", user.isPlayer)
  if target.endure and damage >= target.mon.hp then
    damage = math.max(0, target.mon.hp - 1)
  end
  battle.lastDamage = damage
  local dealt = Bridge.applyMoveDamage(battle, target, damage)
  emitDamage({ battle=battle, user=user, target=target, move=move },
    dealt, { crit=false, typeMult=10 })
  if target.mon.hp <= 0 then battle:onFaint(target) end
end

local runtimeInstalled = false
function SpecialDamage.installRuntime()
  if runtimeInstalled then return end
  runtimeInstalled = true
  local BattleState = require("src.battle.BattleState")
  local original = BattleState.continueBide
  BattleState.continueBide = function(battle, user, target)
    if user and user.crystalBide then
      return SpecialDamage.continueBide(battle, user, target)
    end
    return original(battle, user, target)
  end
end

function SpecialDamage.configure(config)
  config = config or {}
  configured.moves = config.moves or configured.moves
  configured.scripts = config.scripts or configured.scripts
  configured.interpreter = config.interpreter or configured.interpreter
  SpecialDamage.installRuntime()
end

function SpecialDamage.patchMoves(mod, crystalMoves)
  for id in pairs(MOVE_IDS) do
    local row = assert(crystalMoves[id], "missing Crystal special-damage move " .. id)
    local byte = assert(MoveScripts.effectByte(row),
      "missing Crystal effect byte for " .. id)
    local effect = ("CRYSTAL_EFFECT_%02X"):format(byte)
    row.effect = effect
    local patch = {
      effect=effect,
      power=row.power,
      type=row.type,
      accuracy=row.accuracy,
      pp=row.pp,
      effectChance=row.effectChance,
      category=row.category,
    }
    if row.priority ~= nil then patch.priority = row.priority end
    if row.highCrit ~= nil then patch.highCrit = row.highCrit end
    mod.content.moves:patch(id, patch)
  end
end

function SpecialDamage.record()
  return { perform=SpecialDamage.perform }
end

return SpecialDamage
