package.path = "./?.lua;./?/init.lua;" .. package.path

local P = require("mods.CRYSTAL_251.battle.crystal_progression")

local checks, failures = 0, 0
local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end
local function ok(value, message)
  checks = checks + 1
  if not value then fail(message) end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    fail(("%s (got %s, want %s)"):format(message,tostring(got),tostring(want)))
  end
end
local function seq(values)
  local i=0
  return function(a,b)
    i=i+1
    local v=values[i] or 0
    if b then return math.max(a,math.min(b,v)) end
    return v
  end
end
local function mon(species,level,attack,speed)
  return {species=species,level=level or 20,hp=100,status=nil,
    stats={hp=100},dvs={attack=attack or 8,speed=speed or 8},
    statExp={hp=0,attack=0,defense=0,speed=0,special=0}}
end
local function battle(player,target,values)
  return {player={mon=player},enemy={mon=target},rng=seq(values or {})}
end

local target=mon("SNORLAX",20)
local player=mon("PIKACHU",40)
local b=battle(player,target)
local def={catchRate=100,dexEntry={weight=10140}}
eq(P.modifiedCatchRate(b,"ULTRA_BALL",target,def),200,"Ultra Ball doubles")
eq(P.modifiedCatchRate(b,"GREAT_BALL",target,def),150,"Great Ball multiplies by 1.5")
eq(P.modifiedCatchRate(b,"POKE_BALL",target,def),100,"Poke Ball is neutral")
eq(P.modifiedCatchRate(b,"HEAVY_BALL",target,{catchRate=100,dexEntry={weight=1000}}),80,
  "light target loses twenty catch points")
eq(P.modifiedCatchRate(b,"HEAVY_BALL",target,def),140,
  "very heavy target gains forty catch points")
b.crystalFishing=true
eq(P.modifiedCatchRate(b,"LURE_BALL",target,def),255,"Lure Ball triples fishing rate")
b.crystalFishing=false
eq(P.modifiedCatchRate(b,"LURE_BALL",target,def),100,"Lure Ball is neutral outside fishing")
for _,species in ipairs({"MAGNEMITE","GRIMER","TANGELA"}) do
  local fast=mon(species,20)
  eq(P.modifiedCatchRate(b,"FAST_BALL",fast,{catchRate=50}),200,
    "Fast Ball boosts Crystal bug target "..species)
end
eq(P.modifiedCatchRate(b,"FAST_BALL",mon("RAIKOU",20),{catchRate=50}),50,
  "Fast Ball does not boost later flee-table species")
eq(P.modifiedCatchRate(b,"MOON_BALL",target,def),100,"Moon Ball bug gives no multiplier")

P.setGenderRatio("EEVEE",127)
local lovePlayer=mon("EEVEE",30,2,15)
local loveTarget=mon("EEVEE",20,4,8)
local loveBattle=battle(lovePlayer,loveTarget)
eq(P.monGender(lovePlayer),"F","gender derives from Attack and Speed DVs")
eq(P.modifiedCatchRate(loveBattle,"LOVE_BALL",loveTarget,{catchRate=30}),240,
  "Love Ball bug boosts same gender")
loveTarget.dvs.attack=12
eq(P.modifiedCatchRate(loveBattle,"LOVE_BALL",loveTarget,{catchRate=30}),30,
  "Love Ball does not boost opposite gender")

local levelTarget=mon("RATTATA",10)
local levelBattle=battle(mon("PIKACHU",50),levelTarget)
eq(P.modifiedCatchRate(levelBattle,"LEVEL_BALL",levelTarget,{catchRate=20}),160,
  "Level Ball reaches eight times rate")
levelBattle.player.mon.level=30
eq(P.modifiedCatchRate(levelBattle,"LEVEL_BALL",levelTarget,{catchRate=20}),80,
  "Level Ball reaches four times rate")
levelBattle.player.mon.level=15
eq(P.modifiedCatchRate(levelBattle,"LEVEL_BALL",levelTarget,{catchRate=20}),40,
  "Level Ball reaches two times rate")
levelBattle.player.mon.level=10
eq(P.modifiedCatchRate(levelBattle,"LEVEL_BALL",levelTarget,{catchRate=20}),20,
  "Level Ball is neutral at equal level")

local hpTarget=mon("PIDGEY",5)
hpTarget.hp=50
eq(P.finalCatchRate(b,"POKE_BALL",hpTarget,{catchRate=120}),80,
  "Crystal HP catch formula")
hpTarget.status="SLP"
eq(P.finalCatchRate(b,"POKE_BALL",hpTarget,{catchRate=120}),90,
  "sleep adds ten catch points")
hpTarget.status="PAR"
eq(P.finalCatchRate(b,"POKE_BALL",hpTarget,{catchRate=120}),80,
  "paralysis catch bonus bug is preserved")
hpTarget.hp=1
eq(P.finalCatchRate(b,"POKE_BALL",hpTarget,{catchRate=255}),253,
  "near-zero HP reaches Crystal formula maximum")
hpTarget.hp=100
eq(P.finalCatchRate(levelBattle,"LEVEL_BALL",levelTarget,{catchRate=20}),20,
  "Level Ball skips HP calculation")

local caughtBattle=battle(player,mon("CATERPIE",3),{33})
local caught,shakes=P.catchAttempt(caughtBattle,"POKE_BALL",caughtBattle.enemy.mon,{catchRate=100})
ok(caught,"catch succeeds on equality")
eq(shakes,3,"successful catch always shakes three times")
local failedBattle=battle(player,mon("CATERPIE",3),{255,0,255})
local failed,failedShakes=P.catchAttempt(failedBattle,"POKE_BALL",failedBattle.enemy.mon,{catchRate=1})
ok(not failed,"catch fails above final rate")
ok(failedShakes>=0 and failedShakes<=3,"failed wobble count stays in range")

local friend={lastBall="FRIEND_BALL",enemy={mon=mon("PIKACHU",12)},
  crystalCaughtLocation=7,crystalCaughtTime=2}
P.prepareCaughtMon(friend)
eq(friend.enemy.mon.happiness,200,"Friend Ball sets happiness to 200")
eq(friend.enemy.mon.caughtData.level,12,"caught data stores level")
eq(friend.enemy.mon.caughtData.ball,"FRIEND_BALL","caught data stores ball")
eq(friend.enemy.mon.caughtData.location,7,"caught data stores location")
local transformedBattle={lastBall="POKE_BALL",enemy={mon=mon("MEW",30),transformed=true}}
P.prepareCaughtMon(transformedBattle)
eq(transformedBattle.enemy.mon.species,"DITTO","transformed catch bug stores Ditto")

local a,bmon,c=mon("A",10),mon("B",10),mon("C",10)
c.heldItem="EXP_SHARE"
local calls={}
local expBattle={crystal251Active=true,game={save={party={a,bmon,c}}}}
P.awardExp(function() fail("Crystal award should replace vanilla") end,{
  battle=expBattle,participants=2,alive={a,bmon},
  applyShare=function(m,split,announce)
    calls[#calls+1]={m=m,split=split,announce=announce,
      context=m._crystal251ExpContext}
  end,
})
eq(#calls,3,"EXP Share makes participant and holder passes")
eq(calls[1].split,4,"participants divide half reward")
eq(calls[2].split,4,"second participant divides half reward")
eq(calls[3].split,2,"sole EXP Share holder receives other half")
ok(calls[1].context and calls[3].context,"Crystal experience context wraps both passes")

calls={}
c.heldItem=nil
P.awardExp(function() fail("Crystal award should replace vanilla") end,{
  battle=expBattle,participants=2,alive={a,bmon},
  applyShare=function(m,split) calls[#calls+1]={m=m,split=split} end,
})
eq(#calls,2,"ordinary reward pays participants only")
eq(calls[1].split,2,"ordinary reward divides by participants")

eq(P.trainerBaseReward({oppClass="OPP_YOUNGSTER"}),4,
  "Youngster uses Crystal base reward")
eq(P.trainerBaseReward({oppClass="OPP_BROCK"}),25,
  "Brock uses Crystal base reward")

P.installRuntime()
local Experience=require("src.battle.Experience")
local Stats=require("src.pokemon.Stats")
local expData={constants={levelCap=100},pokemon={TEST={growthRate="MEDIUM_FAST",
  baseStats={hp=50,attack=50,defense=50,speed=50,special=50},learnset={}}}}
local lucky=mon("TEST",10)
lucky.exp=1000
lucky.dvs={hp=0,attack=0,defense=0,speed=0,special=0}
lucky.stats=Stats.calc(expData.pokemon.TEST,10,lucky.dvs,lucky.statExp)
lucky.heldItem="LUCKY_EGG"
lucky.pokerus=1
lucky.traded=true
lucky._crystal251ExpContext=true
local levels,gained=Experience.apply(expData,lucky,{baseExp=10,
  baseStats={hp=10,attack=10,defense=10,speed=10,special=10}},10,true,1,true)
eq(gained,46,"traded trainer and Lucky Egg bonuses apply in Crystal order")
eq(lucky.statExp.attack,20,"Pokerus doubles stat experience")
eq(#levels,0,"small Crystal award does not create a false level-up")

local BattleState=require("src.battle.BattleState")
local run={crystal251Active=true,kind="wild",runAttempts=1,rng=seq({255}),
  player={}}
ok(BattleState.runRollVanilla(run,100,50),"faster Crystal battler escapes")
run.crystalBattleType="trap"
ok(not BattleState.runRollVanilla(run,100,50),"trap battle blocks escape")
run.crystalBattleType="contest"
ok(BattleState.runRollVanilla(run,1,255),"contest battle always escapes")
run.crystalBattleType=nil
run.player.cantEscape=true
ok(not BattleState.runRollVanilla(run,100,50),"Mean Look blocks escape")

local ItemEffects=require("src.inventory.ItemEffects")
for _,id in ipairs({"HEAVY_BALL","LEVEL_BALL","LURE_BALL","FAST_BALL",
  "FRIEND_BALL","MOON_BALL","LOVE_BALL"}) do
  ok(ItemEffects.isBall(id),id.." is usable as a battle ball")
end

if failures>0 then
  io.stderr:write(("%d/%d checks passed, %d FAILURES (Crystal progression)\n")
    :format(checks-failures,checks,failures))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal capture and progression)"):format(checks,checks))
