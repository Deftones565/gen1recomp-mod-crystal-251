package.path = "./?.lua;./?/init.lua;" .. package.path

local AI = require("mods.CRYSTAL_251.battle.crystal_ai")

local checks, failures = 0, 0
local function fail(message)
  failures=failures+1; io.stderr:write("FAIL "..message.."\n")
end
local function ok(value,message)
  checks=checks+1; if not value then fail(message) end
end
local function eq(got,want,message)
  checks=checks+1
  if got~=want then fail(("%s (got %s, want %s)"):format(message,tostring(got),tostring(want))) end
end
local function seq(values)
  local i=0
  return function(a,b)
    i=i+1; local v=values[i]; if v==nil then v=a end
    if v<a then v=a elseif v>b then v=b end
    return v
  end
end

local moves={
  TACKLE={id="TACKLE",index=33,effect="NO_ADDITIONAL_EFFECT",power=35,type="NORMAL",category="physical",accuracy=95},
  EMBER={id="EMBER",index=52,effect="BURN_SIDE_EFFECT1",power=40,type="FIRE",category="special",accuracy=100},
  WATER_GUN={id="WATER_GUN",index=55,effect="NO_ADDITIONAL_EFFECT",power=40,type="WATER",category="special",accuracy=100},
  GROWL={id="GROWL",index=45,effect="ATTACK_DOWN1_EFFECT",power=0,type="NORMAL",category="status",accuracy=100},
  SWORDS_DANCE={id="SWORDS_DANCE",index=14,effect="CRYSTAL_EFFECT_32",power=0,type="NORMAL",category="status",accuracy=100},
  TOXIC={id="TOXIC",index=92,effect="CRYSTAL_EFFECT_21",power=0,type="POISON",category="status",accuracy=85},
  RECOVER={id="RECOVER",index=105,effect="HEAL_EFFECT",power=0,type="NORMAL",category="status",accuracy=100},
  HYPER_BEAM={id="HYPER_BEAM",index=63,effect="HYPER_BEAM_EFFECT",power=150,type="NORMAL",category="physical",accuracy=90},
  QUICK_ATTACK={id="QUICK_ATTACK",index=98,effect="NO_ADDITIONAL_EFFECT",power=40,type="NORMAL",category="physical",accuracy=100,priority=1},
  THUNDERBOLT={id="THUNDERBOLT",index=85,effect="PARALYZE_SIDE_EFFECT1",power=95,type="ELECTRIC",category="special",accuracy=100},
  EARTHQUAKE={id="EARTHQUAKE",index=89,effect="CRYSTAL_EFFECT_93",power=100,type="GROUND",category="physical",accuracy=100},
  WRAP={id="WRAP",index=35,effect="TRAP_TARGET_EFFECT",power=15,type="NORMAL",category="physical",accuracy=85},
  SPLASH={id="SPLASH",index=150,effect="SPLASH_EFFECT",power=0,type="NORMAL",category="status",accuracy=100},
}
local chart={matchups={
  {attacker="FIRE",defender="GRASS",multiplier=20},
  {attacker="WATER",defender="FIRE",multiplier=20},
  {attacker="ELECTRIC",defender="WATER",multiplier=20},
  {attacker="GROUND",defender="ELECTRIC",multiplier=20},
  {attacker="GROUND",defender="FLYING",multiplier=0},
  {attacker="NORMAL",defender="GHOST",multiplier=0},
}}
local pokemon={
  PIKACHU={types={"ELECTRIC"}}, CHARMANDER={types={"FIRE"}},
  BULBASAUR={types={"GRASS","POISON"}}, PIDGEY={types={"NORMAL","FLYING"}},
}
local function mon(species,level,types,moveIds)
  local list={}
  for _,id in ipairs(moveIds or {"TACKLE"}) do list[#list+1]={id=id,pp=20} end
  return {species=species,level=level or 50,hp=200,stats={hp=200,attack=100,defense=100,
    speed=100,special=100,specialAttack=100,specialDefense=100},moves=list,types=types}
end
local function battler(isPlayer,m,types)
  return {isPlayer=isPlayer,name=m.species,mon=m,curMoves=m.moves,curTypes=types or m.types or {},stages={}}
end
local function battle(opts)
  opts=opts or {}
  local em=mon(opts.enemySpecies or "CHARMANDER",50,opts.enemyTypes or {"FIRE"},
    opts.enemyMoves or {"TACKLE","GROWL","EMBER","TOXIC"})
  local pm=mon(opts.playerSpecies or "BULBASAUR",50,opts.playerTypes or {"GRASS","POISON"},
    opts.playerMoves or {"TACKLE"})
  local b={crystal251Active=true,kind=opts.kind or "trainer",trainer={id=opts.trainer or "OPP_BIRD_KEEPER",name="AI"},
    data={moves=moves,type_chart=chart,pokemon=pokemon,items={HYPER_POTION={name="HYPER POTION"},FULL_HEAL={name="FULL HEAL"}}},
    rng=opts.rng or function(a) return a end,enemyParty={em},enemyIndex=1}
  b.enemy=battler(false,em,opts.enemyTypes or {"FIRE"})
  b.player=battler(true,pm,opts.playerTypes or {"GRASS","POISON"})
  return b
end

-- Crystal starts every usable move at 20 and unusable slots at 80.
do
  local b=battle{}
  b.trainer.crystalAI={layers={}}
  b.enemy.curMoves[2].pp=0
  b.enemy.disabledSlot=3
  local scores=AI.scoreMoves(b,b.enemy)
  eq(scores[1].score,20,"usable move starts at Crystal score 20")
  eq(scores[2].score,80,"zero-PP move starts at score 80")
  eq(scores[3].score,80,"disabled move starts at score 80")
end

-- Wild Pokemon skip every scoring layer and choose uniformly from legal moves.
do
  local b=battle{kind="wild",rng=seq{2}}
  b.enemy.curMoves[2].pp=0
  local picked=AI.chooseMove(b.enemy,b.rng,b)
  eq(picked.id,"EMBER","wild choice samples compact usable list")
end

-- Types: immunity is +10, super-effective damage is -1.
do
  local b=battle{trainer="OPP_SCIENTIST",enemyMoves={"EARTHQUAKE","THUNDERBOLT"},playerTypes={"ELECTRIC"}}
  local scores=AI.scoreMoves(b,b.enemy)
  ok(scores[1].score<scores[2].score,"type layer prefers super-effective Earthquake")
  b.player.curTypes={"FLYING"}
  scores=AI.scoreMoves(b,b.enemy)
  ok(scores[1].score>=30,"type layer dismisses an immune move")
end

-- Offensive and setup layers use Crystal's exact +/-2 weights.
do
  local b=battle{trainer="OPP_HIKER",enemyMoves={"TACKLE","SPLASH"}}
  local scores=AI.scoreMoves(b,b.enemy)
  eq(scores[2].score,22,"offensive layer greatly discourages zero-power moves")
  b=battle{trainer="OPP_BUG_CATCHER",enemyMoves={"SWORDS_DANCE","TACKLE"},rng=seq{0}}
  scores=AI.scoreMoves(b,b.enemy)
  eq(scores[1].score,18,"setup layer greatly encourages first-turn stat boosts")
end

-- Basic/status redundancy dismisses status moves against an occupied status.
do
  local b=battle{trainer="OPP_BIRD_KEEPER",enemyMoves={"TOXIC","TACKLE"}}
  b.player.mon.status="PAR"
  local scores=AI.scoreMoves(b,b.enemy)
  ok(scores[1].score>=30,"status move is dismissed against statused target")
end

-- Smart trapping AI encourages a fresh trap but discourages refreshing one.
do
  local b=battle{trainer="OPP_SUPER_NERD",enemyMoves={"WRAP","TACKLE"},rng=seq{0}}
  local scores=AI.scoreMoves(b,b.enemy)
  eq(scores[1].score,18,"smart AI greatly encourages first-turn Wrap")
  b=battle{trainer="OPP_SUPER_NERD",enemyMoves={"WRAP","TACKLE"},rng=seq{0}}
  b.player.crystalTrapTurns=3
  scores=AI.scoreMoves(b,b.enemy)
  eq(scores[1].score,21,"smart AI discourages Wrap while the target is trapped")
  ok(scores[1].score>scores[2].score,"active trap makes another damaging move preferable")
end

-- Aggressive uses deterministic Crystal damage estimates and keeps max damage.
do
  local b=battle{trainer="OPP_GENTLEMAN",enemyMoves={"TACKLE","HYPER_BEAM"},playerTypes={"NORMAL"}}
  local scores=AI.scoreMoves(b,b.enemy)
  ok((scores[1].damage or 0)<(scores[2].damage or 0),"damage estimator ranks Hyper Beam above Tackle")
  ok(scores[1].score>scores[2].score,"aggressive layer discourages weaker damage")
end

-- Risky gives a decisive preference to a guaranteed KO.
do
  local b=battle{trainer="OPP_BIKER",enemyMoves={"TACKLE","QUICK_ATTACK"},playerTypes={"NORMAL"}}
  b.player.mon.hp=5
  local scores=AI.scoreMoves(b,b.enemy)
  ok(scores[1].score<=15 and scores[2].score<=15,"risky layer rewards KO moves")
end

-- Minimum score only; ties are sampled uniformly among minima.
do
  local b=battle{trainer="OPP_YOUNGSTER",enemyMoves={"TACKLE","TACKLE"},rng=seq{2}}
  local picked=AI.chooseMove(b.enemy,b.rng,b)
  eq(picked,b.enemy.curMoves[2],"tie chooser samples only minimum-score moves")
end

-- No legal move means Struggle.
do
  local b=battle{enemyMoves={"TACKLE"}}
  b.enemy.curMoves[1].pp=0
  local picked=AI.chooseMove(b.enemy,b.rng,b)
  eq(picked.id,"STRUGGLE","enemy uses Struggle without legal PP")
end

-- Class profile mapping includes Crystal boss layers and items.
do
  local b=battle{trainer="OPP_BLAINE"}
  local p=AI.profileFor(b)
  eq(#p.layers,7,"boss profile gets seven Crystal scoring layers")
  eq(p.items[1],"MAX_POTION","Blaine gets Crystal Max Potion")
  eq(p.items[2],"FULL_HEAL","Blaine gets Crystal Full Heal")
end

-- Battle Tower always uses Falkner's full scoring row, permits AI switching,
-- and never exposes trainer-item slots.
do
  local b=battle{trainer="OPP_BLAINE"}
  b.battleTower=true
  local p=AI.profileFor(b)
  eq(#p.layers,7,"Battle Tower uses the full Crystal AI layer set")
  eq(#p.items,0,"Battle Tower disables trainer items")
  eq(p.switch,"sometimes","Battle Tower uses Falkner switch frequency")
  b.enemy.mon.hp=20
  b.enemyParty={b.enemy.mon}
  eq(AI.classAction(b),nil,"Battle Tower AI cannot select a trainer item")
end

-- Switch candidate prefers immunity/resistance plus a super-effective reply.
do
  local b=battle{trainer="OPP_BIRD_KEEPER",playerTypes={"ELECTRIC"},playerMoves={"THUNDERBOLT"}}
  b.player.lastMove="THUNDERBOLT"; b.player.usedMoves={"THUNDERBOLT"}
  local fire=mon("CHARMANDER",50,{"FIRE"},{"TACKLE"})
  local ground=mon("PIKACHU",50,{"GROUND"},{"EARTHQUAKE"})
  b.enemyParty={b.enemy.mon,fire,ground}
  local index=AI.switchCandidate(b)
  eq(index,3,"switch search prefers immune mon with super-effective move")
end

-- Perish count 1 forces maximum switch tier; trapping blocks switching.
do
  local b=battle{trainer="OPP_BIRD_KEEPER"}
  b.enemyParty={b.enemy.mon,mon("PIKACHU",40,{"ELECTRIC"},{"TACKLE"})}
  b.enemy.perishTurns=1
  local assessment=AI.switchAssessment(b)
  eq(assessment.tier,3,"Perish count one requests maximum switch chance")
  b.enemy.cantEscape=true
  eq(AI.switchAssessment(b),nil,"Mean Look blocks AI switching")
end

-- Crystal switch frequency thresholds are direct byte comparisons.
do
  local b=battle{rng=seq{50,51}}
  eq(AI.shouldSwitch(b,"sometimes",1),true,"sometimes tier 1 succeeds below 51")
  eq(AI.shouldSwitch(b,"sometimes",1),false,"sometimes tier 1 fails at 51")
end

-- Item slots are not consumed until the action actually executes.
do
  local b=battle{trainer="OPP_BROCK"}
  b.enemy.mon.hp=100
  b.enemyParty={b.enemy.mon}
  local action=AI.classAction(b)
  eq(action.item,"HYPER_POTION","Brock selects his Crystal item")
  ok(not next(b.crystalTrainerItemsUsed),"selection alone does not consume trainer item")
end

-- Used-move tracking mirrors Crystal's four-entry unique list and AI state.
do
  local b=battle{}
  local user=b.player
  AI.recordMove(b,user,moves.TACKLE)
  AI.recordMove(b,user,moves.EMBER)
  AI.recordMove(b,user,moves.TACKLE)
  AI.recordMove(b,user,moves.WATER_GUN)
  AI.recordMove(b,user,moves.GROWL)
  AI.recordMove(b,user,moves.TOXIC)
  eq(#b.crystalPlayerUsedMoves,4,"used-move history is capped at four")
  eq(b.crystalPlayerUsedMoves[1],"EMBER","fifth unique move drops the oldest")
  eq(b.crystalPlayerUsedMoves[4],"TOXIC","newest used move occupies the final slot")
  eq(user.crystalTurnsTaken,6,"each non-charge move increments turns taken")
  eq(user.crystalLastMoveCategory,"status","last move category is recorded for AI")
  eq(user.lastCounterMove,"TOXIC","last counter move mirrors the displayed move")
  AI.recordMove(b,user,moves.TACKLE,{chargeRelease=true})
  eq(user.crystalTurnsTaken,6,"charge release does not increment turns taken")
  eq(user.lastCounterMove,"TOXIC","charge release does not replace last move")
end

-- Counter and Mirror Coat estimate the previous opposing damage category.
do
  local b=battle{enemyMoves={"TACKLE"}}
  b.lastDamage=37
  b.player.crystalLastMoveCategory="physical"
  moves.COUNTER={id="COUNTER",index=68,effect="COUNTER_EFFECT",power=1,type="FIGHTING",category="physical",accuracy=100}
  moves.MIRROR_COAT={id="MIRROR_COAT",index=243,effect="CRYSTAL_EFFECT_90",power=1,type="PSYCHIC",category="special",accuracy=100}
  eq(AI.estimateDamage(b,b.enemy,b.player,{id="COUNTER",pp=20}),74,"Counter estimate doubles physical damage")
  eq(AI.estimateDamage(b,b.enemy,b.player,{id="MIRROR_COAT",pp=20}),0,"Mirror Coat rejects physical damage")
  b.player.crystalLastMoveCategory="special"
  eq(AI.estimateDamage(b,b.enemy,b.player,{id="MIRROR_COAT",pp=20}),74,"Mirror Coat estimate doubles special damage")
end

-- Runtime installation records live move use before delegating to BattleState.
do
  local fakeTrainerAI={
    chooseMove=function() return nil end,
    classAction=function() return nil end,
    useItem=function() return {} end,
  }
  local fakeBattleState={
    performMove=function(self,user,target,moveInst) self._baseMove=moveInst.id end,
  }
  package.loaded["src.battle.TrainerAI"]=fakeTrainerAI
  package.loaded["src.battle.BattleState"]=fakeBattleState
  AI.installRuntime()
  local b=battle{}
  function b:moveDef(inst) return self.data.moves[inst.id] end
  fakeBattleState.performMove(b,b.player,b.enemy,b.player.curMoves[1],false)
  eq(b._baseMove,"TACKLE","AI move tracker delegates to the live move pipeline")
  eq(b.player.crystalTurnsTaken,1,"live move tracker increments turns taken")
  eq(b.crystalPlayerUsedMoves[1],"TACKLE","live move tracker records player move knowledge")
end

if failures>0 then
  io.stderr:write(("%d/%d checks failed (Crystal enemy AI)\n"):format(failures,checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal enemy AI)"):format(checks,checks))
