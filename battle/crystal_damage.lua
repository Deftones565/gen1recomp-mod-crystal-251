-- Generation II damage pipeline for CRYSTAL_251.
--
-- Everything in this file is mod-owned. The engine's Gen I calculator remains
-- untouched. While CRYSTAL_251 is active, every ordinary damaging move is
-- routed here; command-driven damage families stay on their existing paths
-- until their dedicated migration patches.

local CrystalDamage = {}
-- Use the released Gen II rule kernels directly.  The surrounding code is the
-- Gen I adapter (battler wrappers, queue, animation, and text); these modules
-- remain the source of truth for the actual Crystal arithmetic.
local Gen2Damage = require("mods.CRYSTAL_251.battle.gen2.Damage")
local CrystalStats = require("mods.CRYSTAL_251.battle.crystal_stats")
local CommandInterpreter = require("mods.CRYSTAL_251.battle.command_interpreter")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local CrystalItems = require("mods.CRYSTAL_251.battle.crystal_items")

-- These moves do not use the ordinary damage hook. special_damage.lua runs
-- their command-specific formula, delayed, or reflected-damage paths.
local DEFERRED = MoveScripts.DEFERRED
CrystalDamage.DEFERRED = DEFERRED

local configuredMoves = {}
local configuredBaseStats = {}
local configuredScripts = {}
local configuredInterpreter = CommandInterpreter.new()

-- Generation II damage categories are determined entirely by move type.
local PHYSICAL_TYPES = {
  NORMAL=true, FIGHTING=true, FLYING=true, POISON=true, GROUND=true,
  ROCK=true, BUG=true, GHOST=true, STEEL=true,
}

-- data/battle/critical_hit_chances.asm: 1/15, 1/8, 1/4, 1/3, 1/2.
-- High-critical moves add two stages in Crystal; Focus Energy adds one.
local CRIT_THRESHOLDS = { 17, 32, 64, 85, 128 }

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function calcStat(base, dv, statExp, level)
  local root = math.ceil(math.sqrt(math.max(0, statExp or 0)))
  local effort = math.floor(math.min(255, root) / 4)
  return math.floor((((base or 1) + (dv or 0)) * 2 + effort)
    * (level or 1) / 100) + 5
end

function CrystalDamage.calculateStats(mon, base)
  -- Backport of Gen2 Mon.stats. Gen I stores one Special DV/Exp, so both
  -- split special stats intentionally consume that shared value.
  mon, base = mon or {}, base or {}
  local dvs, exp, level = mon.dvs or {}, mon.statExp or {}, mon.level or 1
  local special = dvs.special or dvs.specialAttack or dvs.specialDefense or 0
  local function stat(baseValue, dv, expValue)
    local effort = math.floor(math.sqrt(expValue or 0) / 4)
    return math.floor(((baseValue or 1) * 2 + (dv or 0) * 2 + effort)
      * level / 100) + 5
  end
  local hpDv = (dvs.attack or 0) % 2 * 8
    + (dvs.defense or 0) % 2 * 4
    + (dvs.speed or 0) % 2 * 2
    + special % 2
  return {
    hp = math.floor(((base.hp or 1) * 2 + hpDv * 2
      + math.floor(math.sqrt(exp.hp or 0) / 4)) * level / 100)
      + level + 10,
    attack = stat(base.attack, dvs.attack, exp.attack),
    defense = stat(base.defense, dvs.defense, exp.defense),
    speed = stat(base.speed, dvs.speed, exp.speed),
    specialAttack = stat(base.specialAttack or base.special, special,
      exp.special or exp.specialAttack),
    specialDefense = stat(base.specialDefense or base.special, special,
      exp.special or exp.specialDefense),
  }
end

function CrystalDamage.attachBattler(battler, baseStats)
  if not (battler and battler.mon) then return nil end
  baseStats = baseStats or configuredBaseStats
  local base = baseStats and baseStats[battler.mon.species]
  if not base then return nil end
  CrystalStats.ensure(battler)
  local state = battler.crystal251Battle or {}
  battler.crystal251Battle = state
  if not state.transformed then
    state.baseStats = base
    state.stats = CrystalDamage.calculateStats(battler.mon, base)
  end
  return state
end

local function copyTable(source)
  local out = {}
  for key, value in pairs(source or {}) do out[key] = value end
  return out
end

function CrystalDamage.transformBattler(user, target, baseStats)
  baseStats = baseStats or configuredBaseStats
  local targetState = CrystalDamage.attachBattler(target, baseStats)
  local userState = CrystalDamage.attachBattler(user, baseStats)
  if not (targetState and userState) then return nil end
  CrystalStats.copy(user, target)
  userState.transformed = true
  userState.transformedSpecies = target.mon.species
  userState.baseStats = targetState.baseStats
  userState.stats = copyTable(targetState.stats)
  return userState
end

function CrystalDamage.clearTransform(battler)
  if battler then battler.crystal251Battle = nil end
end

function CrystalDamage.moveFor(moveOrId, moves)
  moves = moves or configuredMoves
  local id = type(moveOrId) == "table" and moveOrId.id or moveOrId
  return id and moves and moves[id] or nil
end

function CrystalDamage.isRouted(moveOrId, moves)
  local id = type(moveOrId) == "table" and moveOrId.id or moveOrId
  local move = CrystalDamage.moveFor(moveOrId, moves)
    or (type(moveOrId) == "table" and moveOrId or nil)
  return id ~= nil and not DEFERRED[id]
    and move ~= nil and (move.power or 0) > 0 and move.category ~= "status"
end

-- The registered Gen I move table is still engine-owned. Before the outer
-- CRYSTAL_251 damage wrapper applies variable-power/type changes, temporarily
-- seed that table with the imported Crystal record. The original row is
-- restored immediately after the calculation.
function CrystalDamage.prepareMove(move, moves)
  local crystal = CrystalDamage.moveFor(move, moves)
  if not crystal or not CrystalDamage.isRouted(crystal, moves) then return nil end
  local token = {
    power = move.power,
    type = move.type,
    category = move.category,
    highCrit = move.highCrit,
  }
  move.power = crystal.power
  move.type = crystal.type
  move.category = PHYSICAL_TYPES[crystal.type] and "physical" or "special"
  move.highCrit = crystal.highCrit
  return token
end

function CrystalDamage.restoreMove(move, token)
  if not token then return end
  move.power = token.power
  move.type = token.type
  move.category = token.category
  move.highCrit = token.highCrit
end

local function stageFor(battler, stat)
  return CrystalStats.get(battler, stat)
end

local function applyStage(value, stage)
  return Gen2Damage.applyStage(value, clamp(stage or 0, -6, 6))
end

local function categoryOf(move)
  return PHYSICAL_TYPES[move.type] and "physical" or "special"
end

local function critRoll(user, move, rng)
  local stage = Gen2Damage.criticalLevel({
    focusEnergy = user.focusEnergy,
    highCritMove = move.highCrit,
    speciesItemBonus = CrystalItems.criticalStage(user, move) >= 2,
  })
  return Gen2Damage.rollCritical(stage, function(chance)
    -- BattleRandom is byte-based in the Gen 1 shell; preserve that stream
    -- while applying the Gen 2 1-in-N ladder.
    local byte = rng(0, 255, 1)
    return byte < math.floor(256 / chance) and 0 or 1
  end)
end

CrystalDamage.rollCritical = critRoll

local function hasType(battler, typeId)
  for _, current in ipairs(battler.curTypes or {}) do
    if current == typeId then return true end
  end
  return false
end

local function chartRows(chart, moveType, targetTypes)
  if chart and chart.rows then return chart.rows(moveType, targetTypes) end
  return {}
end

local function chartEffectiveness(chart, moveType, targetTypes)
  if chart and chart.effectiveness then
    return chart.effectiveness(moveType, targetTypes)
  end
  local mult = 10
  for _, row in ipairs(chartRows(chart, moveType, targetTypes)) do
    mult = math.floor(mult * row / 10)
  end
  return mult
end

-- Apply Crystal's weather, STAB and type-matchup commands to an already
-- calculated damage value. Consecutive-move families call this after their
-- command-specific multiplier, preserving Crystal's integer ordering.
function CrystalDamage.applyStabType(ctx, damage, opts, config)
  opts = opts or {}
  config = config or {}
  local user, target, move = assert(ctx.user), assert(ctx.target), assert(ctx.move)
  local chart = config.typeChart or require("src.battle.TypeChart")
  damage = math.max(0, math.floor(damage or 0))
  if opts.typeless then return damage, 10, false end

  local weather = ctx.battle and ctx.battle.weather
  if weather == "rain" then
    if move.type == "WATER" then damage = math.floor(damage * 3 / 2)
    elseif move.type == "FIRE" then damage = math.floor(damage / 2) end
  elseif weather == "sun" then
    if move.type == "FIRE" then damage = math.floor(damage * 3 / 2)
    elseif move.type == "WATER" then damage = math.floor(damage / 2) end
  end

  if move.id ~= "STRUGGLE" and hasType(user, move.type) then
    damage = math.floor(damage * 3 / 2)
  end

  local targetTypes = target.curTypes or {}
  local typeMult = chartEffectiveness(chart, move.type, targetTypes)
  if typeMult == 0 then return 0, 0, true end
  for _, mult in ipairs(chartRows(chart, move.type, targetTypes)) do
    damage = math.max(1, math.floor(damage * mult / 10))
  end
  return damage, typeMult, false
end

function CrystalDamage.applyVariation(damage, rng, opts)
  opts = opts or {}
  damage = math.max(0, math.floor(damage or 0))
  if opts.typeless then return damage end
  rng = rng or function(_, high) return high end
  if damage > 1 then
    local variation = Gen2Damage.MIN_VARIATION
      + rng(0, Gen2Damage.MAX_VARIATION - Gen2Damage.MIN_VARIATION)
    damage = math.floor(damage * variation / 100)
  end
  return math.max(1, damage)
end

-- Execute one ordinary damaging move through Crystal's command stream.
-- Accuracy, animation and HP application still belong to the battle phase;
-- this function owns the damage-phase commands that are already migrated.
function CrystalDamage.compute(ctx, config)
  config = config or {}
  local user, target = assert(ctx.user), assert(ctx.target)
  local move = assert(ctx.move)
  local opts = ctx.opts or {}
  local rng = opts.rng or ctx.rng or function(a, b) return b or a end
  local chart = config.typeChart
  if not chart then chart = require("src.battle.TypeChart") end

  local userState = CrystalDamage.attachBattler(user, config.baseStats)
  local targetState = CrystalDamage.attachBattler(target, config.baseStats)
  if not (userState and targetState) then return nil end

  if (move.power or 0) <= 0 or move.category == "status" then
    return 0, { crit=false, typeMult=10, crystal251=true, commandTrace={} }
  end

  local script = opts.script or (config.scripts or configuredScripts)[move.id]
    or MoveScripts.forMove(move)
  local interpreter = config.interpreter or configuredInterpreter
  local category = categoryOf(move)
  local attackStat = category == "special" and "specialAttack" or "attack"
  local defenseStat = category == "special" and "specialDefense" or "defense"
  local state = {
    user=user, target=target, move=move, opts=opts, rng=rng, chart=chart,
    userState=userState, targetState=targetState,
    category=category, attackStat=attackStat, defenseStat=defenseStat,
    attackStage=stageFor(user, attackStat),
    defenseStage=stageFor(target, defenseStat),
    crit=false, ignoreStages=false,
  }

  local handlers = {}

  handlers.critical = function(run)
    run.crit = opts.forceCrit
    if run.crit == nil then run.crit = critRoll(user, move, rng) end
    -- Crystal uses unmodified stats only when the defender's relevant stage is
    -- at least the attacker's. Otherwise the critical retains both stages and
    -- any active screen before receiving its x2 multiplier.
    run.ignoreStages = run.crit and run.attackStage <= run.defenseStage
  end

  handlers.damagestats = function(run)
    local attack, defense
    if run.ignoreStages then
      attack = userState.stats[run.attackStat]
      defense = targetState.stats[run.defenseStat]
    else
      attack = applyStage(userState.stats[run.attackStat], run.attackStage)
      defense = applyStage(targetState.stats[run.defenseStat], run.defenseStage)

      if run.category == "physical" and user.mon.status == "BRN"
         and not user.hazeStatReset then
        attack = math.max(1, math.floor(attack / 2))
      end
      if run.category == "special" and target.lightScreen then defense = defense * 2 end
      if run.category == "physical" and target.reflect then defense = defense * 2 end
    end

    attack, defense = CrystalItems.modifyDamageStats(
      user, target, run.category, attack, defense)
    if opts.explode then defense = math.max(1, math.floor(defense / 2)) end
    run.attack, run.defense = attack, defense
  end

  handlers.damagecalc = function(run)
    local level = user.mon.level or 1
    -- BattleCommand_DamageCalc is now the released Gen II implementation;
    -- item/critical/weather/STAB/type ordering remains in the adapter stages
    -- below because those stages also feed the Gen I battle presentation.
    local damage = Gen2Damage.base(level, move.power or 0,
      run.attack, run.defense)
    damage = CrystalItems.modifyBaseDamage(user, move, damage)
    if run.crit then damage = math.min(65535, damage * 2) end
    run.damage = math.min(Gen2Damage.MAX_DAMAGE - Gen2Damage.MIN_DAMAGE,
      damage) + Gen2Damage.MIN_DAMAGE
  end

  handlers.stab = function(run)
    local damage, typeMult, immune = CrystalDamage.applyStabType(ctx,
      run.damage, opts, config)
    run.damage, run.typeMult, run.immune = damage, typeMult, immune
    if immune then run.stop = true end
  end

  handlers.damagevariation = function(run)
    if run.immune then return end
    run.damage = CrystalDamage.applyVariation(run.damage, rng, opts)
  end

  local executed = interpreter:run(script, { state=state, handlers=handlers }, "damage")
  local info = {
    crit=executed.immune and false or executed.crit,
    typeMult=executed.typeMult or 10,
    crystal251=true,
    attackStat=executed.attackStat, defenseStat=executed.defenseStat,
    attack=executed.attack, defense=executed.defense,
    moveType=move.type, category=executed.category or categoryOf(move),
    effectName=script.effectName, commandTrace=executed.trace,
  }
  if executed.immune then return 0, info end
  return math.max(1, executed.damage or 0), info
end


function CrystalDamage.computeWithCommands(ctx, commands, opts, config)
  opts = copyTable(opts)
  opts.script = {
    id=ctx.move.id,
    index=ctx.move.index or 0,
    effect=ctx.move.effect,
    effectName="CommandSpecificDamage",
    mode="special",
    commands=commands,
  }
  local input = copyTable(ctx)
  input.opts = opts
  input.rng = input.rng or opts.rng
  return CrystalDamage.compute(input, config)
end

function CrystalDamage.install(mod, config)
  config = config or {}
  configuredMoves = config.moves or {}
  configuredBaseStats = config.baseStats or {}
  configuredScripts = config.scripts or {}
  configuredInterpreter = config.interpreter or CommandInterpreter.new()

  local function attachBattle(battle)
    if not battle then return end
    CrystalDamage.attachBattler(battle.player, config.baseStats)
    CrystalDamage.attachBattler(battle.enemy, config.baseStats)
  end

  mod.events:on("battle.started", function(ev)
    attachBattle(ev and ev.battle)
  end)
  mod.events:on("battle.battler_switched", function(ev)
    local battler = ev and ev.battler
    CrystalDamage.clearTransform(battler)
    CrystalDamage.attachBattler(battler, config.baseStats)
  end)

  -- effects.lua's variable-power/Foresight wrapper runs outside this one at
  -- priority 60. Priority 40 sees the temporary Crystal move row and replaces
  -- every ordinary damage calculation while leaving command damage deferred.
  mod.hooks:wrap("battle.damage", function(next, ctx)
    if not (ctx and ctx.move and CrystalDamage.isRouted(ctx.move, config.moves)) then
      return next(ctx)
    end
    local damage, info = CrystalDamage.compute(ctx, config)
    if damage == nil then return next(ctx) end
    return damage, info
  end, 40)
end

return CrystalDamage
