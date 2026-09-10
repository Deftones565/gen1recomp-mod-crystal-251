-- Gen 2 trainer AI (engine/battle/ai/scoring.asm + engine/battle/ai/move.asm).
--
-- The cart scores every move the enemy knows, then picks the *lowest* score:
-- each scoring layer walks the move list and either `dec [hl]` to encourage a
-- move or `inc [hl]` to discourage it.  Which layers run is a per-class bit
-- field, TRNATTR_AI_MOVE_WEIGHTS, which the extractor already carries on each
-- trainer class record as `attributes` -- bytes 4 and 5, little-endian.
--
-- A class with no flags (and every wild mon) simply picks at random, which is
-- what AIChooseMove does when wEnemyTrainerAIFlags is zero.  That is also the
-- honest fallback for a layer this file does not model: it never scores, so it
-- never scores wrongly.

local Damage = require("mods.CRYSTAL_251.battle.gen2.Damage")

local Ai = {}

-- constants/trainer_data_constants.asm, shift_const order.
Ai.FLAGS = {
  BASIC = 0x0001,
  SETUP = 0x0002,
  TYPES = 0x0004,
  OFFENSIVE = 0x0008,
  SMART = 0x0010,
  OPPORTUNIST = 0x0020,
  AGGRESSIVE = 0x0040,
  CAUTIOUS = 0x0080,
  STATUS = 0x0100,
  RISKY = 0x0200,
}

-- AIChooseMove seeds every slot with this before the layers run.
Ai.BASE_SCORE = 20

-- BASE_AI_SWITCH_SCORE: CheckPlayerMoveTypeMatchups starts here and walks the
-- score down for every super-effective move the player has shown.
Ai.BASE_SWITCH_SCORE = 10

-- TrainerClassAttributes is {item1, item2, baseMoney, aiLo, aiHi, switchLo,
-- switchHi, pad}; the AI word is bytes 4 and 5, little-endian.
function Ai.flagsOf(attributes)
  if type(attributes) ~= "table" then return 0 end
  return (attributes[4] or 0) + (attributes[5] or 0) * 256
end

function Ai.has(flags, name)
  local bit = Ai.FLAGS[name]
  if not bit then return false end
  return math.floor((flags or 0) / bit) % 2 == 1
end

-- data/battle/ai/stall_moves.asm and residual_moves.asm, keyed by effect: the
-- moves AI_Opportunist stops using when it is nearly dead and the ones
-- AI_Cautious stops using after its first turn.
Ai.STALL_EFFECTS = {
  EFFECT_HEAL = true, EFFECT_TOXIC = true, EFFECT_LEECH_SEED = true,
  EFFECT_LIGHT_SCREEN = true, EFFECT_REFLECT = true, EFFECT_SAFEGUARD = true,
  EFFECT_MIST = true, EFFECT_SUBSTITUTE = true, EFFECT_PERISH_SONG = true,
  EFFECT_MEAN_LOOK = true, EFFECT_SPIKES = true, EFFECT_ATTRACT = true,
  EFFECT_CONFUSE = true, EFFECT_DISABLE = true, EFFECT_ENCORE = true,
  EFFECT_RAIN_DANCE = true, EFFECT_SUNNY_DAY = true, EFFECT_SANDSTORM = true,
  EFFECT_MORNING_SUN = true, EFFECT_SYNTHESIS = true, EFFECT_MOONLIGHT = true,
}

Ai.RESIDUAL_EFFECTS = {
  EFFECT_TOXIC = true, EFFECT_LEECH_SEED = true, EFFECT_NIGHTMARE = true,
  EFFECT_CURSE = true, EFFECT_SPIKES = true, EFFECT_PERISH_SONG = true,
  EFFECT_MEAN_LOOK = true, EFFECT_ATTRACT = true, EFFECT_ENCORE = true,
  EFFECT_DISABLE = true, EFFECT_LIGHT_SCREEN = true, EFFECT_REFLECT = true,
  EFFECT_SAFEGUARD = true, EFFECT_MIST = true,
}

-- The two blocks AI_Setup keys off: EFFECT_ATTACK_UP..EFFECT_EVASION_UP and
-- their _2 forms raise the user, the _DOWN forms lower the target.
Ai.STAT_UP_EFFECTS = {}
Ai.STAT_DOWN_EFFECTS = {}
for _, stat in ipairs({ "ATTACK", "DEFENSE", "SPEED", "SP_ATK", "SP_DEF",
    "ACCURACY", "EVASION" }) do
  Ai.STAT_UP_EFFECTS["EFFECT_" .. stat .. "_UP"] = true
  Ai.STAT_UP_EFFECTS["EFFECT_" .. stat .. "_UP_2"] = true
  Ai.STAT_DOWN_EFFECTS["EFFECT_" .. stat .. "_DOWN"] = true
  Ai.STAT_DOWN_EFFECTS["EFFECT_" .. stat .. "_DOWN_2"] = true
end

-- Effects that do nothing but inflict a major status, which is what the
-- BASIC and STATUS layers care about.
Ai.STATUS_EFFECTS = {
  EFFECT_SLEEP = "sleep", EFFECT_POISON = "poison", EFFECT_TOXIC = "toxic",
  EFFECT_PARALYZE = "paralyze", EFFECT_BURN = "burn",
  EFFECT_FREEZE = "freeze", EFFECT_CONFUSE = "confuse",
}

-- The type matchup a move would get, x10 (10 = neutral, 0 = immune).
local function matchupOf(context, def, defender)
  local chart = context.typeChart or {}
  return Damage.typeMultiplier(def.type, defender.types or {}, chart.matchups)
end

-- A rough expected damage, used only to rank moves against each other: the
-- real roll's randomness would make the AI's own choice non-deterministic,
-- which is not what the cart does (AI_Aggressive compares wCurDamage from a
-- no-random pass).
local function expectedDamage(context, attacker, defender, def)
  if (def.power or 0) <= 0 then return 0 end
  local damage = Damage.calc({
    level = attacker.level or 1,
    power = def.power,
    moveType = def.type,
    attacker = {
      attack = (attacker.stats or {}).attack,
      specialAttack = (attacker.stats or {}).specialAttack,
      types = attacker.types,
      stages = context.attackerStages,
    },
    defender = {
      defense = (defender.stats or {}).defense,
      specialDefense = (defender.stats or {}).specialDefense,
      types = defender.types,
      stages = context.defenderStages,
    },
    types = (context.typeChart or {}).types,
    matchups = (context.typeChart or {}).matchups,
    -- AIDamageCalc runs BattleCommand_DamageCalc itself (scoring.asm:3002-3016),
    -- so the enemy's estimate takes the `srl c` too (effect_commands.asm:2904-2909).
    defenseHalved = def.effect == "EFFECT_SELFDESTRUCT",
    critical = false,
    random = function() return 0 end,
  })
  return damage
end

--------------------------------------------------------------------------
-- AI_Smart (engine/battle/ai/scoring.asm)
--------------------------------------------------------------------------
--
-- The heaviest layer: a 70-entry table of per-EFFECT handlers, each one a few
-- lines of "look at the HP, the speed and the statuses, then encourage or
-- discourage".  `dec [hl]` encourages (a LOWER score wins) and `inc [hl]`
-- discourages; AIDiscourageMove adds ten, which is what "dismiss" means.
--
-- The handlers below are transcribed one for one.  An effect with no handler
-- is simply not scored by this layer, which is exactly what the cart does with
-- an effect that is not in its table.

-- AIDiscourageMove.
local DISMISS = 10

-- The two coin flips the scoring layers use.  `cp 20 percent - 1` succeeds
-- (carry set, meaning "return without scoring") on the LOW roll, so the
-- helpers below read as "does the encouragement happen".
local function chance(random, percent)
  return (random(100) + 1) <= percent
end

-- state (all optional; a missing field simply never fires its branch):
--   enemyHp / enemyMaxHp / playerHp / playerMaxHp
--   enemyFaster            AICompareSpeed
--   enemyTurns / playerTurns  how many turns each mon has been out
--   playerStatus / enemyStatus
--   playerToxic, playerLeechSeed, playerCharged, playerFlying
--   enemyRage, enemyProtectCount, enemyFuryCutter
--   stages (the enemy's) / playerStages
--   knownEffects           the effects the enemy's own move list carries
--   enemyMoveIds           the move IDS the enemy knows (AIHasMoveInArray)
--   enemyTypes / playerTypes   both slots, IN ORDER: the weather and Curse
--                          handlers read slot 1 before slot 2 and a swapped
--                          pair scores differently
--   playerSpecialType      either player type is on the special side of
--                          constants/type_constants.asm (`cp SPECIAL`)
--   playerMatchupScore     CheckPlayerMoveTypeMatchups' wEnemyAISwitchScore
--   playerLastMovePp / playerLastMoveMatchup / playerLastMoveSpecial
--   playerSpecialMoves     the special twin of playerPhysicalMoves
--   playerUsedEffects      the EFFECTS behind wPlayerUsedMoves
--   playerFuryCutter / playerRollout   the player's own ramp
--   playerFlyingUp / playerUnderground SUBSTATUS_FLYING and _UNDERGROUND
--                          split apart, where playerFlying is the mask
--   playerLastMon          AICheckLastPlayerMon
--   enemyToxic, enemyLeechSeed, enemySpikes, enemyPartyStatus
--   enemyPerishCount, enemySleepTurns, enemyHasBench
--   enemyInaccurateEffectiveMove   AI_Smart_LockOn's `.checkmove` verdict,
--                          explicitly false when the loop found nothing
--   playerLockOn           SUBSTATUS_LOCK_ON on the player, which is the
--                          enemy's own Lock-On having landed (the cart sets
--                          the bit on the TARGET); it also drives
--                          Ai.lockOnPostPass
--   hiddenPowerPower / hiddenPowerMatchup   HiddenPowerDamage's d and matchup
--   weather                wBattleWeather, "sun" / "rain" / "sandstorm"
--
-- These are read but never produced, because the port models no such
-- volatile yet; their branches are dead until it does:
--   playerTrapped, playerInLove, playerIdentified, playerNightmare,
--   playerCursed, playerMinimized, enemyWrapped, conversion2Matchup
local function fraction(value, max, part)
  if not (value and max and max > 0) then return nil end
  return value >= max * part
end

Ai.SMART = {}
local S = Ai.SMART

-- Greatly encourage a sleep move when the enemy can follow it with Dream
-- Eater or Nightmare; a coin flip otherwise.
S.EFFECT_SLEEP = function(ctx, st)
  local combo = st.knownEffects
    and (st.knownEffects.EFFECT_DREAM_EATER or st.knownEffects.EFFECT_NIGHTMARE)
  if not combo then return 0 end
  if not chance(ctx.random, 50) then return 0 end
  return -2
end

-- Dream Eater: 90% chance to greatly encourage.  AI_Basic is what keeps it
-- off an awake target.
S.EFFECT_DREAM_EATER = function(ctx)
  if chance(ctx.random, 10) then return 0 end
  return -3
end

-- Absorb and friends: discouraged when resisted, encouraged when the enemy is
-- hurt and the matchup is at least neutral.
S.EFFECT_LEECH_HIT = function(ctx, st, matchup)
  if (matchup or 10) < 10 then
    if chance(ctx.random, 39) then return 0 end
    return 1
  end
  if (matchup or 10) == 10 then return 0 end
  if fraction(st.enemyHp, st.enemyMaxHp, 1) then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -1
end

-- Toxic and Leech Seed (AI_Smart_Toxic, which AI_Smart_LeechSeed shares):
-- pointless once the target is already low, since the residual will not get
-- the turns to matter.  AICheckPlayerHalfHP sets carry when the player is
-- ABOVE half and the routine is `ret c`, so the discouragement lands BELOW
-- half; S.EFFECT_OHKO reads the same idiom the same way.
local function halfHpDiscourage(_, st)
  if fraction(st.playerHp, st.playerMaxHp, 0.5) then return 0 end
  return 1
end
S.EFFECT_TOXIC = halfHpDiscourage
S.EFFECT_LEECH_SEED = halfHpDiscourage

-- Light Screen / Reflect: only worth it at full HP.
local function fullHpOnly(ctx, st)
  if fraction(st.enemyHp, st.enemyMaxHp, 1) then return 0 end
  if chance(ctx.random, 8) then return 0 end
  return 1
end
S.EFFECT_LIGHT_SCREEN = fullHpOnly
S.EFFECT_REFLECT = fullHpOnly

-- Evasion up: dismissed at the cap, greatly encouraged at full HP (and
-- especially against a badly poisoned target), discouraged when nearly dead.
S.EFFECT_EVASION_UP = function(ctx, st)
  if (st.stages and st.stages.evasion or 0) >= 6 then return DISMISS end
  if fraction(st.enemyHp, st.enemyMaxHp, 1) then
    if st.playerToxic then return -2 end
    if chance(ctx.random, 70) then return -2 end
    return 0
  end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 3 end
  if chance(ctx.random, 4) then return -2 end
  return 0
end

-- Swift and friends: worth it once accuracy or evasion has moved three stages.
S.EFFECT_ALWAYS_HIT = function(ctx, st)
  local accDown = (st.stages and st.stages.accuracy or 0) <= -3
  local evaUp = (st.playerStages and st.playerStages.evasion or 0) >= 3
  if not (accDown or evaUp) then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -2
end

-- OHKO: dismissed against a higher-level target, discouraged once the target
-- is below half.
S.EFFECT_OHKO = function(_, st)
  if (st.playerLevel or 1) > (st.enemyLevel or 1) then return DISMISS end
  if fraction(st.playerHp, st.playerMaxHp, 0.5) then return 0 end
  return 1
end

-- Confusion: worth less the lower the target already is.
S.EFFECT_CONFUSE = function(ctx, st)
  local score = 0
  if not fraction(st.playerHp, st.playerMaxHp, 0.5) then
    if not chance(ctx.random, 10) then score = score + 1 end
    if not fraction(st.playerHp, st.playerMaxHp, 0.25) then
      score = score + 1
    end
  end
  return score
end

-- Paralysis: greatly encouraged when the enemy is the SLOWER one, discouraged
-- against a nearly-dead target.
S.EFFECT_PARALYZE = function(ctx, st)
  if not fraction(st.playerHp, st.playerMaxHp, 0.25) then
    if chance(ctx.random, 50) then return 0 end
    return 1
  end
  if st.enemyFaster then return 0 end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -2
end

-- Substitute: dismissed below half HP.
S.EFFECT_SUBSTITUTE = function(_, st)
  if fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 0 end
  return DISMISS
end

-- Hyper Beam: a finisher, not an opener.
S.EFFECT_HYPER_BEAM = function(ctx, st)
  if fraction(st.enemyHp, st.enemyMaxHp, 0.5) then
    if chance(ctx.random, 35) then return 0 end
    local score = 1
    if not chance(ctx.random, 50) then score = score + 1 end
    return score
  end
  if fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 0 end
  if chance(ctx.random, 50) then return 0 end
  return -1
end

-- Reversal and Skull Bash both want the enemy nearly dead.
local function needsLowHp(_, st)
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 0 end
  return 1
end
S.EFFECT_REVERSAL = needsLowHp
S.EFFECT_SKULL_BASH = needsLowHp

-- Belly Drum: full HP or nothing.
S.EFFECT_BELLY_DRUM = function(_, st)
  if (st.stages and st.stages.attack or 0) >= 3 then return 5 end
  if fraction(st.enemyHp, st.enemyMaxHp, 1) then return 0 end
  if fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 1 end
  return 5
end

-- Attract: an opener.
S.EFFECT_ATTRACT = function(ctx, st)
  if (st.playerTurns or 0) == 0 then
    if chance(ctx.random, 79) then return -1 end
    return 0
  end
  if chance(ctx.random, 20) then return 0 end
  return 1
end

-- Quick Attack and friends: only when the enemy is already slower, dismissed
-- against something off the field, encouraged when it would finish the job.
S.EFFECT_PRIORITY_HIT = function(_, st, _, damage)
  if st.enemyFaster then return 0 end
  if st.playerFlying then return DISMISS end
  if damage and st.playerHp and damage >= st.playerHp then return -1 end
  return 0
end

-- Protect: never twice running, and worth it against a charging or poisoned
-- target.
S.EFFECT_PROTECT = function(_, st)
  if (st.enemyProtectCount or 0) > 0 then return 2 end
  if st.playerLockOn then return 1 end
  if (st.playerFuryCutter or 0) >= 3 then return -1 end
  if st.playerCharged or st.playerToxic or st.playerLeechSeed then return -1 end
  return 0
end

-- Endure: for a Reversal follow-up, and never at high HP.
S.EFFECT_ENDURE = function(ctx, st)
  if (st.enemyProtectCount or 0) > 0 then return 2 end
  if fraction(st.enemyHp, st.enemyMaxHp, 1) then return 2 end
  if fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 1 end
  if st.knownEffects and st.knownEffects.EFFECT_REVERSAL then
    if chance(ctx.random, 20) then return 0 end
    return -3
  end
  return 0
end

-- Rollout and Fury Cutter: the ramp is only worth starting when nothing is
-- going to interrupt it.
local function rollout(ctx, st)
  local risky = st.enemyStatus == "paralyze" or st.enemyConfused
    or st.enemyInLove
    or not fraction(st.enemyHp, st.enemyMaxHp, 0.25)
    or (st.stages and st.stages.accuracy or 0) < 0
    or (st.playerStages and st.playerStages.evasion or 0) >= 1
  if not risky then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return 1
end
S.EFFECT_ROLLOUT = rollout

-- Fury Cutter adds its own ramp bonus and then falls through to Rollout's
-- check, which is literally what the ASM does.
S.EFFECT_FURY_CUTTER = function(ctx, st)
  local count = st.enemyFuryCutterCount or 0
  local score = 0
  if count >= 1 then score = score - 1 end
  if count >= 2 then score = score - 2 end
  if count >= 3 then score = score - 3 end
  return score + rollout(ctx, st)
end

-- Rage: worth continuing once it is building.
S.EFFECT_RAGE = function(ctx, st)
  if not st.enemyRage then return 0 end
  if chance(ctx.random, 50) then return -1 end
  return -1 - math.min(3, st.enemyRageCount or 0)
end

-- Encore: only from ahead, and only against a weak or resisted move.
S.EFFECT_ENCORE = function(_, st, _, _, playerLastPower)
  if not st.enemyFaster then return 1 end
  if not st.playerLastMove then return DISMISS end
  if (playerLastPower or 0) == 0 then return -1 end
  return 0
end

-- Counter: worth it when the player's known moves are mostly physical.
S.EFFECT_COUNTER = function(_, st)
  if (st.playerPhysicalMoves or 0) == 0 then return 1 end
  return -1
end

--------------------------------------------------------------------------
-- The rest of AI_Smart_EffectHandlers, in the jumptable's own order.
--------------------------------------------------------------------------
--
-- Several entries in the table point at ONE cart body carrying two or more
-- labels; those share a Lua local here rather than being copied, and the
-- comment names every label that sits on it.  Where a shared body is reached
-- by an ASM fallthrough (`.greatly_discourage` dropping into `.discourage`)
-- the two deltas are added together into a single return, because the cart
-- really does run both.

-- Selfdestruct and Explosion (AI_Smart_Selfdestruct): a last resort.  Greatly
-- discouraged above half HP, left alone at or below a quarter (nothing left to
-- lose), and greatly discouraged 92% of the time in between.  `.discourage` is
-- reached from both ends, which is why the same +3 appears twice.
S.EFFECT_SELFDESTRUCT = function(ctx, st)
  if fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 3 end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 0 end
  if chance(ctx.random, 8) then return 0 end
  return 3
end

-- data/battle/ai/useful_moves.asm: the nineteen moves AI_Smart_MirrorMove,
-- AI_Smart_Mimic and AI_Smart_Disable test the player's last move against.
-- The keys are the cache's own move ids, so PSYCHIC is PSYCHIC_M.
local USEFUL_MOVES = {
  DOUBLE_EDGE = true, SING = true, FLAMETHROWER = true, HYDRO_PUMP = true,
  SURF = true, ICE_BEAM = true, BLIZZARD = true, HYPER_BEAM = true,
  SLEEP_POWDER = true, THUNDERBOLT = true, THUNDER = true, EARTHQUAKE = true,
  TOXIC = true, PSYCHIC_M = true, HYPNOSIS = true, RECOVER = true,
  FIRE_BLAST = true, SOFTBOILED = true, SUPER_FANG = true,
}

-- Mirror Move (AI_Smart_MirrorMove).  With nothing to copy it is dismissed
-- only when the enemy is FASTER, because a faster enemy moves before the
-- player and would copy nothing; from behind the player will have moved by
-- then, so the cart says nothing.  With a useful move on the table it is a
-- coin flip to encourage, and a faster enemy encourages again.
S.EFFECT_MIRROR_MOVE = function(ctx, st)
  if not st.playerLastMove then
    if not st.enemyFaster then return 0 end
    return DISMISS
  end
  if not USEFUL_MOVES[st.playerLastMove] then return 0 end
  if chance(ctx.random, 50) then return 0 end
  if not st.enemyFaster then return -1 end
  if chance(ctx.random, 10) then return -1 end
  return -2
end

-- Sand-Attack and friends (AI_Smart_AccuracyDown).  The HP block picks one
-- bonus: a full-health player facing a healthy enemy is a big encouragement, a
-- nearly dead player a big discouragement.  The tail then re-reads the board
-- (badly poisoned, seeded, accuracy already under the enemy's evasion, mid
-- ramp) and can cancel it, which the cart's own comments admit to.
S.EFFECT_ACCURACY_DOWN = function(ctx, st)
  local score = 0
  if fraction(st.playerHp, st.playerMaxHp, 1)
      and fraction(st.enemyHp, st.enemyMaxHp, 0.5) then
    if st.playerToxic then return -2 end
    if chance(ctx.random, 70) then return -2 end
  elseif not fraction(st.playerHp, st.playerMaxHp, 0.25) then
    score = 2
  elseif chance(ctx.random, 4) then
    return -2
  elseif fraction(st.playerHp, st.playerMaxHp, 0.5) then
    if chance(ctx.random, 20) then return -2 end
  elseif not chance(ctx.random, 50) then
    -- `.hp_mismatch_3`'s 50% miss falls THROUGH into `.hp_mismatch_2`, so the
    -- move is at +2 before the tail below ever runs.
    score = 2
  end
  -- .not_encouraged, which `.hp_mismatch_2` also falls into: a move already at
  -- +2 can still be pulled back down here.
  if st.playerToxic then
    if chance(ctx.random, 31) then return score end
    return score - 2
  end
  if st.playerLeechSeed then
    if chance(ctx.random, 50) then return score end
    return score - 1
  end
  local enemyEva = st.stages and st.stages.evasion or 0
  local playerAcc = st.playerStages and st.playerStages.accuracy or 0
  if playerAcc < enemyEva then return score + 1 end
  if (st.playerFuryCutter or 0) > 0 then return score - 2 end
  if st.playerRollout then return score - 2 end
  return score + 1
end

-- wPlayerStatLevels / wEnemyStatLevels order, in Battle.newStages' names.
-- AI_Smart_ResetStats' loop counter is NUM_LEVEL_STATS (8) but it decrements
-- BEFORE every read, so it walks these seven and stops short of the ABILITY
-- pseudo-stat BattleCommand_Curse uses.
local STAGE_KEYS = { "attack", "defense", "speed", "specialAttack",
  "specialDefense", "accuracy", "evasion" }

-- Haze (AI_Smart_ResetStats): worth it once the board has turned, meaning any
-- of the enemy's own stages sits at -3 or worse or any of the player's at +3 or
-- better.  84% to encourage then, a flat discouragement when neither is true.
-- The cart bails out of the enemy loop the moment it finds a low stage and only
-- then walks the player's, which is the same answer as one combined pass.
S.EFFECT_RESET_STATS = function(ctx, st)
  local worth = false
  for _, key in ipairs(STAGE_KEYS) do
    if (st.stages and st.stages[key] or 0) <= -3 then worth = true end
    if (st.playerStages and st.playerStages[key] or 0) >= 3 then worth = true end
  end
  if not worth then return 1 end
  if chance(ctx.random, 16) then return 0 end
  return -1
end

-- Bide (AI_Smart_Bide): full HP or nothing.  The same shape as Light Screen's
-- check, but the cart rolls 10% here where fullHpOnly rolls 8%, so the two
-- cannot share a body.
S.EFFECT_BIDE = function(ctx, st)
  if fraction(st.enemyHp, st.enemyMaxHp, 1) then return 0 end
  if chance(ctx.random, 10) then return 0 end
  return 1
end

-- Whirlwind and Roar (AI_Smart_ForceSwitch), which AI_Smart_BatonPass repeats
-- instruction for instruction: only worth blowing the player away once it HAS
-- shown a super-effective move, which CheckPlayerMoveTypeMatchups reports as a
-- switch score below BASE_AI_SWITCH_SCORE.
local function switchMatchup(_, st)
  local score = st.playerMatchupScore
  if score == nil then return 0 end
  if score < Ai.BASE_SWITCH_SCORE then return 0 end
  return 1
end
S.EFFECT_FORCE_SWITCH = switchMatchup

-- Recover, Rest, Softboiled (AI_Smart_Heal): 90% to greatly encourage below a
-- quarter HP, discouraged above half, nothing in between.  AI_Smart_MorningSun,
-- AI_Smart_Synthesis and AI_Smart_Moonlight are three more labels on this one
-- body, so all four effects share it.
local function healSelf(ctx, st)
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then
    if chance(ctx.random, 10) then return 0 end
    return -2
  end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 0 end
  return 1
end
S.EFFECT_HEAL = healSelf

-- Razor Wind (AI_Smart_RazorWind, shared with AI_Smart_Unused2B).  A two turn
-- move, so the cart drops it while a Perish count is running out, hits it with
-- a flat +6 (deliberately NOT AIDiscourageMove's ten) if the player has ever
-- shown Protect, and discourages it four times in five while the enemy is
-- confused or at or below half HP.  The confused case falls straight into the
-- 79% roll without ever testing HP.
local function razorWind(ctx, st)
  if st.enemyPerishCount and st.enemyPerishCount < 3 then return 1 end
  if st.playerUsedEffects and st.playerUsedEffects.EFFECT_PROTECT then
    return 6
  end
  if not st.enemyConfused then
    if fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 0 end
  end
  if chance(ctx.random, 79) then return 0 end
  return 1
end
S.EFFECT_RAZOR_WIND = razorWind

-- Super Fang (AI_Smart_SuperFang) halves what is left, so the only thing the
-- cart checks is whether there is enough left to halve.
S.EFFECT_SUPER_FANG = function(_, st)
  if fraction(st.playerHp, st.playerMaxHp, 0.25) then return 0 end
  return 1
end

-- Bind, Wrap, Fire Spin, Clamp (AI_Smart_TrapTarget): half the time greatly
-- encouraged against a target that is already suffering (badly poisoned, in
-- love, identified, mid Rollout, having a Nightmare) or still on its first
-- turn, and half the time discouraged otherwise or while the trap is already
-- running.  The encourage side also wants the enemy above a quarter HP to
-- survive the lock.
S.EFFECT_TRAP_TARGET = function(ctx, st)
  local encourage = false
  if not st.playerTrapped then
    encourage = st.playerToxic or st.playerInLove or st.playerRollout
      or st.playerIdentified or st.playerNightmare
      or (st.playerTurns or 0) == 0
  end
  if not encourage then
    if chance(ctx.random, 50) then return 0 end
    return 1
  end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 0 end
  if chance(ctx.random, 50) then return 0 end
  return -2
end

-- AI_Smart_Unused2B is the second label on AI_Smart_RazorWind's body.
S.EFFECT_UNUSED_2B = razorWind

-- Amnesia (AI_Smart_SpDefenseUp2): discouraged below half HP or once Sp.Def is
-- already at +4, ignored from +2 up, and 80% to greatly encourage below that
-- when the player carries a special type.  The cart reuses the value already in
-- `a` for the second compare, so the +2 gate reads the same Sp.Def stage it
-- just tested against +4.
S.EFFECT_SP_DEF_UP_2 = function(ctx, st)
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 1 end
  local stage = st.stages and st.stages.specialDefense or 0
  if stage >= 4 then return 1 end
  if stage >= 2 then return 0 end
  if not st.playerSpecialType then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -2
end

-- Icy Wind, and ONLY Icy Wind (AI_Smart_SpeedDownHit): the cart gates on
-- wEnemyMoveStruct + MOVE_ANIM, so Bubble, Bubblebeam and Constrict share the
-- effect but never reach the body.  Almost 90% to greatly encourage on the
-- player's first turn, while the player is the faster one and the enemy is
-- still above a quarter HP.
S.EFFECT_SPEED_DOWN_HIT = function(ctx, st)
  if ctx.moveId ~= "ICY_WIND" then return 0 end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 0 end
  if (st.playerTurns or 0) ~= 0 then return 0 end
  if st.enemyFaster then return 0 end
  if chance(ctx.random, 12) then return 0 end
  return -2
end

-- Mimic (AI_Smart_Mimic): with nothing to copy it is dismissed from ahead and
-- merely discouraged from behind, because `.dismiss` falls through into
-- `.discourage`.  Otherwise it wants the enemy above half HP and a copied move
-- that is at least neutral coming back at its owner: the cart sets hBattleTurn
-- to 1, so BattleCheckTypeMatchup defends with the PLAYER's types.
S.EFFECT_MIMIC = function(ctx, st)
  if not st.playerLastMove then
    if st.enemyFaster then return DISMISS end
    return 1
  end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 1 end
  local copied = st.playerLastMoveMatchup
  if copied == nil then return 0 end
  if copied < 10 then return 1 end
  local score = 0
  if copied > 10 and not chance(ctx.random, 50) then score = -1 end
  if not USEFUL_MOVES[st.playerLastMove] then return score end
  if chance(ctx.random, 50) then return score end
  return score - 1
end

-- AI_Smart_Disable.  Only worth it from ahead: the slower enemy skips straight
-- to the discourage.  From ahead, a 61% encourage when the player's last move
-- is one of UsefulMoves.  The "does my own move have power" test on the way out
-- reads wEnemyMoveStruct + MOVE_POWER, which is 0 for every stock
-- EFFECT_DISABLE move, so on an unmodded cart a boring last move always falls
-- through into `.discourage`; the `damage` argument stands in for it so a
-- modded Disable with real power keeps the branch.
S.EFFECT_DISABLE = function(ctx, st, _, damage)
  if st.enemyFaster then
    if USEFUL_MOVES[st.playerLastMove] then
      if chance(ctx.random, 39) then return 0 end
      return -1
    end
    if (damage or 0) > 0 then return 0 end
  end
  if chance(ctx.random, 8) then return 0 end
  return 1
end

-- AI_Smart_PainSplit: discourage while doubling the enemy's HP would still
-- overshoot the player's, since the split would then hand HP away.  The cart
-- does this as one 16 bit compare of [player HP] against [enemy HP * 2]; its
-- own comment states the test backwards.
S.EFFECT_PAIN_SPLIT = function(_, st)
  if not (st.enemyHp and st.playerHp) then return 0 end
  if st.playerHp >= st.enemyHp * 2 then return 0 end
  return 1
end

-- AI_Smart_Snore, shared verbatim with AI_Smart_SleepTalk (one label falls
-- into the other).  The cart tests the sleep counter against 1, so it
-- discourages only on the last sleeping turn and greatly encourages everything
-- else, an AWAKE enemy included; AI_Redundant is what keeps these off an awake
-- mon.
local function snoreOrSleepTalk(_, st)
  local count = st.enemySleepTurns
  if count == nil then return 0 end
  if count == 1 then return 3 end
  return -3
end
S.EFFECT_SNORE = snoreOrSleepTalk

-- AI_Smart_Conversion2.  CART BUG (docs/bugs_and_glitches.md): the guard reads
-- `ld a, [wLastPlayerMove] / and a / jr nz, .discourage`, so it discourages
-- once the player HAS moved and takes the matchup path only on turn one, where
-- the move index it looks up is 0 - 1 = $ff, past the end of Moves.  The
-- inverted test is kept; the garbage read becomes st.conversion2Matchup, which
-- the port leaves nil so that path scores nothing.
S.EFFECT_CONVERSION2 = function(ctx, st)
  if not st.playerLastMove then
    local matchup = st.conversion2Matchup
    if matchup ~= nil then
      if matchup > 10 then
        if chance(ctx.random, 50) then return 0 end
        return -1
      end
      if matchup == 10 then return 0 end
    else
      return 0
    end
  end
  -- .discourage
  if chance(ctx.random, 10) then return 0 end
  return 1
end

-- AI_Smart_LockOn.  Pointless when the player is already locked on, worthless
-- when nearly dead, and only from ahead once past half HP.  It then wants a
-- reason: the player's evasion up three, the enemy's accuracy down three, or
-- failing both, at least one shaky-but-effective move to aim.
-- The dismissal is only half of `.player_locked_on`: the branch also walks the
-- enemy's OWN move list and encourages every shaky move by two, which is a
-- score edit on OTHER moves and so cannot live in a per-move handler.  That
-- half is Ai.lockOnPostPass, run from Ai.choose once the table is done.
S.EFFECT_LOCK_ON = function(ctx, st)
  if st.playerLockOn then return DISMISS end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return 1 end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.5) and not st.enemyFaster then
    return 1
  end
  local evasion = st.playerStages and st.playerStages.evasion or 0
  if evasion >= 3 then
    if chance(ctx.random, 50) then return 0 end
    return -2
  end
  if evasion >= 1 then return 0 end
  local accuracy = st.stages and st.stages.accuracy or 0
  if accuracy <= -3 then
    if chance(ctx.random, 50) then return 0 end
    return -2
  end
  if accuracy < 0 then return 0 end
  -- .checkmove: the loop reaches .discourage only when no move qualified.
  if st.enemyInaccurateEffectiveMove == false then return 1 end
  return 0
end

-- `71 percent - 1`, the raw ($ff-scaled) accuracy AI_Smart_LockOn calls shaky.
Ai.LOCK_ON_ACCURACY = 0xb4

-- AI_Smart_LockOn's `.player_locked_on` half, as a post-pass over the finished
-- score table.  With the lock-on already up the layer stops caring about its
-- own slot and doubly encourages every move the enemy would otherwise struggle
-- to land ("dec [hl]" twice per move under `71 percent - 1`); the `.dismiss`
-- tail that then buries Lock-On itself is what S.EFFECT_LOCK_ON returns.
--
-- The loop is per Lock-On in the list, not per turn: a mon carrying both
-- Lock-On and Mind Reader runs the scoring layer twice and so lands the
-- encouragement twice, which is exactly what the cart does.
--
-- `defs` is the move definition for each score slot, in the same order.
function Ai.lockOnPostPass(scores, defs)
  local rounds = 0
  for i = 1, #scores do
    local def = defs[i]
    if def and def.effect == "EFFECT_LOCK_ON" then rounds = rounds + 1 end
  end
  if rounds == 0 then return scores end
  for i = 1, #scores do
    local def = defs[i]
    -- accuracyRaw is the cart's own byte; the percentage is the fallback for a
    -- caller that only has the human-readable number.
    local raw = def and (def.accuracyRaw
      or (def.accuracy and math.floor(def.accuracy * 255 / 100)))
    if raw and raw < Ai.LOCK_ON_ACCURACY then
      scores[i] = scores[i] - 2 * rounds
    end
  end
  return scores
end

-- AI_Smart_DefrostOpponent.  Dead twice over, and both are kept: no move
-- carries EFFECT_DEFROST_OPPONENT (the cart says so itself), and the status it
-- reads is wEnemyMonStatus, the AI's OWN freeze, not the opponent the effect
-- names.
S.EFFECT_DEFROST_OPPONENT = function(_, st)
  if st.enemyStatus ~= "freeze" then return 0 end
  return -3
end

-- AI_Smart_SleepTalk is the same label body as AI_Smart_Snore.
S.EFFECT_SLEEP_TALK = snoreOrSleepTalk

-- AI_Smart_DestinyBond is the third label on the body `needsLowHp` already
-- carries for AI_Smart_Reversal and AI_Smart_SkullBash.
S.EFFECT_DESTINY_BOND = needsLowHp

-- AI_Smart_Spite.  With nothing to drain yet it is a stall move: dismissed
-- from ahead, half discouraged from behind.  Once the player has shown a move
-- it goes by that move's remaining PP: under 6 is worth taking, 15 or more is
-- not.  The cart reads the raw PP byte without masking off the PP Up bits, so
-- a move with any PP Ups always lands on `.discourage`; the port stores plain
-- PP and has no such bits to mask, so that quirk cannot be reproduced.
S.EFFECT_SPITE = function(ctx, st)
  if not st.playerLastMove then
    if st.enemyFaster then return DISMISS end
    if chance(ctx.random, 50) then return 0 end
    return 1
  end
  -- `.moveloop` falls out with no score when that move is not in the player's
  -- current move list, which is what a nil PP stands in for here.
  local pp = st.playerLastMovePp
  if pp == nil then return 0 end
  if pp < 6 then
    if chance(ctx.random, 39) then return 0 end
    return -2
  end
  if pp >= 15 then return 1 end
  if not chance(ctx.random, 39) then return 0 end
  return 1
end

-- AI_Smart_HealBell.  The cart ORs the status byte of every unfainted mon in
-- wOTParty: nothing statused and a clean active mon dismisses the move.
-- Otherwise one step of encouragement for the active mon being statused, and a
-- coin flip for two more when that status is sleep or freeze, the two it cannot
-- simply wait out.  `.ok` is reached both by the `jr z` and by falling through
-- the `dec [hl]`, so the bonus stacks on top of the first step.
S.EFFECT_HEAL_BELL = function(ctx, st)
  if st.enemyPartyStatus == nil then return 0 end
  if not st.enemyPartyStatus then
    -- .no_status: the party copy can lag the active mon, which is the only way
    -- this test and the one above disagree.
    if st.enemyStatus then return 0 end
    return DISMISS
  end
  local score = 0
  if st.enemyStatus then score = score - 1 end
  if st.enemyStatus == "sleep" or st.enemyStatus == "freeze" then
    if chance(ctx.random, 50) then return score end
    score = score - 2
  end
  return score
end

-- AI_Smart_Thief: `ld a, [hl] / add $1e`.  Three times a dismissal, so Thief is
-- only ever picked when nothing else is left.
S.EFFECT_THIEF = function()
  return 30
end

-- AI_Smart_MeanLook.  Needs the enemy above half HP and the player holding
-- something in reserve (trapping the player's last mon is dismissed outright).
-- 80% to greatly encourage against a player who is already suffering, else
-- discourage unless CheckPlayerMoveTypeMatchups says the player has nothing
-- effective to answer with.
-- CART BUG (docs/bugs_and_glitches.md): the badly-poisoned test reads
-- wEnemySubStatus5, so the AI encourages Mean Look when IT is the poisoned one.
S.EFFECT_MEAN_LOOK = function(ctx, st)
  local encourage = false
  if fraction(st.enemyHp, st.enemyMaxHp, 0.5) then
    if st.playerLastMon then return DISMISS end
    if st.enemyToxic then
      encourage = true
    elseif st.playerInLove or st.playerRollout or st.playerIdentified
        or st.playerNightmare then
      encourage = true
    elseif (st.playerMatchupScore or Ai.BASE_SWITCH_SCORE)
        >= Ai.BASE_SWITCH_SCORE + 1 then
      return 0
    end
  end
  if not encourage then return 1 end
  if chance(ctx.random, 20) then return 0 end
  return -3
end

-- AI_Smart_Nightmare: a flat coin flip.  AI_Basic is what keeps it off a
-- target that is not asleep.
S.EFFECT_NIGHTMARE = function(ctx)
  if chance(ctx.random, 50) then return 0 end
  return -1
end

-- AI_Smart_FlameWheel: five steps of encouragement when the enemy is frozen,
-- because Flame Wheel and Sacred Fire thaw their own user in Gen 2.  Its status
-- read really is the enemy's own, unlike AI_Smart_DefrostOpponent's.
S.EFFECT_FLAME_WHEEL = function(_, st)
  if st.enemyStatus ~= "freeze" then return 0 end
  return -5
end

-- Curse (AI_Smart_Curse).  A Ghost type enemy pays half its HP for a residual,
-- so that half of the routine wants a healthy enemy, an uncursed target and the
-- target's very first turn; the non-Ghost half is an Attack boost and wants a
-- target it can actually punch, meaning neither of its types is special.
S.EFFECT_CURSE = function(ctx, st)
  local enemyTypes = st.enemyTypes or {}
  local playerTypes = st.playerTypes or {}
  if enemyTypes[1] == "GHOST" or enemyTypes[2] == "GHOST" then
    -- .ghost_curse: dismissed at or below 25% (the cut would be suicide), and
    -- discouraged at or below 50%.
    if not fraction(st.enemyHp, st.enemyMaxHp, 0.25) then return DISMISS end
    if not fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 1 end
    if st.playerCursed then return DISMISS end
    if (st.playerTurns or 0) > 0 then return 0 end
    if chance(ctx.random, 50) then return 0 end
    return -2
  end
  if not fraction(st.enemyHp, st.enemyMaxHp, 0.5) then return 1 end
  -- wEnemyAtkLevel against BASE_STAT_LEVEL + 4 and + 2: at +4 the boost is
  -- discouraged outright, at +2 the AI simply has no opinion left.
  local attack = st.stages and st.stages.attack or 0
  if attack >= 4 then return 1 end
  if attack >= 2 then return 0 end
  -- `cp GHOST` comes before `cp SPECIAL`, and `.greatly_discourage` falls
  -- THROUGH into `.discourage`, so a Ghost FIRST type is +2, not +1.
  if playerTypes[1] == "GHOST" then return 2 end
  if st.playerSpecialType then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -2
end

-- Foresight (AI_Smart_Foresight).  Worth 61% encouragement when the accuracy
-- war has already been lost (enemy accuracy at -3, player evasion at +3) or
-- when the target is a Ghost the enemy's Normal and Fighting moves cannot
-- touch; a flat 92% discouragement otherwise.
S.EFFECT_FORESIGHT = function(ctx, st)
  local playerTypes = st.playerTypes or {}
  local encourage = (st.stages and st.stages.accuracy or 0) <= -3
    or (st.playerStages and st.playerStages.evasion or 0) >= 3
    or playerTypes[1] == "GHOST" or playerTypes[2] == "GHOST"
  if not encourage then
    if chance(ctx.random, 8) then return 0 end
    return 1
  end
  if chance(ctx.random, 39) then return 0 end
  return -2
end

-- Perish Song (AI_Smart_PerishSong).  FindAliveEnemyMons first: with nothing on
-- the bench the countdown kills the enemy too, which is worth five points of
-- discouragement.  A trapped player cannot run from it, so that is the one case
-- the cart encourages; otherwise it is only left alone while the AI is losing
-- the matchup and would rather rotate out anyway.
S.EFFECT_PERISH_SONG = function(ctx, st)
  if st.enemyHasBench == false then return 5 end
  if st.playerTrapped then
    if chance(ctx.random, 50) then return 0 end
    return -1
  end
  local score = st.playerMatchupScore or Ai.BASE_SWITCH_SCORE
  if score < Ai.BASE_SWITCH_SCORE then return 0 end
  if chance(ctx.random, 50) then return 0 end
  return 1
end

-- AI_Smart_Sandstorm's own .SandstormImmuneTypes, walked with IsInArray once
-- per type slot.
local SANDSTORM_IMMUNE = { ROCK = true, GROUND = true, STEEL = true }

-- Sandstorm (AI_Smart_Sandstorm).  Greatly discouraged against anything that
-- shrugs the chip off (`.greatly_discourage` falls through into `.discourage`,
-- hence +2), discouraged once the target is at or below half (the chip will not
-- decide the fight any more), a coin flip otherwise.
S.EFFECT_SANDSTORM = function(ctx, st)
  local playerTypes = st.playerTypes or {}
  if SANDSTORM_IMMUNE[playerTypes[1] or ""]
      or SANDSTORM_IMMUNE[playerTypes[2] or ""] then
    return 2
  end
  if not fraction(st.playerHp, st.playerMaxHp, 0.5) then return 1 end
  if chance(ctx.random, 50) then return 0 end
  return -1
end

-- Swagger (AI_Smart_Swagger) jumps straight into AI_Smart_Attract: both are
-- openers, 80% encouraged on the target's first turn and 80% discouraged after.
S.EFFECT_SWAGGER = S.EFFECT_ATTRACT

-- Safeguard (AI_Smart_Safeguard).  80% discouraged once the PLAYER is at or
-- below half HP: the cart reads the player's bar, not the enemy's, on the
-- theory that a nearly dead target is not going to status anything.
-- AICheckPlayerHalfHP sets carry when the player is ABOVE half and the routine
-- is `ret c`, so this layer only ever discourages.
S.EFFECT_SAFEGUARD = function(ctx, st)
  if fraction(st.playerHp, st.playerMaxHp, 0.5) then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return 1
end

-- Magnitude (AI_Smart_Magnitude), which AI_Smart_Earthquake shares outright.
-- It only ever fires when the player's last move was Dig: greatly encouraged if
-- the player is underground right now and the enemy moves first, and a coin
-- flip when the player has surfaced but the enemy is SLOWER, which is the
-- cart's guess that the player is about to dig again.  The two speed tests are
-- opposite senses of the same AICompareSpeed carry.
local function smartEarthquake(ctx, st)
  if st.playerLastMove ~= "DIG" then return 0 end
  if st.playerUnderground then
    if not st.enemyFaster then return 0 end
    return -2
  end
  -- .could_dig
  if st.enemyFaster then return 0 end
  if chance(ctx.random, 50) then return 0 end
  return -1
end
S.EFFECT_MAGNITUDE = smartEarthquake

-- Baton Pass (AI_Smart_BatonPass) is AI_Smart_ForceSwitch's body again: the
-- cart never looks at what the enemy would actually be passing.
S.EFFECT_BATON_PASS = switchMatchup

-- Pursuit (AI_Smart_Pursuit).  50% chance to greatly encourage it once the
-- target is at or below 25% and likely to run or rotate; 80% discouraged
-- otherwise, since at full HP it is just a 40 power Dark move.
S.EFFECT_PURSUIT = function(ctx, st)
  if not fraction(st.playerHp, st.playerMaxHp, 0.25) then
    if chance(ctx.random, 50) then return 0 end
    return -2
  end
  if chance(ctx.random, 20) then return 0 end
  return 1
end

-- Rapid Spin (AI_Smart_RapidSpin).  80% chance to greatly encourage it when it
-- would actually clear something off the ENEMY's own side: a Bind style trap,
-- Leech Seed, or Spikes.  No opinion at all otherwise.
S.EFFECT_RAPID_SPIN = function(ctx, st)
  if not (st.enemyWrapped or st.enemyLeechSeed or st.enemySpikes) then
    return 0
  end
  if chance(ctx.random, 20) then return 0 end
  return -2
end

-- AI_Smart_MorningSun, AI_Smart_Synthesis and AI_Smart_Moonlight are three more
-- labels on AI_Smart_Heal's body.  The cart makes no weather check at all here,
-- even though the three moves heal different fractions by weather.
S.EFFECT_MORNING_SUN = healSelf
S.EFFECT_SYNTHESIS = healSelf
S.EFFECT_MOONLIGHT = healSelf

-- Hidden Power (AI_Smart_HiddenPower): the cart throws away the Normal-type
-- stub in the move table and recomputes the move's real type and base power
-- from the enemy's DVs (HiddenPowerDamage), then scores THAT.  Resisted, or
-- under 50 power, is discouraged; super effective, or a full 70 power at
-- neutral, is encouraged.  The `matchup` argument the layer passes in is
-- deliberately unused: it is the declared type's, which is what the cart
-- discards.
S.EFFECT_HIDDEN_POWER = function(_, st)
  local power, matchup = st.hiddenPowerPower, st.hiddenPowerMatchup
  if not (power and matchup) then return 0 end
  -- cp EFFECTIVE: not very effective, or immune, is `.bad`.
  if matchup < 10 then return 1 end
  if power < 50 then return 1 end
  -- cp EFFECTIVE + 1: super effective is `.good` whatever the power is.
  if matchup > 10 then return -1 end
  if power < 70 then return 0 end
  return -1
end

-- Rain Dance and Sunny Day share AI_Smart_WeatherMove and its two tails,
-- AIBadWeatherType (three inc [hl]) and AIGoodWeatherType (two dec [hl]).
-- The player's type slots are read IN ORDER, bad then good per slot, so a
-- Fire/Water target reads as "good" for Rain Dance where a Water/Fire one reads
-- as "bad": that ordering is load bearing, do not fold it into a set.
local function weatherTypeVerdict(types, badType, goodType)
  for i = 1, 2 do
    local slot = (types or {})[i]
    if slot == badType then return "bad" end
    if slot == goodType then return "good" end
  end
  return nil
end

-- AIBadWeatherType.
local BAD_WEATHER = 3

-- AIGoodWeatherType: the weather would disfavour the player type-wise, so set
-- it up while the player is still above half, and only while one of the two
-- mons is still on its first turn.
local function goodWeatherType(_, st)
  if not fraction(st.playerHp, st.playerMaxHp, 0.5) then return 0 end
  if (st.playerTurns or 0) == 0 then return -2 end
  if (st.enemyTurns or 0) ~= 0 then return 0 end
  return -2
end

-- AI_Smart_WeatherMove: greatly discouraged unless the enemy actually knows a
-- move off the matching list, and again once the player is at or below half; a
-- coin flip encourages it otherwise.
local function weatherMove(ctx, st, moves)
  if not st.enemyMoveIds then return 0 end
  local hasOne = false
  for _, id in ipairs(moves) do
    if st.enemyMoveIds[id] then hasOne = true break end
  end
  if not hasOne then return BAD_WEATHER end
  if not fraction(st.playerHp, st.playerMaxHp, 0.5) then return BAD_WEATHER end
  if chance(ctx.random, 50) then return 0 end
  return -1
end

-- data/battle/ai/rain_dance_moves.asm, in list order.
local RAIN_DANCE_MOVES = {
  "WATER_GUN", "HYDRO_PUMP", "SURF", "BUBBLEBEAM", "THUNDER", "WATERFALL",
  "CLAMP", "BUBBLE", "CRABHAMMER", "OCTAZOOKA", "WHIRLPOOL",
}

-- Rain Dance (AI_Smart_RainDance): greatly discouraged against a Water-type (it
-- would hand the player the boost), taken eagerly against a Fire-type, and
-- otherwise only worth it when the enemy has something on RainDanceMoves to
-- spend the weather on.
S.EFFECT_RAIN_DANCE = function(ctx, st)
  local verdict = weatherTypeVerdict(st.playerTypes, "WATER", "FIRE")
  if verdict == "bad" then return BAD_WEATHER end
  if verdict == "good" then return goodWeatherType(ctx, st) end
  return weatherMove(ctx, st, RAIN_DANCE_MOVES)
end

-- data/battle/ai/sunny_day_moves.asm, in list order.  CART BUG, kept: the list
-- leaves out SOLARBEAM, FLAME_WHEEL and MOONLIGHT, so the AI never encourages
-- Sunny Day for the three moves that want it most
-- (docs/bugs_and_glitches.md).
local SUNNY_DAY_MOVES = {
  "FIRE_PUNCH", "EMBER", "FLAMETHROWER", "FIRE_SPIN", "FIRE_BLAST",
  "SACRED_FIRE", "MORNING_SUN", "SYNTHESIS",
}

-- Sunny Day (AI_Smart_SunnyDay): the mirror of Rain Dance, Fire-type bad and
-- Water-type good, sharing AI_Smart_WeatherMove by fallthrough in the cart.
S.EFFECT_SUNNY_DAY = function(ctx, st)
  local verdict = weatherTypeVerdict(st.playerTypes, "FIRE", "WATER")
  if verdict == "bad" then return BAD_WEATHER end
  if verdict == "good" then return goodWeatherType(ctx, st) end
  return weatherMove(ctx, st, SUNNY_DAY_MOVES)
end

-- Psych Up copies the player's stat levels, so it is only worth it when the
-- player is the one who has been setting up: AI_Smart_PsychUp sums both sides
-- and discourages when the enemy is already ahead.
-- Two cart quirks, both kept.  The sums walk NUM_LEVEL_STATS = 8 entries, one
-- past EVASION into the ABILITY slot BattleCommand_Curse uses; both sides read
-- the same slot, so the comparison is unchanged and the Lua sums the seven real
-- stages.  And the encouraging tail asks for a player evasion that is both at
-- least +2 and below +1, so its 80% dec [hl] is dead code the cart itself
-- flags: this handler can only ever return +1 or 0.
S.EFFECT_PSYCH_UP = function(ctx, st)
  local mine, theirs = st.stages, st.playerStages
  if not (mine and theirs) then return 0 end
  local enemySum, playerSum = 0, 0
  for _, key in ipairs(STAGE_KEYS) do
    enemySum = enemySum + (mine[key] or 0)
    playerSum = playerSum + (theirs[key] or 0)
  end
  if enemySum >= playerSum then return 1 end
  if (theirs.accuracy or 0) < -1 then return 0 end
  if (theirs.evasion or 0) < 2 then return 0 end
  -- Never reached: evasion cannot be at least +2 and below +1 at once.
  if (theirs.evasion or 0) >= 1 then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -1
end

-- Mirror Coat answers special damage, so AI_Smart_MirrorCoat counts how many of
-- the moves the player has ACTUALLY used are special AND do damage.  Three or
-- more is enough on its own; one or two only counts when the player's last move
-- was special damage too; none at all is discouraged outright.  This is
-- AI_Smart_Counter's routine with `jr c` and `jr nc` swapped on the type test.
S.EFFECT_MIRROR_COAT = function(ctx, st, _, _, playerLastPower)
  local special = st.playerSpecialMoves
  if special == nil then return 0 end
  if special == 0 then return 1 end
  local encourage = special >= 3
  if not encourage then
    encourage = st.playerLastMove ~= nil and (playerLastPower or 0) > 0
      and st.playerLastMoveSpecial == true
  end
  if not encourage then return 0 end
  if chance(ctx.random, 39) then return 0 end
  return -1
end

-- Twister and Gust share one body (AI_Smart_Twister falls straight into
-- AI_Smart_Gust): both hit a target that is up in the air, so the cart only
-- looks at them when the player's last move was Fly.  Already flying and slower
-- than the enemy is a free double hit; still on the ground is a coin flip on
-- predicting the Fly, and only from behind, since going second is what lands
-- the hit.  This reads SUBSTATUS_FLYING specifically, not the FLYING|UNDERGROUND
-- mask st.playerFlying carries.
local function smartGust(ctx, st)
  if st.playerLastMove ~= "FLY" then return 0 end
  if st.playerFlyingUp then
    if not st.enemyFaster then return 0 end
    return -2
  end
  -- .couldFly: try to predict the Fly this turn.
  if st.enemyFaster then return 0 end
  if chance(ctx.random, 50) then return 0 end
  return -1
end
S.EFFECT_TWISTER = smartGust

-- AI_Smart_Earthquake is the label AI_Smart_Magnitude sits on.
S.EFFECT_EARTHQUAKE = smartEarthquake

-- Future Sight (AI_Smart_FutureSight) lands a turn late, which is exactly when
-- a player who is flying or underground comes back down.  The cart checks the
-- speed first here and the substatus first in AI_Smart_Fly; same answer either
-- way, and both read the combined FLYING|UNDERGROUND mask.
S.EFFECT_FUTURE_SIGHT = function(_, st)
  if not st.enemyFaster then return 0 end
  if not st.playerFlying then return 0 end
  return -2
end

-- AI_Smart_Gust shares AI_Smart_Twister's body; see smartGust above.
S.EFFECT_GUST = smartGust

-- Stomp (AI_Smart_Stomp) doubles against a minimized target, so an 80%
-- encourage once the player has used Minimize at all.
S.EFFECT_STOMP = function(ctx, st)
  if not st.playerMinimized then return 0 end
  if chance(ctx.random, 20) then return 0 end
  return -1
end

-- SolarBeam (AI_Smart_Solarbeam) skips its charge turn in sun and is halved in
-- rain, and the cart scores exactly that: 80% to greatly encourage while the
-- sun is out, 90% to greatly discourage while it is raining, no opinion in
-- anything else.
S.EFFECT_SOLARBEAM = function(ctx, st)
  if st.weather == "sun" then
    if chance(ctx.random, 20) then return 0 end
    return -2
  end
  if st.weather ~= "rain" then return 0 end
  if chance(ctx.random, 10) then return 0 end
  return 2
end

-- Thunder (AI_Smart_Thunder) drops to 50% accuracy in sun, so a 90% chance to
-- discourage it while the sun is out.  The cart scores nothing at all for rain,
-- even though Thunder never misses then: that asymmetry is the routine as
-- written.
S.EFFECT_THUNDER = function(ctx, st)
  if st.weather ~= "sun" then return 0 end
  if chance(ctx.random, 10) then return 0 end
  return 1
end

-- Fly and Dig, both EFFECT_FLY (AI_Smart_Fly): a semi-invulnerable player is
-- about to come back down, so a FASTER enemy can start its own two-turn move
-- now and land it as the player reappears.  Three dec [hl], the layer's
-- strongest push.  AICompareSpeed returns carry when the ENEMY is faster and
-- the routine is `ret nc`, which reads backwards against the cart's own comment.
S.EFFECT_FLY = function(_, st)
  if not st.playerFlying then return 0 end
  if not st.enemyFaster then return 0 end
  return -3
end

--------------------------------------------------------------------------
-- The switch / item layer (engine/battle/ai/items.asm, switch.asm)
--------------------------------------------------------------------------
--
-- TRNATTR_AI_ITEM_SWITCH is bytes 6-7 of the class attributes.  Three flags
-- decide how eager the class is to rotate; CheckAbleToSwitch scores the bench
-- and the flag turns that score into a probability.

Ai.SWITCH_FLAGS = {
  OFTEN = 0x0001,
  RARELY = 0x0002,
  SOMETIMES = 0x0004,
}

function Ai.switchFlagsOf(attributes)
  if type(attributes) ~= "table" then return 0 end
  return (attributes[6] or 0) + (attributes[7] or 0) * 256
end

-- CheckAbleToSwitch's answer, as its two nybbles: the high one is how strongly
-- the AI wants to rotate ($10 / $20 / $30) and the low one is the party slot.
-- Perish Song at one turn left is the maximum; otherwise it is whether the
-- player's moves beat what is out and something on the bench does better.
--
-- state:
--   bench        array of { index, mon, resists, superEffective, healthy }
--   perishCount  the active mon's perish counter, or nil
--   matchupScore CheckPlayerMoveTypeMatchups' score (10 is neutral)
function Ai.switchScore(state)
  state = state or {}
  local candidates = {}
  for _, entry in ipairs(state.bench or {}) do
    if entry.healthy then candidates[#candidates + 1] = entry end
  end
  if #candidates == 0 then return 0, nil end
  if state.perishCount == 1 then
    return 0x30, candidates[1].index
  end
  -- Below BASE_AI_SWITCH_SCORE means the player's moves are winning.
  if (state.matchupScore or 10) >= 10 then return 0, nil end
  local best, weight
  for _, entry in ipairs(candidates) do
    if entry.resists and entry.superEffective then
      best, weight = entry.index, 0x20
      break
    elseif entry.resists and not best then
      best, weight = entry.index, 0x10
    end
  end
  if not best then return 0, nil end
  return weight, best
end

-- The flag turns the score into a roll.  These are the cart's own percentages
-- (SwitchOften / SwitchRarely / SwitchSometimes), and a score of $30 inverts
-- the test: the AI switches UNLESS the roll comes up.
Ai.SWITCH_CHANCES = {
  OFTEN = { [0x10] = 50, [0x20] = 79, [0x30] = 96 },
  SOMETIMES = { [0x10] = 20, [0x20] = 50, [0x30] = 80 },
  RARELY = { [0x10] = 8, [0x20] = 12, [0x30] = 21 },
}

function Ai.shouldSwitch(attributes, score, random)
  if score == 0 then return false end
  local flags = Ai.switchFlagsOf(attributes)
  local name
  for key, mask in pairs(Ai.SWITCH_FLAGS) do
    if math.floor(flags / mask) % 2 == 1 then name = key break end
  end
  if not name then return false end
  local percent = (Ai.SWITCH_CHANCES[name] or {})[score]
  if not percent then return false end
  return ((random and random(100) or 0) + 1) <= percent
end

-- AI_TryItem's table, in the order the cart walks it: the first item the
-- trainer holds whose condition is met is the one used.  A trainer only uses
-- an item at all when its active mon is its highest-level one (.IsHighestLevel).
Ai.ITEM_ORDER = {
  "FULL_RESTORE", "MAX_POTION", "HYPER_POTION", "SUPER_POTION", "POTION",
  "X_ACCURACY", "FULL_HEAL", "GUARD_SPEC", "DIRE_HIT", "X_ATTACK",
  "X_DEFEND", "X_SPEED", "X_SPECIAL",
}

Ai.HEAL_ITEMS = {
  FULL_RESTORE = math.huge, MAX_POTION = math.huge,
  HYPER_POTION = 200, SUPER_POTION = 50, POTION = 20,
}

-- The healing items want the mon below half and missing at least what they
-- would restore; FULL_HEAL wants a status.  Everything else is a stat booster
-- and is used on the first turn.
function Ai.chooseItem(state)
  state = state or {}
  local held = {}
  for _, id in ipairs(state.items or {}) do held[id] = true end
  if not state.isHighestLevel then return nil end
  local hp, maxHp = state.hp or 0, state.maxHp or 1
  for _, id in ipairs(Ai.ITEM_ORDER) do
    if held[id] then
      local heal = Ai.HEAL_ITEMS[id]
      if heal then
        if hp * 2 <= maxHp and (maxHp - hp) >= math.min(heal, maxHp) / 2 then
          return id
        end
      elseif id == "FULL_HEAL" then
        if state.status then return id end
      elseif (state.enemyTurns or 0) == 0 then
        return id
      end
    end
  end
  return nil
end

--------------------------------------------------------------------------
-- The scoring layers, as ai_classes records
--------------------------------------------------------------------------
--
-- One record per AI_* pass of engine/battle/ai/scoring.asm, in the shape
-- src/mods/Schemas.lua's `ai_classes` registry validates.  Same registry NAME
-- Gen 1 fills from src/battle/TrainerAI.lua, the same `kind = "layer"`, and
-- the same score signature fn(view, def, score) -> score -- Gen 1's LAYER_1..
-- LAYER_3 and these ten are the same kind of thing, so they share the noun.
--
-- The ids are the TRNATTR_AI_MOVE_WEIGHTS flag names, which is what makes them
-- addressable: `flag` names the bit in Ai.FLAGS that turns the layer on, so a
-- class with no bits set runs no layers at all -- AIChooseMove's own answer
-- when wEnemyTrainerAIFlags is zero.  `flag` is the one field Gen 2 adds; a
-- mod's own layer may leave it out, and then it runs for every class that runs
-- any AI at all.
--
-- `view` is the state a layer scores against, rebuilt per move by Ai.choose:
--   context / random / flags     the caller's own
--   attacker / defender          the two mons, types resolved
--   move / damage / damaging / status   the move being scored
--   best                         the highest expected damage of the set
Ai.LAYERS = {
  -- AI_Basic: never throw a status move at a target that already has one, and
  -- never use a move whose only effect has already landed.  The confusion
  -- moves read SUBSTATUS_CONFUSED (defender.confused), not the status byte,
  -- since confusion is a volatile on the cart.
  BASIC = { kind = "layer", flag = "BASIC",
    score = function(view, _, score)
      local status, defender = view.status, view.defender
      if status and (defender.status
          or (status == "confuse" and defender.confused)) then
        return score + 5
      end
      return score
    end },
  -- AI_Types: dismiss what the target is immune to, encourage super-effective,
  -- discourage not very effective.
  TYPES = { kind = "layer", flag = "TYPES",
    score = function(view, def, score)
      if not view.damaging then return score end
      local matchup = matchupOf(view.context, def, view.defender)
      if matchup == 0 then return score + 10 end
      if matchup > 10 then return score - 1 end
      if matchup < 10 then return score + 1 end
      return score
    end },
  -- AI_Offensive: discourage anything that does not do damage.
  OFFENSIVE = { kind = "layer", flag = "OFFENSIVE",
    score = function(view, _, score)
      if view.damaging then return score end
      return score + 1
    end },
  -- AI_Aggressive: encourage whichever move hits hardest and discourage every
  -- other damaging one.
  AGGRESSIVE = { kind = "layer", flag = "AGGRESSIVE",
    score = function(view, _, score)
      if not view.damaging then return score end
      if view.damage >= view.best and view.best > 0 then return score - 1 end
      return score + 1
    end },
  -- AI_Status: refuse a status move outright against a target that already has
  -- that status.
  STATUS = { kind = "layer", flag = "STATUS",
    score = function(view, _, score)
      if view.status and view.defender.status == view.status then
        return score + 10
      end
      return score
    end },
  -- AI_Risky: take a kill when one is on the table, whatever else says.
  RISKY = { kind = "layer", flag = "RISKY",
    score = function(view, _, score)
      if view.damage >= (view.defender.hp or 0) and view.damage > 0 then
        return score - 5
      end
      return score
    end },
  -- AI_Setup: stat moves on turn one, and almost never after.
  SETUP = { kind = "layer", flag = "SETUP",
    score = function(view, def, score)
      local context, random = view.context, view.random
      local up = Ai.STAT_UP_EFFECTS[def.effect]
      local down = Ai.STAT_DOWN_EFFECTS[def.effect]
      if up then
        if (context.enemyTurns or 0) == 0 and random(2) == 0 then
          return score - 2
        end
        return score + 2
      elseif down then
        if (context.playerTurns or 0) == 0 and random(2) == 0 then
          return score - 2
        end
        return score + 2
      end
      return score
    end },
  -- AI_Opportunist: no stalling when the enemy is nearly dead.
  OPPORTUNIST = { kind = "layer", flag = "OPPORTUNIST",
    score = function(view, def, score)
      if not Ai.STALL_EFFECTS[def.effect] then return score end
      local hp, maxHp = view.context.enemyHp, view.context.enemyMaxHp
      if not (hp and maxHp and hp * 2 <= maxHp) then return score end
      local low = hp * 4 <= maxHp
      if low or view.random(2) == 0 then return score + 1 end
      return score
    end },
  -- AI_Cautious: 90% chance to drop a residual move after turn one.
  CAUTIOUS = { kind = "layer", flag = "CAUTIOUS",
    score = function(view, def, score)
      if (view.context.enemyTurns or 0) <= 0 then return score end
      if not Ai.RESIDUAL_EFFECTS[def.effect] then return score end
      if view.random(100) < 90 then return score + 1 end
      return score
    end },
  -- AI_Smart: the per-effect layer.  Ai.lockOnPostPass is its one pass that
  -- edits somebody else's slot, so Ai.choose runs that after the move loop.
  SMART = { kind = "layer", flag = "SMART",
    score = function(view, def, score)
      local handler = Ai.SMART[def.effect]
      if not handler then return score end
      local context, random = view.context, view.random
      local state = context.smart or {}
      state.random = state.random or random
      -- AI_Smart_SpeedDownHit is the one handler that reads the move it is
      -- scoring (wEnemyMoveStruct + MOVE_ANIM), so the id rides along.
      local delta = handler({ random = random, moveId = view.move.id }, state,
        matchupOf(context, def, view.defender), view.damage,
        context.playerLastPower)
      return score + (delta or 0)
    end },
}

-- scoring.asm's own order.  It is load bearing: SETUP, OPPORTUNIST and
-- CAUTIOUS each roll, so a reordering changes which move gets which byte.
Ai.LAYER_ORDER = {
  "BASIC", "TYPES", "OFFENSIVE", "AGGRESSIVE", "STATUS", "RISKY",
  "SETUP", "OPPORTUNIST", "CAUTIOUS", "SMART",
}

-- vanilla registrations, engine-owned (Schemas.ENGINE), so a mod's register of
-- one of these ids collides the way it does on Red and has to say override
function Ai.registerInto(registry, _, owner)
  for id, record in pairs(Ai.LAYERS) do
    registry:register(id, record, owner)
  end
end

-- the merged `ai_classes` record for an id, the module's own when no loader ran
function Ai.classFor(data, id)
  if id == nil then return nil end
  local merged = data and data.gen2AiClasses
  return (merged and merged[id]) or Ai.LAYERS[id]
end

-- The ordered layer list for one AI word: the vanilla ten in scoring.asm order
-- first, each resolved through the registry so a mod's patch of AI_Smart is the
-- one that runs, then any layer a mod registered under a new id, in sorted id
-- order so the roll sequence is the same on every boot.  A layer's `flag` gates
-- it on the class's bits; a mod layer without one runs for every class that
-- runs any AI at all, which is the only honest default when the ten flag bits
-- are all spoken for.
function Ai.layersFor(data, flags)
  local out, seen = {}, {}
  for _, id in ipairs(Ai.LAYER_ORDER) do
    seen[id] = true
    if Ai.has(flags, id) then
      local record = Ai.classFor(data, id)
      if record and record.score then out[#out + 1] = record end
    end
  end
  local merged = data and data.gen2AiClasses
  if merged then
    local extra = {}
    for id, record in pairs(merged) do
      if not seen[id] and record and record.score
          and (record.kind == nil or record.kind == "layer")
          and (record.flag == nil or Ai.has(flags, record.flag)) then
        extra[#extra + 1] = id
      end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do out[#out + 1] = merged[id] end
  end
  return out
end

-- context:
--   moves        array of { id, pp } the enemy may use
--   moveDef(id)  the move record
--   attacker     the enemy mon, with .types resolved
--   defender     the player's mon, with .types resolved
--   typeChart    { types, matchups }
--   attackerStages / defenderStages
--   flags        the class's AI word
--   random(n)    0..n-1
--
-- Returns the chosen move id, plus the score table for the tests to read.
function Ai.choose(context)
  local moves = {}
  for _, move in ipairs(context.moves or {}) do
    if (move.pp or 0) > 0 then moves[#moves + 1] = move end
  end
  if #moves == 0 then return nil, {} end

  local random = context.random or function(n) return 0 end
  local flags = context.flags or 0
  if flags == 0 then
    -- No AI: pick at random, the way a wild mon does.
    return moves[random(#moves) + 1].id, {}
  end

  local attacker, defender = context.attacker or {}, context.defender or {}
  local scores, damages, defs = {}, {}, {}
  local best = -1
  for i, move in ipairs(moves) do
    scores[i] = Ai.BASE_SCORE
    local def = context.moveDef and context.moveDef(move.id) or nil
    defs[i] = def
    damages[i] = def and expectedDamage(context, attacker, defender, def) or 0
    if damages[i] > best then best = damages[i] end
  end

  -- The scoring layers this class runs, resolved once: which records exist is
  -- a property of the boot, not of the move being scored, and the per-move
  -- loop below is hot.
  local layers = Ai.layersFor(context.data, flags)

  local view = {
    context = context, random = random, flags = flags,
    attacker = attacker, defender = defender, best = best,
  }
  for i, move in ipairs(moves) do
    local def = defs[i]
    if def then
      -- the per-move half of the view, rebuilt in place so ten layers share
      -- one table rather than allocating ten
      view.move = move
      view.damage = damages[i]
      view.damaging = (def.power or 0) > 0
      view.status = Ai.STATUS_EFFECTS[def.effect]
      for _, record in ipairs(layers) do
        scores[i] = record.score(view, def, scores[i]) or scores[i]
      end
    end
  end

  -- The one scoring layer that edits somebody else's slot, so it cannot run
  -- inside the per-move pass above.
  if Ai.has(flags, "SMART") and (context.smart or {}).playerLockOn then
    Ai.lockOnPostPass(scores, defs)
  end

  -- Lowest score wins; ties are broken by a roll so a trainer is not perfectly
  -- predictable turn to turn.
  local lowest = math.huge
  for _, score in ipairs(scores) do
    if score < lowest then lowest = score end
  end
  local tied = {}
  for i, score in ipairs(scores) do
    if score == lowest then tied[#tied + 1] = moves[i].id end
  end
  return tied[random(#tied) + 1], scores
end

return Ai
