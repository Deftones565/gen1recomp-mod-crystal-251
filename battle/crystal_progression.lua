local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
local Happiness = require("mods.CRYSTAL_251.core.gen2.Happiness")

local Progression = {}
Progression.Happiness = Happiness

function Progression.ensureHappiness(mon)
  if type(mon) ~= "table" or mon.isEgg then return end
  if mon.happiness == nil then mon.happiness = Happiness.BASE end
end

local BALLS = {
  MASTER_BALL=true, ULTRA_BALL=true, GREAT_BALL=true, POKE_BALL=true,
  HEAVY_BALL=true, LEVEL_BALL=true, LURE_BALL=true, FAST_BALL=true,
  FRIEND_BALL=true, MOON_BALL=true, LOVE_BALL=true,
  SAFARI_BALL=true,
}
Progression.BALLS = BALLS

local WOBBLE = {
  {1,63},{2,75},{3,84},{4,90},{5,95},{7,103},{10,113},{15,126},
  {20,134},{30,149},{40,160},{50,169},{60,177},{80,191},{100,201},
  {120,211},{140,220},{160,227},{180,234},{200,240},{220,246},
  {240,251},{254,253},{255,255},
}
Progression.WOBBLE = WOBBLE

Progression.setGenderRatio = Gender.setRatio

local function clamp(value, low, high)
  value = math.floor(tonumber(value) or 0)
  if value < low then return low end
  if value > high then return high end
  return value
end

local monGender = Gender.forMon
Progression.monGender = monGender

local function weightKg(def)
  local dex = def and def.dexEntry
  if not dex then return 0 end
  if dex.weightKg then return dex.weightKg end
  return (tonumber(dex.weight) or 0) * 0.045359237
end

local function multiplyRate(rate, multiplier)
  return clamp(math.floor(rate * multiplier), 1, 255)
end

function Progression.modifiedCatchRate(battle, ball, target, targetDef, rateOverride)
  local rate = clamp(rateOverride or (targetDef and targetDef.catchRate) or 0, 1, 255)
  local player = battle and battle.player and battle.player.mon
  if ball == "ULTRA_BALL" then
    rate = multiplyRate(rate, 2)
  elseif ball == "GREAT_BALL" or ball == "SAFARI_BALL" then
    rate = multiplyRate(rate, 1.5)
  elseif ball == "HEAVY_BALL" then
    local kg = weightKg(targetDef)
    local delta = kg < 102.4 and -20 or kg < 204.8 and 0
      or kg < 307.2 and 20 or kg < 409.6 and 30 or 40
    rate = clamp(rate + delta, 1, 255)
  elseif ball == "LURE_BALL" and battle and battle.crystalFishing then
    rate = multiplyRate(rate, 3)
  elseif ball == "FAST_BALL" then
    local species = target and target.species
    if species == "MAGNEMITE" or species == "GRIMER" or species == "TANGELA" then
      rate = multiplyRate(rate, 4)
    end
  elseif ball == "LOVE_BALL" and player and target
      and player.species == target.species then
    local a, b = monGender(player), monGender(target)
    if a and a == b then rate = multiplyRate(rate, 8) end
  elseif ball == "LEVEL_BALL" and player and target then
    local p, e = player.level or 1, target.level or 1
    if math.floor(p / 4) > e then rate = multiplyRate(rate, 8)
    elseif math.floor(p / 2) > e then rate = multiplyRate(rate, 4)
    elseif p > e then rate = multiplyRate(rate, 2) end
  end
  return rate
end

function Progression.finalCatchRate(battle, ball, target, targetDef, rateOverride)
  local rate = Progression.modifiedCatchRate(battle, ball, target, targetDef, rateOverride)
  if ball == "LEVEL_BALL" then return rate end
  local maxhp = math.max(1, target and target.stats and target.stats.hp or 1)
  local hp = clamp(target and target.hp or maxhp, 0, maxhp)
  local value = math.floor((3 * maxhp - 2 * hp) * rate / (3 * maxhp))
  value = math.max(1, value)
  if target and (target.status == "SLP" or target.status == "FRZ") then
    value = value + 10
  end
  return clamp(value, 1, 255)
end

function Progression.wobbleCount(finalRate, rng)
  local probability = 255
  for _, row in ipairs(WOBBLE) do
    if finalRate <= row[1] then probability = row[2] break end
  end
  local shakes = 0
  for _ = 1, 3 do
    if rng(0,255) >= probability then break end
    shakes = shakes + 1
  end
  return shakes
end

function Progression.catchAttempt(battle, ball, target, targetDef, rateOverride)
  if ball == "MASTER_BALL" or battle.crystalTutorialCatch then return true, 3 end
  local finalRate = Progression.finalCatchRate(battle, ball, target, targetDef, rateOverride)
  battle.crystalFinalCatchRate = finalRate
  local caught = battle.rng(0,255) <= finalRate
  return caught, caught and 3 or Progression.wobbleCount(finalRate, battle.rng)
end

local function transformed(battler)
  return battler and (battler.transformed
    or (battler.crystal251Battle and battler.crystal251Battle.transformed)
    or battler.transformedSpecies ~= nil)
end

function Progression.prepareCaughtMon(battle)
  local mon = battle and battle.enemy and battle.enemy.mon
  if not mon then return end
  if transformed(battle.enemy) then mon.species = "DITTO" end
  Progression.ensureHappiness(mon)
  if battle.lastBall == "FRIEND_BALL" then mon.happiness = 200 end
  mon.caughtData = {
    level = mon.level,
    ball = battle.lastBall,
    location = battle.crystalCaughtLocation or 0,
    time = battle.crystalCaughtTime or 0,
  }
end

local function expContext(mon, fn)
  local old = mon._crystal251ExpContext
  mon._crystal251ExpContext = true
  local ok, a, b = pcall(fn)
  mon._crystal251ExpContext = old
  if not ok then error(a, 0) end
  return a, b
end

local function noExperienceBattle(battle)
  return battle.kind == "link" or battle.linkRole ~= nil
    or battle.battleTower or battle.inBattleTowerBattle
    or battle.crystalBattleTower
end
Progression.noExperienceBattle = noExperienceBattle

function Progression.awardExp(next, ctx)
  local battle = ctx and ctx.battle
  if not (battle and battle.crystal251Active) then return next(ctx) end
  -- GiveExperiencePoints returns immediately in link and Battle Tower
  -- battles. Do not delegate to Gen I's award path in those modes.
  if noExperienceBattle(battle) then return end

  local party = (battle.game and battle.game.save
    and battle.game.save.party) or {}
  local partySet, holders, seenHolders = {}, {}, {}
  for _, mon in ipairs(party) do
    if type(mon) == "table" then partySet[mon] = true end
    if type(mon) == "table" and not seenHolders[mon]
        and (tonumber(mon.hp) or 0) > 0 and mon.heldItem == "EXP_SHARE" then
      seenHolders[mon] = true
      holders[#holders + 1] = mon
    end
  end

  -- Crystal divides by wBattleParticipantsNotFainted, not by every mon that
  -- has ever faced this opponent. Rebuild the live participant list so stale
  -- or duplicated context entries cannot dilute the award.
  local participants, seenParticipants = {}, {}
  for _, mon in ipairs(ctx.alive or {}) do
    if partySet[mon] and not seenParticipants[mon]
        and (tonumber(mon.hp) or 0) > 0 then
      seenParticipants[mon] = true
      participants[#participants + 1] = mon
    end
  end
  if #participants == 0 then
    local active = battle.player and battle.player.mon
    if partySet[active] and (tonumber(active.hp) or 0) > 0 then
      participants[1] = active
    end
  end

  local function apply(mon, split, announce)
    return expContext(mon, function() return ctx.applyShare(mon, split, announce) end)
  end
  if #holders == 0 then
    for _, mon in ipairs(participants) do
      apply(mon, math.max(1, #participants), true)
    end
  else
    for _, mon in ipairs(participants) do
      apply(mon, math.max(1, #participants) * 2, true)
    end
    -- This is deliberately a second pass. A living holder that participated
    -- receives both awards, matching Crystal's two GiveExperiencePoints calls.
    for _, mon in ipairs(holders) do apply(mon, #holders * 2, "expShare") end
  end
end

local REWARD = {
  OPP_YOUNGSTER=4, OPP_BUG_CATCHER=4, OPP_LASS=6, OPP_SAILOR=10,
  OPP_JR_TRAINER_M=5, OPP_JR_TRAINER_F=5, OPP_POKEMANIAC=15,
  OPP_SUPER_NERD=8, OPP_HIKER=8, OPP_BIKER=8, OPP_BURGLAR=22,
  OPP_ENGINEER=25, OPP_JUGGLER=10, OPP_FISHER=10, OPP_SWIMMER=5,
  OPP_CUE_BALL=8, OPP_GAMBLER=18, OPP_BEAUTY=22, OPP_PSYCHIC_TR=8,
  OPP_ROCKER=8, OPP_BLACKBELT=6, OPP_CHANNELER=10, OPP_TAMER=15,
  OPP_BIRD_KEEPER=6, OPP_SCIENTIST=25, OPP_GENTLEMAN=18, OPP_ROCKET=10,
  OPP_COOLTRAINER_M=12, OPP_COOLTRAINER_F=12, OPP_RIVAL1=15,
  OPP_RIVAL2=25, OPP_RIVAL3=25, OPP_PROF_OAK=25, OPP_BROCK=25,
  OPP_MISTY=25, OPP_LT_SURGE=25, OPP_ERIKA=25, OPP_KOGA=25,
  OPP_SABRINA=25, OPP_BLAINE=25, OPP_LORELEI=25, OPP_BRUNO=25,
  OPP_AGATHA=25, OPP_LANCE=25, OPP_GIOVANNI=25,
}
Progression.TRAINER_REWARD = REWARD

function Progression.trainerBaseReward(battle)
  return REWARD[battle and battle.oppClass]
    or (battle and battle.trainer and battle.trainer.baseMoney) or 0
end

function Progression.installRuntime()
  local BattleState = require("src.battle.BattleState")
  local Experience = require("src.battle.Experience")
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local Runtime = require("src.mods.Runtime")
  local ItemEffects = require("src.inventory.ItemEffects")

  for id in pairs(BALLS) do ItemEffects.BALLS[id] = true end

  if not Experience._crystal251ProgressionBridge then
    Experience._crystal251ProgressionBridge = true
    local originalApply = Experience.apply
    Experience.apply = function(data, mon, defeatedDef, level, isTrainer,
                                numParticipants, traded)
      if not mon._crystal251ExpContext then
        return originalApply(data, mon, defeatedDef, level, isTrainer,
          numParticipants, traded)
      end
      local share = math.max(1, numParticipants or 1)
      local pokerus = mon.pokerus and mon.pokerus ~= 0
      for _, key in ipairs(Stats.ORDER) do
        local gain = math.floor((defeatedDef.baseStats[key] or 0) / share)
        if pokerus then gain = gain * 2 end
        mon.statExp[key] = math.min(65535, (mon.statExp[key] or 0) + gain)
      end
      local gained = Experience.gainFor(defeatedDef, level, isTrainer,
        share, traded, data.constants)
      if mon.heldItem == "LUCKY_EGG" then gained = math.floor(gained * 1.5) end
      local speciesDef = data.pokemon[mon.species]
      local cap = data.constants and data.constants.levelCap or 100
      local maxExp = Growth.expForLevel(speciesDef.growthRate, cap, data.growth_rates)
      mon.exp = math.min(maxExp, mon.exp + gained)
      local levels = {}
      local newLevel = Growth.levelForExp(speciesDef.growthRate, mon.exp, cap,
        data.growth_rates)
      while mon.level < math.min(newLevel, cap) do
        mon.level = mon.level + 1
        Happiness.levelUp(mon)
        local old = mon.stats
        mon.stats = Stats.calc(speciesDef, mon.level, mon.dvs, mon.statExp)
        mon.hp = math.min(mon.stats.hp, mon.hp + (mon.stats.hp - old.hp))
        levels[#levels + 1] = mon.level
        if Runtime.wants("pokemon.level_up") then
          Runtime.emit("pokemon.level_up", {mon=mon,level=mon.level,
            prevLevel=mon.level-1,
            learnable=Experience.movesLearnedAt(speciesDef,mon.level)})
        end
      end
      return levels, gained
    end
  end

  if BattleState._crystal251ProgressionBridge then return end
  BattleState._crystal251ProgressionBridge = true

  local originalNewWild = BattleState.newWild
  BattleState.newWild = function(game, species, level, opts)
    local battle = originalNewWild(game, species, level, opts)
    battle.crystalFishing = opts and opts.hooked or false
    battle.crystalBattleType = opts and opts.crystalBattleType or nil
    return battle
  end

  local originalCatchAttempt = BattleState.catchAttempt
  BattleState.catchAttempt = function(self, ball, rateOverride)
    if not self.crystal251Active then return originalCatchAttempt(self, ball, rateOverride) end
    return Progression.catchAttempt(self, ball, self.enemy.mon, self.enemy.def, rateOverride)
  end

  local originalStoreCaughtMon = BattleState.storeCaughtMon
  BattleState.storeCaughtMon = function(self, ...)
    if self.crystal251Active then Progression.prepareCaughtMon(self) end
    return originalStoreCaughtMon(self, ...)
  end

  local originalRun = BattleState.runRollVanilla
  BattleState.runRollVanilla = function(self, pSpd, eSpd)
    if not self.crystal251Active then return originalRun(self, pSpd, eSpd) end
    local kind = self.crystalBattleType
    if kind == "debug" or kind == "contest" then return true end
    if kind == "trap" or kind == "celebi" or kind == "force_shiny"
       or kind == "suicune" then return false end
    if self.kind == "trainer" then return false end
    if self.player and (self.player.cantEscape or self.player.crystalTrapTurns) then
      return false
    end
    if pSpd >= eSpd then return true end
    local divisor = math.floor(eSpd / 4) % 256
    if divisor == 0 then return true end
    local value = math.floor(pSpd * 32 / divisor)
      + 30 * math.max(0, (self.runAttempts or 1) - 1)
    return value >= 256 or self.rng(0,255) <= value
  end

  local originalMarkParticipant = BattleState.markParticipant
  BattleState.markParticipant = function(self, ...)
    local result = originalMarkParticipant(self, ...)
    if self.crystal251Active and self.player and self.player.mon
       and self.player.mon.heldItem == "AMULET_COIN" then
      self.crystalAmuletCoin = true
    end
    return result
  end

  local originalEnemyMonFainted = BattleState.enemyMonFainted
  BattleState.enemyMonFainted = function(self, ...)
    if not (self.crystal251Active and self.kind == "trainer"
      and not self.battleTower) then
      return originalEnemyMonFainted(self, ...)
    end
    local last = true
    for _, mon in ipairs(self.enemyParty or {}) do
      if mon ~= self.enemy.mon and (mon.hp or 0) > 0 then last = false break end
    end
    if not last then return originalEnemyMonFainted(self, ...) end
    local old = self.trainer
    local multiplier = self.crystalAmuletCoin and 2 or 1
    self.trainer = setmetatable({baseMoney=Progression.trainerBaseReward(self)*multiplier},
      {__index=old})
    local ok, result = pcall(originalEnemyMonFainted, self, ...)
    self.trainer = old
    if self.game and self.game.save then
      self.game.save.money = math.min(999999, self.game.save.money or 0)
    end
    if not ok then error(result,0) end
    return result
  end

  local originalFinish = BattleState.finish
  BattleState.finish = function(self, ...)
    if self.crystal251Active and self.payDay and self.result == "win"
       and not self._crystalPayDayAdjusted then
      if self.crystalAmuletCoin then self.payDay = self.payDay * 2 end
      self.payDay = math.min(999999, self.payDay)
      self._crystalPayDayAdjusted = true
    end
    local result = originalFinish(self, ...)
    if self.crystal251Active and self.game and self.game.save then
      self.game.save.money = math.min(999999, self.game.save.money or 0)
    end
    return result
  end
end

return Progression
