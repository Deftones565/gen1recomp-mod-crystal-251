-- Declarative Pokemon Crystal command streams for all 251 move records.
--
-- Crystal's move table stores an effect byte; that byte selects one script
-- family.  We preserve the family name and command ordering here. Ordinary
-- damage families are executable by command_interpreter.lua now. Specialized
-- families remain explicit dispatch_effect commands until their dedicated
-- migration patches replace the existing effect-registry implementation.

local Catalog = require("mods.CRYSTAL_251.catalog")

local MoveScripts = {}

-- data/moves/effects_pointers.asm, indexed by the raw effect byte + 1.
local EFFECT_NAMES = {
  "NormalHit", "DoSleep", "PoisonHit", "LeechHit", "BurnHit",
  "FreezeHit", "ParalyzeHit", "Selfdestruct", "DreamEater", "MirrorMove",
  "AttackUp", "DefenseUp", "SpeedUp", "SpecialAttackUp",
  "SpecialDefenseUp", "AccuracyUp", "EvasionUp", "NormalHit",
  "AttackDown", "DefenseDown", "SpeedDown", "SpecialAttackDown",
  "SpecialDefenseDown", "AccuracyDown", "EvasionDown", "ResetStats",
  "Bide", "Rampage", "ForceSwitch", "MultiHit", "Conversion",
  "FlinchHit", "Heal", "Toxic", "PayDay", "LightScreen", "TriAttack",
  "NormalHit", "OHKOHit", "RazorWind", "SuperFang", "StaticDamage",
  "TrapTarget", "NormalHit", "MultiHit", "NormalHit", "Mist",
  "FocusEnergy", "RecoilHit", "DoConfuse", "AttackUp2", "DefenseUp2",
  "SpeedUp2", "SpecialAttackUp2", "SpecialDefenseUp2", "AccuracyUp2",
  "EvasionUp2", "Transform", "AttackDown2", "DefenseDown2", "SpeedDown2",
  "SpecialAttackDown2", "SpecialDefenseDown2", "AccuracyDown2",
  "EvasionDown2", "Reflect", "DoPoison", "DoParalyze", "AttackDownHit",
  "DefenseDownHit", "SpeedDownHit", "SpecialAttackDownHit",
  "SpecialDefenseDownHit", "AccuracyDownHit", "EvasionDownHit", "SkyAttack",
  "ConfuseHit", "PoisonMultiHit", "NormalHit", "Substitute", "HyperBeam",
  "Rage", "Mimic", "Metronome", "LeechSeed", "Splash", "Disable",
  "StaticDamage", "Psywave", "Counter", "Encore", "PainSplit", "Snore",
  "Conversion2", "LockOn", "Sketch", "DefrostOpponent", "SleepTalk",
  "DestinyBond", "Reversal", "Spite", "FalseSwipe", "HealBell",
  "NormalHit", "TripleKick", "Thief", "MeanLook", "Nightmare",
  "FlameWheel", "Curse", "NormalHit", "Protect", "Spikes", "Foresight",
  "PerishSong", "Sandstorm", "Endure", "Rollout", "Swagger", "FuryCutter",
  "Attract", "Return", "Present", "Frustration", "Safeguard", "SacredFire",
  "Magnitude", "BatonPass", "Pursuit", "RapidSpin", "NormalHit", "NormalHit",
  "MorningSun", "Synthesis", "Moonlight", "HiddenPower", "RainDance",
  "SunnyDay", "DefenseUpHit", "AttackUpHit", "AllUpHit", "FakeOut",
  "BellyDrum", "PsychUp", "MirrorCoat", "SkullBash", "Twister",
  "Earthquake", "FutureSight", "Gust", "Stomp", "Solarbeam", "Thunder",
  "Teleport", "BeatUp", "Fly", "DefenseCurl",
}
MoveScripts.EFFECT_NAMES = EFFECT_NAMES

-- Command-driven damage paths are intentionally not sent through the ordinary
-- formula. They use the dedicated command bodies below.
local DEFERRED = {
  BIDE=true, COUNTER=true, MIRROR_COAT=true, FUTURE_SIGHT=true, BEAT_UP=true,
  PSYWAVE=true, SONICBOOM=true, DRAGON_RAGE=true, SEISMIC_TOSS=true,
  NIGHT_SHADE=true, SUPER_FANG=true, REVERSAL=true, FLAIL=true, PRESENT=true,
  GUILLOTINE=true, HORN_DRILL=true, FISSURE=true,
}
MoveScripts.DEFERRED = DEFERRED

-- These families still use the ordinary Crystal formula, but their command
-- streams own repeated hits, post-formula multipliers, and forced continuations.
local SEQUENCED = {
  THRASH=true, PETAL_DANCE=true, OUTRAGE=true,
  DOUBLESLAP=true, COMET_PUNCH=true, FURY_ATTACK=true, PIN_MISSILE=true,
  SPIKE_CANNON=true, BARRAGE=true, FURY_SWIPES=true, BONE_RUSH=true,
  DOUBLE_KICK=true, BONEMERANG=true, TWINEEDLE=true, TRIPLE_KICK=true,
  RAGE=true, ROLLOUT=true, FURY_CUTTER=true,
}
MoveScripts.SEQUENCED = SEQUENCED

local BYTE_BY_MOVE = {
  WHIRLWIND=0x1c, ROAR=0x1c, TELEPORT=0x99,
  BIDE=0x1a,
  GUILLOTINE=0x26, HORN_DRILL=0x26, FISSURE=0x26,
  RAZOR_WIND=0x27, SUPER_FANG=0x28,
  SKY_ATTACK=0x4b, SKULL_BASH=0x91, SOLARBEAM=0x97,
  SONICBOOM=0x29, DRAGON_RAGE=0x29, SEISMIC_TOSS=0x57,
  NIGHT_SHADE=0x57, PSYWAVE=0x58, COUNTER=0x59,
}

local ALIAS_BYTES = {}
for byte, alias in pairs(Catalog.effectAliases or {}) do
  if ALIAS_BYTES[alias] == nil or byte < ALIAS_BYTES[alias] then
    ALIAS_BYTES[alias] = byte
  end
end

local function effectByte(move)
  local effect = move and move.effect
  local raw = type(effect) == "string" and effect:match("^CRYSTAL_EFFECT_(%x%x)$")
  if raw then return tonumber(raw, 16) end
  return BYTE_BY_MOVE[move and move.id] or ALIAS_BYTES[effect]
end
MoveScripts.effectByte = effectByte

local function clone(commands)
  local out = {}
  for i, command in ipairs(commands) do
    if type(command) == "table" then
      local row = {}
      for key, value in pairs(command) do row[key] = value end
      out[i] = row
    else
      out[i] = command
    end
  end
  return out
end

local NORMAL_HIT = {
  "checkobedience", "usedmovetext", "doturn", "critical", "damagestats",
  "damagecalc", "stab", "damagevariation", "checkhit", "moveanim",
  "failuretext", "applydamage", "criticaltext", "supereffectivetext",
  "checkfaint", "buildopponentrage", "kingsrock", "endmove",
}
MoveScripts.NORMAL_HIT = NORMAL_HIT

local function damaging(effectName)
  local commands = clone(NORMAL_HIT)
  if effectName ~= "NormalHit" then
    table.insert(commands, #commands, { op="dispatch_effect", effect=effectName })
  end
  return commands
end

local PRIMARY = {
  DoSleep=true, AttackUp=true, DefenseUp=true, SpeedUp=true,
  SpecialAttackUp=true, SpecialDefenseUp=true, AccuracyUp=true, EvasionUp=true,
  AttackDown=true, DefenseDown=true, SpeedDown=true, SpecialAttackDown=true,
  SpecialDefenseDown=true, AccuracyDown=true, EvasionDown=true,
  AttackUp2=true, DefenseUp2=true, SpeedUp2=true, SpecialAttackUp2=true,
  SpecialDefenseUp2=true, AccuracyUp2=true, EvasionUp2=true,
  AttackDown2=true, DefenseDown2=true, SpeedDown2=true, SpecialAttackDown2=true,
  SpecialDefenseDown2=true, AccuracyDown2=true, EvasionDown2=true,
  DoPoison=true, DoParalyze=true, DoConfuse=true,
}

local function primary(effectName)
  return {
    "checkobedience", "usedmovetext", "doturn",
    { op="dispatch_effect", effect=effectName }, "endmove",
  }
end

local STATUS_COMMANDS = {
  DoSleep = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "checksafeguard", "sleeptarget", "endmove",
  },
  Toxic = {
    "checkobedience", "usedmovetext", "doturn", "checkhit", "stab",
    "checksafeguard", "poison", "endmove",
  },
  Mist = {
    "checkobedience", "usedmovetext", "doturn", "mist", "endmove",
  },
  FocusEnergy = {
    "checkobedience", "usedmovetext", "doturn", "focusenergy", "endmove",
  },
  DoConfuse = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "checksafeguard", "confuse", "endmove",
  },
  DoPoison = {
    "checkobedience", "usedmovetext", "doturn", "checkhit", "stab",
    "checksafeguard", "poison", "endmove",
  },
  DoParalyze = {
    "checkobedience", "usedmovetext", "doturn", "stab", "checkhit",
    "checksafeguard", "paralyze", "endmove",
  },
  Substitute = {
    "checkobedience", "usedmovetext", "doturn", "substitute", "endmove",
  },
  LeechSeed = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "leechseed", "endmove",
  },
  Disable = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "disable", "endmove",
  },
  Encore = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "encore", "endmove",
  },
  MeanLook = {
    "checkobedience", "usedmovetext", "doturn", "arenatrap", "endmove",
  },
  Nightmare = {
    "checkobedience", "usedmovetext", "doturn", "nightmare", "endmove",
  },
  Protect = {
    "checkobedience", "usedmovetext", "doturn", "protect", "endmove",
  },
  Foresight = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "foresight", "endmove",
  },
  PerishSong = {
    "checkobedience", "usedmovetext", "doturn", "perishsong", "endmove",
  },
  Endure = {
    "checkobedience", "usedmovetext", "doturn", "endure", "endmove",
  },
  Attract = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "attract", "endmove",
  },
  Safeguard = {
    "checkobedience", "usedmovetext", "doturn", "safeguard", "endmove",
  },
  Spikes = {
    "checkobedience", "usedmovetext", "doturn", "spikes", "endmove",
  },
}

local SWITCH_COMMANDS = {
  ForceSwitch = {
    "checkobedience", "usedmovetext", "doturn", "checkhit",
    "forceswitch", "endmove",
  },
  BatonPass = {
    "checkobedience", "usedmovetext", "doturn", "batonpass", "endmove",
  },
  Pursuit = {
    "checkobedience", "usedmovetext", "doturn", "critical",
    "damagestats", "damagecalc", "stab", "damagevariation", "pursuit",
    "checkhit", "moveanim", "failuretext", "applydamage", "criticaltext",
    "supereffectivetext", "checkfaint", "buildopponentrage", "kingsrock",
    "endmove",
  },
}
MoveScripts.SWITCH_COMMANDS = SWITCH_COMMANDS
MoveScripts.STATUS_COMMANDS = STATUS_COMMANDS

local SPECIAL_COMMANDS = {
  Rampage = {
    "checkrampage", "checkobedience", "doturn", "rampage",
    "usedmovetext", "checkhit", "critical", "damagestats",
    "damagecalc", "stab", "damagevariation", "clearmissdamage",
    "moveanim", "failuretext", "applydamage", "criticaltext",
    "supereffectivetext", "checkfaint", "buildopponentrage",
    "kingsrock", "endmove",
  },
  MultiHit = {
    "checkobedience", "usedmovetext", "doturn", "startloop",
    "lowersub", "checkhit", "critical", "damagestats", "damagecalc",
    "stab", "damagevariation", "clearmissdamage", "moveanimnosub",
    "failuretext", "applydamage", "criticaltext", "cleartext",
    "supereffectivelooptext", "checkfaint", "buildopponentrage",
    "endloop", "raisesub", "kingsrock", "endmove",
  },
  PoisonMultiHit = {
    "checkobedience", "usedmovetext", "doturn", "startloop",
    "lowersub", "checkhit", "effectchance", "critical", "damagestats",
    "damagecalc", "stab", "damagevariation", "clearmissdamage",
    "moveanimnosub", "failuretext", "applydamage", "criticaltext",
    "cleartext", "supereffectivelooptext", "checkfaint",
    "buildopponentrage", "endloop", "raisesub", "kingsrock",
    "poisontarget", "endmove",
  },
  Rage = {
    "checkobedience", "usedmovetext", "doturn", "critical",
    "damagestats", "damagecalc", "stab", "checkhit", "ragedamage",
    "damagevariation", "moveanim", "failuretext", "rage",
    "applydamage", "criticaltext", "supereffectivetext", "checkfaint",
    "buildopponentrage", "kingsrock", "endmove",
  },
  TripleKick = {
    "checkobedience", "usedmovetext", "doturn", "startloop",
    "lowersub", "checkhit", "critical", "damagestats", "damagecalc",
    "triplekick", "stab", "damagevariation", "clearmissdamage",
    "moveanimnosub", "failuretext", "applydamage", "criticaltext",
    "cleartext", "supereffectivelooptext", "checkfaint",
    "buildopponentrage", "kickcounter", "endloop", "raisesub",
    "kingsrock", "endmove",
  },
  Rollout = {
    "checkrollout", "checkobedience", "doturn", "usedmovetext",
    "critical", "damagestats", "damagecalc", "stab", "checkhit",
    "rolloutpower", "damagevariation", "moveanim", "failuretext",
    "applydamage", "criticaltext", "supereffectivetext", "checkfaint",
    "buildopponentrage", "kingsrock", "endmove",
  },
  FuryCutter = {
    "checkobedience", "usedmovetext", "doturn", "critical",
    "damagestats", "damagecalc", "stab", "checkhit", "furycutter",
    "damagevariation", "moveanim", "failuretext", "applydamage",
    "criticaltext", "supereffectivetext", "checkfaint",
    "buildopponentrage", "kingsrock", "endmove",
  },
  Bide = {
    "storeenergy", "checkobedience", "doturn", "usedmovetext",
    "unleashenergy", "resettypematchup", "checkhit", "moveanim",
    "bidefailtext", "applydamage", "checkfaint", "buildopponentrage",
    "kingsrock", "endmove",
  },
  OHKOHit = {
    "checkobedience", "usedmovetext", "doturn", "stab", "ohko",
    "moveanim", "failuretext", "applydamage", "criticaltext",
    "supereffectivetext", "checkfaint", "buildopponentrage", "endmove",
  },
  SuperFang = {
    "checkobedience", "usedmovetext", "doturn", "constantdamage",
    "checkhit", "resettypematchup", "moveanim", "failuretext",
    "applydamage", "checkfaint", "buildopponentrage", "kingsrock",
    "endmove",
  },
  Psywave = {
    "checkobedience", "usedmovetext", "doturn", "constantdamage",
    "checkhit", "resettypematchup", "moveanim", "failuretext",
    "applydamage", "checkfaint", "buildopponentrage", "kingsrock",
    "endmove",
  },
  StaticDamage = {
    "checkobedience", "usedmovetext", "doturn", "constantdamage",
    "checkhit", "resettypematchup", "moveanim", "failuretext",
    "applydamage", "checkfaint", "buildopponentrage", "kingsrock",
    "endmove",
  },
  Reversal = {
    "checkobedience", "usedmovetext", "doturn", "constantdamage", "stab",
    "checkhit", "moveanim", "failuretext", "applydamage",
    "supereffectivetext", "checkfaint", "buildopponentrage", "kingsrock",
    "endmove",
  },
  Counter = {
    "checkobedience", "usedmovetext", "doturn", "counter", "moveanim",
    "failuretext", "applydamage", "checkfaint", "buildopponentrage",
    "kingsrock", "endmove",
  },
  Present = {
    "checkobedience", "usedmovetext", "doturn", "checkhit", "critical",
    "damagestats", "present", "damagecalc", "stab", "damagevariation",
    "clearmissdamage", "failuretext", "applydamage", "criticaltext",
    "supereffectivetext", "checkfaint", "buildopponentrage", "kingsrock",
    "endmove",
  },
  MirrorCoat = {
    "checkobedience", "usedmovetext", "doturn", "mirrorcoat", "moveanim",
    "failuretext", "applydamage", "checkfaint", "buildopponentrage",
    "kingsrock", "endmove",
  },
  FutureSight = {
    "checkfuturesight", "checkobedience", "usedmovetext", "doturn",
    "damagestats", "damagecalc", "futuresight", "damagevariation",
    "checkhit", "moveanimnosub", "failuretext", "applydamage",
    "checkfaint", "buildopponentrage", "endmove",
  },
  BeatUp = {
    "checkobedience", "usedmovetext", "movedelay", "doturn", "startloop",
    "lowersub", "checkhit", "critical", "beatup", "damagecalc",
    "damagevariation", "clearmissdamage", "moveanimnosub", "failuretext",
    "applydamage", "criticaltext", "cleartext", "supereffectivelooptext",
    "checkfaint", "buildopponentrage", "endloop", "beatupfailtext",
    "raisesub", "kingsrock", "endmove",
  },
}
MoveScripts.SPECIAL_COMMANDS = SPECIAL_COMMANDS

function MoveScripts.forMove(move)
  assert(type(move) == "table" and move.id, "Crystal move record is required")
  local byte = effectByte(move)
  local effectName = byte and EFFECT_NAMES[byte + 1] or tostring(move.effect or "Unknown")
  local isDamage = (move.power or 0) > 0 and move.category ~= "status"
  local mode
  local commands
  if SWITCH_COMMANDS[effectName] then
    mode = "switch"
    commands = clone(SWITCH_COMMANDS[effectName])
  elseif STATUS_COMMANDS[effectName] then
    mode = "status"
    commands = clone(STATUS_COMMANDS[effectName])
  elseif DEFERRED[move.id] then
    mode = "special"
    commands = clone(assert(SPECIAL_COMMANDS[effectName],
      "missing command-specific Crystal script for " .. move.id
        .. " (" .. tostring(effectName) .. ")"))
  elseif SEQUENCED[move.id] then
    mode = "sequence"
    commands = clone(assert(SPECIAL_COMMANDS[effectName],
      "missing consecutive Crystal script for " .. move.id
        .. " (" .. tostring(effectName) .. ")"))
  elseif isDamage then
    mode = "ordinary"
    commands = damaging(effectName)
  elseif PRIMARY[effectName] then
    mode = "primary"
    commands = primary(effectName)
  else
    mode = "specialized"
    commands = primary(effectName)
  end
  return {
    id=move.id, index=move.index or 0, effect=move.effect,
    effectByte=byte, effectName=effectName, mode=mode,
    commands=commands,
  }
end

function MoveScripts.build(moves)
  local scripts, count, indexes = {}, 0, {}
  for id, move in pairs(moves or {}) do
    local script = MoveScripts.forMove(move)
    script.id = id
    scripts[id] = script
    count = count + 1
    if script.index and script.index > 0 then
      assert(not indexes[script.index], "duplicate Crystal move index " .. script.index)
      indexes[script.index] = id
    end
  end
  scripts.__count = count
  return scripts
end

function MoveScripts.validate(scripts, interpreter, expected)
  expected = expected or 251
  local count, indexes = 0, {}
  for id, script in pairs(scripts or {}) do
    if id ~= "__count" then
      count = count + 1
      if script.id ~= id then return false, id .. " script id mismatch" end
      if not script.effectName then return false, id .. " has no effect family" end
      if script.index and script.index > 0 then
        if indexes[script.index] then return false, "duplicate move index " .. script.index end
        indexes[script.index] = id
      end
      if interpreter then
        local ok, err = interpreter:validate(script)
        if not ok then return false, err end
      end
    end
  end
  if count ~= expected then
    return false, ("expected %d Crystal scripts, got %d"):format(expected, count)
  end
  for index = 1, expected do
    if not indexes[index] then return false, "missing Crystal move index " .. index end
  end
  return true
end

return MoveScripts
