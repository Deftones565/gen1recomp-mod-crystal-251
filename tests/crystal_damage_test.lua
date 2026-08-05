package.path = "./?.lua;./?/init.lua;" .. package.path

local Damage = require("mods.CRYSTAL_251.battle.crystal_damage")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n")
      :format(label, tostring(got), tostring(want)))
  end
end
local function check(value, label)
  eq(not not value, true, label)
end

local baseStats = {
  ATTACKER = {
    attack=80, defense=70, speed=90, specialAttack=130, specialDefense=65,
  },
  TARGET = {
    attack=70, defense=120, speed=50, specialAttack=65, specialDefense=65,
  },
  TINY = {
    attack=5, defense=5, speed=5, specialAttack=5, specialDefense=5,
  },
  WALL = {
    attack=255, defense=255, speed=5, specialAttack=255, specialDefense=255,
  },
}

local function mon(species, level)
  return {
    species=species, level=level or 50, status=nil,
    dvs={ attack=15, defense=15, speed=15, special=15 },
    statExp={ attack=0, defense=0, speed=0, special=0 },
  }
end

local function battler(species, types, level)
  return {
    mon=mon(species, level), stages={}, curTypes=types,
  }
end

local neutralChart = {
  rows=function() return {} end,
  effectiveness=function() return 10 end,
}

local quarterChart = {
  rows=function() return { 5, 5 } end,
  effectiveness=function() return 2 end,
}

local moves = {
  TACKLE={ id="TACKLE", power=35, type="NORMAL", category="physical" },
  THUNDERBOLT={ id="THUNDERBOLT", power=95, type="ELECTRIC", category="special" },
  PSYCHIC_M={ id="PSYCHIC_M", power=90, type="PSYCHIC_TYPE", category="special", effect="CRYSTAL_EFFECT_48" },
  SHADOW_BALL={ id="SHADOW_BALL", power=80, type="GHOST", category="physical" },
  CRUNCH={ id="CRUNCH", power=80, type="DARK", category="special" },
  SURF={ id="SURF", power=95, type="WATER", category="special" },
  STRUGGLE={ id="STRUGGLE", power=50, type="NORMAL", category="physical" },
  SLASH={ id="SLASH", power=70, type="NORMAL", category="physical", highCrit=true },
  BITE={ id="BITE", power=60, type="DARK", category="special" },
  WING_ATTACK={ id="WING_ATTACK", power=60, type="FLYING", category="physical" },
  HIDDEN_POWER={ id="HIDDEN_POWER", power=1, type="NORMAL", category="physical" },
  RETURN={ id="RETURN", power=1, type="NORMAL", category="physical" },
  SONICBOOM={ id="SONICBOOM", power=20, type="NORMAL", category="physical" },
  COUNTER={ id="COUNTER", power=1, type="FIGHTING", category="physical" },
  PRESENT={ id="PRESENT", power=1, type="NORMAL", category="physical" },
  GROWL={ id="GROWL", power=0, type="NORMAL", category="status" },
}

local config = { baseStats=baseStats, moves=moves, typeChart=neutralChart }
local stats = Damage.calculateStats(mon("ATTACKER"), baseStats.ATTACKER)
eq(stats.specialAttack, 150, "split Special Attack stat")
eq(stats.specialDefense, 85, "split Special Defense stat")

eq(Damage.isRouted("TACKLE", moves), true, "Tackle uses Crystal damage")
eq(Damage.isRouted("THUNDERBOLT", moves), true,
  "ordinary Generation I special move uses Crystal damage")
eq(Damage.isRouted("STRUGGLE", moves), true, "Struggle uses the ordinary formula")
eq(Damage.isRouted("RETURN", moves), true, "Return uses the ordinary formula after power setup")
eq(Damage.isRouted("HIDDEN_POWER", moves), true,
  "Hidden Power uses the ordinary formula after type and power setup")
eq(Damage.isRouted("SONICBOOM", moves), false, "fixed damage stays deferred")
eq(Damage.isRouted("COUNTER", moves), false, "counter damage stays deferred")
eq(Damage.isRouted("PRESENT", moves), false, "Present stays deferred")
eq(Damage.isRouted("GROWL", moves), false, "status move is not routed")

local nativeBite = { id="BITE", power=60, type="NORMAL", category="physical" }
local biteToken = Damage.prepareMove(nativeBite, moves)
check(biteToken ~= nil, "Crystal move preparation accepts ordinary old moves")
eq(nativeBite.type, "DARK", "Bite uses its Crystal Dark type")
eq(nativeBite.category, "special", "Bite uses the Generation II type category")
Damage.restoreMove(nativeBite, biteToken)
eq(nativeBite.type, "NORMAL", "native Bite definition is restored")
local nativeWing = { id="WING_ATTACK", power=35, type="FLYING", category="physical" }
local wingToken = Damage.prepareMove(nativeWing, moves)
eq(nativeWing.power, 60, "Wing Attack uses its Crystal base power")
Damage.restoreMove(nativeWing, wingToken)
eq(nativeWing.power, 35, "native Wing Attack power is restored")

local hidden = { id="HIDDEN_POWER", power=1, type="NORMAL", category="physical" }
local hiddenToken = Damage.prepareMove(hidden, moves)
hidden.power, hidden.type = 70, "ICE"
local hiddenUser = battler("ATTACKER", {"ICE"})
local hiddenTarget = battler("TARGET", {"NORMAL"})
local _, hiddenInfo = Damage.compute({
  battle={}, user=hiddenUser, target=hiddenTarget, move=hidden,
  opts={ forceCrit=false }, rng=function(_, high) return high end,
}, config)
eq(hiddenInfo.attackStat, "specialAttack",
  "Hidden Power category follows its calculated Generation II type")
Damage.restoreMove(hidden, hiddenToken)
eq(hidden.type, "NORMAL", "Hidden Power registered type is restored")

local function compute(moveId, userTypes, targetTypes, weather, extra)
  extra = extra or {}
  local user = battler(extra.userSpecies or "ATTACKER", userTypes, extra.level)
  local target = battler(extra.targetSpecies or "TARGET", targetTypes, extra.targetLevel)
  if extra.userStages then user.stages = extra.userStages end
  if extra.targetStages then target.stages = extra.targetStages end
  target.reflect = extra.reflect
  target.lightScreen = extra.lightScreen
  local cfg = extra.typeChart and {
    baseStats=baseStats, moves=moves, typeChart=extra.typeChart,
  } or config
  local calls = 0
  local rng = extra.rng or function(_, high) return high end
  return Damage.compute({
    battle={ weather=weather }, user=user, target=target,
    move=moves[moveId], opts={ forceCrit=extra.forceCrit },
    rng=function(a, b) calls = calls + 1; return rng(a, b, calls) end,
  }, cfg)
end

local psychic, psychicInfo = compute("PSYCHIC_M", {"PSYCHIC_TYPE"}, {"NORMAL"}, nil,
  { forceCrit=false })
eq(psychic, 106, "Psychic uses Special Attack against Special Defense")
eq(psychicInfo.attackStat, "specialAttack", "Psychic attack stat selection")
eq(psychicInfo.defenseStat, "specialDefense", "Psychic defense stat selection")
eq(psychicInfo.effectName, "SpecialDefenseDownHit",
  "Psychic damage reports its Crystal effect family")
eq(table.concat(psychicInfo.commandTrace or {}, ","),
  "critical,damagestats,damagecalc,stab,damagevariation,endmove",
  "Psychic damage executes the declarative command stream")

local shadow, shadowInfo = compute("SHADOW_BALL", {"GHOST"}, {"NORMAL"}, nil,
  { forceCrit=false })
eq(shadow, 40, "Shadow Ball remains physical in Generation II")
eq(shadowInfo.attackStat, "attack", "Shadow Ball attack stat selection")
eq(shadowInfo.defenseStat, "defense", "Shadow Ball defense stat selection")

local crunch, crunchInfo = compute("CRUNCH", {"DARK"}, {"NORMAL"}, nil,
  { forceCrit=false })
eq(crunch, 96, "Crunch uses the special side of the split")
eq(crunchInfo.attackStat, "specialAttack", "Crunch attack stat selection")

local surf = compute("SURF", {"WATER"}, {"NORMAL"}, "rain", { forceCrit=false })
eq(surf, 168, "rain and STAB use Crystal integer ordering")

local stagedUser = battler("ATTACKER", {"PSYCHIC_TYPE"})
local stagedTarget = battler("TARGET", {"NORMAL"})
stagedUser.stages.specialAttack = 1
stagedTarget.stages.specialDefense = 1
local staged, stagedInfo = Damage.compute({
  battle={}, user=stagedUser, target=stagedTarget, move=moves.PSYCHIC_M,
  opts={ forceCrit=false }, rng=function(_, high) return high end,
}, config)
eq(staged, 108, "independent equal Special stages cancel")
eq(stagedInfo.attack, 225, "Special Attack stage is independent")
eq(stagedInfo.defense, 127, "Special Defense stage is independent")

local critBypassScreen = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  forceCrit=true, reflect=true, userStages={ attack=0 }, targetStages={ defense=0 },
})
local critWithoutScreen = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  forceCrit=true, userStages={ attack=0 }, targetStages={ defense=0 },
})
eq(critBypassScreen, critWithoutScreen,
  "critical hit bypasses Reflect when defense stage is not lower")

local critKeepsScreen = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  forceCrit=true, reflect=true, userStages={ attack=1 }, targetStages={ defense=0 },
})
local critBoostedNoScreen = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  forceCrit=true, userStages={ attack=1 }, targetStages={ defense=0 },
})
check(critKeepsScreen < critBoostedNoScreen,
  "critical hit keeps Reflect when the attack stage is higher")

local highCritInfo
_, highCritInfo = compute("SLASH", {"NORMAL"}, {"NORMAL"}, nil, {
  rng=function(a, b, call) return call == 1 and 63 or b end,
})
local normalCritInfo
_, normalCritInfo = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  rng=function(a, b, call) return call == 1 and 63 or b end,
})
eq(highCritInfo.crit, true, "high-critical move adds two critical stages")
eq(normalCritInfo.crit, false, "ordinary move keeps the base critical rate")

local struggleNormal = compute("STRUGGLE", {"NORMAL"}, {"NORMAL"}, nil,
  { forceCrit=false })
local struggleFire = compute("STRUGGLE", {"FIRE"}, {"NORMAL"}, nil,
  { forceCrit=false })
eq(struggleNormal, struggleFire, "Struggle never receives STAB")

local tiny = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  forceCrit=false, userSpecies="TINY", targetSpecies="WALL", level=1,
  targetLevel=100, typeChart=quarterChart,
})
eq(tiny, 1, "non-immune quarter-effective damage floors to one")

local _, truncInfo = compute("TACKLE", {"NORMAL"}, {"NORMAL"}, nil, {
  forceCrit=false, targetSpecies="WALL", level=100, targetLevel=100,
  userStages={ attack=6 }, targetStages={ defense=6 }, reflect=true,
})
eq(truncInfo.defense, 124,
  "screen-boosted Defense is quartered repeatedly until it fits one byte")
check(truncInfo.attack <= 255,
  "Attack is quartered alongside Defense during repeated truncation")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal standard damage)\n"):format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal standard damage)\n"):format(checks, checks))
