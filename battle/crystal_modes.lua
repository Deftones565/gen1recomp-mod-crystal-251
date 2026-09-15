local RuntimePatches = require("mods.CRYSTAL_251.lib.runtime_patches")
-- Pokemon Crystal battle-mode rules for CRYSTAL_251.
--
-- Crystal uses the same command engine for wild, trainer, Battle Tower and
-- link battles, but the surrounding policy differs materially.  This module
-- keeps those differences mod-local and installs them only for Crystal-owned
-- battles.  pret/pokecrystal is the parity reference:
--   * engine/battle/core.asm (_BattleRandom, TryEnemyFlee, mode gates)
--   * engine/link/link.asm (ten exchanged link RNG seeds)
--   * engine/battle/read_trainer_dvs.asm + data/trainers/dvs.asm
--   * engine/battle/ai/{move,items,switch}.asm (Battle Tower policy)

local Modes = {}

local SERIAL_RNS_LENGTH = 10
local SERIAL_OUTPUTS_PER_STREAM = SERIAL_RNS_LENGTH - 1

local POLICIES = {
  wild = {
    run = true, capture = true, enemyAI = false, trainerItems = false,
    obedience = true, deterministicLink = false,
  },
  trainer = {
    run = false, capture = false, enemyAI = true, trainerItems = true,
    obedience = true, deterministicLink = false,
  },
  battle_tower = {
    run = false, capture = false, enemyAI = true, trainerItems = false,
    obedience = false, deterministicLink = false,
  },
  link = {
    run = "forfeit", capture = false, enemyAI = false, trainerItems = false,
    obedience = false, deterministicLink = true,
  },
}
Modes.POLICIES = POLICIES
Modes.SERIAL_RNS_LENGTH = SERIAL_RNS_LENGTH
Modes.SERIAL_OUTPUTS_PER_STREAM = SERIAL_OUTPUTS_PER_STREAM

local SOMETIMES_FLEE = {
  MAGNEMITE=true, GRIMER=true, TANGELA=true, MR_MIME=true, MR__MIME=true,
  EEVEE=true, PORYGON=true, DRATINI=true, DRAGONAIR=true, TOGETIC=true,
  UMBREON=true, UNOWN=true, SNUBBULL=true, HERACROSS=true,
}
local OFTEN_FLEE = {
  CUBONE=true, ARTICUNO=false, ZAPDOS=false, MOLTRES=false, QUAGSIRE=true,
  DELIBIRD=true, PHANPY=true, TEDDIURSA=true,
}
local ALWAYS_FLEE = { RAIKOU=true, ENTEI=true }
Modes.SOMETIMES_FLEE = SOMETIMES_FLEE
Modes.OFTEN_FLEE = OFTEN_FLEE
Modes.ALWAYS_FLEE = ALWAYS_FLEE

local function clampByte(value)
  value = math.floor(tonumber(value) or 0) % 256
  if value < 0 then value = value + 256 end
  return value
end

function Modes.modeOf(battle)
  if not battle then return nil end
  if battle.kind == "link" or battle.linkRole then return "link" end
  if battle.battleTower or battle.inBattleTowerBattle
     or battle.crystalBattleTower then return "battle_tower" end
  if battle.kind == "trainer" then return "trainer" end
  return "wild"
end

function Modes.policyFor(battleOrMode)
  local mode = type(battleOrMode) == "string" and battleOrMode
    or Modes.modeOf(battleOrMode)
  return POLICIES[mode or "wild"]
end

function Modes.activate(battle, mode)
  if not battle then return battle end
  mode = mode or Modes.modeOf(battle)
  battle.crystal251Active = true
  battle.crystalBattleMode = mode
  if mode == "battle_tower" then
    battle.battleTower = true
    battle.inBattleTowerBattle = true
  elseif mode == "link" then
    battle.crystalLinkBattle = true
  end
  return battle
end

-- Crystal's link RNG stores ten exchanged bytes.  Calls return bytes 0..8;
-- after the ninth output all ten streams advance independently by
--     next = old * 5 + 1 (mod 256)
-- and the output index wraps to zero.  The tenth seed is intentionally not
-- returned directly, matching _BattleRandom's SERIAL_RNS_LENGTH - 1 check.
local function normaliseSeeds(seedOrSeeds)
  local seeds = {}
  if type(seedOrSeeds) == "table" then
    for i = 1, SERIAL_RNS_LENGTH do
      seeds[i] = clampByte(seedOrSeeds[i] or 0)
    end
  else
    -- The real host obtains ten hardware-RNG bytes and sends them to the
    -- external-clock peer.  The recomp handshake currently supplies one
    -- shared integer, so expand it deterministically into the same ten-byte
    -- shape.  Once expanded, byte consumption exactly follows Crystal.
    local value = clampByte(seedOrSeeds or 1)
    for i = 1, SERIAL_RNS_LENGTH do
      value = (value * 5 + 1) % 256
      seeds[i] = value
    end
  end
  return seeds
end
Modes.normaliseSeeds = normaliseSeeds

function Modes.makeLinkRng(seedOrSeeds)
  local state = {
    seeds = normaliseSeeds(seedOrSeeds),
    count = 0,
    calls = 0,
  }

  local function nextByte()
    local index = state.count + 1
    local value = state.seeds[index]
    state.count = state.count + 1
    state.calls = state.calls + 1
    if state.count >= SERIAL_OUTPUTS_PER_STREAM then
      state.count = 0
      for i = 1, SERIAL_RNS_LENGTH do
        state.seeds[i] = (state.seeds[i] * 5 + 1) % 256
      end
    end
    return value
  end

  local function rng(a, b)
    local raw = nextByte()
    if a == nil then return raw / 256 end
    if b == nil then b, a = a, 1 end
    a, b = math.floor(a), math.floor(b)
    if b < a then a, b = b, a end
    local width = b - a + 1
    if width <= 1 then return a end
    return a + (raw % width)
  end

  state.nextByte = nextByte
  state.rng = rng
  return rng, state
end

local function sortedKeys(value)
  local keys = {}
  for key in pairs(value or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function scalar(value)
  if value == nil then return "-" end
  if type(value) == "boolean" then return value and "1" or "0" end
  if type(value) == "table" then return tostring(value.id or value.species or "?") end
  return tostring(value)
end

local STAGE_KEYS = {
  "attack", "defense", "speed", "special", "specialAttack",
  "specialDefense", "accuracy", "evasion",
}
local VOLATILE_KEYS = {
  "attracted", "bideDamage", "bideTurns", "boundTurns", "cantEscape",
  "cantEscapeFrom", "chargeReady", "charging", "confusedTurns",
  "crystalBide", "crystalJustFrozen", "crystalLastMoveCategory",
  "crystalRageCounter", "crystalRageMove", "crystalTrapDamage",
  "crystalTrapMove", "crystalTrapSource", "crystalTrapTurns",
  "crystalTurnsTaken", "cursed", "defenseCurl", "destinyBond",
  "disabledMove", "disabledSlot", "disabledTurns", "encoreMove",
  "encoreSetTurn", "encoreTurns", "endure", "flinched", "focusEnergy",
  "forcedMove", "forcedMoveTurns", "foresight", "furyCutterCount",
  "hazeStatReset", "infatuatedWith", "invulnerable", "invulnerableMove", "lastCounterMove",
  "lastMove", "lastMoveCategory", "lastMovePower", "leechSeeded",
  "leechSeededBy", "lightScreen", "lightScreenTurns", "lockOnTurns",
  "lockedTarget", "mist", "mustRecharge", "nightmare", "perishTurns",
  "protect", "protectChain", "protectLastTurn", "rageMove", "reflect",
  "reflectTurns", "rolloutCount", "safeguard", "safeguardTurns",
  "skipMove", "sleepTurns", "substituteHP", "thrashAnnounced",
  "thrashMove", "thrashTurns", "toxicCounter", "turnsTaken", "usedMoves",
}

local function moveString(mon)
  local out = {}
  for i, move in ipairs((mon and mon.moves) or {}) do
    out[i] = table.concat({ scalar(move.id), scalar(move.pp),
      scalar(move.ppUps) }, ":")
  end
  return table.concat(out, ",")
end

local function statsVector(value)
  value = value or {}
  return table.concat({ scalar(value.hp), scalar(value.attack),
    scalar(value.defense), scalar(value.speed), scalar(value.special),
    scalar(value.specialAttack), scalar(value.specialDefense) }, ",")
end

local function monString(mon)
  if not mon then return "nil" end
  return table.concat({
    scalar(mon.species), scalar(mon.level), scalar(mon.exp), scalar(mon.hp),
    scalar(mon.status), scalar(mon.heldItem), scalar(mon.happiness),
    statsVector(mon.dvs), statsVector(mon.statExp), statsVector(mon.stats),
    moveString(mon),
  }, "|")
end

local function stagesString(battler)
  local values = {}
  local stages = battler and battler.stages or {}
  for i, key in ipairs(STAGE_KEYS) do values[i] = scalar(stages[key] or 0) end
  return table.concat(values, ",")
end

local function damageRecordString(owner, value)
  if type(value) ~= "table" then return scalar(value) end
  local relation = "-"
  if value.from then relation = value.from == owner and "SELF" or "OPP" end
  return table.concat({ scalar(value.damage), scalar(value.turn),
    scalar(value.category), scalar(value.moveId), scalar(value.power),
    scalar(value.effect), relation }, ":")
end

local function volatileScalar(owner, key, value)
  if key == "crystalLastDamageTaken" then
    return damageRecordString(owner, value)
  end
  if key == "usedMoves" and type(value) == "table" then
    local out = {}
    for i, move in ipairs(value) do out[i] = scalar(move) end
    return table.concat(out, "/")
  end
  if type(value) == "table" then
    if value.mon then return value == owner and "SELF" or "OPP" end
    if value.id then return scalar(value.id) end
    return "TABLE"
  end
  return scalar(value)
end

local function volatileString(battler)
  local values = {}
  for _, key in ipairs(VOLATILE_KEYS) do
    local value = battler and battler[key]
    if value ~= nil and value ~= false and value ~= 0 then
      values[#values + 1] = key .. "=" .. volatileScalar(battler, key, value)
    end
  end
  local damage = battler and battler.crystalLastDamageTaken
  if damage then
    values[#values + 1] = "crystalLastDamageTaken="
      .. damageRecordString(battler, damage)
  end
  return table.concat(values, ",")
end

local function battlerString(battler)
  if not (battler and battler.mon) then return "nil" end
  return table.concat({ monString(battler.mon),
    table.concat(battler.curTypes or {}, "/"), stagesString(battler),
    volatileString(battler) }, "|")
end

local function partyString(party)
  local out = {}
  for i, mon in ipairs(party or {}) do out[i] = monString(mon) end
  return table.concat(out, ";")
end

local function mapString(value)
  if type(value) ~= "table" then return scalar(value) end
  local out = {}
  for _, key in ipairs(sortedKeys(value)) do
    local entry = value[key]
    if type(entry) == "table" then entry = mapString(entry) end
    out[#out + 1] = tostring(key) .. "=" .. scalar(entry)
  end
  return table.concat(out, ",")
end

local function futureSightString(entry)
  if type(entry) ~= "table" then return scalar(entry) end
  -- `source` is a live battler object and may contain references unsuitable
  -- for canonical serialization.  Crystal's pending record is side-owned;
  -- the target slot already determines the source side, so only stored battle
  -- bytes belong in the link digest.
  return table.concat({
    scalar(entry.turns), scalar(entry.baseDamage or entry.damage),
    scalar(entry.moveId), scalar(entry.category),
  }, ",")
end

local function rngString(state)
  if not state then return "-" end
  local seeds = {}
  for i = 1, SERIAL_RNS_LENGTH do seeds[i] = scalar(state.seeds[i]) end
  return tostring(state.count or 0) .. ":" .. table.concat(seeds, ",")
end

-- Host-first canonical Crystal state.  The base link implementation already
-- hashes ordinary HP/status/PP; this adds every Generation II field that can
-- alter a later decision, plus the shared RNG cursor itself.
function Modes.linkSyncString(battle)
  if not battle then return "nil" end
  local hostActive, guestActive, hostParty, guestParty
  if battle.linkRole == "guest" then
    hostActive, guestActive = battle.enemy, battle.player
    hostParty, guestParty = battle.enemyParty, battle.playerParty
  else
    hostActive, guestActive = battle.player, battle.enemy
    hostParty, guestParty = battle.playerParty, battle.enemyParty
  end
  local function orient(sides)
    sides = sides or {}
    if battle.linkRole == "guest" then return sides.enemy, sides.player end
    return sides.player, sides.enemy
  end
  local hostScreens, guestScreens = orient(battle.crystalScreens)
  local hostStatus, guestStatus = orient(battle.crystalStatusSides)
  local hazardCompat = battle.crystalSpikes or battle.crystalHazards or {}
  local hazards = {
    player = hazardCompat.player ~= nil and hazardCompat.player
      or battle.playerSpikes,
    enemy = hazardCompat.enemy ~= nil and hazardCompat.enemy
      or battle.enemySpikes,
  }
  local hostHazards, guestHazards = orient(hazards)
  local futureSight = battle.crystalFutureSight or {}
  local hostFutureSight, guestFutureSight
  if battle.linkRole == "guest" then
    hostFutureSight, guestFutureSight = futureSight.enemy, futureSight.player
  else
    hostFutureSight, guestFutureSight = futureSight.player, futureSight.enemy
  end
  return table.concat({
    "HA=" .. battlerString(hostActive),
    "GA=" .. battlerString(guestActive),
    "HP=" .. partyString(hostParty),
    "GP=" .. partyString(guestParty),
    "HS=" .. mapString(hostScreens),
    "GS=" .. mapString(guestScreens),
    "HST=" .. mapString(hostStatus),
    "GST=" .. mapString(guestStatus),
    "HH=" .. mapString(hostHazards),
    "GH=" .. mapString(guestHazards),
    "W=" .. scalar(battle.weather or (battle.field and battle.field.weather)),
    "WT=" .. scalar(battle.weatherTurns),
    "LD=" .. scalar(battle.lastDamage),
    "AS=" .. mapString(battle.crystalActedSides),
    "HFS=" .. futureSightString(hostFutureSight),
    "GFS=" .. futureSightString(guestFutureSight),
    "R=" .. rngString(battle.crystalLinkRngState),
  }, "#")
end

local function digest(value)
  local ok, Fingerprint = pcall(require, "src.link.Fingerprint")
  if ok and Fingerprint and Fingerprint.digest then
    return Fingerprint.digest(value)
  end
  -- Deterministic fallback for isolated tests.
  local h = 2166136261
  for i = 1, #value do
    h = (h * 16777619 + value:byte(i)) % 4294967296
  end
  return ("%08x"):format(h)
end
Modes.digest = digest

function Modes.attachCrystalHash(battle, message)
  if not (battle and message and message.type == "hash") then return message end
  if message.crystal251 then return message end
  local extra = digest(Modes.linkSyncString(battle))
  local turn = message.turn or 0
  local localHash = battle.localHashes and battle.localHashes[turn]
  if localHash ~= nil then
    localHash = tostring(localHash) .. "|C251=" .. extra
    battle.localHashes[turn] = localHash
    message.value = localHash
  else
    message.value = tostring(message.value or "") .. "|C251=" .. extra
  end
  local parts = message.parts
  local localParts = battle.localParts and battle.localParts[turn]
  if parts and parts.actives then
    local combined = digest(tostring(parts.actives) .. "|" .. extra)
    parts.actives = combined
    if localParts then localParts.actives = combined end
  end
  message.crystal251 = extra
  return message
end

function Modes.shouldWildFlee(battle)
  if not (battle and Modes.modeOf(battle) == "wild" and battle.enemy
     and battle.enemy.mon and (battle.enemy.mon.hp or 0) > 0) then
    return false
  end
  if battle.player and battle.player.cantEscape then return false end
  if battle.enemy.crystalTrapTurns or battle.enemy.boundTurns then return false end
  local status = battle.enemy.mon.status
  if status == "SLP" or status == "FRZ" then return false end
  local species = battle.enemy.mon.species
  if ALWAYS_FLEE[species] then return true end
  local value = clampByte(battle.rng(0, 255))
  if value >= 129 then return false end
  if OFTEN_FLEE[species] then return true end
  if value >= 26 then return false end
  return SOMETIMES_FLEE[species] == true
end

-- Trainer class DVs from data/trainers/dvs.asm, mapped onto the Kanto class
-- ids used by the recomp.  Unmapped classes use Crystal's common 9/8/8/8.
local TRAINER_DVS = {
  DEFAULT={9,8,8,8},
  OPP_BROCK={9,8,8,8}, OPP_MISTY={7,8,8,8},
  OPP_LT_SURGE={9,8,8,8}, OPP_ERIKA={7,8,8,8},
  OPP_KOGA={13,12,13,13}, OPP_SABRINA={7,13,8,7},
  OPP_BLAINE={9,8,8,8}, OPP_GIOVANNI={13,12,13,13},
  OPP_LORELEI={13,12,13,13}, OPP_BRUNO={13,12,13,13},
  OPP_AGATHA={7,15,13,15}, OPP_LANCE={13,12,13,13},
  OPP_RIVAL1={13,13,13,13}, OPP_RIVAL2={9,8,8,8},
  OPP_RIVAL3={13,12,13,13}, OPP_PROF_OAK={9,8,8,8},
  OPP_YOUNGSTER={9,8,8,8}, OPP_BUG_CATCHER={9,8,8,8},
  OPP_LASS={5,8,8,8}, OPP_SAILOR={9,8,8,8},
  OPP_JR_TRAINER_M={9,8,8,8}, OPP_JR_TRAINER_F={6,10,10,8},
  OPP_POKEMANIAC={9,8,8,8}, OPP_SUPER_NERD={9,8,8,8},
  OPP_HIKER={10,8,8,8}, OPP_BIKER={9,8,8,8},
  OPP_BURGLAR={9,8,8,8}, OPP_ENGINEER={9,8,8,8},
  OPP_JUGGLER={9,8,8,8}, OPP_FISHER={9,8,8,8},
  OPP_SWIMMER={9,8,8,8}, OPP_CUE_BALL={9,8,8,8},
  OPP_GAMBLER={9,8,8,8}, OPP_BEAUTY={6,9,12,8},
  OPP_PSYCHIC_TR={9,8,8,8}, OPP_ROCKER={9,8,8,8},
  OPP_BLACKBELT={9,8,8,8}, OPP_CHANNELER={7,8,8,8},
  OPP_TAMER={9,8,8,8}, OPP_BIRD_KEEPER={9,8,8,8},
  OPP_SCIENTIST={9,8,8,8}, OPP_GENTLEMAN={9,8,8,8},
  OPP_ROCKET={13,8,10,8}, OPP_COOLTRAINER_M={13,8,12,8},
  OPP_COOLTRAINER_F={7,12,12,8},
}
Modes.TRAINER_DVS = TRAINER_DVS

function Modes.trainerDVs(classId)
  local row = TRAINER_DVS[classId] or TRAINER_DVS.DEFAULT
  local attack, defense, speed, special = row[1], row[2], row[3], row[4]
  local hp = (attack % 2) * 8 + (defense % 2) * 4
    + (speed % 2) * 2 + (special % 2)
  return { hp=hp, attack=attack, defense=defense, speed=speed, special=special }
end

local function applySlotData(battle, partyIndex)
  local trainer = battle and battle.trainer
  local partyDef = trainer and trainer.parties and trainer.parties[partyIndex or 1]
  if not partyDef then return end
  for i, slot in ipairs(partyDef) do
    local mon = battle.enemyParty and battle.enemyParty[i]
    if mon then
      if slot.item ~= nil or slot.heldItem ~= nil then
        mon.heldItem = slot.heldItem or slot.item
      end
      if slot.happiness ~= nil then mon.happiness = slot.happiness end
    end
  end
end

function Modes.applyTrainerDVs(battle, classId, partyIndex)
  if not battle or Modes.modeOf(battle) ~= "trainer" then return battle end
  classId = classId or battle.oppClass
  applySlotData(battle, partyIndex)
  local ok, Stats = pcall(require, "src.pokemon.Stats")
  if not ok then return battle end
  local dvs = Modes.trainerDVs(classId)
  for _, mon in ipairs(battle.enemyParty or {}) do
    local def = battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
    if def then
      local oldMax = mon.stats and mon.stats.hp or mon.hp or 1
      local missing = math.max(0, oldMax - (mon.hp or oldMax))
      mon.dvs = { hp=dvs.hp, attack=dvs.attack, defense=dvs.defense,
        speed=dvs.speed, special=dvs.special }
      mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
      mon.hp = math.max(0, mon.stats.hp - missing)
    end
  end
  if battle.enemy and battle.enemy.mon then
    for index, mon in ipairs(battle.enemyParty or {}) do
      if mon == battle.enemy.mon then
        local BattleState = require("src.battle.BattleState")
        battle.enemy = BattleState.makeBattler(battle.data, mon, false)
        battle.enemy.crystal251Active = true
        battle.enemyIndex = index
        if battle.syncSides then battle:syncSides() end
        break
      end
    end
  end
  -- InitEnemyTrainer explicitly removes RIVAL1's first held item.
  if classId == "OPP_RIVAL1" and battle.enemyParty and battle.enemyParty[1] then
    battle.enemyParty[1].heldItem = nil
    if battle.enemyIndex == 1 and battle.enemy then battle.enemy.mon.heldItem = nil end
  end
  return battle
end

function Modes.packLinkExtras(mon)
  return {
    heldItem = mon and mon.heldItem or nil,
    happiness = mon and mon.happiness or nil,
    pokerus = mon and mon.pokerus or nil,
    caughtData = mon and mon.caughtData or nil,
  }
end

function Modes.unpackLinkExtras(data, mon, packed, strict)
  if not mon then return nil, "missing Pokemon" end
  local extra = packed and (packed.crystal251 or packed.crystal) or nil
  if not extra then return mon end
  local item = extra.heldItem
  if item ~= nil and data and data.items and not data.items[item] then
    if strict then return nil, "unknown held item" end
    item = nil
  end
  mon.heldItem = item
  if extra.happiness ~= nil then
    mon.happiness = math.max(0, math.min(255, math.floor(extra.happiness)))
  end
  if extra.pokerus ~= nil then mon.pokerus = clampByte(extra.pokerus) end
  if extra.caughtData ~= nil then mon.caughtData = extra.caughtData end
  return mon
end

function Modes.installProtocolBridge()
  local Protocol = RuntimePatches.watch(require("src.link.Protocol"))
  if Protocol._crystal251ModeBridge then return end
  Protocol._crystal251ModeBridge = true
  local originalPack = Protocol.packMon
  Protocol.packMon = function(mon)
    local packed = originalPack(mon)
    packed.crystal251 = Modes.packLinkExtras(mon)
    return packed
  end
  local originalUnpack = Protocol.unpackMon
  Protocol.unpackMon = function(data, packed, opts)
    local mon, why = originalUnpack(data, packed, opts)
    if not mon then return nil, why end
    return Modes.unpackLinkExtras(data, mon, packed, opts and opts.strict)
  end
end

function Modes.configureLinkBattle(battle, net, opts)
  if not battle then return battle end
  opts = opts or {}
  Modes.activate(battle, "link")
  local rng, state = Modes.makeLinkRng(opts.crystalRNs or opts.seed or 1)
  battle.rng = rng
  battle.crystalLinkRngState = state

  if net and not battle._crystal251NetSendWrapped then
    battle._crystal251NetSendWrapped = true
    local originalSend = net.send
    battle._crystal251OriginalNetSend = originalSend
    RuntimePatches.capture(function()
      RuntimePatches.watch(net)
      net.send = function(self, message, ...)
        if message and message.type == "hash" then
          Modes.attachCrystalHash(battle, message)
        end
        return originalSend(self, message, ...)
      end
    end)()
  end

  -- In Crystal, RUN in the Colosseum is BATTLEACTION_FORFEIT.  The base link
  -- layer already understands the definite win/loss `forfeit` message for its
  -- shot clock; reuse it instead of the recomp's former mutual-draw RUN.
  battle.tryRun = function(self)
    if self.result or self.linkEnded then return end
    if self.net and self.net.send then
      self.net:send({ type="forfeit", reason="run" })
    end
    self.phase = "messages"
    self.afterQueue = "finish"
    self.result = "lose"
    if self.say then self:say("You forfeited the\nlink battle!") end
  end

  local originalFinish = battle.finish
  if originalFinish and not battle._crystal251FinishWrapped then
    battle._crystal251FinishWrapped = true
    battle.finish = function(self, ...)
      local result = originalFinish(self, ...)
      if net and self._crystal251OriginalNetSend
         and net.send ~= self._crystal251OriginalNetSend then
        net.send = self._crystal251OriginalNetSend
      end
      return result
    end
  end
  return battle
end

function Modes.healBattleTowerParty(data, party)
  for _, mon in ipairs(party or {}) do
    local maxHP = mon.stats and mon.stats.hp or mon.hp or 1
    mon.hp = maxHP
    mon.status = nil
    for _, move in ipairs(mon.moves or {}) do
      local def = data and data.moves and data.moves[move.id]
      if def then
        local ppUps = math.max(0, math.min(3, math.floor(move.ppUps or 0)))
        move.pp = (def.pp or 0) + ppUps * math.floor((def.pp or 0) / 5)
      end
    end
  end
  return party
end

function Modes.markBattleTower(battle)
  if not battle then return battle end
  Modes.activate(battle, "battle_tower")
  battle.crystalTrainerItemsUsed = {}
  battle.crystalBattleTowerAI = true
  return battle
end

function Modes.installRuntime()
  Modes.installProtocolBridge()

  local BattleState = RuntimePatches.watch(require("src.battle.BattleState"))
  if not BattleState._crystal251ModeBridge then
    BattleState._crystal251ModeBridge = true

    local originalNewWild = BattleState.newWild
    BattleState.newWild = function(game, species, level, opts)
      return Modes.activate(originalNewWild(game, species, level, opts), "wild")
    end

    local originalNewTrainer = BattleState.newTrainer
    BattleState.newTrainer = function(game, classId, partyIndex)
      local battle = originalNewTrainer(game, classId, partyIndex)
      Modes.activate(battle, "trainer")
      Modes.applyTrainerDVs(battle, classId, partyIndex)
      return battle
    end

    BattleState.newBattleTower = function(game, classId, partyIndex, opts)
      -- RunBattleTowerTrainer heals the player's party before and after every
      -- match.  Tower opponents retain the DVs supplied by their generated
      -- party data rather than ordinary trainer-class DVs.
      Modes.healBattleTowerParty(game.data, game.save and game.save.party)
      local battle = originalNewTrainer(game, classId, partyIndex)
      Modes.markBattleTower(battle)
      applySlotData(battle, partyIndex)
      if battle.player then battle.player.crystal251Active = true end
      if battle.enemy then battle.enemy.crystal251Active = true end
      if opts and opts.level then battle.battleTowerLevel = opts.level end
      local originalFinish = battle.finish
      if originalFinish then
        battle.finish = function(self, ...)
          Modes.healBattleTowerParty(self.data,
            self.game and self.game.save and self.game.save.party)
          return originalFinish(self, ...)
        end
      end
      return battle
    end

    local originalResolveTurn = BattleState.resolveTurn
    BattleState.resolveTurn = function(self, playerAction)
      if self and self.crystal251Active and Modes.shouldWildFlee(self) then
        self.phase = "messages"
        self.afterQueue = "finish"
        self.result = "run"
        if self.say then
          self:say("Wild " .. tostring(self.enemy.name or self.enemy.mon.species)
            .. " fled!")
        end
        return
      end
      return originalResolveTurn(self, playerAction)
    end
  end

  local LinkBattle = RuntimePatches.watch(require("src.link.LinkBattle"))
  if not LinkBattle._crystal251ModeBridge then
    LinkBattle._crystal251ModeBridge = true
    local originalNew = LinkBattle.new
    LinkBattle.new = function(game, net, opts)
      local battle, why = originalNew(game, net, opts)
      if not battle then return nil, why end
      return Modes.configureLinkBattle(battle, net, opts)
    end
    if LinkBattle.newSpectator then
      local originalSpectator = LinkBattle.newSpectator
      LinkBattle.newSpectator = function(game, net, opts)
        local battle, why = originalSpectator(game, net, opts)
        if not battle then return nil, why end
        return Modes.configureLinkBattle(battle, net, opts)
      end
    end
  end
end

return RuntimePatches.installers(Modes)
