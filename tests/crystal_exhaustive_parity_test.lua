package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local path = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP Crystal exhaustive parity (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local addresses = require("mods.CRYSTAL_251.addresses")
local revision = addresses.revisions["f2f52230b536214ef7c9924f483392993e226cfb"]
local cache = require("mods.CRYSTAL_251.lib.extractor").extract(raw, revision, {
  writePicture = function() end,
})
local encoded = require("mods.CRYSTAL_251.lib.json").encode(cache)

local oldInfo, oldRead = love.filesystem.getInfo, love.filesystem.read
love.filesystem.getInfo = function(p, kind)
  if p == "crystal_251/content.json" then return { type = "file" } end
  return oldInfo(p, kind)
end
love.filesystem.read = function(p)
  if p == "crystal_251/content.json" then return encoded end
  return oldRead(p)
end

local Data = require("src.core.Data")
Data:load()
local run = T.sdk.loadMod("mods/CRYSTAL_251", { data = Data })
love.filesystem.getInfo, love.filesystem.read = oldInfo, oldRead
T.eq(#run.errors, 0, "Crystal 251 loads before exhaustive parity")

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local EffectRegistry = require("src.battle.EffectRegistry")

local data = run.data
local exports = assert(run.loader.exports.CRYSTAL_251)
local crystalMoves = assert(exports.crystalMoves)
local scripts = assert(exports.crystalMoveScripts)
local interpreter = assert(exports.crystalCommandInterpreter)
local cacheByIndex = {}
for _, move in ipairs(cache.moves) do cacheByIndex[move.index] = move end

local function seq(value)
  return function(a, b)
    local v = value
    if a ~= nil and v < a then v = a end
    if b ~= nil and v > b then v = b end
    return v
  end
end

local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  save.options = save.options or {}
  save.options.ruleset = "gen1_faithful"
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return {
    data = data,
    save = save,
    stack = stack,
    input = { wasPressed = function() return true end },
  }
end

local function newBattle(moveId)
  local lead = Pokemon.new(data, "MEW", 50, function() return 15 end)
  local bench = Pokemon.new(data, "RATTATA", 30, function() return 15 end)
  local third = Pokemon.new(data, "BULBASAUR", 30, function() return 15 end)
  lead.moves = { { id = moveId, pp = 40 } }
  bench.moves = { { id = "TACKLE", pp = 35 } }
  third.moves = { { id = "GROWL", pp = 40 } }
  local battle = BattleState.newWild(makeGame({ lead, bench, third }), "MEW", 50)
  battle.turnCount = 1
  battle.phase = "menu"
  battle.rng = seq(255)
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    battler.mon.stats.hp = 1000
    battler.mon.hp = 1000
    battler.mon.stats.attack = 100
    battler.mon.stats.defense = 100
    battler.mon.stats.speed = 100
    battler.mon.stats.special = 100
    battler.curStats = battler.mon.stats
    battler.shownHP = battler.mon.hp
    battler.stages = battler.stages or {}
    battler.mon.heldItem = nil
  end
  return battle
end

local function neutralTargetType(moveType)
  if moveType == "GHOST" then return "PSYCHIC_TYPE" end
  return "NORMAL"
end

local metadataFields = {
  "id", "name", "index", "power", "type", "accuracy", "pp",
  "effectChance", "crystalAnim", "category", "priority", "highCrit",
}
local seenIds, seenIndexes = {}, {}
local modeCounts, routedCount = {}, 0
local effectiveEffectByte = {
  POISONPOWDER=0x42, POISON_GAS=0x42,
  PSYCHIC_M=0x48, CRUNCH=0x48, SHADOW_BALL=0x48,
}

for index = 1, 251 do
  local imported = assert(cacheByIndex[index], "missing extracted move " .. index)
  local live = crystalMoves[imported.id]
  local registered = data.moves[imported.id]
  local script = scripts[imported.id]

  T.check(live ~= nil, imported.id .. " exists in the imported Crystal move table")
  T.check(registered ~= nil, imported.id .. " resolves in the merged move registry")
  T.check(script ~= nil, imported.id .. " has a Crystal command script")
  T.check(not seenIds[imported.id], imported.id .. " appears once by id")
  T.check(not seenIndexes[index], imported.id .. " appears once by index")
  seenIds[imported.id], seenIndexes[index] = true, true

  if live then
    for _, field in ipairs(metadataFields) do
      T.eq(live[field], imported[field], imported.id .. " preserves ROM " .. field)
    end
    T.eq(MoveScripts.effectByte(live),
      effectiveEffectByte[imported.id] or MoveScripts.effectByte(imported),
      imported.id .. " resolves to the effective Crystal effect byte")
    local record = data.move_effects and data.move_effects[live.effect]
    T.check(record ~= nil, imported.id .. " resolves to an effect record")
    T.check(not record or record.implemented ~= false,
      imported.id .. " has no unimplemented effect placeholder")
  end

  if script then
    T.eq(script.index, index, imported.id .. " script keeps canonical index")
    T.eq(script.id, imported.id, imported.id .. " script keeps canonical id")
    T.check(#script.commands > 0, imported.id .. " script is not empty")
    local last = script.commands[#script.commands]
    local lastOp = type(last) == "table" and (last.op or last[1]) or last
    T.eq(lastOp, "endmove", imported.id .. " script terminates with endmove")
    local ok, err = interpreter:validate(script)
    T.check(ok, err or (imported.id .. " script validates"))
    modeCounts[script.mode] = (modeCounts[script.mode] or 0) + 1
  end

  if live and (live.power or 0) > 0 and CrystalDamage.isRouted(imported.id) then
    routedCount = routedCount + 1
    local battle = newBattle(imported.id)
    battle.enemy.curTypes = { neutralTargetType(live.type) }

    local okMin, minDamage, minInfo = pcall(function()
      return battle:computeDamage(battle.player, battle.enemy, live, {
        forceCrit = false,
        rng = seq(217),
      })
    end)
    T.check(okMin, imported.id .. " minimum damage vector executes")

    local okMax, maxDamage, maxInfo = pcall(function()
      return battle:computeDamage(battle.player, battle.enemy, live, {
        forceCrit = false,
        rng = seq(255),
      })
    end)
    T.check(okMax, imported.id .. " maximum damage vector executes")

    local okCrit, critDamage, critInfo = pcall(function()
      return battle:computeDamage(battle.player, battle.enemy, live, {
        forceCrit = true,
        rng = seq(255),
      })
    end)
    T.check(okCrit, imported.id .. " critical damage vector executes")

    if okMin and okMax and okCrit then
      T.check(minInfo and minInfo.crystal251 == true,
        imported.id .. " minimum vector uses Crystal damage")
      T.check(maxInfo and maxInfo.crystal251 == true,
        imported.id .. " maximum vector uses Crystal damage")
      T.check(critInfo and critInfo.crystal251 == true,
        imported.id .. " critical vector uses Crystal damage")
      T.check(minDamage >= 1, imported.id .. " minimum damage is positive")
      T.check(maxDamage >= minDamage,
        imported.id .. " maximum damage is not below minimum")
      T.check(critDamage >= maxDamage,
        imported.id .. " neutral critical damage is not below maximum normal damage")

      local categoryType = maxInfo.moveType or live.type
      local physical = categoryType == "NORMAL" or categoryType == "FIGHTING"
        or categoryType == "FLYING" or categoryType == "POISON"
        or categoryType == "GROUND" or categoryType == "ROCK"
        or categoryType == "BUG" or categoryType == "GHOST"
        or categoryType == "STEEL"
      T.eq(maxInfo.attackStat, physical and "attack" or "specialAttack",
        imported.id .. " uses the Generation II attacking stat")
      T.eq(maxInfo.defenseStat, physical and "defense" or "specialDefense",
        imported.id .. " uses the Generation II defending stat")
      if imported.id ~= "HIDDEN_POWER" then
        T.eq(maxInfo.moveType, live.type,
          imported.id .. " damage vector uses the imported type")
      else
        T.check(maxInfo.moveType ~= nil,
          "HIDDEN_POWER damage vector resolves its DV-derived type")
      end
      T.eq(table.concat(maxInfo.commandTrace or {}, ","),
        "critical,damagestats,damagecalc,stab,damagevariation,endmove",
        imported.id .. " follows the ordinary Crystal damage command order")

      if live.type == "FIRE" or live.type == "WATER" then
        local clear = maxDamage
        battle.weather = "rain"
        local rain = battle:computeDamage(battle.player, battle.enemy, live, {
          forceCrit = false, rng = seq(255),
        })
        battle.weather = "sun"
        local sun = battle:computeDamage(battle.player, battle.enemy, live, {
          forceCrit = false, rng = seq(255),
        })
        if live.type == "FIRE" then
          T.check(sun > clear and clear > rain,
            imported.id .. " follows Crystal sun and rain modifiers")
        else
          T.check(rain > clear and clear > sun,
            imported.id .. " follows Crystal rain and sun modifiers")
        end
      end
    end
  end
end

local function damagePair(id, setup)
  local battle = newBattle(id)
  battle.enemy.curTypes = { neutralTargetType(crystalMoves[id].type) }
  local normal = battle:computeDamage(
    battle.player, battle.enemy, crystalMoves[id], {
      forceCrit=false, rng=seq(255),
    })
  setup(battle)
  local modified = battle:computeDamage(
    battle.player, battle.enemy, crystalMoves[id], {
      forceCrit=false, rng=seq(255),
    })
  return normal, modified
end

for _, row in ipairs({
  { id="GUST", field="FLY" },
  { id="TWISTER", field="FLY" },
  { id="EARTHQUAKE", field="DIG" },
  { id="MAGNITUDE", field="DIG" },
}) do
  local normal, doubled = damagePair(row.id, function(battle)
    battle.enemy.invulnerableMove = row.field
  end)
  T.eq(doubled, math.min(65535, normal * 2),
    row.id .. " doubles final damage against " .. row.field)
end

local stomp, stompMinimized = damagePair("STOMP", function(battle)
  battle.enemy.minimized = true
end)
T.eq(stompMinimized, math.min(65535, stomp * 2),
  "STOMP doubles final damage against a minimized target")

local thunderBattle = newBattle("THUNDER")
local thunderMove = data.moves.THUNDER
local thunderRecord = thunderBattle:effectRecord(thunderMove.effect)
local thunderCtx = EffectRegistry.makeCtx(
  thunderBattle, thunderBattle.player, thunderBattle.enemy,
  thunderMove, thunderBattle.player.curMoves[1], false)
local checkedAccuracy
thunderCtx.accuracyRoll = function()
  checkedAccuracy = thunderMove.accuracy
  return false
end
thunderBattle.weather = "rain"
T.eq(thunderRecord.accuracy(thunderCtx), true,
  "THUNDER always hits in rain")
thunderBattle.weather = "sun"
T.eq(thunderRecord.accuracy(thunderCtx), false,
  "THUNDER still performs an accuracy check in sun")
T.eq(math.floor(checkedAccuracy * 255 / 100), 128,
  "THUNDER uses Crystal's 50 percent plus one threshold in sun")
T.eq(thunderMove.accuracy, crystalMoves.THUNDER.accuracy,
  "THUNDER restores its imported accuracy after the sun check")

local triBattle = newBattle("TRI_ATTACK")
local triMove = data.moves.TRI_ATTACK
local triRecord = triBattle:effectRecord(triMove.effect)
local triCtx = EffectRegistry.makeCtx(
  triBattle, triBattle.player, triBattle.enemy,
  triMove, triBattle.player.curMoves[1], false)
triCtx.rng = function() return 16 end
triRecord.run(triCtx)
T.eq(triBattle.enemy.mon.status, "PAR",
  "TRI_ATTACK selects its Crystal paralysis branch")

local curlBattle = newBattle("DEFENSE_CURL")
local curlMove = data.moves.DEFENSE_CURL
local curlRecord = curlBattle:effectRecord(curlMove.effect)
local curlCtx = EffectRegistry.makeCtx(
  curlBattle, curlBattle.player, curlBattle.enemy,
  curlMove, curlBattle.player.curMoves[1], false)
curlRecord.run(curlCtx)
T.eq(curlBattle.player.stages.defense, 1,
  "DEFENSE_CURL raises Defense")
T.eq(curlBattle.player.defenseCurl, true,
  "DEFENSE_CURL sets the Rollout curl flag")

local minimizeBattle = newBattle("MINIMIZE")
local minimizeMove = data.moves.MINIMIZE
local minimizeRecord = minimizeBattle:effectRecord(minimizeMove.effect)
local minimizeCtx = EffectRegistry.makeCtx(
  minimizeBattle, minimizeBattle.player, minimizeBattle.enemy,
  minimizeMove, minimizeBattle.player.curMoves[1], false)
minimizeRecord.run(minimizeCtx)
T.eq(minimizeBattle.player.minimized, true,
  "MINIMIZE sets the Stomp vulnerability flag")

T.eq(scripts.__count, 251, "the exported script table covers all 251 moves")
T.check(routedCount > 100,
  "the exhaustive matrix covers the ordinary damaging move set")
T.check((modeCounts.ordinary or 0) > 0, "ordinary move scripts are represented")
T.check((modeCounts.status or 0) > 0, "status move scripts are represented")
T.check((modeCounts.primary or 0) > 0, "primary effect scripts are represented")
T.check((modeCounts.specialized or 0) > 0, "specialized effect scripts are represented")
T.check((modeCounts.special or 0) > 0, "special-damage scripts are represented")
T.check((modeCounts.sequence or 0) > 0, "multi-turn scripts are represented")
T.check((modeCounts.switch or 0) > 0, "switching scripts are represented")

local ok, err = MoveScripts.validate(scripts, interpreter, 251)
T.check(ok, err or "the complete Crystal command table validates")

run.release()
T.finish("Crystal exhaustive move and damage parity")
