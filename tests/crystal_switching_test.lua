package.path = "./?.lua;./?/init.lua;" .. package.path

local Runtime = require("src.mods.Runtime")
local emitted = {}
Runtime.events = {
  emit=function(_, name, payload) emitted[#emitted + 1] = { name=name, payload=payload } end,
}

local function makeBattler(_, mon, isPlayer)
  return {
    mon=mon,
    isPlayer=isPlayer,
    name=mon.nickname or mon.species,
    curTypes=mon.types or { "NORMAL" },
    curStats=mon.stats,
    curMoves=mon.moves or {},
    stages={},
  }
end
local BattleStateStub = { makeBattler=makeBattler }
function BattleStateStub.enemyAction(self) return self.testEnemyAction end
function BattleStateStub.executeAction(self, user, target, action)
  self.lastExecuted = { user=user, target=target, action=action }
end
function BattleStateStub.resolveSwitch(self, newMon)
  self.delegatedSwitch = newMon
  return "delegated"
end
function BattleStateStub.resolveTurn(self, action)
  self.delegatedTurn = action
  return "turn"
end
package.loaded["src.battle.BattleState"] = BattleStateStub

local Switching = require("mods.CRYSTAL_251.battle.crystal_switching")
local Interpreter = require("mods.CRYSTAL_251.battle.command_interpreter")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n")
      :format(label, tostring(got), tostring(want)))
  end
end
local function check(value, label) eq(not not value, true, label) end

local function mon(species, hp, maxhp, types)
  return {
    species=species,
    nickname=species,
    hp=hp or maxhp or 160,
    level=50,
    stats={ hp=maxhp or 160, attack=100, defense=100, speed=100,
      specialAttack=100, specialDefense=100 },
    types=types or { "NORMAL" },
    moves={},
  }
end

local function battler(species, isPlayer, hp, maxhp, types)
  return makeBattler(nil, mon(species, hp, maxhp, types), isPlayer)
end

local function battle(playerParty, enemyParty, kind)
  local b = {
    data={},
    kind=kind or "trainer",
    game={ save={ party=playerParty or {} } },
    enemyParty=enemyParty or {},
    enemyIndex=1,
    turnCount=1,
    messages={},
    crystal251Active=true,
  }
  b.player = makeBattler(nil, b.game.save.party[1], true)
  b.enemy = makeBattler(nil, b.enemyParty[1] or mon("WILD"), false)
  function b:syncSides() self.sides={ self.player, self.enemy } end
  function b:sideOf(who) return who.isPlayer and self.player or self.enemy end
  function b:sayNext(text) self.messages[#self.messages + 1] = text end
  function b:drainNext(who, hp) self.drained={ who=who, hp=hp } end
  function b:cancelMoveAnim() self.animCancelled=true end
  b:syncSides()
  return b
end

local p1, p2, p3 = mon("P1"), mon("P2"), mon("P3")
local e1, e2, e3 = mon("E1"), mon("E2"), mon("E3")
local b = battle({p1,p2,p3}, {e1,e2,e3})
local indexes, party, active = Switching.healthyIndexes(b, b.player)
eq(#indexes, 2, "player has two healthy replacements")
eq(indexes[1], 2, "player first replacement index")
eq(indexes[2], 3, "player second replacement index")
eq(party, b.game.save.party, "player party selected")
eq(active, 1, "player active index")
indexes, party, active = Switching.healthyIndexes(b, b.enemy)
eq(#indexes, 2, "enemy has two healthy replacements")
eq(indexes[1], 2, "enemy first replacement index")
eq(indexes[2], 3, "enemy second replacement index")
eq(party, b.enemyParty, "enemy party selected")
eq(active, 1, "enemy active index")
e2.hp = 0
indexes = Switching.healthyIndexes(b, b.enemy)
eq(#indexes, 1, "fainted enemy replacement excluded")
eq(indexes[1], 3, "remaining enemy replacement selected")
e2.hp = e2.stats.hp

local rolls = { 7, 0, 2 }
local at = 0
local picked = Switching.pickForcedIndex(b, b.enemy, function()
  at = at + 1
  return rolls[at]
end)
eq(picked, 3, "forced switch retries invalid raw slots")
eq(at, 3, "forced switch consumes rejection rolls")

for _, row in ipairs({
  {50,50,0,true}, {80,20,0,true}, {40,60,0,false},
  {40,60,14,false}, {40,60,15,true}, {1,100,24,false}, {1,100,25,true},
}) do
  local used = false
  local result = Switching.wildForceSucceeds(row[1], row[2], function()
    used = true
    return row[3]
  end)
  eq(result, row[4], ("wild force %d/%d roll %d"):format(row[1],row[2],row[3]))
  eq(used, row[1] < row[2], "wild force samples only when user is lower")
end

local previous = battler("OLD", true)
local incoming = battler("NEW", true)
previous.stages = { attack=3, defense=-2, speed=1 }
local passFields = {
  "substituteHP", "confusedTurns", "focusEnergy", "leechSeeded",
  "cursed", "perishTurns", "foresight", "defenseCurl", "mist",
  "cantEscape", "protect", "endure", "toxicCounter",
  "crystalRageCounter", "bideTurns",
}
for index, field in ipairs(passFields) do previous[field] = index end
local resetFields = {
  "disabledTurns", "disabledSlot", "disabledMove", "disableTurns",
  "encoreTurns", "encoreMove", "encoreSetTurn", "infatuatedWith",
  "transformed", "lastMove", "trappingTurns", "trapMove", "trapDamage",
  "boundTurns", "crystalTrapTurns", "crystalTrapSource", "crystalTrapMove",
  "destinyBond", "rolloutCount", "furyCutterCount",
}
for _, field in ipairs(resetFields) do previous[field] = "set" end
previous.nightmare = true
Switching.transferBatonState(previous, incoming)
eq(incoming.stages.attack, 3, "Baton Pass copies Attack stage")
eq(incoming.stages.defense, -2, "Baton Pass copies Defense stage")
eq(incoming.stages.speed, 1, "Baton Pass copies Speed stage")
for index, field in ipairs(passFields) do
  eq(incoming[field], index, "Baton Pass copies " .. field)
end
for _, field in ipairs(resetFields) do
  eq(incoming[field], nil, "Baton Pass resets " .. field)
end
eq(incoming.nightmare, nil, "awake Baton Pass target drops Nightmare")
incoming.mon.status = "SLP"
Switching.transferBatonState(previous, incoming)
eq(incoming.nightmare, true, "sleeping Baton Pass target keeps Nightmare")

local partialPrevious = battler("PARTIAL_OLD", true)
local partialIncoming = battler("PARTIAL_NEW", true)
partialPrevious.cantEscape = true
partialPrevious.cantEscapeFrom = { source=true }
partialPrevious.crystalTrapTurns = 3
partialPrevious.crystalTrapSource = partialPrevious.cantEscapeFrom
partialPrevious.crystalTrapMove = "WRAP"
Switching.transferBatonState(partialPrevious, partialIncoming)
eq(partialIncoming.cantEscape, nil, "Baton Pass clears partial-trap switch lock")
eq(partialIncoming.cantEscapeFrom, nil, "Baton Pass clears partial-trap source")
eq(partialIncoming.crystalTrapTurns, nil, "Baton Pass clears partial-trap turns")
eq(partialIncoming.crystalTrapSource, nil, "Baton Pass clears partial-trap residual source")
eq(partialIncoming.crystalTrapMove, nil, "Baton Pass clears partial-trap move")

local meanPrevious = battler("MEAN_OLD", true)
local meanIncoming = battler("MEAN_NEW", true)
meanPrevious.cantEscape = true
meanPrevious.cantEscapeFrom = { source=true }
Switching.transferBatonState(meanPrevious, meanIncoming)
eq(meanIncoming.cantEscape, true, "Baton Pass preserves Mean Look switch lock")
eq(meanIncoming.cantEscapeFrom, meanPrevious.cantEscapeFrom,
  "Baton Pass preserves Mean Look source")

local spikeBattle = battle({mon("P",160,160)}, {mon("E",160,160)})
local spikeCtx = { battle=spikeBattle, user=spikeBattle.player }
eq(Switching.spikes(spikeCtx)[1], "SPIKES scattered all around!", "Spikes succeeds once")
eq(spikeBattle.enemySpikes, true, "player Spikes marks enemy side")
eq(Switching.spikes(spikeCtx)[1], "But, it failed!", "second Spikes fails")
local enemyCtx = { battle=spikeBattle, user=spikeBattle.enemy }
Switching.spikes(enemyCtx)
eq(spikeBattle.playerSpikes, true, "enemy Spikes marks player side")
local sub = spikeBattle.player
sub.substituteHP = 40
local damage = Switching.applySpikes(spikeBattle, sub)
eq(damage, 20, "Spikes deals one eighth")
eq(sub.mon.hp, 140, "Spikes damages actual HP")
eq(sub.substituteHP, 40, "Spikes bypasses Substitute")
eq(sub.faintQueued, nil, "Spikes does not queue an immediate faint")
local flying = battler("FLY", false, 160, 160, {"FLYING"})
spikeBattle.enemy = flying
spikeBattle.enemySpikes = true
eq(Switching.applySpikes(spikeBattle, flying), 0, "Flying ignores Spikes")
eq(flying.mon.hp, 160, "Flying keeps HP")
local tiny = battler("TINY", false, 1, 1)
spikeBattle.enemy = tiny
eq(Switching.applySpikes(spikeBattle, tiny), 1, "Spikes has one damage floor")
eq(tiny.mon.hp, 0, "Spikes can reduce HP to zero")
eq(tiny.faintQueued, nil, "zero HP Spikes bug remains unqueued")

local lead = mon("LEAD")
local bench = mon("BENCH")
local forceBattle = battle({mon("PLAYER")}, {lead,bench})
local forceCtx = {
  battle=forceBattle, user=forceBattle.player, target=forceBattle.enemy,
  move={id="ROAR"}, rng=function() return 1 end,
}
local failed = Switching.forceSwitch(forceCtx)
check(failed[1]:find("didn't affect",1,true), "trainer force fails before target action")
eq(forceBattle.enemy.mon, lead, "failed force keeps active enemy")
forceBattle.crystalActedSides = { enemy=1 }
local forced = Switching.forceSwitch(forceCtx)
check(forced[1]:find("dragged out",1,true), "trainer force succeeds after target action")
eq(forceBattle.enemy.mon, bench, "trainer force selects healthy replacement")
eq(forceBattle.enemyIndex, 2, "trainer force updates enemy index")
eq(emitted[#emitted].payload.forced, true, "forced switch event is marked")

local trappedLead = mon("TRAPPED")
local trappedBench = mon("FREE")
local trappedBattle = battle({mon("PLAYER")}, {trappedLead,trappedBench})
trappedBattle.enemy.cantEscape = true
trappedBattle.crystalActedSides = { enemy=1 }
local trappedCtx = {
  battle=trappedBattle, user=trappedBattle.player, target=trappedBattle.enemy,
  move={id="WHIRLWIND"}, rng=function() return 1 end,
}
Switching.forceSwitch(trappedCtx)
eq(trappedBattle.enemy.mon, trappedBench, "forced switch bypasses Mean Look")

local soloBattle = battle({mon("PLAYER")}, {mon("SOLO")})
soloBattle.crystalActedSides = { enemy=1 }
local soloCtx = {
  battle=soloBattle, user=soloBattle.player, target=soloBattle.enemy,
  move={id="ROAR"}, rng=function() return 0 end,
}
check(Switching.forceSwitch(soloCtx)[1]:find("didn't affect",1,true),
  "forced switch fails without backup")

for _, battleType in ipairs({"forceshiny","trap","celebi","suicune"}) do
  local special = battle({mon("PLAYER")}, {mon("A"),mon("B")})
  special.battleType = battleType
  special.crystalActedSides = { enemy=1 }
  local ctx = { battle=special, user=special.player, target=special.enemy,
    move={id="ROAR"}, rng=function() return 1 end }
  Switching.forceSwitch(ctx)
  eq(special.enemy.mon.species, "A", "force switch blocked in " .. battleType)
end

local wild = battle({mon("PLAYER")}, {}, "wild")
wild.enemy.mon.level = 40
wild.player.mon.level = 60
local wildCtx = { battle=wild, user=wild.player, target=wild.enemy,
  move={id="ROAR"}, rng=function() return 0 end }
Switching.forceSwitch(wildCtx)
eq(wild.result, "run", "wild Roar ends battle")
eq(wild.afterQueue, "finish", "wild Roar enters finish phase")

local bpLead = mon("BP_LEAD")
local bpFirst = mon("BP_FIRST")
local bpChosen = mon("BP_CHOSEN")
local bpBattle = battle({bpLead,bpFirst,bpChosen}, {mon("ENEMY")})
bpBattle.player.stages.attack = 4
bpBattle.player.substituteHP = 55
bpBattle.batonPassChoice = function() return 3 end
local bpCtx = { battle=bpBattle, user=bpBattle.player, target=bpBattle.enemy,
  say=function(text) bpBattle:sayNext(text) end }
eq(Switching.batonPass(bpCtx), true, "Baton Pass succeeds")
eq(bpBattle.player.mon, bpChosen, "Baton Pass uses selected replacement")
eq(bpBattle.player.stages.attack, 4, "Baton Pass transfers stages")
eq(bpBattle.player.substituteHP, 55, "Baton Pass transfers Substitute")
eq(emitted[#emitted].payload.batonPass, true, "Baton Pass event is marked")

local failBP = battle({mon("ONLY")}, {mon("ENEMY")})
local failCtx = { battle=failBP, user=failBP.player, target=failBP.enemy,
  say=function(text) failBP:sayNext(text) end }
eq(Switching.batonPass(failCtx), false, "Baton Pass fails without replacement")
eq(failBP.player.mon.species, "ONLY", "failed Baton Pass keeps user")
eq(failBP.animCancelled, true, "failed Baton Pass cancels animation")

local patched = {}
local fakeMod = { content={ moves={
  get=function(_, id) return id == "ROAR" or id == "WHIRLWIND" end,
  patch=function(_, id, row) patched[id]=row end,
} } }
local crystalMoves = {
  ROAR={ id="ROAR", effect="SWITCH_AND_TELEPORT_EFFECT" },
  WHIRLWIND={ id="WHIRLWIND", effect="SWITCH_AND_TELEPORT_EFFECT" },
}
eq(Switching.patchMoves(fakeMod, crystalMoves), 2, "switch patch routes two moves")
eq(crystalMoves.ROAR.effect, "CRYSTAL_EFFECT_1C", "Roar gets Crystal effect")
eq(crystalMoves.WHIRLWIND.effect, "CRYSTAL_EFFECT_1C", "Whirlwind gets Crystal effect")
eq(patched.ROAR.priority, -1, "Roar gets Crystal priority")
eq(patched.WHIRLWIND.priority, -1, "Whirlwind gets Crystal priority")

local rows = {
  {id="ROAR", byte=0x1c, power=0, family="ForceSwitch", mode="switch",
    commands={"checkobedience","usedmovetext","doturn","checkhit","forceswitch","endmove"}},
  {id="WHIRLWIND", byte=0x1c, power=0, family="ForceSwitch", mode="switch",
    commands={"checkobedience","usedmovetext","doturn","checkhit","forceswitch","endmove"}},
  {id="BATON_PASS", byte=0x7f, power=0, family="BatonPass", mode="switch",
    commands={"checkobedience","usedmovetext","doturn","batonpass","endmove"}},
  {id="PURSUIT", byte=0x80, power=40, family="Pursuit", mode="switch",
    commands={"checkobedience","usedmovetext","doturn","critical","damagestats",
      "damagecalc","stab","damagevariation","pursuit","checkhit","moveanim",
      "failuretext","applydamage","criticaltext","supereffectivetext","checkfaint",
      "buildopponentrage","kingsrock","endmove"}},
  {id="SPIKES", byte=0x70, power=0, family="Spikes", mode="status",
    commands={"checkobedience","usedmovetext","doturn","spikes","endmove"}},
}
local interpreter = Interpreter.new()
for index, row in ipairs(rows) do
  local script = MoveScripts.forMove({
    id=row.id, index=index, effect=("CRYSTAL_EFFECT_%02X"):format(row.byte),
    power=row.power, type="NORMAL", category=row.power > 0 and "physical" or "status",
  })
  eq(script.effectName, row.family, row.id .. " resolves switch family")
  eq(script.mode, row.mode, row.id .. " uses expected command mode")
  eq(#script.commands, #row.commands, row.id .. " command count")
  for commandIndex, command in ipairs(row.commands) do
    local actual = type(script.commands[commandIndex]) == "table"
      and script.commands[commandIndex].op or script.commands[commandIndex]
    eq(actual, command, row.id .. " command " .. commandIndex)
  end
  local valid, err = interpreter:validate(script)
  check(valid, err or (row.id .. " command stream validates"))
end

Switching.installRuntime()

local trappedRuntime = {
  crystal251Active=true, player={ cantEscape=true, name="TRAPPED" }, queue={}, nextInsert=4096,
  phase="menu", afterQueue=nil,
}
function trappedRuntime:say(text) self.queue[#self.queue + 1] = { text=text } end
function trappedRuntime:sayNext() error("trapped menu rejection must not use sayNext") end
function trappedRuntime:romText(_, fallback, ...) return fallback:format(...) end
local ok, trappedResult = pcall(BattleStateStub.resolveSwitch, trappedRuntime, { id="BENCH" })
check(ok, "trapped menu switch rejection tolerates stale nextInsert")
eq(trappedResult, false, "trapped menu switch rejects the selection")
eq(#trappedRuntime.queue, 1, "trapped menu switch appends one message")
eq(trappedRuntime.queue[1].text, "TRAPPED\ncan't be recalled!",
  "trapped menu switch reports the Crystal recall failure")
eq(trappedRuntime.nextInsert, 0, "trapped menu switch clears stale insertion state")
eq(trappedRuntime.delegatedSwitch, nil, "trapped menu switch does not delegate")

local partialSource = {}
local partialRuntime = {
  crystal251Active=true,
  player={ crystalTrapTurns=2, crystalTrapSource=partialSource, name="BOUND" },
  enemy=partialSource, queue={}, nextInsert=255, phase="menu",
}
function partialRuntime:say(text) self.queue[#self.queue + 1] = { text=text } end
function partialRuntime:sayNext() error("partial trap rejection must not use sayNext") end
function partialRuntime:romText(_, fallback, ...) return fallback:format(...) end
ok, trappedResult = pcall(BattleStateStub.resolveSwitch, partialRuntime, { id="BENCH" })
check(ok, "partial-trap switch rejection tolerates a missing mirror flag")
eq(trappedResult, false, "partial-trap switch rejects the selection")
eq(#partialRuntime.queue, 1, "partial-trap switch appends one message")
eq(partialRuntime.nextInsert, 0, "partial-trap switch clears stale insertion state")

local staleTrapRuntime = {
  crystal251Active=true,
  player={ crystalTrapTurns=26, crystalTrapSource=27, name="STALE" },
  enemy={}, queue={}, nextInsert=511, phase="menu",
}
local staleBench = { id="STALE_BENCH" }
eq(BattleStateStub.resolveSwitch(staleTrapRuntime, staleBench), "delegated",
  "stale partial-trap data does not block switching")
eq(staleTrapRuntime.delegatedSwitch, staleBench,
  "stale partial-trap data preserves the selected mon")

local freeRuntime = {
  crystal251Active=true, player={}, queue={}, nextInsert=777, phase="menu",
}
function freeRuntime:say(text) self.queue[#self.queue + 1] = { text=text } end
function freeRuntime:romText(_, fallback, ...) return fallback:format(...) end
local benchRuntime = { id="BENCH" }
eq(BattleStateStub.resolveSwitch(freeRuntime, benchRuntime), "delegated",
  "legal switch delegates to the base battle state")
eq(freeRuntime.delegatedSwitch, benchRuntime, "legal switch keeps the selected mon")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal switching)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal switching)"):format(checks, checks))
