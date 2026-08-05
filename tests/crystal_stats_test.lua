package.path = "./?.lua;./?/init.lua;" .. package.path

local CrystalStats = require("mods.CRYSTAL_251.battle.crystal_stats")
local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")

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

local legacy = { stages={ special=2 } }
CrystalStats.ensure(legacy)
eq(legacy.stages.specialAttack, 2, "legacy Special seeds Special Attack")
eq(legacy.stages.specialDefense, 2, "legacy Special seeds Special Defense")
eq(legacy.stages.special, nil, "legacy shared Special stage is removed")

local old, new, changed = CrystalStats.change(legacy, "specialAttack", 1)
eq(old, 2, "Special Attack change reports old stage")
eq(new, 3, "Special Attack changes independently")
check(changed, "Special Attack change reports success")
eq(legacy.stages.specialDefense, 2, "Special Attack does not alter Special Defense")

CrystalStats.change(legacy, "specialDefense", -8)
eq(legacy.stages.specialDefense, -6, "Special Defense clamps at minus six")
eq(legacy.stages.specialAttack, 3, "Special Defense does not alter Special Attack")

local source = {
  stages={ attack=3, defense=-2, speed=1, specialAttack=4,
    specialDefense=-3, accuracy=2, evasion=-1, special=6 },
}
local target = { stages={ special=-4, extra=99 }, hazeStatReset=true }
CrystalStats.copy(target, source)
for _, stat in ipairs(CrystalStats.STAGE_KEYS) do
  eq(target.stages[stat], source.stages[stat], "Psych Up copy includes " .. stat)
end
eq(target.stages.special, nil, "Psych Up copy does not recreate shared Special")
eq(target.stages.extra, nil, "Psych Up copies only Crystal stat stages")
eq(target.hazeStatReset, nil, "stage copy requests stat recalculation")

CrystalStats.reset(target)
for _, stat in ipairs(CrystalStats.STAGE_KEYS) do
  eq(target.stages[stat], 0, "Haze resets " .. stat)
end

local baseStats = {
  USER={ attack=40, defense=50, speed=60, specialAttack=70, specialDefense=80 },
  FOE={ attack=90, defense=100, speed=110, specialAttack=120, specialDefense=130 },
}
local function battler(species)
  return {
    mon={ species=species, level=50,
      dvs={ attack=15, defense=15, speed=15, special=15 },
      statExp={ attack=0, defense=0, speed=0, special=0 } },
    stages={}, curTypes={"NORMAL"},
  }
end
local user, foe = battler("USER"), battler("FOE")
foe.stages = { attack=2, specialAttack=3, specialDefense=-2, evasion=1 }
local foeState = CrystalDamage.attachBattler(foe, baseStats)
local transformed = CrystalDamage.transformBattler(user, foe, baseStats)
check(transformed and transformed.transformed, "Transform marks the split-stat state")
eq(transformed.stats.specialAttack, foeState.stats.specialAttack,
  "Transform copies current Special Attack stat")
eq(transformed.stats.specialDefense, foeState.stats.specialDefense,
  "Transform copies current Special Defense stat")
eq(user.stages.specialAttack, 3, "Transform copies Special Attack stage")
eq(user.stages.specialDefense, -2, "Transform copies Special Defense stage")
eq(user.stages.special, nil, "Transform keeps split stages canonical")

local copiedAttack = transformed.stats.specialAttack
CrystalDamage.attachBattler(user, baseStats)
eq(user.crystal251Battle.stats.specialAttack, copiedAttack,
  "ordinary stat attachment preserves transformed stats")
CrystalDamage.clearTransform(user)
CrystalDamage.attachBattler(user, baseStats)
check(user.crystal251Battle.stats.specialAttack ~= copiedAttack,
  "switch cleanup restores the user's own split stats")

if failures > 0 then
  print(("%d/%d checks passed, %d FAILURES (Crystal split stat stages)")
    :format(checks - failures, checks, failures))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal split stat stages)"):format(checks, checks))
