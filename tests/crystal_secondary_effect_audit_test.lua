-- Exhaustive ROM-backed audit of Crystal's chance-based damaging effects.
--
-- Every registered probability-gated effect family is exercised through the
-- live battle pipeline in both attack directions.  A zero chance must leave
-- status, confusion, flinch and stat stages unchanged; a 255 chance must
-- change the appropriate battle state.  The two manually-gated exceptions,
-- Twineedle and Thief, receive the same boundary checks.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local romPath = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(romPath, "rb")
if not file then
  print("SKIP Crystal secondary-effect audit (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local addresses = require("mods.CRYSTAL_251.addresses")
local run, cache = require("mods.CRYSTAL_251.tests._real_rom_mod").load(T, raw)
local Data = run.data
T.eq(#run.errors, 0, "Crystal 251 loads for the secondary-effect audit")

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Effects = require("mods.CRYSTAL_251.effects")
local data = run.data

local EXPECTED_FAMILIES = {
  CRYSTAL_EFFECT_02=true, CRYSTAL_EFFECT_04=true,
  CRYSTAL_EFFECT_05=true, CRYSTAL_EFFECT_06=true,
  CRYSTAL_EFFECT_1F=true, CRYSTAL_EFFECT_24=true,
  CRYSTAL_EFFECT_44=true, CRYSTAL_EFFECT_45=true,
  CRYSTAL_EFFECT_46=true, CRYSTAL_EFFECT_47=true,
  CRYSTAL_EFFECT_48=true, CRYSTAL_EFFECT_49=true,
  CRYSTAL_EFFECT_4A=true, CRYSTAL_EFFECT_4C=true,
  CRYSTAL_EFFECT_5C=true, CRYSTAL_EFFECT_6C=true,
  CRYSTAL_EFFECT_7D=true, CRYSTAL_EFFECT_8A=true,
  CRYSTAL_EFFECT_8B=true, CRYSTAL_EFFECT_8C=true,
  CRYSTAL_EFFECT_92=true, CRYSTAL_EFFECT_96=true,
  CRYSTAL_EFFECT_98=true,
}

local familyCount = 0
for effectId in pairs(Effects.CHANCE_EFFECTS) do
  familyCount = familyCount + 1
  T.check(EXPECTED_FAMILIES[effectId],
    effectId .. " is explicitly covered by the secondary-effect audit")
end
for effectId in pairs(EXPECTED_FAMILIES) do
  T.check(Effects.CHANCE_EFFECTS[effectId],
    effectId .. " remains registered as a chance-based effect")
end
T.eq(familyCount, 23, "all 23 chance-based effect families are discovered")

-- Probe the wrapper itself for every family, including dormant records that
-- no current move selects.  At zero the underlying callback must be skipped;
-- at 255 the sentinel context proves that callback was reached.
for effectId in pairs(EXPECTED_FAMILIES) do
  local record = assert(data.move_effects[effectId], effectId)
  local zeroCtx = setmetatable({
    move={ id="AUDIT", type="NORMAL", effectChance=0 },
    rng=function() return 0 end,
  }, {
    __index=function(_, key)
      error("SECONDARY_HANDLER_REACHED:" .. tostring(key))
    end,
  })
  local zeroOk, zeroResult = pcall(record.run, zeroCtx)
  T.check(zeroOk and type(zeroResult) == "table" and #zeroResult == 0,
    effectId .. " skips its callback at chance 0")

  local maxCtx = setmetatable({
    move={ id="AUDIT", type="NORMAL", effectChance=255 },
    -- Sixteen passes the 255 chance gate and gives Tri Attack a nonzero
    -- selector immediately instead of repeating its reserved-zero roll.
    rng=function() return 16 end,
  }, getmetatable(zeroCtx))
  local maxOk, maxError = pcall(record.run, maxCtx)
  T.check(not maxOk and tostring(maxError):find(
      "SECONDARY_HANDLER_REACHED", 1, true) ~= nil,
    effectId .. " reaches its callback at chance 255")
end

local function seq(values, fallback)
  local at = 0
  return function(low, high)
    at = at + 1
    local value = values[at]
    if value == nil then value = fallback end
    if value < low then return low end
    if value > high then return high end
    return value
  end
end

local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  save.options = save.options or {}
  save.options.ruleset = "gen1_faithful"
  local stack = { states={} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return {
    data=data, save=save, stack=stack,
    input={ wasPressed=function() return true end },
  }
end

local function stabilize(battler)
  battler.mon.stats.hp = 2000
  battler.mon.hp = 2000
  battler.mon.stats.attack = 100
  battler.mon.stats.defense = 100
  battler.mon.stats.speed = 100
  battler.mon.stats.special = 100
  battler.mon.stats.specialAttack = 100
  battler.mon.stats.specialDefense = 100
  battler.curStats = battler.mon.stats
  battler.shownHP = battler.mon.hp
  battler.mon.status = nil
  battler.stages = {
    attack=0, defense=0, speed=0, specialAttack=0, specialDefense=0,
    accuracy=0, evasion=0,
  }
  battler.confusedTurns, battler.flinched = nil, nil
  battler.mon.heldItem = nil
end

local function newBattle(moveId)
  local lead = Pokemon.new(data, "MEW", 50, function() return 15 end)
  lead.moves = { { id=moveId, pp=40 } }
  local battle = BattleState.newWild(makeGame({ lead }), "SNORLAX", 50)
  battle.turnCount, battle.phase = 1, "menu"
  battle.queue, battle.nextInsert = {}, 0
  stabilize(battle.player)
  stabilize(battle.enemy)
  battle:syncSides()
  battle.computeDamage = function()
    return 10, { crit=false, typeMult=10 }
  end
  return battle
end

local STAGE_KEYS = {
  "attack", "defense", "speed", "specialAttack", "specialDefense",
  "accuracy", "evasion",
}
local function effectState(battle)
  local out = {}
  for _, side in ipairs({ battle.player, battle.enemy }) do
    out[#out + 1] = tostring(side.mon.status)
    out[#out + 1] = tostring(side.confusedTurns)
    out[#out + 1] = tostring(side.flinched)
    for _, stat in ipairs(STAGE_KEYS) do
      out[#out + 1] = tostring((side.stages and side.stages[stat]) or 0)
    end
  end
  return table.concat(out, "|")
end

local function performAtChance(moveId, attackerIsPlayer, chance)
  local battle = newBattle(moveId)
  local move = assert(data.moves[moveId], moveId)
  local oldChance = move.effectChance
  move.effectChance = chance
  local user = attackerIsPlayer and battle.player or battle.enemy
  local target = attackerIsPlayer and battle.enemy or battle.player
  if moveId == "SNORE" then
    user.mon.status, user.sleepTurns = "SLP", 2
  end
  local before = effectState(battle)
  -- Accuracy, the mod-owned chance roll, then Tri Attack's status selector.
  battle.rng = seq({ 0, 0, 16 }, 16)
  local ok, err = pcall(battle.performMove, battle, user, target,
    { id=moveId, pp=move.pp or 40 })
  move.effectChance = oldChance
  T.check(ok, moveId .. " executes at chance " .. chance
    .. (attackerIsPlayer and " as player" or " as enemy")
    .. (ok and "" or ": " .. tostring(err)))
  return before, effectState(battle)
end

local familyMoves, auditedMoves = {}, 0
for moveId, move in pairs(data.moves) do
  if (move.index or 999) <= 251 and Effects.CHANCE_EFFECTS[move.effect] then
    familyMoves[move.effect] = (familyMoves[move.effect] or 0) + 1
    T.check((move.effectChance or 0) > 0,
      moveId .. " has a nonzero imported secondary-effect chance")
    for _, playerSide in ipairs({ true, false }) do
      local zeroBefore, zeroAfter = performAtChance(moveId, playerSide, 0)
      T.eq(zeroAfter, zeroBefore,
        moveId .. " suppresses its secondary at chance 0"
          .. (playerSide and " as player" or " as enemy"))
      local maxBefore, maxAfter = performAtChance(moveId, playerSide, 255)
      T.neq(maxAfter, maxBefore,
        moveId .. " applies its secondary at chance 255"
          .. (playerSide and " as player" or " as enemy"))
    end
    auditedMoves = auditedMoves + 1
  end
end
T.check(auditedMoves > familyCount,
  "the audit exercises every move, including shared effect families")

-- Twineedle owns its poison roll in the multi-hit command implementation.
for _, chance in ipairs({ 0, 255 }) do
  local battle = newBattle("TWINEEDLE")
  local move = data.moves.TWINEEDLE
  local oldChance = move.effectChance
  move.effectChance = chance
  battle.rng = seq({ 0, 0, 16 }, 16)
  battle:performMove(battle.player, battle.enemy, { id="TWINEEDLE", pp=20 })
  move.effectChance = oldChance
  local expected = false
  if chance ~= 0 then expected = "PSN" end
  T.eq(battle.enemy.mon.status or false, expected,
    "Twineedle " .. (chance == 0 and "suppresses" or "applies")
      .. " its manual poison chance")
end

-- Thief owns its item-transfer roll in its after-damage callback.
for _, chance in ipairs({ 0, 255 }) do
  local battle = newBattle("THIEF")
  local move = data.moves.THIEF
  local oldChance = move.effectChance
  move.effectChance = chance
  battle.enemy.mon.heldItem = "BERRY"
  battle.rng = seq({ 0, 0, 16 }, 16)
  battle:performMove(battle.player, battle.enemy, { id="THIEF", pp=25 })
  move.effectChance = oldChance
  local expected = false
  if chance ~= 0 then expected = "BERRY" end
  T.eq(battle.player.mon.heldItem or false, expected,
    "Thief " .. (chance == 0 and "suppresses" or "applies")
      .. " its manual item-transfer chance")
end

run.release()
T.finish(("Crystal secondary-effect audit (%d moves, %d families)")
  :format(auditedMoves + 2, familyCount + 2))
