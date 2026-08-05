package.path = "./?.lua;./?/init.lua;" .. package.path

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

local interpreter = Interpreter.new()
eq(#MoveScripts.EFFECT_NAMES, 157, "Crystal exposes all 157 effect families")

local tackle = MoveScripts.forMove({
  id="TACKLE", index=33, effect="NO_ADDITIONAL_EFFECT",
  power=35, type="NORMAL", category="physical",
})
eq(tackle.effectByte, 0, "Tackle resolves the normal-hit effect byte")
eq(tackle.effectName, "NormalHit", "Tackle resolves the NormalHit family")
eq(tackle.mode, "ordinary", "Tackle uses an executable ordinary script")
eq(tackle.commands[1], "checkobedience", "ordinary script starts with obedience")
eq(tackle.commands[4], "critical", "ordinary script reaches critical")
eq(tackle.commands[#tackle.commands], "endmove", "ordinary script terminates")

local growth = MoveScripts.forMove({
  id="GROWTH", index=74, effect="CRYSTAL_EFFECT_0D",
  power=0, type="NORMAL", category="status",
})
eq(growth.effectName, "SpecialAttackUp", "Growth resolves split Special Attack")
eq(growth.mode, "primary", "Growth is a primary command script")
eq(growth.commands[4].op, "dispatch_effect", "primary script retains effect dispatch")

local amnesia = MoveScripts.forMove({
  id="AMNESIA", index=133, effect="CRYSTAL_EFFECT_36",
  power=0, type="PSYCHIC_TYPE", category="status",
})
eq(amnesia.effectName, "SpecialDefenseUp2", "Amnesia resolves split Special Defense")

local psychic = MoveScripts.forMove({
  id="PSYCHIC_M", index=94, effect="CRYSTAL_EFFECT_48",
  power=90, type="PSYCHIC_TYPE", category="special",
})
eq(psychic.effectName, "SpecialDefenseDownHit",
  "Psychic resolves the Special Defense hit family")

local future = MoveScripts.forMove({
  id="FUTURE_SIGHT", index=248, effect="CRYSTAL_EFFECT_94",
  power=80, type="PSYCHIC_TYPE", category="special",
})
eq(future.effectName, "FutureSight", "Future Sight resolves its effect family")
eq(future.mode, "special", "Future Sight uses its command-specific damage path")
eq(future.commands[1], "checkfuturesight", "Future Sight starts with its due-turn check")
eq(future.commands[7], "futuresight", "Future Sight stores damage before variation")

local beatUp = MoveScripts.forMove({
  id="BEAT_UP", index=251, effect="CRYSTAL_EFFECT_9A",
  power=10, type="DARK", category="special",
})
eq(beatUp.effectName, "BeatUp", "Beat Up resolves its effect family")
eq(beatUp.mode, "special", "Beat Up uses its command-specific damage path")
eq(beatUp.commands[7], "checkhit", "Beat Up performs one accuracy check before its loop")
eq(beatUp.commands[9], "beatup", "Beat Up selects each eligible contributor")

local doubleSlap = MoveScripts.forMove({
  id="DOUBLESLAP", index=3, effect="CRYSTAL_EFFECT_1D",
  power=15, type="NORMAL", category="physical",
})
eq(doubleSlap.effectName, "MultiHit", "DoubleSlap resolves the MultiHit family")
eq(doubleSlap.mode, "sequence", "DoubleSlap uses the consecutive command path")
eq(doubleSlap.commands[4], "startloop", "MultiHit starts its repeated-hit loop")
eq(doubleSlap.commands[6], "checkhit", "ordinary multi-hit checks accuracy before damage")

local tripleKick = MoveScripts.forMove({
  id="TRIPLE_KICK", index=167, effect="CRYSTAL_EFFECT_68",
  power=10, type="FIGHTING", category="physical",
})
eq(tripleKick.mode, "sequence", "Triple Kick uses the consecutive command path")
eq(tripleKick.commands[10], "triplekick",
  "Triple Kick multiplies base damage before STAB")
eq(tripleKick.commands[11], "stab", "Triple Kick applies STAB after kick scaling")

local rollout = MoveScripts.forMove({
  id="ROLLOUT", index=205, effect="CRYSTAL_EFFECT_75",
  power=30, type="ROCK", category="physical",
})
eq(rollout.mode, "sequence", "Rollout uses the consecutive command path")
eq(rollout.commands[1], "checkrollout", "Rollout starts with its continuation check")
eq(rollout.commands[8], "stab", "Rollout applies STAB before checking accuracy")
eq(rollout.commands[10], "rolloutpower",
  "Rollout scales completed pre-variation damage")

local rage = MoveScripts.forMove({
  id="RAGE", index=99, effect="CRYSTAL_EFFECT_51",
  power=20, type="NORMAL", category="physical",
})
eq(rage.mode, "sequence", "Rage uses the consecutive command path")
eq(rage.commands[7], "stab", "Rage applies STAB before checking accuracy")
eq(rage.commands[9], "ragedamage", "Rage scales damage after the hit check")

local synthetic = {}
for index = 1, 251 do
  local id = ("MOVE_%03d"):format(index)
  synthetic[id] = {
    id=id, index=index, effect=("CRYSTAL_EFFECT_%02X"):format((index - 1) % 157),
    power=index % 3 == 0 and 0 or 40,
    type="NORMAL", category=index % 3 == 0 and "status" or "physical",
  }
end
local scripts = MoveScripts.build(synthetic)
eq(scripts.__count, 251, "builder emits one script per move")
local valid, err = MoveScripts.validate(scripts, interpreter, 251)
check(valid, err or "all generated scripts validate")

local handlers = {}
for _, op in ipairs({ "critical", "damagestats", "damagecalc", "stab", "damagevariation" }) do
  local command = op
  handlers[command] = function(state)
    state[command] = true
  end
end
local state = interpreter:run(tackle, { handlers=handlers }, "damage")
eq(table.concat(state.trace, ","),
  "critical,damagestats,damagecalc,stab,damagevariation,endmove",
  "damage phase follows the Crystal command order")
for _, op in ipairs({ "critical", "damagestats", "damagecalc", "stab", "damagevariation" }) do
  check(state[op], op .. " handler executed")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal command interpreter)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal command interpreter)"):format(checks, checks))
