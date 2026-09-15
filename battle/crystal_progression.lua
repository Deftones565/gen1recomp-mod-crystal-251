local RuntimePatches = require("mods.CRYSTAL_251.lib.runtime_patches")
local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
local Catching = require("mods.CRYSTAL_251.battle.gen2.Catching")
local Runtime = require("src.mods.Runtime")
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

local STATUS = {SLP="sleep",FRZ="freeze",BRN="burn",PSN="poison",PAR="paralyze"}
function Progression.catchOptions(battle, ball, target, targetDef, rateOverride)
  local player = battle and battle.player and battle.player.mon or {}
  target, targetDef = target or {}, targetDef or {}
  local dex = targetDef.dexEntry or {}
  return {
    ball=ball, hp=target.hp, maxHp=target.stats and target.stats.hp,
    catchRate=rateOverride or targetDef.catchRate or 45,
    status=STATUS[target.status] or target.status,
    weight=dex.weight or (dex.weightKg and math.floor(dex.weightKg / 0.045359237 + 0.5)),
    level=target.level, playerLevel=player.level,
    species=target.species, playerSpecies=player.species,
    gender=monGender(target), playerGender=monGender(player),
    fishing=battle and battle.crystalFishing,
    random=function(n) return battle.rng(0,n-1) end,
  }
end

function Progression.modifiedCatchRate(battle, ball, target, targetDef, rateOverride)
  local opts=Progression.catchOptions(battle,ball,target,targetDef,rateOverride)
  local record=Catching.recordFor(ball)
  local rate=opts.catchRate
  if record and record.specialty then rate=record.specialty(rate,opts)
  elseif record and record.multiplier then rate=rate*record.multiplier end
  return clamp(rate,1,255)
end

function Progression.finalCatchRate(battle, ball, target, targetDef, rateOverride)
  return Catching.rate(Progression.catchOptions(battle,ball,target,targetDef,rateOverride))
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
  local function attempt(_,mon,def,o)
    local converted=Progression.catchOptions(battle,ball,mon,def,o.rateOverride)
    converted.random=function(n) return (o.rng or battle.rng)(0,n-1) end
    local caught,rate=Catching.vanillaAttempt(converted)
    battle.crystalFinalCatchRate=rate
    return caught,caught and 3 or Progression.wobbleCount(rate,o.rng or battle.rng)
  end
  if Runtime.wantsHook("catch.rate") then
    return Runtime.call("catch.rate",attempt,ball,target,targetDef,
      {rng=battle.rng,rateOverride=rateOverride,battle=battle})
  end
  return attempt(ball,target,targetDef,{rng=battle.rng,rateOverride=rateOverride})
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
    mapId = battle.game and battle.game.overworld and battle.game.overworld.map
      and battle.game.overworld.map.id,
    ball = battle.lastBall,
    location = battle.crystalCaughtLocation or 0,
    time = battle.crystalCaughtTime or 0,
  }
end

local function expContext(mon, fn, landmark)
  local old = mon._crystal251ExpContext
  local oldLandmark = mon._crystal251ExpLandmark
  mon._crystal251ExpContext = true
  mon._crystal251ExpLandmark = landmark
  local ok, a, b = pcall(fn)
  mon._crystal251ExpContext = old
  mon._crystal251ExpLandmark = oldLandmark
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
    return expContext(mon, function() return ctx.applyShare(mon, split, announce) end,
      battle.game and battle.game.overworld and battle.game.overworld.map
        and battle.game.overworld.map.id)
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
  local BattleState = RuntimePatches.watch(require("src.battle.BattleState"))
  local Experience = RuntimePatches.watch(require("src.battle.Experience"))
  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  local ItemEffects = require("src.inventory.ItemEffects")

  local itemBalls = RuntimePatches.watch(ItemEffects.BALLS)
  for id in pairs(BALLS) do itemBalls[id] = true end

  if not Experience._crystal251ProgressionBridge then
    Experience._crystal251ProgressionBridge = true
    local originalApply = Experience.apply
    Experience.apply = function(data, mon, defeatedDef, level, isTrainer,
                                numParticipants, traded, opts)
      if not mon._crystal251ExpContext then
        return originalApply(data, mon, defeatedDef, level, isTrainer,
          numParticipants, traded, opts)
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
      local levels, steps = {}, {}
      local newLevel = Growth.levelForExp(speciesDef.growthRate, mon.exp, cap,
        data.growth_rates)
      local from = opts and opts.from
      local lv, stats, hp = mon.level, mon.stats, mon.hp
      if from then lv, stats, hp = from.level, from.stats, from.hp end
      while lv < math.min(newLevel, cap) do
        lv = lv + 1
        local old = stats
        stats = Stats.calc(speciesDef, lv, mon.dvs, mon.statExp)
        hp = math.min(stats.hp, hp + (stats.hp - old.hp))
        local step = {level=lv, stats=stats, hp=hp,
          crystalFriendshipEvent=Happiness.levelUpEvent(mon, mon._crystal251ExpLandmark)}
        levels[#levels + 1] = lv
        steps[#steps + 1] = step
        if not (opts and opts.defer) then
          Experience.commit(data, mon, step)
        end
      end
      return levels, gained, steps
    end
    local originalCommit = Experience.commit
    Experience.commit = function(data, mon, step)
      if step.crystalFriendshipEvent then
        Happiness.change(mon, step.crystalFriendshipEvent)
      end
      return originalCommit(data, mon, step)
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

return RuntimePatches.installers(Progression)
