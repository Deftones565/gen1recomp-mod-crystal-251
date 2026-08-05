package.path = "./?.lua;./?/init.lua;" .. package.path

local Status = require("mods.CRYSTAL_251.battle.crystal_status")
local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
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

local function mon(name, player, opts)
  opts = opts or {}
  return {
    isPlayer=player, name=name,
    mon={ species=opts.species or name, hp=opts.hp or 160, status=opts.status,
      dvs={ attack=opts.attackDV or 8, speed=opts.speedDV or 8 },
      stats={ hp=opts.maxhp or 160 }, moves=opts.moves or {} },
    curTypes=opts.types or { "NORMAL" }, stages={},
    curMoves=opts.moves or {}, substituteHP=opts.substituteHP,
  }
end

local function battle(player, enemy, rolls)
  local at = 0
  local b = {
    player=player, enemy=enemy, turnCount=1, messages={},
    crystal251Active=true,
  }
  function b.rng(low, high)
    at = at + 1
    local value = rolls and rolls[at]
    if value == nil then return low end
    return value
  end
  function b:sayNext(text) self.messages[#self.messages + 1] = text end
  function b:applyDamage(target, damage)
    local dealt = math.min(target.mon.hp, math.max(0, math.floor(damage)))
    target.mon.hp = target.mon.hp - dealt
    return dealt
  end
  function b:onFaint(target) target.faintQueued = true end
  Status.beginBattle(b)
  return b
end

local function context(b, user, target, id, rolls)
  local at = 0
  return {
    battle=b, user=user, target=target,
    move={ id=id or "TEST", type="NORMAL" },
    moveInst={ id=id or "TEST", pp=10 },
    rng=function(low, high)
      at = at + 1
      local value = rolls and rolls[at]
      if value == nil then return low end
      return value
    end,
    drain=function() end,
  }
end

-- Major-status immunity and protection gates.
do
  local p, e = mon("MEW", true), mon("STEELIX", false, { types={"STEEL","GROUND"} })
  local b = battle(p, e, { 2 })
  eq(#Status.inflict(b, e, "PSN", {}), 0, "Steel is immune to poison")
  eq(#Status.inflict(b, e, "PAR", { moveType="ELECTRIC" }), 0,
    "Ground blocks Electric paralysis")
  check(#Status.inflict(b, e, "PAR", { moveType="NORMAL" }) > 0,
    "non-Electric paralysis can affect Ground")

  e.mon.status = nil
  e.substituteHP = 20
  eq(#Status.inflict(b, e, "BRN", {}), 0, "Substitute blocks major status")
  e.substituteHP = nil
  Status.sideFor(b, e).safeguardTurns = 5
  Status.syncSide(b, e)
  eq(#Status.inflict(b, e, "SLP", {}), 0, "Safeguard blocks sleep")
end

-- Sleep wakes and still acts in Generation II; Rest stores two lost turns.
do
  local p, e = mon("MEW", true, { status="SLP" }), mon("DITTO", false)
  local b = battle(p, e)
  p.sleepTurns = 1
  local can, messages = Status.beforeMove(p, b.rng, b, { id="TACKLE" })
  eq(can, true, "a waking battler may act")
  eq(p.mon.status, nil, "waking clears sleep")
  check(messages[1] and messages[1]:find("woke up", 1, true),
    "wake message is emitted")

  p.mon.hp, p.mon.status = 40, "BRN"
  local ctx = context(b, p, e, "REST")
  local rest = Status.rest(ctx)
  eq(p.mon.hp, 160, "Rest fully heals")
  eq(p.mon.status, "SLP", "Rest replaces the old status with sleep")
  eq(p.sleepTurns, 3, "Rest stores two fully asleep turns")
  check(#rest > 0, "Rest returns success text")

  local low = mon("LOW", false)
  local lowBattle = battle(p, low, { 1 })
  Status.inflict(lowBattle, low, "SLP", {})
  eq(low.sleepTurns, 1, "ordinary sleep accepts Crystal's minimum counter")
  low.mon.status = nil
  local high = mon("HIGH", false)
  local highBattle = battle(p, high, { 7 })
  Status.inflict(highBattle, high, "SLP", {})
  eq(high.sleepTurns, 7, "ordinary sleep accepts Crystal's maximum counter")
end

-- Sleep and freeze take precedence over a queued flinch.
do
  local p, e = mon("MEW", true, { status="SLP" }), mon("DITTO", false)
  local b = battle(p, e)
  p.sleepTurns, p.flinched = 2, true
  local can = Status.beforeMove(p, b.rng, b, { id="TACKLE" })
  eq(can, false, "sleep stops the move before flinch")
  eq(p.flinched, true, "sleep leaves the queued flinch intact")
  p.mon.status, p.sleepTurns = nil, nil
  can = Status.beforeMove(p, b.rng, b, { id="TACKLE" })
  eq(can, false, "the preserved flinch stops the next move check")
  eq(p.flinched, false, "the flinch is consumed when reached")
end

-- Crystal poison, Toxic, burn and Leech Seed residual fractions.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e)
  p.mon.status = "PSN"
  Status.residual(p, e, b)
  eq(p.mon.hp, 140, "ordinary poison deals one eighth")

  p.mon.hp, p.toxicCounter = 160, 1
  Status.residual(p, e, b)
  eq(p.mon.hp, 150, "first Toxic tick deals one sixteenth")
  eq(p.toxicCounter, 2, "Toxic counter advances")
  Status.residual(p, e, b)
  eq(p.mon.hp, 130, "second Toxic tick doubles")

  p.mon.status, p.mon.hp, p.toxicCounter = "BRN", 160, nil
  Status.residual(p, e, b)
  eq(p.mon.hp, 140, "burn deals one eighth")

  p.mon.status, p.mon.hp, p.leechSeeded = nil, 160, true
  e.mon.hp = 100
  Status.residual(p, e, b)
  eq(p.mon.hp, 140, "Leech Seed drains one eighth")
  eq(e.mon.hp, 120, "Leech Seed heals the opponent by damage dealt")
end

-- Confusion, flinch, paralysis and Disable follow the Crystal move gate.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e, { 0 })
  p.confusedTurns = 2
  local can, _, selfHit = Status.beforeMove(p, b.rng, b, { id="TACKLE" })
  eq(can, false, "confusion can interrupt the move")
  eq(selfHit, true, "confusion reports self-hit")

  p.confusedTurns, p.flinched = nil, true
  can = Status.beforeMove(p, b.rng, b, { id="TACKLE" })
  eq(can, false, "flinch stops the move")
  eq(p.flinched, false, "flinch is consumed")

  p.mon.status = "PAR"
  can = Status.beforeMove(p, function() return 62 end, b, { id="TACKLE" })
  eq(can, false, "paralysis stops on Crystal random values below 63")
  can = Status.beforeMove(p, function() return 63 end, b, { id="TACKLE" })
  eq(can, true, "paralysis allows the boundary value 63")

  p.mon.status = nil
  p.disabledMove, p.disabledSlot, p.disabledTurns = "SURF", 2, 3
  can = Status.beforeMove(p, function() return 255 end, b, { id="SURF" })
  eq(can, false, "Disable blocks the selected move")
  eq(p.disabledTurns, 2, "Disable counter ticks before the check")
  can = Status.beforeMove(p, function() return 255 end, b, { id="TACKLE" })
  eq(can, true, "a different move remains usable")
end

-- Disable and Encore validate the last move, PP and Substitute.
do
  local moves = { {id="TACKLE",pp=10}, {id="SURF",pp=5} }
  local p = mon("MEW", true, { moves=moves })
  local e = mon("DITTO", false, { moves=moves })
  local b = battle(p, e)
  e.lastMove = "SURF"
  local ctx = context(b, p, e, "DISABLE", { 5 })
  check(Status.disable(ctx)[1]:find("disabled", 1, true), "Disable succeeds")
  eq(e.disabledMove, "SURF", "Disable records the move id")
  eq(e.disabledSlot, 2, "Disable records the current slot")
  eq(e.disabledTurns, 5, "Disable uses the rolled duration")

  e.disabledMove, e.disabledSlot, e.disabledTurns = nil, nil, nil
  ctx = context(b, p, e, "ENCORE", { 4 })
  check(Status.encore(ctx)[1]:find("ENCORE", 1, true), "Encore succeeds")
  eq(e.encoreMove, "SURF", "Encore records the last move")
  eq(e.encoreTurns, 4, "Encore uses the rolled duration")
  eq(e.encoreSetTurn, 1, "Encore stamps the application turn")

  e.encoreMove, e.encoreTurns, e.encoreSetTurn = nil, nil, nil
  e.substituteHP = 1
  eq(Status.encore(ctx)[1], "But, it failed!", "Substitute blocks Encore")
  e.substituteHP, e.lastMove = nil, "STRUGGLE"
  eq(Status.disable(ctx)[1], "But, it failed!", "Disable rejects Struggle")
end

-- Substitute uses one quarter max HP and fails at exact-cost HP.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e)
  local ctx = context(b, p, e, "SUBSTITUTE")
  Status.substitute(ctx)
  eq(p.mon.hp, 120, "Substitute pays one quarter max HP")
  eq(p.substituteHP, 40, "Substitute has exactly the paid HP")

  p.substituteHP, p.mon.hp = nil, 40
  eq(Status.substitute(ctx)[1], "Too weak to make a SUBSTITUTE!",
    "Substitute fails when current HP equals the cost")
end

-- Safeguard belongs to the side and therefore survives switching.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e)
  local ctx = context(b, p, e, "SAFEGUARD")
  Status.startSafeguard(ctx)
  eq(Status.sideFor(b, p).safeguardTurns, 5, "Safeguard starts for five turns")
  local incoming = mon("CELEBI", true)
  Status.onSwitch(b, incoming, p, false)
  eq(incoming.safeguardTurns, 5, "incoming battler inherits side Safeguard")
  Status.endTurn(b)
  eq(Status.sideFor(b, incoming).safeguardTurns, 4,
    "Safeguard decrements once per completed turn")
end

do
  Gender.setRatio("ATTRACT_MON", 127)
  local p = mon("PLAYER", true, {
    species="ATTRACT_MON", attackDV=8, speedDV=0,
  })
  local e = mon("ENEMY", false, {
    species="ATTRACT_MON", attackDV=7, speedDV=15,
  })
  local b = battle(p, e)
  local ctx = context(b, p, e, "ATTRACT")
  Status.attract(ctx)
  eq(e.infatuatedWith, p, "Attract accepts opposite derived genders")
  e.infatuatedWith = nil
  e.mon.dvs.attack, e.mon.dvs.speed = 8, 0
  eq(Status.attract(ctx)[1], "But, it failed!",
    "Attract rejects equal derived genders")
  Gender.setRatio("ATTRACT_MON", 255)
  eq(Status.attract(ctx)[1], "But, it failed!",
    "Attract rejects genderless species")
end

-- Partial trapping is residual damage and never prevents the target acting.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e)
  local ctx = context(b, p, e, "WRAP", { 3 })
  Status.trapAfterDamage(ctx, 12)
  eq(e.crystalTrapTurns, 3, "partial trap stores the rolled duration")
  eq(e.cantEscapeFrom, p, "partial trap records its source")
  ctx.rng = function() return 5 end
  Status.trapAfterDamage(ctx, 12)
  eq(e.crystalTrapTurns, 3, "repeated Wrap does not refresh an active trap")
  eq(e.crystalTrapSource, p, "repeated Wrap preserves the original trap source")
  eq(e.crystalTrapMove, "WRAP", "repeated Wrap preserves the original trap move")
  local can = Status.beforeMove(e, function() return 255 end, b, { id="TACKLE" })
  eq(can, true, "partial trapping does not immobilize the target")
  Status.residual(e, p, b)
  eq(e.mon.hp, 150, "partial trap deals one sixteenth residual")
  eq(e.crystalTrapTurns, 2, "partial trap duration decrements after residual")
  Status.clearTrap(e)
  eq(e.cantEscape, nil, "ending the trap restores escape")
end

-- Nightmare, Curse and Perish Song use independent volatile state.
do
  local p = mon("MEW", true, { status="SLP" })
  local e = mon("DITTO", false)
  local b = battle(p, e)
  p.nightmare, p.cursed = true, true
  Status.endTurn(b)
  eq(p.mon.hp, 80, "Curse and Nightmare each deal one quarter")

  p.mon.hp, p.mon.status, p.nightmare, p.cursed = 160, nil, nil, nil
  local ctx = context(b, p, e, "PERISH_SONG")
  Status.perishSong(ctx)
  eq(p.perishTurns, 3, "Perish Song starts the user at three")
  eq(e.perishTurns, 3, "Perish Song starts the target at three")
  Status.endTurn(b)
  eq(p.perishTurns, 2, "Perish count falls at end of turn")
  Status.endTurn(b)
  Status.endTurn(b)
  eq(p.mon.hp, 0, "Perish count zero faints the user")
  eq(p.faintQueued, true, "Perish faint is queued")
end

-- Normal switching clears volatile state; Baton Pass keeps transferred state.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e)
  p.substituteHP, p.confusedTurns, p.perishTurns = 20, 3, 2
  p.encoreMove, p.encoreTurns, p.toxicCounter = "SURF", 3, 4
  e.infatuatedWith, e.cantEscapeFrom = p, p
  e.cantEscape = true
  local incoming = mon("CELEBI", true)
  Status.onSwitch(b, incoming, p, false)
  eq(p.substituteHP, nil, "normal switch clears Substitute")
  eq(p.confusedTurns, nil, "normal switch clears confusion")
  eq(p.perishTurns, nil, "normal switch clears Perish Song")
  eq(p.encoreTurns, nil, "normal switch clears Encore")
  eq(p.toxicCounter, nil, "normal switch clears Toxic progression")
  eq(e.infatuatedWith, nil, "normal switch clears opposing attraction link")
  eq(e.cantEscapeFrom, nil, "normal switch clears Mean Look source link")

  local outgoing = mon("MEW", true)
  local passed = mon("CELEBI", true)
  e.cantEscape, e.cantEscapeFrom = true, outgoing
  Status.onSwitch(b, passed, outgoing, true)
  eq(e.cantEscapeFrom, passed, "Baton Pass retargets trapping source")

  local wrapper = mon("WRAPPER", true)
  local replacement = mon("REPLACEMENT", true)
  e.cantEscape, e.cantEscapeFrom = true, wrapper
  e.crystalTrapTurns, e.crystalTrapSource, e.crystalTrapMove = 3, wrapper, "WRAP"
  Status.onSwitch(b, replacement, wrapper, true)
  eq(e.crystalTrapTurns, nil, "Baton Pass ends a partial trap from its source")
  eq(e.crystalTrapSource, nil, "Baton Pass drops the old partial-trap source")
  eq(e.cantEscape, nil, "ended partial trap releases switching")
  eq(e.cantEscapeFrom, nil, "ended partial trap clears its source link")
end

-- Rapid Spin clears seed, partial trapping and the user's Spikes side.
do
  local p, e = mon("MEW", true), mon("DITTO", false)
  local b = battle(p, e)
  b.playerSpikes = true
  p.leechSeeded, p.crystalTrapTurns = true, 3
  p.crystalTrapSource, p.cantEscapeFrom, p.cantEscape = e, e, true
  local ctx = context(b, p, e, "RAPID_SPIN")
  Status.rapidSpin(ctx)
  eq(p.leechSeeded, nil, "Rapid Spin clears Leech Seed")
  eq(p.crystalTrapTurns, nil, "Rapid Spin clears partial trapping")
  eq(b.playerSpikes, nil, "Rapid Spin clears Spikes from the user's side")
end

-- Status families now expose their Crystal command bodies without fallback.
do
  local interpreter = Interpreter.new()
  local rows = {
    { id="HYPNOSIS", byte=0x01, family="DoSleep", first="checkobedience",
      command="sleeptarget" },
    { id="TOXIC", byte=0x21, family="Toxic", first="checkobedience",
      command="poison" },
    { id="SUBSTITUTE", byte=0x4f, family="Substitute", first="checkobedience",
      command="substitute" },
    { id="DISABLE", byte=0x56, family="Disable", first="checkobedience",
      command="disable" },
    { id="ENCORE", byte=0x5a, family="Encore", first="checkobedience",
      command="encore" },
    { id="PERISH_SONG", byte=0x72, family="PerishSong", first="checkobedience",
      command="perishsong" },
    { id="SAFEGUARD", byte=0x7c, family="Safeguard", first="checkobedience",
      command="safeguard" },
  }
  for index, row in ipairs(rows) do
    local script = MoveScripts.forMove({
      id=row.id, index=index, effect=("CRYSTAL_EFFECT_%02X"):format(row.byte),
      power=0, type="NORMAL", category="status",
    })
    eq(script.effectName, row.family, row.id .. " resolves its status family")
    eq(script.mode, "status", row.id .. " uses a status command stream")
    eq(script.commands[1], row.first, row.id .. " starts with obedience")
    local found, fallback = false, false
    for _, command in ipairs(script.commands) do
      local op = type(command) == "table" and command.op or command
      if op == row.command then found = true end
      if op == "dispatch_effect" then fallback = true end
    end
    eq(found, true, row.id .. " contains its status command")
    eq(fallback, false, row.id .. " no longer uses dispatch_effect")
    local valid, err = interpreter:validate(script)
    check(valid, err or (row.id .. " status stream validates"))
  end
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal status and volatile state)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal status and volatile state)")
  :format(checks, checks))
