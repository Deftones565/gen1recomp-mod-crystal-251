local RuntimePatches = require("mods.CRYSTAL_251.lib.runtime_patches")
-- Pokemon Crystal enemy AI for CRYSTAL_251.
--
-- This is a mod-local port of pret/pokecrystal's AIChooseMove scoring layers,
-- damage estimation and AI switching policy.  Every runtime hook is gated by
-- battle.crystal251Active; the base engine's Generation I AI stays untouched.

local CrystalAI = {}

local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
local Gen2AI = require("mods.CRYSTAL_251.battle.gen2.Ai")

local BASE_SCORE = 20
local UNUSABLE_SCORE = 80
local BASE_SWITCH_SCORE = 10

CrystalAI.BASE_SCORE = BASE_SCORE
CrystalAI.UNUSABLE_SCORE = UNUSABLE_SCORE
CrystalAI.BASE_SWITCH_SCORE = BASE_SWITCH_SCORE

local LAYER_ORDER = {
  "basic", "setup", "types", "offensive", "smart",
  "opportunist", "aggressive", "cautious", "status", "risky",
}

-- The Gen I extractor keeps the original effect aliases for compatibility.
-- Translate the effects that Gen 2's released AI actually scores before
-- handing a move to the vendored Gen 2 scorer.
local GEN2_EFFECTS = {
  [1]="EFFECT_SLEEP", [2]="EFFECT_POISON", [3]="EFFECT_LEECH_SEED",
  [4]="EFFECT_BURN", [5]="EFFECT_FREEZE", [6]="EFFECT_PARALYZE",
  [8]="EFFECT_DREAM_EATER", [10]="EFFECT_ATTACK_UP", [11]="EFFECT_DEFENSE_UP",
  [12]="EFFECT_SPEED_UP", [13]="EFFECT_SP_ATK_UP", [14]="EFFECT_SP_DEF_UP",
  [15]="EFFECT_ACCURACY_UP", [16]="EFFECT_EVASION_UP",
  [18]="EFFECT_ATTACK_DOWN", [19]="EFFECT_DEFENSE_DOWN", [20]="EFFECT_SPEED_DOWN",
  [21]="EFFECT_SP_ATK_DOWN", [22]="EFFECT_SP_DEF_DOWN", [23]="EFFECT_ACCURACY_DOWN",
  [24]="EFFECT_EVASION_DOWN", [32]="EFFECT_HEAL", [33]="EFFECT_TOXIC",
  [35]="EFFECT_LIGHT_SCREEN", [46]="EFFECT_MIST", [47]="EFFECT_FOCUS_ENERGY",
  [49]="EFFECT_CONFUSE", [50]="EFFECT_ATTACK_UP_2", [51]="EFFECT_DEFENSE_UP_2",
  [52]="EFFECT_SPEED_UP_2", [53]="EFFECT_SP_ATK_UP_2", [54]="EFFECT_SP_DEF_UP_2",
  [55]="EFFECT_ACCURACY_UP_2", [56]="EFFECT_EVASION_UP_2",
  [58]="EFFECT_ATTACK_DOWN_2", [59]="EFFECT_DEFENSE_DOWN_2", [60]="EFFECT_SPEED_DOWN_2",
  [65]="EFFECT_REFLECT", [79]="EFFECT_SUBSTITUTE", [84]="EFFECT_LEECH_SEED",
  [86]="EFFECT_DISABLE", [94]="EFFECT_ENCORE", [106]="EFFECT_MEAN_LOOK",
  [108]="EFFECT_NIGHTMARE", [109]="EFFECT_CURSE", [111]="EFFECT_PROTECT",
  [112]="EFFECT_SPIKES", [114]="EFFECT_PERISH_SONG", [115]="EFFECT_SANDSTORM",
  [117]="EFFECT_ENDURE", [121]="EFFECT_ATTRACT", [124]="EFFECT_SAFEGUARD",
  [130]="EFFECT_BATON_PASS", [131]="EFFECT_PURSUIT", [132]="EFFECT_RAPID_SPIN",
  [136]="EFFECT_MORNING_SUN", [137]="EFFECT_SYNTHESIS", [138]="EFFECT_MOONLIGHT",
  [140]="EFFECT_RAIN_DANCE", [141]="EFFECT_SUNNY_DAY", [145]="EFFECT_BELLY_DRUM",
  [146]="EFFECT_PSYCH_UP", [147]="EFFECT_MIRROR_COAT", [149]="EFFECT_FUTURE_SIGHT",
}

local AI_FLAG_BY_LAYER = {
  basic="BASIC", setup="SETUP", types="TYPES", offensive="OFFENSIVE",
  smart="SMART", opportunist="OPPORTUNIST", aggressive="AGGRESSIVE",
  cautious="CAUTIOUS", status="STATUS", risky="RISKY",
}

-- Crystal trainer-class attributes mapped onto the Kanto trainer identities
-- used by the recomp.  Bosses/rivals use Crystal's full seven-layer boss AI;
-- ordinary classes use their closest same-named Crystal class.
local FULL = {"basic","setup","smart","aggressive","cautious","status","risky"}
local PROFILES = {
  DEFAULT={layers={"basic","status"},switch="sometimes"},
  OPP_YOUNGSTER={layers={"basic","status"},switch="sometimes"},
  OPP_BUG_CATCHER={layers={"basic","setup","status"},switch="sometimes"},
  OPP_LASS={layers={"basic","cautious","status"},switch="often"},
  OPP_SAILOR={layers={"basic","offensive","opportunist","status"},switch="sometimes"},
  OPP_JR_TRAINER_M={layers={"basic","cautious","status"},switch="sometimes"},
  OPP_JR_TRAINER_F={layers={"basic","cautious","status"},switch="sometimes"},
  OPP_POKEMANIAC={layers={"basic","setup","offensive","aggressive","status"},switch="sometimes"},
  OPP_SUPER_NERD={layers={"basic","types","smart","status"},switch="sometimes"},
  OPP_HIKER={layers={"basic","offensive","status"},switch="sometimes"},
  OPP_BIKER={layers={"basic","types","status","risky"},switch="sometimes"},
  OPP_BURGLAR={layers={"basic","offensive","cautious","status"},switch="sometimes"},
  OPP_ENGINEER={layers={"basic","setup","types","status","risky"},switch="sometimes"},
  OPP_JUGGLER={layers={"basic","types","smart","status"},switch="sometimes"},
  OPP_FISHER={layers={"basic","types","opportunist","cautious","status"},switch="often"},
  OPP_SWIMMER={layers={"basic","setup","types","offensive","status"},switch="sometimes"},
  OPP_CUE_BALL={layers={"basic","types","status","risky"},switch="sometimes"},
  OPP_GAMBLER={layers={"basic","setup","aggressive","status"},switch="sometimes"},
  OPP_BEAUTY={layers={"basic","types","opportunist","cautious","status"},switch="sometimes"},
  OPP_PSYCHIC_TR={layers={"basic","types","opportunist","cautious","status"},switch="sometimes"},
  OPP_ROCKER={layers={"basic","setup","types","cautious","status"},switch="sometimes"},
  OPP_BLACKBELT={layers={"basic","offensive","status","risky"},switch="sometimes"},
  OPP_CHANNELER={layers={"basic","setup","types","cautious","status","risky"},switch="sometimes"},
  OPP_TAMER={layers={"basic","setup","offensive","aggressive","status"},switch="sometimes"},
  OPP_BIRD_KEEPER={layers={"basic","types","offensive","opportunist","status"},switch="sometimes"},
  OPP_SCIENTIST={layers={"basic","setup","types","status","risky"},switch="sometimes"},
  OPP_GENTLEMAN={layers={"basic","setup","aggressive","status"},switch="sometimes"},
  OPP_ROCKET={layers={"basic","setup","types","opportunist","cautious","status","risky"},switch="sometimes"},
  OPP_COOLTRAINER_M={layers=FULL,switch="sometimes"},
  OPP_COOLTRAINER_F={layers=FULL,switch="sometimes"},
  OPP_RIVAL1={layers=FULL,switch="sometimes"},
  OPP_RIVAL2={layers=FULL,switch="sometimes"},
  OPP_RIVAL3={layers=FULL,switch="sometimes"},
  OPP_PROF_OAK={layers={"basic","aggressive","status"},switch="sometimes"},
  OPP_BROCK={layers=FULL,switch="sometimes",items={"HYPER_POTION"}},
  OPP_MISTY={layers=FULL,switch="sometimes",items={"FULL_HEAL"}},
  OPP_LT_SURGE={layers=FULL,switch="sometimes",items={"HYPER_POTION"}},
  OPP_ERIKA={layers=FULL,switch="sometimes",items={"HYPER_POTION"}},
  OPP_KOGA={layers=FULL,switch="sometimes",items={"FULL_HEAL","FULL_RESTORE"}},
  OPP_SABRINA={layers=FULL,switch="sometimes",items={"HYPER_POTION"}},
  OPP_BLAINE={layers=FULL,switch="sometimes",items={"MAX_POTION","FULL_HEAL"}},
  OPP_LORELEI={layers=FULL,switch="sometimes",items={"MAX_POTION"}},
  OPP_BRUNO={layers=FULL,switch="sometimes",items={"MAX_POTION"}},
  OPP_AGATHA={layers=FULL,switch="sometimes",items={"FULL_HEAL","MAX_POTION"}},
  OPP_LANCE={layers=FULL,switch="sometimes",items={"FULL_HEAL","FULL_RESTORE"}},
  OPP_GIOVANNI={layers=FULL,switch="sometimes",items={"FULL_RESTORE"}},
}
CrystalAI.PROFILES = PROFILES

local STATUS_ONLY = {
  [0x01]=true,[0x21]=true,[0x31]=true,[0x42]=true,[0x43]=true,
  [0x54]=true,[0x56]=true,[0x5a]=true,[0x68]=true,[0x6d]=true,
  [0x71]=true,[0x72]=true,[0x79]=true,[0x7c]=true,[0x81]=true,
}
local STAT_UP = {
  [0x0a]=true,[0x0b]=true,[0x0c]=true,[0x0d]=true,[0x0e]=true,[0x0f]=true,
  [0x32]=true,[0x33]=true,[0x34]=true,[0x35]=true,[0x36]=true,[0x37]=true,
  [0x3b]=true,
}
local STAT_DOWN = {
  [0x12]=true,[0x13]=true,[0x14]=true,[0x15]=true,[0x16]=true,[0x17]=true,
  [0x3c]=true,[0x3d]=true,[0x3e]=true,[0x3f]=true,[0x40]=true,[0x41]=true,
}
local TRAP_TARGET = {
  WHIRLPOOL=true, FIRE_SPIN=true, WRAP=true, BIND=true, CLAMP=true,
}
local RESIDUAL = {
  TOXIC=true, LEECH_SEED=true, SANDSTORM=true, NIGHTMARE=true,
  CURSE=true, PERISH_SONG=true, WHIRLPOOL=true, FIRE_SPIN=true,
  WRAP=true, BIND=true, CLAMP=true,
}
local STALL = {
  RECOVER=true, SOFTBOILED=true, REST=true, PROTECT=true, DETECT=true,
  ENDURE=true, SUBSTITUTE=true, DOUBLE_TEAM=true, MINIMIZE=true,
  SAND_ATTACK=true, SMOKESCREEN=true, FLASH=true, ACID_ARMOR=true,
  BARRIER=true, HARDEN=true, WITHDRAW=true, DEFENSE_CURL=true,
}
local RISKY = {
  SELFDESTRUCT=true, EXPLOSION=true, DOUBLE_EDGE=true, TAKE_DOWN=true,
  SUBMISSION=true, STRUGGLE=true, JUMP_KICK=true, HI_JUMP_KICK=true,
  HYPER_BEAM=true, DESTINY_BOND=true, REVERSAL=true, FLAIL=true,
}
local FIXED = {
  SONICBOOM=20, DRAGON_RAGE=40,
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function rngByte(battle)
  local rng = battle and battle.rng or function(a) return a end
  return clamp(math.floor(rng(0,255) or 0),0,255)
end

local function chance(battle, threshold)
  return rngByte(battle) < threshold
end

local function hpFraction(battler)
  if not (battler and battler.mon and battler.mon.stats) then return 1 end
  return (battler.mon.hp or 0) / math.max(1,battler.mon.stats.hp or 1)
end

local function activeIndex(battle)
  return battle.enemyIndex or 1
end

local function moveDef(battle, moveInst)
  return moveInst and battle and battle.data and battle.data.moves
    and battle.data.moves[moveInst.id] or moveInst
end

local function effectByte(def)
  return MoveScripts.effectByte(def)
end

local function category(def)
  if not def then return nil end
  if def.category and def.category ~= "status" then return def.category end
  local physical = {NORMAL=true,FIGHTING=true,FLYING=true,POISON=true,
    GROUND=true,ROCK=true,BUG=true,GHOST=true,STEEL=true}
  if (def.power or 0) <= 0 then return "status" end
  return physical[def.type] and "physical" or "special"
end

local function typeEffectiveness(battle, moveType, targetTypes)
  local ok, chart = pcall(require,"src.battle.TypeChart")
  if ok and chart and chart.effectiveness then
    local worked, value = pcall(chart.effectiveness,moveType,targetTypes or {})
    if worked then return value end
  end
  local mult = 10
  local rows = battle and battle.data and battle.data.type_chart
    and battle.data.type_chart.matchups or {}
  for _, row in ipairs(rows) do
    if row.attacker == moveType then
      for _, targetType in ipairs(targetTypes or {}) do
        if row.defender == targetType then
          mult = math.floor(mult * row.multiplier / 10)
          break
        end
      end
    end
  end
  return mult
end

local function hasMove(user,id)
  for _, move in ipairs(user and user.curMoves or {}) do
    if move.id == id then return true end
  end
  return false
end

local function hasBackup(battle)
  for index, mon in ipairs(battle and battle.enemyParty or {}) do
    if index ~= activeIndex(battle) and (mon.hp or 0) > 0 then return true end
  end
  return false
end

function CrystalAI.profileFor(battle)
  local trainer = battle and battle.trainer
  local id = trainer and (trainer.aiClass or trainer.id)
  -- Battle Tower always indexes the first TrainerClassAttributes row
  -- (Falkner): full boss-style scoring, no held trainer items, and
  -- SWITCH_SOMETIMES regardless of the displayed opponent class.
  local tower = battle and (battle.battleTower or battle.inBattleTowerBattle
    or battle.crystalBattleTower)
  local base = tower and {layers=FULL,switch="sometimes",items={}}
    or PROFILES[id] or PROFILES.DEFAULT
  local profile = {layers={},switch=base.switch,items={}}
  for i,v in ipairs(base.layers or {}) do profile.layers[i]=v end
  for i,v in ipairs(base.items or {}) do profile.items[i]=v end
  if trainer and trainer.crystalAI and not tower then
    local custom = trainer.crystalAI
    if custom.layers then profile.layers=custom.layers end
    if custom.switch then profile.switch=custom.switch end
    if custom.items then profile.items=custom.items end
  end
  return profile
end

function CrystalAI.estimateDamage(battle,user,target,moveInst)
  local def = moveDef(battle,moveInst)
  if not def then return 0 end
  local id = def.id or moveInst.id
  if FIXED[id] then return FIXED[id] end
  if id == "SEISMIC_TOSS" or id == "NIGHT_SHADE" then
    return user.mon.level or 1
  end
  if id == "SUPER_FANG" then return math.max(1,math.floor((target.mon.hp or 1)/2)) end
  if id == "PSYWAVE" then return math.max(1,math.floor((user.mon.level or 1)*3/2)-1) end
  if id == "OHKO" or id == "FISSURE" or id == "GUILLOTINE" or id == "HORN_DRILL" then
    return (user.mon.level or 1) >= (target.mon.level or 1) and (target.mon.hp or 0) or 0
  end
  if id == "COUNTER" then
    local lastCategory = target.crystalLastMoveCategory or target.lastMoveCategory
    return lastCategory == "physical" and math.max(0,(battle.lastDamage or 0)*2) or 0
  end
  if id == "MIRROR_COAT" then
    local lastCategory = target.crystalLastMoveCategory or target.lastMoveCategory
    return lastCategory == "special" and math.max(0,(battle.lastDamage or 0)*2) or 0
  end
  if id == "REVERSAL" or id == "FLAIL" then
    local maxhp = math.max(1,user.mon.stats.hp or 1)
    local n = math.floor((user.mon.hp or 1)*48/maxhp)
    def = {id=id,index=def.index,effect=def.effect,type=def.type,accuracy=def.accuracy,
      category=def.category,power=n<=1 and 200 or n<=4 and 150 or n<=9 and 100
        or n<=16 and 80 or n<=32 and 40 or 20}
  end
  if (def.power or 0) <= 0 then return 0 end
  local ok, damage = pcall(CrystalDamage.compute,{
    battle=battle,user=user,target=target,move=def,
    opts={rng=function(_,high) return high end,forceCrit=false},
    rng=function(_,high) return high end,
  })
  if ok and type(damage)=="number" then return damage end
  -- Fallback for lightweight tests without imported base stats.
  local attack = category(def)=="special"
    and (user.mon.stats.specialAttack or user.mon.stats.special or 1)
    or (user.mon.stats.attack or 1)
  local defense = category(def)=="special"
    and (target.mon.stats.specialDefense or target.mon.stats.special or 1)
    or (target.mon.stats.defense or 1)
  local base = math.floor((math.floor(2*(user.mon.level or 1)/5)+2)
    *(def.power or 0)*attack/math.max(1,defense)/50)+2
  local mult = typeEffectiveness(battle,def.type,target.curTypes)
  return mult==0 and 0 or math.max(1,math.floor(base*mult/10))
end

local function redundant(battle,user,target,def)
  local id, byte = def.id, effectByte(def)
  if STATUS_ONLY[byte] and (target.mon.status or target.safeguardTurns or target.safeguard) then
    return true
  end
  if (id=="HYPNOSIS" or id=="SING" or id=="SLEEP_POWDER" or id=="SPORE" or id=="LOVELY_KISS")
     and target.mon.status=="SLP" then return true end
  if id=="DREAM_EATER" and target.mon.status~="SLP" then return true end
  if (id=="RECOVER" or id=="SOFTBOILED" or id=="REST" or id=="MORNING_SUN"
      or id=="SYNTHESIS" or id=="MOONLIGHT") and hpFraction(user)>=1 then return true end
  if id=="REST" and user.mon.status=="SLP" then return true end
  if id=="SUBSTITUTE" and (user.substituteHP or hpFraction(user)<=0.25) then return true end
  if id=="LEECH_SEED" and target.leechSeededBy then return true end
  if id=="DISABLE" and (target.disabledSlot or not target.lastMove) then return true end
  if id=="ENCORE" and (target.encoreTurns or not target.lastMove) then return true end
  if (id=="MEAN_LOOK" or id=="SPIDER_WEB") and target.cantEscape then return true end
  if id=="PERISH_SONG" and target.perishTurns then return true end
  if id=="SAFEGUARD" and (user.safeguardTurns or user.safeguard) then return true end
  if id=="REFLECT" and (user.reflectTurns or user.reflect) then return true end
  if id=="LIGHT_SCREEN" and (user.lightScreenTurns or user.lightScreen) then return true end
  if id=="RAIN_DANCE" and battle.weather=="rain" then return true end
  if id=="SUNNY_DAY" and battle.weather=="sun" then return true end
  if id=="SANDSTORM" and battle.weather=="sand" then return true end
  if id=="FUTURE_SIGHT" and battle.crystalFutureSight and battle.crystalFutureSight.player then return true end
  if id=="SPIKES" and ((battle.crystalSpikes and battle.crystalSpikes.player)
      or battle.playerSpikes) then return true end
  if id=="ROAR" or id=="WHIRLWIND" then
    local party = battle.playerParty or (battle.game and battle.game.save and battle.game.save.party) or {}
    local alive = 0
    for _, mon in ipairs(party) do if (mon.hp or 0) > 0 then alive = alive + 1 end end
    if alive <= 1 then return true end
  end
  if id=="BATON_PASS" and not hasBackup(battle) then return true end
  if STAT_UP[byte] then
    local stat = ({[0x0a]="attack",[0x0b]="defense",[0x0c]="speed",[0x0d]="specialAttack",
      [0x0e]="accuracy",[0x0f]="evasion",[0x32]="attack",[0x33]="defense",
      [0x34]="speed",[0x35]="specialAttack",[0x36]="accuracy",[0x37]="evasion"})[byte]
    if stat and (user.stages[stat] or 0)>=6 then return true end
  end
  if STAT_DOWN[byte] then
    local stat = ({[0x12]="attack",[0x13]="defense",[0x14]="speed",[0x15]="specialAttack",
      [0x16]="accuracy",[0x17]="evasion",[0x3c]="attack",[0x3d]="defense",
      [0x3e]="speed",[0x3f]="specialAttack",[0x40]="accuracy",[0x41]="evasion"})[byte]
    if stat and (target.stages[stat] or 0)<=-6 then return true end
  end
  return false
end

local function layerBasic(battle,user,target,rows)
  for _,row in ipairs(rows) do
    if row.score<UNUSABLE_SCORE and redundant(battle,user,target,row.def) then
      row.score=row.score+10
    end
  end
end

local function layerSetup(battle,user,target,rows)
  for _,row in ipairs(rows) do
    local byte=effectByte(row.def)
    local isUp,isDown=STAT_UP[byte],STAT_DOWN[byte]
    if isUp or isDown then
      local first = isUp and ((user.turnsTaken or user.crystalTurnsTaken or 0)==0)
        or isDown and ((target.turnsTaken or target.crystalTurnsTaken or 0)==0)
      if first then
        if chance(battle,128) then row.score=row.score-2 end
      elseif not chance(battle,31) then row.score=row.score+2 end
    end
  end
end

local function layerTypes(battle,user,target,rows)
  local hasDifferentDamage={}
  for i,row in ipairs(rows) do
    if (row.def.power or 0)>0 then
      for j,other in ipairs(rows) do
        if i~=j and (other.def.power or 0)>0 and other.def.type~=row.def.type then
          hasDifferentDamage[i]=true break
        end
      end
    end
  end
  for i,row in ipairs(rows) do
    local mult=typeEffectiveness(battle,row.def.type,target.curTypes)
    row.typeMult=mult
    if mult==0 then row.score=row.score+10
    elseif mult>10 and (row.def.power or 0)>0 then row.score=row.score-1
    elseif mult<10 and hasDifferentDamage[i] then row.score=row.score+1 end
  end
end

local function layerOffensive(_,_,_,rows)
  for _,row in ipairs(rows) do if (row.def.power or 0)==0 then row.score=row.score+2 end end
end

local function layerSmart(battle,user,target,rows)
  local enemyHP,playerHP=hpFraction(user),hpFraction(target)
  for _,row in ipairs(rows) do
    local id,def=row.def.id,row.def
    if id=="HYPNOSIS" or id=="SING" or id=="SLEEP_POWDER" or id=="SPORE" or id=="LOVELY_KISS" then
      if hasMove(user,"DREAM_EATER") or hasMove(user,"NIGHTMARE") or chance(battle,128) then row.score=row.score-2 end
    elseif id=="DREAM_EATER" then row.score=row.score-3
    elseif id=="SELFDESTRUCT" or id=="EXPLOSION" then
      if enemyHP>0.5 or not hasBackup(battle) then row.score=row.score+3 end
    elseif id=="RECOVER" or id=="SOFTBOILED" or id=="REST" or id=="MORNING_SUN" or id=="SYNTHESIS" or id=="MOONLIGHT" then
      if enemyHP<=0.25 then row.score=row.score-3 elseif enemyHP<=0.5 then row.score=row.score-2 else row.score=row.score+2 end
    elseif id=="TOXIC" or id=="LEECH_SEED" or id=="NIGHTMARE" then
      if playerHP>0.5 then row.score=row.score-1 end
    elseif id=="REFLECT" then
      if target.lastMoveCategory=="physical" or (target.crystalLastMoveCategory=="physical") then row.score=row.score-2 end
    elseif id=="LIGHT_SCREEN" then
      if target.lastMoveCategory=="special" or (target.crystalLastMoveCategory=="special") then row.score=row.score-2 end
    elseif id=="SUPER_FANG" then
      if playerHP>0.5 then row.score=row.score-1 else row.score=row.score+1 end
    elseif TRAP_TARGET[id] then
      local trapped = (tonumber(target.crystalTrapTurns) or 0) > 0
      local useful = target.toxicCounter or target.attracted or target.infatuatedWith
        or target.foresight or (tonumber(target.rolloutCount) or 0) > 0
        or target.nightmare
        or (target.turnsTaken or target.crystalTurnsTaken or 0) == 0
      if trapped or not useful then
        if chance(battle, 128) then row.score = row.score + 1 end
      elseif chance(battle, 128) then
        row.score = row.score - 2
      end
    elseif id=="CONFUSE_RAY" or id=="SUPERSONIC" or id=="SWEET_KISS" or id=="SWAGGER" then
      if not target.confusedTurns then row.score=row.score-1 end
    elseif id=="SUBSTITUTE" then
      if enemyHP>0.5 and (target.mon.status=="TOX" or target.toxicCounter or target.leechSeededBy) then row.score=row.score-2
      elseif enemyHP<=0.25 then row.score=row.score+2 end
    elseif id=="HYPER_BEAM" then
      local damage=CrystalAI.estimateDamage(battle,user,target,row.move)
      if damage>=(target.mon.hp or 0) then row.score=row.score-2 else row.score=row.score+1 end
    elseif id=="COUNTER" then
      if target.lastMoveCategory=="physical" then row.score=row.score-2 else row.score=row.score+1 end
    elseif id=="MIRROR_COAT" then
      if target.lastMoveCategory=="special" then row.score=row.score-2 else row.score=row.score+1 end
    elseif id=="ENCORE" then
      if target.lastMove and (target.lastMovePower or 0)==0 then row.score=row.score-2 end
    elseif id=="SNORE" or id=="SLEEP_TALK" then
      if user.mon.status=="SLP" then row.score=row.score-3 else row.score=row.score+10 end
    elseif id=="DESTINY_BOND" then
      if enemyHP<=0.25 then row.score=row.score-2 else row.score=row.score+1 end
    elseif id=="REVERSAL" or id=="FLAIL" then
      if enemyHP<=0.2 then row.score=row.score-2 elseif enemyHP>0.5 then row.score=row.score+1 end
    elseif id=="THIEF" then
      if not user.mon.heldItem and target.mon.heldItem then row.score=row.score-2 end
    elseif id=="MEAN_LOOK" or id=="SPIDER_WEB" then
      if hasBackup(battle) then row.score=row.score-1 end
    elseif id=="PROTECT" or id=="DETECT" or id=="ENDURE" then
      if enemyHP<=0.25 or user.perishTurns==1 or target.toxicCounter or target.leechSeededBy then row.score=row.score-2
      elseif user.protectLastTurn then row.score=row.score+2 end
    elseif id=="PERISH_SONG" then
      if hasBackup(battle) and not target.perishTurns then row.score=row.score-1 else row.score=row.score+2 end
    elseif id=="SANDSTORM" then
      local immune=false
      for _,t in ipairs(user.curTypes or {}) do if t=="ROCK" or t=="GROUND" or t=="STEEL" then immune=true end end
      if immune then row.score=row.score-1 end
    elseif id=="BATON_PASS" then
      local boosted=false
      for _,v in pairs(user.stages or {}) do if v>0 then boosted=true break end end
      if boosted and hasBackup(battle) then row.score=row.score-2 else row.score=row.score+2 end
    elseif id=="PURSUIT" then
      if target.perishTurns==1 or hpFraction(target)<=0.25 then row.score=row.score-1 end
    elseif id=="RAPID_SPIN" then
      if user.crystalTrapTurns or user.leechSeededBy
         or (battle.crystalSpikes and battle.crystalSpikes.enemy)
         or battle.enemySpikes then row.score=row.score-2 end
    elseif id=="BELLY_DRUM" then
      if enemyHP>0.5 and (user.stages.attack or 0)<6 then row.score=row.score-3 else row.score=row.score+10 end
    elseif id=="PSYCH_UP" then
      local positive=false
      for _,v in pairs(target.stages or {}) do if v>0 then positive=true break end end
      if positive then row.score=row.score-2 else row.score=row.score+2 end
    elseif id=="FUTURE_SIGHT" then
      if not (battle.crystalFutureSight and battle.crystalFutureSight.player) then row.score=row.score-1 end
    elseif id=="QUICK_ATTACK" or id=="MACH_PUNCH" or id=="EXTREMESPEED" then
      if CrystalAI.estimateDamage(battle,user,target,row.move)>=(target.mon.hp or 0) then row.score=row.score-2 end
    end
  end
end

local function layerOpportunist(_,user,_,rows)
  if hpFraction(user)>0.5 then return end
  for _,row in ipairs(rows) do if STALL[row.def.id] then row.score=row.score+2 end end
end

local function layerAggressive(battle,user,target,rows)
  local best=0
  for _,row in ipairs(rows) do
    row.damage=CrystalAI.estimateDamage(battle,user,target,row.move)
    if row.damage>best then best=row.damage end
  end
  if best<=0 then return end
  for _,row in ipairs(rows) do
    if row.damage>0 and row.damage<best then row.score=row.score+1 end
  end
end

local function layerCautious(battle,user,_,rows)
  if (user.turnsTaken or user.crystalTurnsTaken or 0)==0 then return end
  for _,row in ipairs(rows) do
    if RESIDUAL[row.def.id] and not chance(battle,26) then row.score=row.score+1 end
  end
end

local function layerStatus(battle,user,target,rows)
  for _,row in ipairs(rows) do
    local byte=effectByte(row.def)
    if STATUS_ONLY[byte] and redundant(battle,user,target,row.def) then row.score=row.score+10 end
  end
end

local function layerRisky(battle,user,target,rows)
  for _,row in ipairs(rows) do
    local damage=row.damage or CrystalAI.estimateDamage(battle,user,target,row.move)
    if damage>0 and damage>=(target.mon.hp or 0) then
      if not (RISKY[row.def.id] and hpFraction(user)<=0.25 and row.def.id~="REVERSAL" and row.def.id~="FLAIL") then
        row.score=row.score-5
      end
    end
  end
end

local LAYERS={basic=layerBasic,setup=layerSetup,types=layerTypes,
  offensive=layerOffensive,smart=layerSmart,opportunist=layerOpportunist,
  aggressive=layerAggressive,cautious=layerCautious,status=layerStatus,risky=layerRisky}
CrystalAI.LAYERS=LAYERS

function CrystalAI.scoreMoves(battle,battler)
  battler=battler or battle.enemy
  local target=battle.player
  local rows={}
  for index,move in ipairs(battler.curMoves or {}) do
    local def=moveDef(battle,move)
    local usable=def and battler.disabledSlot~=index and (move.pp or 0)>0
    rows[#rows+1]={index=index,move=move,def=def or move,
      score=usable and BASE_SCORE or UNUSABLE_SCORE}
  end
  local profile=CrystalAI.profileFor(battle)
  local enabled={}
  for _,id in ipairs(profile.layers or {}) do enabled[id]=true end
  for _,id in ipairs(LAYER_ORDER) do
    if enabled[id] then LAYERS[id](battle,battler,target,rows) end
  end
  for _,row in ipairs(rows) do row.score=clamp(math.floor(row.score),0,255) end
  return rows
end

local function gen2MoveDef(battle, moveInst)
  local def = moveDef(battle, moveInst)
  if not def then return nil end
  local out = {}
  for key, value in pairs(def) do out[key] = value end
  local byte = effectByte(def)
  out.effect = GEN2_EFFECTS[byte] or def.effect
  return out
end

local function gen2Flags(battle)
  local flags = 0
  for _, layer in ipairs(CrystalAI.profileFor(battle).layers or {}) do
    local name = AI_FLAG_BY_LAYER[layer]
    local bit = name and Gen2AI.FLAGS[name]
    if bit then flags = flags + bit end
  end
  return flags
end

local function typesForGen2(battle, mon)
  if mon and mon.curTypes then return mon.curTypes end
  local pokemon = battle.data and battle.data.pokemon
  local def = pokemon and ((pokemon.get and pokemon:get(mon and mon.species))
    or pokemon[mon and mon.species])
  if not def then return {} end
  if def.types then return def.types end
  local out = {}
  if def.type1 then out[#out + 1] = def.type1 end
  if def.type2 and def.type2 ~= def.type1 then out[#out + 1] = def.type2 end
  return out
end

local function chooseWithGen2AI(battle, battler, rng)
  local target = battle.player or {}
  local chart = battle.data and battle.data.type_chart or {}
  local function random(n)
    if n <= 1 then return 0 end
    local value = rng(1, n)
    return math.max(0, math.min(n - 1, value - 1))
  end
  local choice = Gen2AI.choose({
    moves = battler.curMoves or {},
    moveDef = function(id) return gen2MoveDef(battle, {id=id}) end,
    attacker = { level=(battler.mon or {}).level or battler.level or 1,
      stats=(battler.mon or {}).stats or battler.stats or {},
      types=battler.curTypes or typesForGen2(battle, battler.mon or battler) },
    defender = { hp=(target.mon or {}).hp or target.hp or 0,
      stats=(target.mon or {}).stats or target.stats or {},
      types=target.curTypes or typesForGen2(battle, target.mon or target) },
    attackerStages = battler.stages or {}, defenderStages = target.stages or {},
    typeChart = chart, flags = gen2Flags(battle), random = random,
    data = battle.data, enemyTurns=battler.crystalTurnsTaken or 0,
    playerTurns=target.crystalTurnsTaken or 0,
    enemyHp=(battler.mon or {}).hp or battler.hp, enemyMaxHp=(battler.mon or {}).stats and battler.mon.stats.hp,
    playerHp=(target.mon or {}).hp or target.hp, playerMaxHp=(target.mon or {}).stats and target.mon.stats.hp,
  })
  if choice then
    local matches = {}
    for _, move in ipairs(battler.curMoves or {}) do
      if move.id == choice then matches[#matches + 1] = move end
    end
    -- Gen 2 returns a move id, while the Gen 1 shell keeps move instances.
    -- Preserve the scorer's selected duplicate slot for test fixtures and
    -- cloned moves by resolving the final tied instance deterministically.
    if #matches > 1 then return matches[#matches] end
    if matches[1] then return matches[1] end
  end
end

function CrystalAI.chooseMove(battler,rng,battle)
  battle=battle or {}
  battler=battler or battle.enemy
  rng=rng or battle.rng or function(a) return a end
  local usable={}
  for index,move in ipairs(battler.curMoves or {}) do
    if battler.disabledSlot~=index and (move.pp or 0)>0 then usable[#usable+1]=move end
  end
  if #usable==0 then return {id="STRUGGLE",pp=1,struggle=true} end
  if battle.kind=="wild" then return usable[rng(1,#usable)] end
  local gen2Choice = chooseWithGen2AI(battle, battler, rng)
  if gen2Choice then return gen2Choice end
  local rows=CrystalAI.scoreMoves(battle,battler)
  local best=UNUSABLE_SCORE
  for _,row in ipairs(rows) do if row.score<best then best=row.score end end
  local choices={}
  for _,row in ipairs(rows) do if row.score==best then choices[#choices+1]=row.move end end
  if #choices==0 then return usable[rng(1,#usable)] end
  return choices[rng(1,#choices)]
end

local function monTypes(battle,mon)
  if mon.curTypes then return mon.curTypes end
  local pokemon=battle.data and battle.data.pokemon
  local def=pokemon and ((pokemon.get and pokemon:get(mon.species)) or pokemon[mon.species])
  if not def then return {} end
  if def.types then return def.types end
  local out={}
  if def.type1 then out[#out+1]=def.type1 end
  if def.type2 and def.type2~=def.type1 then out[#out+1]=def.type2 end
  return out
end

local function moveList(mon)
  return mon.moves or mon.curMoves or {}
end

local function benchScore(battle,mon,index)
  local score=0
  local player=battle.player
  local types=monTypes(battle,mon)
  local last=player.lastCounterMove or player.lastMove
  local lastDef=last and battle.data.moves[last]
  if lastDef and (lastDef.power or 0)>0 then
    local mult=typeEffectiveness(battle,lastDef.type,types)
    if mult==0 then score=score+4 elseif mult<10 then score=score+2 elseif mult>10 then score=score-3 end
  end
  for _,move in ipairs(moveList(mon)) do
    local def=moveDef(battle,move)
    if def and (def.power or 0)>0 then
      local mult=typeEffectiveness(battle,def.type,player.curTypes)
      if mult>10 then score=score+4 elseif mult==10 then score=score+1 end
    end
  end
  local maxhp=mon.stats and mon.stats.hp or mon.maxHP or mon.hp or 1
  if (mon.hp or 0)>=math.floor(maxhp/4) then score=score+1 end
  return score,index
end

function CrystalAI.switchCandidate(battle)
  local best,bestScore=nil,-999
  for index,mon in ipairs(battle.enemyParty or {}) do
    if index~=activeIndex(battle) and (mon.hp or 0)>0 then
      local score=benchScore(battle,mon,index)
      if score>bestScore then best,bestScore=index,score end
    end
  end
  return best,bestScore
end

function CrystalAI.switchAssessment(battle)
  if not hasBackup(battle) or not battle.enemy or battle.enemy.cantEscape
     or battle.enemy.crystalTrapTurns or battle.enemy.boundTurns then return nil end
  local candidate,candidateScore=CrystalAI.switchCandidate(battle)
  if not candidate then return nil end
  if battle.enemy.perishTurns==1 then return {index=candidate,tier=3,score=BASE_SWITCH_SCORE+3} end
  local score=BASE_SWITCH_SCORE
  local player=battle.player
  local active=battle.enemy
  local known=player.usedMoves or battle.crystalPlayerUsedMoves or {}
  if #known==0 and player.lastMove then known={player.lastMove} end
  local worst=10
  for _,id in ipairs(known) do
    local def=type(id)=="table" and moveDef(battle,id) or battle.data.moves[id]
    if def and (def.power or 0)>0 then
      worst=math.max(worst,typeEffectiveness(battle,def.type,active.curTypes))
    end
  end
  if worst>10 then score=score-1 elseif worst<10 then score=score+1 end
  local activeBest=0
  for _,move in ipairs(active.curMoves or {}) do
    local def = moveDef(battle,move)
    if def and (def.power or 0) > 0 then
      activeBest=math.max(activeBest,typeEffectiveness(battle,def.type,player.curTypes))
    end
  end
  if activeBest>10 then score=score+1 elseif activeBest<10 then score=score-1 end
  if score>=BASE_SWITCH_SCORE then return nil end
  local tier=candidateScore>=5 and 2 or 1
  return {index=candidate,tier=tier,score=score}
end

local SWITCH_THRESHOLDS={
  often={[1]=128,[2]=202,[3]=246},
  rarely={[1]=20,[2]=31,[3]=54},
  sometimes={[1]=51,[2]=128,[3]=51},
}
CrystalAI.SWITCH_THRESHOLDS=SWITCH_THRESHOLDS

function CrystalAI.shouldSwitch(battle,frequency,tier)
  local tableFor=SWITCH_THRESHOLDS[frequency or "sometimes"] or SWITCH_THRESHOLDS.sometimes
  return chance(battle,tableFor[clamp(tier or 1,1,3)])
end

local function itemUseful(battle,item)
  local Actions=require("mods.CRYSTAL_251.battle.crystal_actions")
  return Actions.trainerItemUseful(battle,item)
end

function CrystalAI.classAction(battle)
  if not (battle and battle.crystal251Active and battle.trainer)
     or battle.kind=="link" then return nil end
  local tower = battle.battleTower or battle.inBattleTowerBattle
    or battle.crystalBattleTower
  if battle.kind~="trainer" and not tower then return nil end
  local profile=CrystalAI.profileFor(battle)
  local assessment=CrystalAI.switchAssessment(battle)
  if assessment and CrystalAI.shouldSwitch(battle,profile.switch,assessment.tier) then
    return {special="aiSwitch",index=assessment.index,crystalAI=true}
  end
  -- AI_TryItem returns immediately in the Battle Tower, but the switch
  -- assessment above still runs using Falkner's class attributes.
  if tower then return nil end
  battle.crystalTrainerItemsUsed=battle.crystalTrainerItemsUsed or {}
  local highest=true
  local activeLevel=battle.enemy.mon.level or 0
  for _,mon in ipairs(battle.enemyParty or {}) do if (mon.level or 0)>activeLevel then highest=false end end
  if highest then
    for slot,item in ipairs(profile.items or {}) do
      if not battle.crystalTrainerItemsUsed[slot] and itemUseful(battle,item) then
        return {special="aiItem",item=item,crystalAI=true,crystalItemSlot=slot}
      end
    end
  end
  return nil
end


local function isChargeRelease(user, moveInst)
  return user and moveInst and user.charging == moveInst and user.chargeReady
end

local function isPPContinuation(user, moveInst)
  if not (user and moveInst) then return false end
  if isChargeRelease(user, moveInst) then return true end
  if user.thrashTurns and user.thrashTurns > 0 and moveInst == user.thrashMove then return true end
  if user.forcedMove and moveInst == user.forcedMove
     and ((user.rolloutCount or 0) > 0 or (user.forcedMoveTurns or 0) > 0) then
    return true
  end
  return false
end

-- UsedMoveText appends each displayed player move once, dropping the oldest
-- entry only when all four slots are occupied.  Last-move and turns-taken
-- state are also AI inputs in Crystal; charge releases are the exception.
function CrystalAI.recordMove(battle,user,moveDefn,opts)
  if not (battle and user and moveDefn) then return end
  opts = opts or {}
  local id = moveDefn.id
  if not id then return end

  if user.isPlayer then
    local used = battle.crystalPlayerUsedMoves or {}
    battle.crystalPlayerUsedMoves = used
    local found = false
    for _, known in ipairs(used) do if known == id then found = true break end end
    if not found then
      if #used >= 4 then table.remove(used,1) end
      used[#used+1] = id
    end
    user.usedMoves = used
  end

  if opts.chargeRelease then return end
  user.crystalTurnsTaken = (user.crystalTurnsTaken or 0) + 1
  local moveCategory = category(moveDefn)
  user.crystalLastMoveCategory = moveCategory
  user.lastMoveCategory = moveCategory
  user.lastMove = id
  user.lastCounterMove = id
end

function CrystalAI.installRuntime()
  local TrainerAI=RuntimePatches.watch(require("src.battle.TrainerAI"))
  local BattleState=RuntimePatches.watch(require("src.battle.BattleState"))
  if not BattleState._crystal251AIMoveTrackingBridge then
    BattleState._crystal251AIMoveTrackingBridge=true
    local originalPerformMove=BattleState.performMove
    BattleState.performMove=function(self,user,target,moveInst,isCalled)
      if not (self and self.crystal251Active and user and moveInst) then
        return originalPerformMove(self,user,target,moveInst,isCalled)
      end
      local def=self.moveDef and self:moveDef(moveInst) or moveDef(self,moveInst)
      local chargeRelease=isChargeRelease(user,moveInst)
      local canAttempt=moveInst.struggle or isCalled or isPPContinuation(user,moveInst)
        or (moveInst.pp or 0)>0
      if def and canAttempt then
        CrystalAI.recordMove(self,user,def,{chargeRelease=chargeRelease,isCalled=isCalled})
      end
      return originalPerformMove(self,user,target,moveInst,isCalled)
    end
  end
  if TrainerAI._crystal251AIBridge then return end
  TrainerAI._crystal251AIBridge=true
  local originalChoose=TrainerAI.chooseMove
  TrainerAI.chooseMove=function(battler,rng,battle)
    if battle and battle.crystal251Active then return CrystalAI.chooseMove(battler,rng,battle) end
    return originalChoose(battler,rng,battle)
  end
  local originalClassAction=TrainerAI.classAction
  TrainerAI.classAction=function(battle)
    if battle and battle.crystal251Active then return CrystalAI.classAction(battle) end
    return originalClassAction(battle)
  end
  local originalUseItem=TrainerAI.useItem
  TrainerAI.useItem=function(battle,item)
    if battle and battle.crystal251Active then
      local profile=CrystalAI.profileFor(battle)
      battle.crystalTrainerItemsUsed=battle.crystalTrainerItemsUsed or {}
      for slot,held in ipairs(profile.items or {}) do
        if held==item and not battle.crystalTrainerItemsUsed[slot] then
          battle.crystalTrainerItemsUsed[slot]=true
          break
        end
      end
    end
    return originalUseItem(battle,item)
  end
end

return RuntimePatches.installers(CrystalAI)
