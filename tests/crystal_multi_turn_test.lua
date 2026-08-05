package.path = "./?.lua;./?/init.lua;" .. package.path

local MultiTurn = require("mods.CRYSTAL_251.battle.multi_turn")
local Interpreter = require("mods.CRYSTAL_251.battle.command_interpreter")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local Bridge = require("mods.CRYSTAL_251.runtime_bridge")

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

-- Crystal's ordinary multi-hit distribution is 3/8, 3/8, 1/8, 1/8.
for _, row in ipairs({
  { 0, nil, 2 }, { 1, nil, 3 },
  { 2, 0, 2 }, { 2, 1, 3 }, { 2, 2, 4 }, { 2, 3, 5 },
  { 3, 0, 2 }, { 3, 3, 5 },
}) do
  local values, at = { row[1], row[2] }, 0
  local got = MultiTurn.twoToFiveCount(function()
    at = at + 1
    return values[at] or 0
  end)
  eq(got, row[3], "ordinary multi-hit roll " .. row[1] .. "/" .. tostring(row[2]))
end

for count, want in ipairs({ 1, 2, 4, 8, 16 }) do
  eq(MultiTurn.rolloutMultiplier(count, false), want,
    "Rollout multiplier on hit " .. count)
  eq(MultiTurn.rolloutMultiplier(count, true), want * 2,
    "Defense Curl Rollout multiplier on hit " .. count)
  eq(MultiTurn.furyCutterMultiplier(count), want,
    "Fury Cutter multiplier on hit " .. count)
end
eq(MultiTurn.furyCutterMultiplier(99), 16, "Fury Cutter damage caps at 16x")
eq(MultiTurn.rageMultiplier(0), 1, "fresh Rage uses 1x damage")
eq(MultiTurn.rageMultiplier(4), 5, "Rage uses counter plus one")
eq(MultiTurn.rageMultiplier(255), 256, "Rage's byte counter reaches 256x")

local moves = {
  DOUBLESLAP={ id="DOUBLESLAP", index=3, effect="CRYSTAL_EFFECT_1D",
    power=15, type="NORMAL", category="physical" },
  TWINEEDLE={ id="TWINEEDLE", index=41, effect="CRYSTAL_EFFECT_4D",
    power=25, type="BUG", category="physical", effectChance=51 },
  TRIPLE_KICK={ id="TRIPLE_KICK", index=167, effect="CRYSTAL_EFFECT_68",
    power=10, type="FIGHTING", category="physical" },
  ROLLOUT={ id="ROLLOUT", index=205, effect="CRYSTAL_EFFECT_75",
    power=30, type="ROCK", category="physical" },
  FURY_CUTTER={ id="FURY_CUTTER", index=210, effect="CRYSTAL_EFFECT_77",
    power=10, type="BUG", category="physical" },
  THRASH={ id="THRASH", index=37, effect="CRYSTAL_EFFECT_1B",
    power=90, type="NORMAL", category="physical" },
  RAGE={ id="RAGE", index=99, effect="CRYSTAL_EFFECT_51",
    power=20, type="NORMAL", category="physical" },
}
local scripts = {}
for id, move in pairs(moves) do scripts[id] = MoveScripts.forMove(move) end
local interpreter = Interpreter.new()
MultiTurn.configure({ moves=moves, scripts=scripts, interpreter=interpreter })

local expectedFamilies = {
  DOUBLESLAP={ "MultiHit", "checkobedience" },
  TWINEEDLE={ "PoisonMultiHit", "checkobedience" },
  TRIPLE_KICK={ "TripleKick", "checkobedience" },
  ROLLOUT={ "Rollout", "checkrollout" },
  FURY_CUTTER={ "FuryCutter", "checkobedience" },
  THRASH={ "Rampage", "checkrampage" },
  RAGE={ "Rage", "checkobedience" },
}
for id, expected in pairs(expectedFamilies) do
  local script = scripts[id]
  eq(script.mode, "sequence", id .. " uses the consecutive command path")
  eq(script.effectName, expected[1], id .. " resolves its Crystal family")
  eq(script.commands[1], expected[2], id .. " starts with the Crystal command")
  local ok, err = interpreter:validate(script)
  check(ok, err or (id .. " command stream validates"))
end

local function sequence(values, fallback)
  local at = 0
  return function()
    at = at + 1
    local value = values and values[at]
    if value == nil then return fallback end
    return value
  end
end

local function makeContext(id, opts)
  opts = opts or {}
  local move = moves[id]
  local user = opts.user or {
    isPlayer=true, name="MEW", mon={ hp=1000, status=opts.status },
    curTypes={ "NORMAL" }, stages={},
  }
  local target = opts.target or {
    isPlayer=false, name="RATTATA", mon={ hp=opts.targetHP or 1000 },
    curTypes={ "NORMAL" }, stages={}, substituteHP=opts.substituteHP,
  }
  local battle = {
    queue={}, messages={}, order={}, nextInsert=0,
    accuracyValues=opts.accuracyValues or {}, accuracyAt=0,
    damageRows=opts.damageRows or {}, damageAt=0,
  }
  function battle:sayNext(text) self.messages[#self.messages + 1] = text end
  function battle:cancelMoveAnim() self.cancelled = true end
  function battle:accuracyRoll()
    self.order[#self.order + 1] = "accuracy"
    self.accuracyAt = self.accuracyAt + 1
    local value = self.accuracyValues[self.accuracyAt]
    if value == nil then return true end
    return value
  end
  function battle:computeDamage()
    self.order[#self.order + 1] = "damage"
    self.damageAt = self.damageAt + 1
    local row = self.damageRows[self.damageAt] or self.damageRows[#self.damageRows]
      or { damage=10, info={ crit=false, typeMult=10 } }
    return row.damage, row.info or { crit=false, typeMult=10 }
  end
  function battle:applyDamage(who, damage)
    if who.substituteHP then
      who.substituteHP = who.substituteHP - damage
      if who.substituteHP <= 0 then who.substituteHP = nil end
      return damage
    end
    local dealt = math.min(damage, who.mon.hp)
    who.mon.hp = who.mon.hp - dealt
    return dealt
  end
  function battle:onFaint(who) who.faintQueued = true end

  local rng = opts.rng or function(_, high) return high end
  local ctx = {
    battle=battle, user=user, target=target, move=move,
    moveInst=opts.moveInst or { id=id, pp=20 }, isCalled=opts.isCalled or false,
    rng=rng,
    say=function(text) battle:sayNext(text) end,
    inflict=function(who, status)
      who.mon.status = status
      return { "status " .. status }
    end,
  }
  return ctx, battle, user, target
end

-- One accuracy check, but a fresh critical/damage calculation for every hit.
do
  local ctx, battle, _, target = makeContext("DOUBLESLAP", {
    rng=sequence({ 1 }, 0), -- three hits
    damageRows={
      { damage=10 }, { damage=20 }, { damage=30 },
    },
  })
  local state = MultiTurn.perform(ctx)
  eq(state.hits, 3, "DoubleSlap lands the selected three hits")
  eq(battle.accuracyAt, 1, "ordinary multi-hit checks accuracy once")
  eq(battle.damageAt, 3, "ordinary multi-hit recalculates every hit")
  eq(target.mon.hp, 940, "ordinary multi-hit applies each independent result")
  eq(#battle.queue, 2, "later multi-hit animations are queued separately")
end

-- Breaking Substitute does not cancel the remaining Crystal hits.
do
  local ctx, _, _, target = makeContext("DOUBLESLAP", {
    rng=sequence({ 0 }, 0), substituteHP=1,
    damageRows={ { damage=10 }, { damage=10 } },
  })
  MultiTurn.perform(ctx)
  eq(target.substituteHP, nil, "first hit breaks Substitute")
  eq(target.mon.hp, 990, "second hit continues into the target")
end

-- Twineedle rolls poison once before the hit loop.
do
  local ctx, battle, _, target = makeContext("TWINEEDLE", {
    rng=function(low, high)
      if high == 255 then return 0 end
      return low
    end,
  })
  MultiTurn.perform(ctx)
  eq(battle.damageAt, 2, "Twineedle performs exactly two hits")
  eq(target.mon.status, "PSN", "Twineedle applies its one post-loop poison")
end

-- Triple Kick checks each kick independently and multiplies before later
-- Crystal damage modifiers.
do
  local ctx, battle, _, target = makeContext("TRIPLE_KICK", {
    accuracyValues={ true, true, false },
    damageRows={ { damage=10 }, { damage=20 }, { damage=30 } },
  })
  local state = MultiTurn.perform(ctx)
  eq(state.hits, 2, "Triple Kick stops at the third failed check")
  eq(battle.accuracyAt, 3, "Triple Kick checks accuracy for every attempted kick")
  eq(battle.damageAt, 2, "a failed kick does not calculate later damage")
  eq(target.mon.hp, 950, "Triple Kick applies x1 then x2 damage")
end

-- Rollout calculates before accuracy, resets on a miss, doubles each hit,
-- and clears the forced sequence after hit five.
do
  local ctx, battle, user, target = makeContext("ROLLOUT", {
    accuracyValues={ false }, damageRows={ { damage=10 } },
  })
  user.rolloutCount, user.forcedMove, user.forcedMoveTurns = 3, ctx.moveInst, 2
  MultiTurn.perform(ctx)
  eq(table.concat(battle.order, ","), "damage,accuracy",
    "Rollout follows Crystal's damage-before-accuracy order")
  eq(user.rolloutCount, nil, "Rollout miss resets its count")
  eq(user.forcedMove, nil, "Rollout miss releases the user")

  ctx, battle, user, target = makeContext("ROLLOUT", {
    damageRows={ { damage=10 } }, targetHP=10000,
  })
  local losses = {}
  for hit = 1, 5 do
    local before = target.mon.hp
    MultiTurn.perform(ctx)
    losses[hit] = before - target.mon.hp
  end
  eq(table.concat(losses, ","), "10,20,40,80,160",
    "Rollout doubles through five successful hits")
  eq(user.rolloutCount, nil, "fifth Rollout clears its count")
  eq(user.forcedMove, nil, "fifth Rollout ends the forced sequence")

  ctx, _, user, target = makeContext("ROLLOUT", {
    damageRows={ { damage=10 } }, targetHP=1000,
  })
  user.defenseCurl = true
  local before = target.mon.hp
  MultiTurn.perform(ctx)
  eq(before - target.mon.hp, 20, "Defense Curl doubles Rollout from hit one")

  ctx, _, user, target = makeContext("ROLLOUT", {
    damageRows={ { damage=10 } }, isCalled=true, status="SLP",
  })
  before = target.mon.hp
  MultiTurn.perform(ctx)
  eq(before - target.mon.hp, 10, "Sleep Talk Rollout uses only base damage")
  eq(user.rolloutCount, nil, "Sleep Talk does not start a Rollout lock")
end

-- Fury Cutter has the same command ordering, but caps damage at 16x and
-- keeps growing only while the move continues to hit.
do
  local ctx, battle, user, target = makeContext("FURY_CUTTER", {
    accuracyValues={ false }, damageRows={ { damage=10 } },
  })
  user.furyCutterCount = 4
  MultiTurn.perform(ctx)
  eq(table.concat(battle.order, ","), "damage,accuracy",
    "Fury Cutter follows Crystal's damage-before-accuracy order")
  eq(user.furyCutterCount, nil, "Fury Cutter miss resets its count")

  ctx, _, user, target = makeContext("FURY_CUTTER", {
    damageRows={ { damage=10 } }, targetHP=10000,
  })
  local losses = {}
  for hit = 1, 6 do
    local before = target.mon.hp
    MultiTurn.perform(ctx)
    losses[hit] = before - target.mon.hp
  end
  eq(table.concat(losses, ","), "10,20,40,80,160,160",
    "Fury Cutter caps at its fifth-use damage")
end

-- Rampage stores one or two future forced uses, then confuses unless protected.
do
  local ctx, _, user = makeContext("THRASH", {
    rng=function(low) return low end, -- one future use, then 2-turn confusion
  })
  MultiTurn.perform(ctx)
  eq(user.thrashTurns, 1, "Thrash can select a two-turn total rampage")
  eq(user.thrashMove, ctx.moveInst, "Thrash stores the forced move instance")
  MultiTurn.perform(ctx)
  eq(user.thrashTurns, nil, "final Thrash releases the move lock")
  eq(user.confusedTurns, 2, "final Thrash starts Crystal confusion")

  ctx, _, user = makeContext("THRASH", { rng=function(low) return low end })
  user.safeguardTurns = 2
  MultiTurn.perform(ctx)
  MultiTurn.perform(ctx)
  eq(user.confusedTurns, nil, "Safeguard blocks post-rampage confusion")

  ctx, _, user = makeContext("THRASH", {
    isCalled=true, status="SLP", rng=function(low) return low end,
  })
  MultiTurn.perform(ctx)
  eq(user.thrashTurns, nil, "Sleep Talk does not create a rampage lock")
end

-- Rage only locks after a successful first use and multiplies by its dedicated
-- counter instead of modifying the Attack stage.
do
  local ctx, battle, user = makeContext("RAGE", {
    accuracyValues={ false }, damageRows={ { damage=10 } },
  })
  MultiTurn.perform(ctx)
  eq(table.concat(battle.order, ","), "damage,accuracy",
    "Rage follows Crystal's damage-before-accuracy order")
  eq(user.rageMove, nil, "a failed first Rage does not lock the user")

  ctx, _, user, target = makeContext("RAGE", {
    damageRows={ { damage=10 } }, targetHP=1000,
  })
  user.crystalRageCounter = 2
  local before = target.mon.hp
  MultiTurn.perform(ctx)
  eq(before - target.mon.hp, 30, "Rage uses counter-plus-one damage")
  eq(user.rageMove, ctx.moveInst, "successful Rage starts the counter state")
  eq(user.crystalRageMove, ctx.moveInst, "Rage marks the Crystal counter path")
end

-- The runtime bridge suppresses the base Gen I Attack-stage implementation.
do
  Bridge.install()
  local BattleState = require("src.battle.BattleState")
  local battle = {
    _crystalMoveDamageDepth=1, messages={},
    sayNext=function(self, text) self.messages[#self.messages + 1] = text end,
    drainNext=function() end,
    romText=function(_, _, fallback) return fallback end,
  }
  local moveInst = { id="RAGE", pp=20 }
  local target = {
    isPlayer=true, name="MEW", mon={ hp=100 }, stages={ attack=0 },
    rageMove=moveInst, crystalRageMove=moveInst, crystalRageCounter=0,
  }
  BattleState.applyDamage(battle, target, 10)
  eq(target.mon.hp, 90, "move damage still reduces a raging target's HP")
  eq(target.crystalRageCounter, 1, "move damage increments Crystal Rage")
  eq(target.stages.attack, 0, "Crystal Rage does not raise Attack stages")
  eq(target.rageMove, moveInst, "the base lock marker is restored")

  battle._crystalMoveDamageDepth = 0
  BattleState.applyDamage(battle, target, 5)
  eq(target.mon.hp, 85, "residual damage still reduces HP")
  eq(target.crystalRageCounter, 1, "residual damage does not build Rage")
  eq(target.stages.attack, 0, "residual damage cannot trigger Gen I Rage")

  local interrupted = {
    rng=function(low) return low end,
    data={ statuses=require("src.battle.Status").RECORDS },
    sayStatusMsg=function() end,
  }
  local rollout = { id="ROLLOUT", pp=20 }
  local frozen = {
    isPlayer=true, name="MEW", mon={ hp=100, status="FRZ" },
    curTypes={ "NORMAL" }, stages={},
    furyCutterCount=4, rolloutCount=3, forcedMove=rollout, forcedMoveTurns=2,
    thrashTurns=1, thrashMove={ id="THRASH" }, thrashAnnounced=true,
  }
  local foe = { isPlayer=false, name="RATTATA", mon={ hp=100 }, stages={} }
  eq(BattleState.statusInterrupt(interrupted, frozen, foe, rollout), true,
    "freeze interrupts a forced consecutive move")
  eq(frozen.furyCutterCount, nil, "interruption clears Fury Cutter")
  eq(frozen.rolloutCount, nil, "interruption clears Rollout")
  eq(frozen.forcedMove, nil, "interruption releases Rollout's forced move")
  eq(frozen.thrashTurns, nil, "interruption clears rampage")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal consecutive moves)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal consecutive moves)"):format(checks, checks))
