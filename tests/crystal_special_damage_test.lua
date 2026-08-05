package.path = "./?.lua;./?/init.lua;" .. package.path

local Special = require("mods.CRYSTAL_251.battle.special_damage")
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

-- Flail / Reversal use Crystal's 48-pixel HP-bar bands.
for _, row in ipairs({
  { 100, 20 }, { 68, 40 }, { 34, 80 },
  { 20, 100 }, { 8, 150 }, { 2, 200 },
}) do
  eq(Special.reversalPower(row[1], 100), row[2],
    "Reversal power at " .. row[1] .. "/100")
end

-- Present's raw-byte table is 40%, 30%, 10%, then 20% healing.
for _, row in ipairs({
  { 0, 40 }, { 102, 40 }, { 103, 80 }, { 179, 80 },
  { 180, 120 }, { 204, 120 }, { 205, "heal" }, { 255, "heal" },
}) do
  eq(Special.presentOutcome(row[1]), row[2],
    "Present outcome for raw roll " .. row[1])
end

-- Fixed-damage families bypass the ordinary stats/STAB/random formula.
eq(Special.fixedDamage("SONICBOOM", 50, 999, nil, 20), 20,
  "SonicBoom deals its encoded 20 damage")
eq(Special.fixedDamage("DRAGON_RAGE", 50, 999, nil, 40), 40,
  "Dragon Rage deals its encoded 40 damage")
eq(Special.fixedDamage("SEISMIC_TOSS", 73, 999), 73,
  "Seismic Toss deals the user's level")
eq(Special.fixedDamage("NIGHT_SHADE", 37, 999), 37,
  "Night Shade deals the user's level")
eq(Special.fixedDamage("SUPER_FANG", 50, 101), 50,
  "Super Fang floors half of odd HP")
eq(Special.fixedDamage("SUPER_FANG", 50, 1), 1,
  "Super Fang has a one-damage floor")

local rolls = { 0, 75, 17 }
local at = 0
local psy = Special.psywaveDamage(50, function()
  at = at + 1
  return rolls[at]
end)
eq(psy, 17, "Psywave rejects zero and values at its exclusive ceiling")
eq(Special.psywaveDamage(1, function() return 0 end), 1,
  "level-one Psywave keeps a one-damage fallback")

-- Crystal adds twice the user's level advantage to the OHKO accuracy byte.
eq(Special.ohkoAccuracyByte(30, 50, 50), 76,
  "equal-level OHKO accuracy uses the encoded 30 percent byte")
eq(Special.ohkoAccuracyByte(30, 60, 50), 96,
  "OHKO accuracy gains two points per level")
eq(Special.ohkoAccuracyByte(30, 150, 1), 255,
  "OHKO accuracy caps at 255")
eq(Special.ohkoAccuracyByte(0, 1, 100), 0,
  "OHKO accuracy has a zero floor")

local target = {}
local physical = {
  damage=90, from=target, category="physical", power=80, moveId="TACKLE",
}
local special = {
  damage=70, from=target, category="special", power=95, moveId="SURF",
}
eq(Special.counterDamage(physical, "physical", "COUNTER", target), 180,
  "Counter doubles physical damage")
eq(Special.counterDamage(special, "special", "MIRROR_COAT", target), 140,
  "Mirror Coat doubles special damage")
eq(Special.counterDamage(special, "physical", "COUNTER", target), nil,
  "Counter rejects special damage")
eq(Special.counterDamage(physical, "special", "MIRROR_COAT", target), nil,
  "Mirror Coat rejects physical damage")
eq(Special.counterDamage({ damage=50, from=target, category="physical",
    power=0, moveId="SONICBOOM" }, "physical", "COUNTER", target), nil,
  "counter moves reject a zero-power source record")
eq(Special.counterDamage({ damage=50, from=target, category="physical",
    power=1, moveId="COUNTER" }, "physical", "COUNTER", target), nil,
  "Counter cannot counter Counter")
eq(Special.counterDamage(physical, "physical", "COUNTER", {}), nil,
  "counter damage must come from the current target")
eq(Special.counterDamage({ damage=40000, from=target, category="physical",
    power=1, moveId="TACKLE" }, "physical", "COUNTER", target), 65535,
  "counter damage caps at 65535")

-- Beat Up uses contributor level/base Attack and target species base Defense,
-- then its own per-hit critical and random variation; it skips STAB/type.
eq(Special.beatUpDamage(50, 10, 100, 100, 255, false), 6,
  "Beat Up neutral maximum vector")
eq(Special.beatUpDamage(50, 10, 100, 100, 217, false), 5,
  "Beat Up minimum variation vector")
eq(Special.beatUpDamage(50, 10, 100, 100, 255, true), 10,
  "Beat Up critical doubles before the plus-two floor")
eq(Special.beatUpDamage(100, 255, 255, 1, 255, true), 999,
  "Beat Up damage caps at 999")

local expectedFamilies = {
  BIDE={ byte=0x1a, family="Bide", first="storeenergy" },
  FISSURE={ byte=0x26, family="OHKOHit", first="checkobedience" },
  SUPER_FANG={ byte=0x28, family="SuperFang", first="checkobedience" },
  SONICBOOM={ byte=0x29, family="StaticDamage", first="checkobedience" },
  DRAGON_RAGE={ byte=0x29, family="StaticDamage", first="checkobedience" },
  SEISMIC_TOSS={ byte=0x57, family="StaticDamage", first="checkobedience" },
  PSYWAVE={ byte=0x58, family="Psywave", first="checkobedience" },
  COUNTER={ byte=0x59, family="Counter", first="checkobedience" },
  REVERSAL={ byte=0x63, family="Reversal", first="checkobedience" },
  PRESENT={ byte=0x7a, family="Present", first="checkobedience" },
  MIRROR_COAT={ byte=0x90, family="MirrorCoat", first="checkobedience" },
  FUTURE_SIGHT={ byte=0x94, family="FutureSight", first="checkfuturesight" },
  BEAT_UP={ byte=0x9a, family="BeatUp", first="checkobedience" },
}
local interpreter = Interpreter.new()
for id, expected in pairs(expectedFamilies) do
  local script = MoveScripts.forMove({
    id=id, index=1, effect=("CRYSTAL_EFFECT_%02X"):format(expected.byte),
    power=1, type="NORMAL", category="physical",
  })
  eq(script.effectByte, expected.byte, id .. " effect byte")
  eq(script.effectName, expected.family, id .. " effect family")
  eq(script.mode, "special", id .. " uses the command-specific path")
  local first = type(script.commands[1]) == "table"
    and script.commands[1].op or script.commands[1]
  eq(first, expected.first, id .. " starts with the Crystal command")
  local last = script.commands[#script.commands]
  eq(type(last) == "table" and last.op or last, "endmove",
    id .. " command stream terminates")
  local valid, err = interpreter:validate(script)
  check(valid, err or (id .. " command stream validates"))
  local hasDispatch = false
  for _, command in ipairs(script.commands) do
    local op = type(command) == "table" and command.op or command
    if op == "dispatch_effect" then hasDispatch = true end
  end
  eq(hasDispatch, false, id .. " no longer falls back to dispatch_effect")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal special damage)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal special damage)"):format(checks, checks))
