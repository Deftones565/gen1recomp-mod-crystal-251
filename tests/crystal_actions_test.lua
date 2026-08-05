package.path = "./?.lua;./?/init.lua;" .. package.path

local Actions = require("mods.CRYSTAL_251.battle.crystal_actions")

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
    fail(("%s (got %s, want %s)"):format(message, tostring(got), tostring(want)))
  end
end

local function sequence(values)
  local index = 0
  return function(a, b)
    index = index + 1
    local value = values[index]
    if value == nil then value = a end
    if value < a then value = a end
    if value > b then value = b end
    return value
  end
end

local function mon(level, otId, moves)
  return {
    species="PIKACHU", level=level or 50, otId=otId,
    hp=200, stats={hp=200,attack=100,defense=100,speed=100,
      special=100,specialAttack=100,specialDefense=100},
    moves=moves or {
      {id="TACKLE",pp=35},{id="GROWL",pp=40},
      {id="THUNDER_WAVE",pp=20},{id="QUICK_ATTACK",pp=30},
    },
  }
end

local function battler(isPlayer, m)
  return {
    isPlayer=isPlayer, name=isPlayer and "SPARKY" or "RAT",
    mon=m, curMoves=m.moves, stages={}, curTypes={"ELECTRIC"},
  }
end

local function battle(opts)
  opts = opts or {}
  local playerMon = mon(opts.level or 80, opts.otId or 999, opts.moves)
  local enemyMon = mon(opts.enemyLevel or 50, 2)
  local b = {
    crystal251Active=true, kind=opts.kind or "trainer",
    game={save={player={id=123,name="RED"},inventory=opts.inventory or {}}},
    data={constants={badges={
      {id="B1"},{id="B2"},{id="B3"},{id="B4"},
      {id="B5"},{id="B6"},{id="B7"},{id="B8"},
    }},items={
      FULL_RESTORE={name="FULL RESTORE"}, MAX_POTION={name="MAX POTION"},
      HYPER_POTION={name="HYPER POTION"}, SUPER_POTION={name="SUPER POTION"},
      POTION={name="POTION"}, FULL_HEAL={name="FULL HEAL"},
      X_ATTACK={name="X ATTACK"}, X_DEFEND={name="X DEFEND"},
      X_SPEED={name="X SPEED"}, X_SPECIAL={name="X SPECIAL"},
      X_ACCURACY={name="X ACCURACY"}, GUARD_SPEC={name="GUARD SPEC."},
      DIRE_HIT={name="DIRE HIT"},
    }},
    trainer={name="CAL"}, aiUses=2,
    rng=opts.rng or function(a) return a end,
    messages={},
  }
  b.player = battler(true, playerMon)
  b.enemy = battler(false, enemyMon)
  b.enemyParty = opts.enemyParty or {enemyMon, mon(40,2)}
  function b:sayNext(message) self.messages[#self.messages+1]=message end
  return b
end

-- Nibble swapping is the first obedience roll's exact GB operation.
eq(Actions.swapNibbles(0x12), 0x21, "obedience RNG swaps nibbles")
eq(Actions.swapNibbles(0xff), 0xff, "nibble swap preserves ff")

-- Crystal obedience badge thresholds, mapped onto the eight-badge world.
for badges, expected in pairs({[0]=10,[1]=10,[2]=30,[3]=30,[4]=50,
                                [5]=50,[6]=70,[7]=70,[8]=101}) do
  local inventory = {}
  for i=1,badges do inventory["B"..i]=true end
  eq(Actions.obedienceLevel(battle{inventory=inventory}), expected,
    ("%d badges set obedience level"):format(badges))
end

do
  local b=battle{inventory={B1=true,B3=true}}
  eq(Actions.obedienceLevel(b),10,
    "out-of-order badges do not substitute for the obedience badge")
  b.game.save.inventory.B2=true
  eq(Actions.obedienceLevel(b),30,
    "second badge slot unlocks level-30 obedience")
end

-- Only an outsider player mon in an ordinary local battle can disobey.
do
  local b = battle{level=100,otId=123,rng=sequence{1,20,10,0}}
  eq(Actions.checkObedience(b,b.player,b.player.curMoves[1]).obey,true,
    "matching OT always obeys")
  b.player.mon.otId=999; b.kind="link"
  eq(Actions.checkObedience(b,b.player,b.player.curMoves[1]).obey,true,
    "link battles skip obedience")
  b.kind="trainer"; b.battleTower=true
  eq(Actions.checkObedience(b,b.player,b.player.curMoves[1]).obey,true,
    "Battle Tower skips obedience")
  b.battleTower=nil
  eq(Actions.checkObedience(b,b.enemy,b.enemy.curMoves[1]).obey,true,
    "enemy battlers cannot disobey")
end

-- Level at or below the badge cap always obeys without consuming RNG.
do
  local called = 0
  local b = battle{level=30,inventory={B1=true,B2=true},rng=function(a) called=called+1 return a end}
  eq(Actions.checkObedience(b,b.player,b.player.curMoves[1]).obey,true,
    "level equal to cap obeys")
  eq(called,0,"automatic obedience consumes no RNG")
end

-- First accepted swapped roll below the cap obeys.
do
  local b = battle{rng=sequence{0}}
  eq(Actions.checkObedience(b,b.player,b.player.curMoves[1]).obey,true,
    "first obedience roll can obey")
end

-- The second roll can make the outsider choose a different legal move.
do
  local b = battle{rng=sequence{1,0,1}}
  local result = Actions.checkObedience(b,b.player,b.player.curMoves[1])
  eq(result.kind,"alternate","second obedience roll selects another move")
  eq(result.action,b.player.curMoves[2],"alternate excludes selected move")
  b.player.disabledSlot=2
  b.rng=sequence{1,0,1}
  result=Actions.checkObedience(b,b.player,b.player.curMoves[1])
  ok(result.kind~="alternate","Disable prevents alternate disobedience move")
end

-- Zero-PP and undefined choices cannot be selected as the alternate.
do
  local moves={{id="TACKLE",pp=10},{id="GROWL",pp=0},{id="TAIL_WHIP",pp=5}}
  local b=battle{moves=moves,rng=sequence{1,0,1}}
  local result=Actions.checkObedience(b,b.player,moves[1])
  eq(result.action,moves[3],"alternate requires positive PP")
end

-- Sleep-only moves take Crystal's special ignored-while-sleeping branch.
do
  local b=battle{rng=sequence{1}}
  b.player.mon.status="SLP"
  local action={id="SNORE",pp=15}; b.player.curMoves={action,{id="TACKLE",pp=10}}
  local result=Actions.checkObedience(b,b.player,action)
  eq(result.kind,"ignored_sleep","sleep-only move uses special obedience branch")
end

-- Third-roll outcomes: nap, self-hit, and the four no-action messages.
do
  local b=battle{level=80,rng=sequence{1,20,0,8}}
  local result=Actions.checkObedience(b,b.player,b.player.curMoves[1])
  eq(result.kind,"nap","low third roll makes outsider nap")
  eq(result.turns,1,"nap counter follows Crystal nonzero sleep roll")

  b.rng=sequence{1,20,5}
  result=Actions.checkObedience(b,b.player,b.player.curMoves[1])
  eq(result.kind,"self_hit","middle third roll causes self-hit")

  b.rng=sequence{1,20,10,0}
  result=Actions.checkObedience(b,b.player,b.player.curMoves[1])
  eq(result.kind,"nothing","high third roll does nothing")
  ok(result.message:find("loafing",1,true)~=nil,"do-nothing choice 0 loafs")
  for roll,word in ipairs({"won't obey","turned away","ignored orders"}) do
    b.rng=sequence{1,20,10,roll}
    result=Actions.checkObedience(b,b.player,b.player.curMoves[1])
    ok(result.message:find(word,1,true)~=nil,
      "do-nothing message choice "..roll)
  end
end

-- Applying disobedience sets sleep, executes an alternate, or hurts self.
do
  local b=battle()
  Actions.applyDisobedience(b,b.player,b.enemy,
    {interrupted=true,kind="nap",turns=4,message="nap"})
  eq(b.player.mon.status,"SLP","nap inflicts sleep")
  eq(b.player.sleepTurns,4,"nap stores exact sleep counter")

  local performed
  function b:performMove(user,target,action,called) performed={user,target,action,called} end
  Actions.applyDisobedience(b,b.player,b.enemy,
    {interrupted=true,kind="alternate",action=b.player.curMoves[2],message="alt"})
  eq(performed[3],b.player.curMoves[2],"alternate executes replacement move")
  eq(performed[4],false,"alternate is a normal PP-consuming move")

  b.player.mon.status=nil; b.player.mon.hp=100
  function b:computeDamage() return 17 end
  function b:applyDamage(target,amount) target.mon.hp=target.mon.hp-amount return amount end
  function b:clearVolatiles(target,selfHit) target.cleared=selfHit end
  Actions.applyDisobedience(b,b.player,b.enemy,
    {interrupted=true,kind="self_hit",message="no"})
  eq(b.player.mon.hp,83,"disobedience self-hit applies confusion damage")
  eq(b.player.cleared,nil,"disobedience self-hit does not run CantMove cleanup")
  eq(b.player.lastMove,nil,"disobedience clears remembered last move")
end

-- Selecting a different move clears Rage and consecutive state before the
-- status gate, while selecting Rage itself preserves the counter.
do
  local b=battle(); local user=b.player
  user.rageMove,user.crystalRageMove,user.crystalRageCounter={}, {}, 4
  user.furyCutterCount=3; user.protectChain=2; user.destinyBond=true
  Actions.onSelectedAction(user,{id="TACKLE"})
  eq(user.rageMove,nil,"another move clears Rage")
  eq(user.crystalRageCounter,nil,"another move clears Rage counter")
  eq(user.furyCutterCount,nil,"another move clears Fury Cutter")
  eq(user.protectChain,nil,"another move clears Protect chain")
  eq(user.destinyBond,nil,"attempting a move ends Destiny Bond")
  user.rageMove,user.crystalRageMove,user.crystalRageCounter={}, {}, 2
  Actions.onSelectedAction(user,{id="RAGE"})
  eq(user.crystalRageCounter,2,"selecting Rage preserves its counter")
end

-- PP handling: one point on the initial selected move, none on continuations,
-- called moves or Struggle, and never below zero.
do
  local b=battle(); local user=b.player; local move=user.curMoves[1]
  move.pp=3
  local usable,consumed=Actions.consumePP(b,user,move,false)
  eq(usable,true,"normal move with PP is usable")
  eq(consumed,true,"normal move reports PP consumption")
  eq(move.pp,2,"normal selected move loses one PP")

  user.charging=move; user.chargeReady=true
  Actions.consumePP(b,user,move,false)
  eq(move.pp,2,"charge release consumes no PP")
  user.charging,user.chargeReady=nil,nil

  user.thrashTurns,user.thrashMove=2,move
  Actions.consumePP(b,user,move,false)
  eq(move.pp,2,"rampage continuation consumes no PP")
  user.thrashTurns,user.thrashMove=nil,nil

  user.forcedMove,user.forcedMoveTurns,user.rolloutCount=move,3,1
  Actions.consumePP(b,user,move,false)
  eq(move.pp,2,"Rollout continuation consumes no PP")
  user.forcedMove,user.forcedMoveTurns,user.rolloutCount=nil,nil,nil

  user.rageMove=move
  Actions.consumePP(b,user,move,false)
  eq(move.pp,1,"each selected Crystal Rage consumes PP")
  user.rageMove=nil

  Actions.consumePP(b,user,move,true)
  eq(move.pp,1,"called move consumes no called-move PP")
  local struggle={id="STRUGGLE",pp=1,struggle=true}
  Actions.consumePP(b,user,struggle,false)
  eq(struggle.pp,1,"Struggle consumes no PP")
  move.pp=0
  usable,consumed=Actions.consumePP(b,user,move,false)
  eq(usable,false,"zero-PP normal move is rejected")
  eq(move.pp,0,"PP never underflows")
end

-- Enemy move legality uses real Crystal PP and falls back to Struggle.
do
  local b=battle()
  b.enemy.curMoves={{id="TACKLE",pp=0},{id="GROWL",pp=4}}
  b.rng=sequence{1}
  eq(Actions.legalizeEnemyAction(b,b.enemy,b.enemy.curMoves[1]),b.enemy.curMoves[2],
    "enemy replaces zero-PP selection with legal move")
  b.enemy.curMoves[2].pp=0
  local action=Actions.legalizeEnemyAction(b,b.enemy,b.enemy.curMoves[1])
  eq(action.id,"STRUGGLE","enemy Struggles when no move is usable")
  eq(action.struggle,true,"enemy fallback is marked Struggle")
  b.enemy.curMoves[1].pp=3; b.enemy.disabledSlot=1
  action=Actions.legalizeEnemyAction(b,b.enemy,b.enemy.curMoves[1])
  eq(action.id,"STRUGGLE","disabled sole move also forces Struggle")
end

-- Trainer item eligibility requires a local trainer battle, remaining uses,
-- and an active monster tied for the highest level in its party.
do
  local b=battle()
  eq(Actions.highestLevelEnemy(b),true,"highest-level active enemy qualifies")
  eq(Actions.trainerItemEligible(b,"POTION"),true,"supported trainer item qualifies")
  b.enemyParty[2].level=60
  eq(Actions.trainerItemEligible(b,"POTION"),false,"lower-level active enemy cannot use item")
  b.enemyParty[2].level=40; b.aiUses=0
  eq(Actions.trainerItemEligible(b,"POTION"),false,"exhausted trainer item count blocks use")
  b.aiUses=1; b.kind="link"
  eq(Actions.trainerItemEligible(b,"POTION"),false,"link battle blocks trainer items")
  b.kind="trainer"; b.battleTower=true
  eq(Actions.trainerItemEligible(b,"POTION"),false,"Battle Tower blocks trainer items")
end

-- Item usefulness mirrors effect preconditions.
do
  local b=battle(); local e=b.enemy
  e.mon.hp=e.mon.stats.hp
  eq(Actions.trainerItemUseful(b,"POTION"),false,"healing item skipped at full HP")
  e.mon.hp=50
  eq(Actions.trainerItemUseful(b,"POTION"),true,"healing item useful below max HP")
  e.mon.hp=e.mon.stats.hp; e.mon.status="PSN"
  eq(Actions.trainerItemUseful(b,"FULL_HEAL"),true,"Full Heal needs major status")
  e.mon.status=nil; e.confusedTurns=3
  eq(Actions.trainerItemUseful(b,"FULL_HEAL"),false,"Full Heal ignores confusion bug")
  eq(Actions.trainerItemUseful(b,"FULL_RESTORE"),true,"Full Restore can cure confusion")
  e.confusedTurns=nil; e.stages.attack=6
  eq(Actions.trainerItemUseful(b,"X_ATTACK"),false,"maxed X stat is not useful")
end

-- Exact trainer item effects, including the enemy Full Heal confusion bug.
do
  local b=battle(); local e=b.enemy
  e.mon.status="PSN"; e.toxicCounter=5; e.confusedTurns=3
  Actions.useTrainerItem(b,"FULL_HEAL")
  eq(e.mon.status,nil,"Full Heal clears major status")
  eq(e.toxicCounter,nil,"Full Heal clears Toxic counter")
  eq(e.confusedTurns,3,"enemy Full Heal does not cure confusion")

  e.mon.hp=1; e.mon.status="BRN"; e.confusedTurns=2
  Actions.useTrainerItem(b,"FULL_RESTORE")
  eq(e.mon.hp,e.mon.stats.hp,"Full Restore heals to max")
  eq(e.mon.status,nil,"Full Restore cures major status")
  eq(e.confusedTurns,nil,"Full Restore cures confusion")

  e.mon.hp=10; Actions.useTrainerItem(b,"POTION")
  eq(e.mon.hp,30,"Potion heals 20")
  Actions.useTrainerItem(b,"SUPER_POTION")
  eq(e.mon.hp,80,"Super Potion heals 50")
  Actions.useTrainerItem(b,"HYPER_POTION")
  eq(e.mon.hp,e.mon.stats.hp,"Hyper Potion heals up to 200")
  e.mon.hp=1; Actions.useTrainerItem(b,"MAX_POTION")
  eq(e.mon.hp,e.mon.stats.hp,"Max Potion heals to max")

  Actions.useTrainerItem(b,"X_ATTACK")
  eq(e.stages.attack,1,"X Attack raises Attack")
  Actions.useTrainerItem(b,"X_DEFEND")
  eq(e.stages.defense,1,"X Defend raises Defense")
  Actions.useTrainerItem(b,"X_SPEED")
  eq(e.stages.speed,1,"X Speed raises Speed")
  Actions.useTrainerItem(b,"X_SPECIAL")
  eq(e.stages.specialAttack,1,"X Special raises Special Attack only")
  eq(e.stages.specialDefense,nil,"X Special does not raise Special Defense")
  Actions.useTrainerItem(b,"X_ACCURACY")
  eq(e.xAccuracy,true,"X Accuracy sets never-miss flag")
  Actions.useTrainerItem(b,"GUARD_SPEC")
  eq(e.mist,true,"Guard Spec sets Mist")
  Actions.useTrainerItem(b,"DIRE_HIT")
  eq(e.focusEnergy,true,"Dire Hit sets Focus Energy")
end

-- Spending a trainer item clears the exact locked/consecutive state bytes.
do
  local b=battle(); local e=b.enemy
  e.bideTurns,e.bideDamage,e.crystalBide=2,30,true
  e.furyCutterCount=4; e.protectChain=3; e.protectLastTurn=7
  e.rageMove={id="RAGE"}; e.crystalRageMove=e.rageMove; e.crystalRageCounter=5
  e.lastCounterMove="TACKLE"
  Actions.useTrainerItem(b,"POTION")
  eq(e.bideTurns,nil,"trainer item clears Bide")
  eq(e.furyCutterCount,nil,"trainer item clears Fury Cutter")
  eq(e.protectChain,nil,"trainer item clears Protect chain")
  eq(e.rageMove,nil,"trainer item clears Rage")
  eq(e.crystalRageCounter,nil,"trainer item clears Rage counter")
  eq(e.lastCounterMove,nil,"trainer item clears last counter move")
end


-- Runtime wrappers keep all changes Crystal-local, decrement both enemy and
-- player PP exactly once, and replace illegal enemy choices before execution.
do
  local FakeBattleState = {}
  function FakeBattleState:menuLockedAction(battler) return battler.rageMove end
  function FakeBattleState:enemyAction() return self.enemy.curMoves[1] end
  function FakeBattleState:statusInterrupt() return false end
  function FakeBattleState:performMove(user,target,moveInst,isCalled)
    self.performed={user=user,target=target,move=moveInst,called=isCalled}
    self.baseSawStruggle=moveInst.struggle == true
    if moveInst.struggle then self.baseAppliedRecoil=true end
    if not moveInst.struggle and not isCalled then
      moveInst.pp=math.max(0,(moveInst.pp or 0)-1)
    end
    if moveInst.id == "SKETCH" then
      moveInst.id="TACKLE"
      moveInst.pp=35
    end
    return "performed"
  end
  function FakeBattleState:playerHasPP() return false end

  local FakeTrainerAI = {}
  function FakeTrainerAI.classAction(b) return b.fakeClassAction end
  function FakeTrainerAI.useItem() return {"base"} end
  package.loaded["src.battle.BattleState"] = FakeBattleState
  package.loaded["src.battle.TrainerAI"] = FakeTrainerAI
  Actions.installRuntime()

  local b=battle{otId=123}
  setmetatable(b,{__index=FakeBattleState})
  b.player.rageMove=b.player.curMoves[1]
  eq(b:menuLockedAction(b.player),nil,
    "runtime Crystal Rage does not force the next action")
  b.player.encoreTurns,b.player.encoreMove=2,"TACKLE"
  eq(b:menuLockedAction(b.player),b.player.curMoves[1],
    "Encore can still force Rage when Rage is the encored move")
  b.player.encoreTurns,b.player.encoreMove=nil,nil
  b.player.rageMove=nil
  b.enemy.curMoves={{id="TACKLE",pp=0},{id="GROWL",pp=3}}
  b.rng=sequence{1}
  eq(b:enemyAction(),b.enemy.curMoves[2],
    "runtime enemy action replaces exhausted move")

  local move=b.player.curMoves[1]; move.pp=3
  eq(b:performMove(b.player,b.enemy,move,false),"performed",
    "runtime PP wrapper delegates move execution")
  eq(move.pp,2,"runtime wrapper and base consume only one PP total")
  eq(b.baseSawStruggle,false,
    "ordinary PP consumption never masquerades as Struggle")
  eq(b.baseAppliedRecoil,nil,
    "ordinary PP consumption cannot trigger Struggle recoil")

  local sketch={id="SKETCH",pp=1}
  eq(b:performMove(b.player,b.enemy,sketch,false),"performed",
    "runtime PP wrapper delegates Sketch")
  eq(sketch.id,"TACKLE","runtime PP wrapper preserves Sketch replacement")
  eq(sketch.pp,35,"runtime PP wrapper preserves copied move base PP")
  eq(b:playerHasPP(),true,"runtime player PP scan uses legal Crystal moves")

  b.player.mon.otId=999; b.player.mon.level=80
  b.rng=sequence{1,0,1}
  local stopped=b:statusInterrupt(b.player,b.enemy,b.player.curMoves[1])
  eq(stopped,true,"runtime obedience interrupts selected action")
  eq(b.performed.move,b.player.curMoves[2],
    "runtime obedience executes alternate move")

  b.fakeClassAction={special="aiItem",item="POTION"}
  b.enemy.mon.hp=10; b.enemyParty={b.enemy.mon,mon(40,2)}; b.aiUses=1
  eq(FakeTrainerAI.classAction(b).item,"POTION",
    "runtime permits useful eligible trainer item")
  local messages=FakeTrainerAI.useItem(b,"POTION")
  eq(b.enemy.mon.hp,30,"runtime trainer item uses Crystal effect")
  ok(type(messages)=="table" and #messages>0,
    "runtime trainer item returns battle messages")

  local non=battle(); non.crystal251Active=false
  setmetatable(non,{__index=FakeBattleState})
  non.enemy.curMoves={{id="TACKLE",pp=0},{id="GROWL",pp=3}}
  eq(non:enemyAction(),non.enemy.curMoves[1],
    "runtime wrappers preserve non-Crystal enemy selection")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal obedience, PP and trainer items)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal obedience, PP and trainer items)")
  :format(checks, checks))
