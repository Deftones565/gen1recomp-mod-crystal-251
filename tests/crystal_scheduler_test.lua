package.path = "./?.lua;./?/init.lua;" .. package.path

local Scheduler = require("mods.CRYSTAL_251.battle.crystal_scheduler")
local Status = require("mods.CRYSTAL_251.battle.crystal_status")
local Items = require("mods.CRYSTAL_251.battle.crystal_items")
local Special = require("mods.CRYSTAL_251.battle.special_damage")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n"):format(
      label, tostring(got), tostring(want)))
  end
end
local function ok(value, label)
  eq(not not value, true, label)
end

local function battler(name, isPlayer, hp)
  hp = hp or 160
  return {
    name=name, isPlayer=isPlayer,
    mon={ species=name, hp=hp, stats={hp=hp}, moves={}, status=nil },
    curTypes={}, curMoves={}, stages={}, crystal251Active=true,
  }
end

local function battle(player, enemy)
  local b = {
    player=player or battler("PLAYER", true),
    enemy=enemy or battler("ENEMY", false),
    crystal251Active=true, kind="trainer", turnCount=1,
    data={ moves={ FUTURE_SIGHT={id="FUTURE_SIGHT",type="PSYCHIC_TYPE"} }, items={} },
    messages={}, animations={}, faints={}, crystalStatusSides={player={},enemy={}},
    crystalScreens={player={},enemy={}},
    rng=function(a) return a end,
  }
  function b:accuracyRoll() return true end
  function b:sayNext(message) self.messages[#self.messages + 1] = message end
  function b:animNext(name, side) self.animations[#self.animations + 1] = {name,side} end
  function b:drainNext() self.drains = (self.drains or 0) + 1 end
  function b:applyDamage(target, damage)
    damage = math.max(0, math.floor(damage or 0))
    if target.substituteHP then
      target.substituteHP = target.substituteHP - damage
      if target.substituteHP <= 0 then target.substituteHP = nil end
      return damage
    end
    local dealt = math.min(damage, target.mon.hp)
    target.mon.hp = target.mon.hp - dealt
    return dealt
  end
  function b:onFaint(target)
    if target.faintQueued then return end
    target.faintQueued = true
    self.faints[#self.faints + 1] = target.isPlayer and "player" or "enemy"
  end
  return b
end

-- Paired routines use player-first locally and enemy-first for the external
-- clock / guest side of a link battle.
do
  local b = battle()
  eq(Scheduler.endOrder(b)[1], b.player, "local end-phase order starts with player")
  b.kind, b.linkRole = "link", "guest"
  eq(Scheduler.endOrder(b)[1], b.enemy, "guest end-phase order starts with enemy")
end

-- Action residuals occur once, immediately after that battler acts.
do
  local b = battle()
  b.player.mon.status = "PSN"
  Scheduler.beginTurn(b)
  ok(Scheduler.afterAction(b, b.player, b.enemy), "player action residual runs")
  eq(b.player.mon.hp, 140, "ordinary poison removes one eighth after action")
  eq(#b.messages, 1, "poison queues one residual message")
  eq(b.messages[1], "PLAYER\nis hurt by poison!",
    "poison residual fits the battle box")
  eq(Scheduler.afterAction(b, b.player, b.enemy), false,
    "same side cannot receive action residual twice in one turn")
  eq(b.player.mon.hp, 140, "duplicate action residual does not damage again")

  b.turnCount = 2
  Scheduler.beginTurn(b)
  b.enemy.mon.hp = 0
  eq(Scheduler.afterAction(b, b.player, b.enemy), false,
    "residual is skipped when the move already fainted the opponent")
  eq(b.player.mon.hp, 140, "skipped residual leaves HP unchanged")
end

do
  local b = battle()
  b.player.mon.status = "PSN"
  b.player.crystalEnteredTurn = 2
  Scheduler.beginTurn(b)
  eq(Scheduler.afterAction(b, b.player, b.enemy), false,
    "newly entered battler skips the outgoing turn residual")
  eq(b.player.mon.hp, 160, "entry-turn residual skip preserves HP")
  b.turnCount = 2
  Scheduler.beginTurn(b)
  ok(Scheduler.afterAction(b, b.player, b.enemy),
    "entered battler receives residual after acting next turn")
  eq(b.player.mon.hp, 140, "next-turn poison removes one eighth")
end

do
  local b = battle()
  b.player.nightmare, b.player.cursed = true, true
  b.player.mon.status = "SLP"
  Scheduler.beginTurn(b)
  Scheduler.afterAction(b, b.player, b.enemy)
  eq(b.player.mon.hp, 80, "Nightmare and Curse each remove one quarter after action")
  eq(#b.messages, 2, "Nightmare and Curse report independently")
  eq(b.messages[1], "PLAYER\nis locked in a\nNIGHTMARE!",
    "Nightmare residual fits the battle box")
  eq(b.messages[2], "PLAYER\nis afflicted by\nthe CURSE!",
    "Curse residual fits the battle box")
end

do
  local b = battle()
  b.player.leechSeeded = true
  b.enemy.mon.hp, b.enemy.mon.stats.hp = 100, 160
  Scheduler.beginTurn(b)
  Scheduler.afterAction(b, b.player, b.enemy)
  eq(b.player.mon.hp, 140, "Leech Seed removes one eighth in Crystal")
  eq(b.enemy.mon.hp, 120, "Leech Seed restores the exact drained amount")
  eq(b.messages[1], "LEECH SEED\nsapped PLAYER!",
    "Leech Seed residual fits the battle box")
end

do
  local b = battle()
  b.player.mon.status = "BRN"
  Scheduler.beginTurn(b)
  Scheduler.afterAction(b, b.player, b.enemy)
  eq(b.messages[1], "PLAYER\nis hurt by its burn!",
    "burn residual fits the battle box")
end

-- HandleWrap decrements first: a count of two damages once, then releases.
do
  local b = battle()
  b.player.crystalTrapTurns = 2
  b.player.crystalTrapMove = "WHIRLPOOL"
  Scheduler.handleWrap(b)
  eq(b.player.crystalTrapTurns, 1, "Wrap count decrements before damage")
  eq(b.player.mon.hp, 150, "partial trapping removes one sixteenth")
  eq(b.messages[#b.messages], "PLAYER's\nhurt by\nWHIRLPOOL!",
    "partial-trap damage uses Crystal battle-text line breaks")
  Scheduler.handleWrap(b)
  eq(b.player.crystalTrapTurns, nil, "zero Wrap count releases the target")
  eq(b.player.mon.hp, 150, "release turn does not deal another trap tick")
  eq(b.messages[#b.messages], "PLAYER\nwas released from\nWHIRLPOOL!",
    "Wrap release uses Crystal battle-text line breaks")
end

do
  local b = battle()
  b.player.crystalTrapTurns, b.player.substituteHP = 3, 20
  Scheduler.handleWrap(b)
  eq(b.player.crystalTrapTurns, 3, "Substitute pauses partial-trap duration")
  eq(b.player.mon.hp, 160, "Substitute pause prevents trap residual")
end

-- Future Sight stores four, decrements on every shared end phase, and strikes
-- when the counter reaches one. Due-turn accuracy, Protect, and Endure apply.
do
  local b = battle()
  b.rng = function(a, z) return z end
  b.crystalFutureSight = { enemy={turns=4,baseDamage=50,moveId="FUTURE_SIGHT",source=b.player} }
  Special.tickFutureSight(b, {b.player,b.enemy})
  eq(b.enemy.mon.hp, 160, "Future Sight remains pending after first decrement")
  eq(b.crystalFutureSight.enemy.turns, 3, "Future Sight count falls four to three")
  Special.tickFutureSight(b, {b.player,b.enemy})
  eq(b.enemy.mon.hp, 160, "Future Sight remains pending after second decrement")
  Special.tickFutureSight(b, {b.player,b.enemy})
  eq(b.enemy.mon.hp, 110, "Future Sight strikes when count reaches one")
  eq(b.crystalFutureSight, nil, "resolved Future Sight slot is cleared")
  eq(b.animations[1][1], "FUTURE_SIGHT", "Future Sight queues its delayed animation")

  local protected = battle()
  protected.enemy.protect = true
  protected.crystalFutureSight = { enemy={turns=2,baseDamage=50,moveId="FUTURE_SIGHT",source=protected.player} }
  Special.tickFutureSight(protected, {protected.player,protected.enemy})
  eq(protected.enemy.mon.hp, 160, "Protect on the due turn blocks Future Sight")

  local endured = battle()
  endured.rng = function(a, z) return z end
  endured.enemy.endure, endured.enemy.mon.hp = true, 1
  endured.crystalFutureSight = { enemy={turns=2,baseDamage=50,moveId="FUTURE_SIGHT",source=endured.player} }
  Special.tickFutureSight(endured, {endured.player,endured.enemy})
  eq(endured.enemy.mon.hp, 1, "Endure on the due turn preserves one HP")
end

do
  local b = battle()
  b.rng = function(a, z) return z end
  b.crystalFutureSight = {
    enemy={turns=2,baseDamage=10,moveId="FUTURE_SIGHT",source=b.player},
    player={turns=2,baseDamage=10,moveId="FUTURE_SIGHT",source=b.enemy},
  }
  Special.tickFutureSight(b, {b.player,b.enemy})
  ok(b.messages[1]:find("Enemy", 1, true),
    "local Future Sight resolves player-owned attack first")

  local g = battle()
  g.kind, g.linkRole = "link", "guest"
  g.rng = function(a, z) return z end
  g.crystalFutureSight = {
    enemy={turns=2,baseDamage=10,moveId="FUTURE_SIGHT",source=g.player},
    player={turns=2,baseDamage=10,moveId="FUTURE_SIGHT",source=g.enemy},
  }
  Special.tickFutureSight(g, Scheduler.endOrder(g))
  ok(g.messages[1]:find("PLAYER", 1, true),
    "guest Future Sight resolves enemy-owned attack first")
end

do
  local b = battle()
  b.rng = function(a, z) return z end
  b.enemy.substituteHP = 30
  b.crystalFutureSight = { enemy={turns=2,baseDamage=50,moveId="FUTURE_SIGHT",source=b.player} }
  Special.tickFutureSight(b, {b.player,b.enemy})
  eq(b.enemy.mon.hp, 160, "Future Sight damage is absorbed by Substitute")
  eq(b.enemy.substituteHP, nil, "Future Sight can break Substitute")
end

-- Weather runs after Future Sight, damages in serial order, and clears only
-- after the final weather tick has applied.
do
  local p, e = battler("MEW", true), battler("GEODUDE", false)
  e.curTypes = {"ROCK","GROUND"}
  local b = battle(p, e)
  b.weather, b.weatherTurns = "sandstorm", 1
  Scheduler.handleWeather(b)
  eq(p.mon.hp, 140, "Sandstorm removes one eighth from vulnerable battler")
  eq(e.mon.hp, 160, "Rock or Ground battler ignores Sandstorm")
  eq(b.weather, nil, "weather clears after final damage tick")
  eq(b.weatherTurns, nil, "weather counter clears with weather")
end

-- Perish Song is checked after Wrap and faints in the paired serial order.
do
  local b = battle()
  b.player.perishTurns, b.enemy.perishTurns = 1, 1
  Status.tickPerish(b, {b.player,b.enemy})
  eq(b.player.mon.hp, 0, "Perish count zero removes all player HP")
  eq(b.enemy.mon.hp, 0, "Perish count zero removes all enemy HP")
  eq(b.messages[1]:find("PLAYER",1,true) ~= nil, true,
    "player Perish message is first in local order")
end

-- End-phase item order: action poison first, then Leftovers; healing berries
-- remain in the later healing-items phase.
do
  local b = battle()
  b.player.mon.status = "PSN"
  b.player.mon.heldItem = "LEFTOVERS"
  b.player.mon.hp, b.player.mon.stats.hp = 100, 160
  Scheduler.beginTurn(b)
  Scheduler.afterAction(b, b.player, b.enemy)
  Items.handleLeftovers(b, {b.player,b.enemy})
  eq(b.player.mon.hp, 90, "poison residual precedes Leftovers recovery")
  eq(b.player.mon.heldItem, "LEFTOVERS", "Leftovers remains held")
end

do
  local b = battle()
  b.player.mon.heldItem = "BERRY"
  b.player.mon.hp, b.player.mon.stats.hp = 70, 160
  Items.handleLeftovers(b, {b.player,b.enemy})
  eq(b.player.mon.hp, 70, "Berry does not activate in Leftovers phase")
  Items.handleHealingItems(b, {b.player,b.enemy})
  eq(b.player.mon.hp, 80, "Berry activates in healing-items phase")
  eq(b.player.mon.heldItem, nil, "healing Berry is consumed")
end

do
  local b = battle()
  b.player.mon.heldItem = "MYSTERYBERRY"
  b.player.curMoves = {{id="TACKLE",pp=0},{id="GROWL",pp=0}}
  Items.handleMysteryBerry(b, {b.player,b.enemy})
  eq(b.player.curMoves[1].pp, 5, "MysteryBerry restores first empty move")
  eq(b.player.curMoves[2].pp, 0, "MysteryBerry restores only one move")
  eq(b.player.mon.heldItem, nil, "MysteryBerry is consumed")
end

-- Defrost is 25/256, skips the application turn, and occurs before field
-- counters and ordinary healing-item checks.
do
  local b = battle()
  b.player.mon.status, b.player.crystalJustFrozen = "FRZ", true
  b.rng = function() return 0 end
  Status.handleDefrost(b, {b.player,b.enemy})
  eq(b.player.mon.status, "FRZ", "newly frozen battler skips same-turn thaw roll")
  eq(b.player.crystalJustFrozen, nil, "new-freeze marker clears after skip")
  Status.handleDefrost(b, {b.player,b.enemy})
  eq(b.player.mon.status, nil, "later 0 roll defrosts the battler")
end

-- Safeguard and screens are side state and tick once per completed turn.
do
  local b = battle()
  b.crystalStatusSides.player.safeguardTurns = 1
  b.crystalScreens.player.reflectTurns = 1
  b.player.safeguardTurns, b.player.reflect, b.player.reflectTurns = 1, true, 1
  Status.tickSafeguard(b)
  Scheduler.handleScreens(b)
  eq(b.player.safeguardTurns, nil, "Safeguard expires at zero")
  eq(b.player.reflect, nil, "Reflect flag clears when side counter expires")
  eq(b.player.reflectTurns, nil, "Reflect counter clears at zero")
end

-- Encore is last among the modeled between-turn effects.
do
  local b = battle()
  b.player.encoreTurns, b.player.encoreMove = 1, "TACKLE"
  b.player.encoreSetTurn = 0
  Status.tickEncore(b, {b.player,b.enemy})
  eq(b.player.encoreTurns, nil, "Encore expires after its final decrement")
  eq(b.player.encoreMove, nil, "Encore move clears on expiration")
end

-- The complete scheduler exposes its exact phase order for deterministic
-- regression tests. Action residuals precede the shared end-phase pipeline.
do
  local b = battle()
  b.crystalSchedulerTrace = {}
  Scheduler.beginTurn(b)
  b.crystalSchedulerTrace = {}
  Scheduler.endTurn(b)
  eq(table.concat(b.crystalSchedulerTrace, ","),
    "residual:player,residual:enemy,future_sight,weather,wrap,perish," ..
    "leftovers,mysteryberry,defrost,safeguard,screens,healing,encore,lockon",
    "scheduler follows Crystal HandleBetweenTurnEffects order")
end

-- Guest/link order reverses paired effects without changing phase order.
do
  local b = battle()
  b.kind, b.linkRole = "link", "guest"
  b.player.crystalTrapTurns, b.enemy.crystalTrapTurns = 2, 2
  b.player.crystalTrapMove, b.enemy.crystalTrapMove = "BIND", "WRAP"
  Scheduler.handleWrap(b)
  ok(b.messages[1]:find("Enemy", 1, true),
    "guest runs enemy partial-trap message first")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal scheduler)\n"):format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal scheduler)"):format(checks, checks))
