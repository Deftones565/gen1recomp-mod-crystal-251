package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local path = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP Crystal move edge parity (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local addresses = require("mods.CRYSTAL_251.addresses")
local revision = addresses.revisions["f2f52230b536214ef7c9924f483392993e226cfb"]
local generatedFiles = {}
local cache = require("mods.CRYSTAL_251.lib.extractor").extract(raw, revision, {
  writePicture = function(generatedPath)
    generatedFiles[#generatedFiles + 1] = generatedPath
  end,
})
cache.importFiles = generatedFiles
local encoded = require("mods.CRYSTAL_251.lib.json").encode(cache)

local generatedSet = {}
for _, generatedPath in ipairs(generatedFiles) do generatedSet[generatedPath] = true end
local oldInfo, oldRead = love.filesystem.getInfo, love.filesystem.read
love.filesystem.getInfo = function(p, kind)
  if p == "crystal_251/content.json" or generatedSet[p] then return { type = "file" } end
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
T.eq(#run.errors, 0, "Crystal 251 loads before edge-parity probes")

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")

local data = run.data

local function seq(values, fallback)
  local i = 0
  return function(a, b)
    i = i + 1
    local value
    if values and values[i] ~= nil then value = values[i]
    elseif fallback ~= nil then value = fallback
    else value = a or 0 end
    if type(value) == "number" then
      if a ~= nil and value < a then value = a end
      if b ~= nil and value > b then value = b end
    end
    return value
  end
end

local function makeMon(species, level, moves)
  local mon = Pokemon.new(data, species or "MEW", level or 50,
    function() return 15 end)
  if moves then mon.moves = moves end
  return mon
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

local function stabilize(battler, hp)
  battler.mon.stats.hp = hp or 1000
  battler.mon.hp = battler.mon.stats.hp
  battler.mon.stats.attack = 100
  battler.mon.stats.defense = 100
  battler.mon.stats.speed = 100
  battler.mon.stats.special = 100
  battler.curStats = battler.mon.stats
  battler.shownHP = battler.mon.hp
end

local function newBattle(moveId, opts)
  opts = opts or {}
  local level = opts.level or 50
  local lead = opts.party and opts.party[1]
    or makeMon(opts.playerSpecies or "MEW", level,
      opts.moves or { { id = moveId, pp = 40 } })
  if not lead.moves or #lead.moves == 0 then
    lead.moves = { { id = moveId, pp = 40 } }
  end
  local party = opts.party or { lead }
  local game = makeGame(party)
  local battle = BattleState.newWild(game, opts.enemySpecies or "SNORLAX", level)
  battle.turnCount = opts.turnCount or 1
  battle.phase = "menu"
  battle.rng = opts.rng or seq(nil, 0)
  battle.kind = opts.kind or "wild"

  if opts.enemyParty then
    battle.enemyParty = opts.enemyParty
    battle.enemyIndex = opts.enemyIndex or 1
    battle.enemy = BattleState.makeBattler(data,
      battle.enemyParty[battle.enemyIndex], false)
  end
  if battle.kind == "trainer" then
    battle.trainer = opts.trainer or { id = "CRYSTAL_EDGE_TEST", name = "TEST" }
    battle.enemyParty = battle.enemyParty or { battle.enemy.mon }
    battle.enemyIndex = battle.enemyIndex or 1
  elseif battle.kind == "link" then
    battle.opponentName = "LINK TEST"
    battle.enemyParty = battle.enemyParty or { battle.enemy.mon }
    battle.enemyIndex = battle.enemyIndex or 1
  end

  stabilize(battle.player, opts.maxHP)
  stabilize(battle.enemy, opts.maxHP)
  battle:syncSides()
  return battle, lead
end

local function perform(battle, moveId, moveInst, user, target)
  user = user or battle.player
  target = target or battle.enemy
  moveInst = moveInst or { id = moveId, pp = data.moves[moveId].pp or 40 }
  battle:performMove(user, target, moveInst)
  return moveInst
end

local function drainQueue(battle)
  local guard = 0
  while #battle.queue > 0 do
    guard = guard + 1
    if guard > 2000 then error("battle queue did not drain") end
    local row = table.remove(battle.queue, 1)
    battle.nextInsert = 0
    if row.fn then row.fn() end
  end
  battle.nextInsert = 0
end

local function hasText(battle, fragment)
  for _, row in ipairs(battle.queue or {}) do
    if row.text and row.text:find(fragment, 1, true) then return true end
  end
  return false
end

local function textCount(battle, fragment)
  local count = 0
  for _, row in ipairs(battle.queue or {}) do
    if row.text and row.text:find(fragment, 1, true) then count = count + 1 end
  end
  return count
end

local function stage(battler, stat)
  return (battler.stages and battler.stages[stat]) or 0
end

local function endTurn(battle, turn)
  Runtime.emit("battle.turn_ended", {
    battle = battle,
    turn = turn or battle.turnCount or 0,
  })
end

local function switched(battle, previous, incoming, batonPass)
  battle:syncSides()
  Runtime.emit("battle.battler_switched", {
    battle = battle,
    side = battle:sideOf(incoming),
    battler = incoming,
    previous = previous,
    batonPass = batonPass or false,
  })
end

local function withField(tbl, key, value, fn)
  local old = tbl[key]
  tbl[key] = value
  local ok, err = pcall(fn)
  tbl[key] = old
  if not ok then error(err, 0) end
end

local function case(name, fn)
  local ok, err = pcall(fn)
  T.check(ok, name .. (ok and "" or " (" .. tostring(err) .. ")"))
end

local function observedPower(moveId, opts)
  opts = opts or {}
  local move = data.moves[moveId]
  local seen
  run.loader.hooks:call("battle.damage", function(ctx)
    seen = ctx.move.power
    return 1, { crit = false, typeMult = 10 }
  end, {
    battle = { weather = opts.weather },
    move = move,
    rng = opts.rng or seq(nil, 255),
    user = {
      mon = {
        hp = opts.hp or 100,
        happiness = opts.happiness,
        stats = { hp = opts.maxHP or 100 },
        dvs = opts.dvs or { attack=15, defense=15, speed=15, special=15 },
      },
      rolloutCount = opts.rolloutCount,
      furyCutterCount = opts.furyCutterCount,
      defenseCurl = opts.defenseCurl,
    },
    target = {
      mon = { hp = 1000, stats = { hp = 1000 } },
      curTypes = opts.targetTypes or { "NORMAL" },
    },
  })
  return seen
end

-- -------------------------------------------------------------------------
-- Accuracy failure and semi-invulnerability
-- -------------------------------------------------------------------------

case("Sweet Kiss accuracy failure has no effect", function()
  local battle = newBattle("SWEET_KISS")
  battle.accuracyRoll = function() return false end
  perform(battle, "SWEET_KISS")
  T.eq(battle.enemy.confusedTurns, nil,
    "Sweet Kiss miss does not confuse")
end)

case("Iron Tail accuracy failure suppresses damage and its secondary", function()
  local battle = newBattle("IRON_TAIL")
  battle.accuracyRoll = function() return false end
  local hp, defense = battle.enemy.mon.hp, stage(battle.enemy, "defense")
  perform(battle, "IRON_TAIL")
  T.eq(battle.enemy.mon.hp, hp, "Iron Tail miss deals no damage")
  T.eq(stage(battle.enemy, "defense"), defense,
    "Iron Tail miss does not lower Defense")
end)

case("ordinary new damaging moves miss a Fly target", function()
  local battle = newBattle("MEGAHORN")
  battle.enemy.invulnerable = true
  battle.enemy.invulnerableMove = "FLY"
  local hp = battle.enemy.mon.hp
  perform(battle, "MEGAHORN")
  T.eq(battle.enemy.mon.hp, hp, "Megahorn cannot hit Fly")
end)

case("always-hit moves still respect semi-invulnerability", function()
  local battle = newBattle("FAINT_ATTACK")
  battle.enemy.invulnerable = true
  battle.enemy.invulnerableMove = "FLY"
  local hp = battle.enemy.mon.hp
  perform(battle, "FAINT_ATTACK")
  T.eq(battle.enemy.mon.hp, hp, "Faint Attack cannot hit Fly")
end)

case("Twister is the new-move exception that can hit Fly", function()
  local ordinary = newBattle("TWISTER")
  local hp1 = ordinary.enemy.mon.hp
  perform(ordinary, "TWISTER")
  local normalDamage = hp1 - ordinary.enemy.mon.hp

  local flying = newBattle("TWISTER")
  flying.enemy.invulnerable = true
  flying.enemy.invulnerableMove = "FLY"
  local hp2 = flying.enemy.mon.hp
  perform(flying, "TWISTER")
  T.check(hp2 - flying.enemy.mon.hp > normalDamage,
    "Twister hits Fly for doubled damage")
end)

-- -------------------------------------------------------------------------
-- Immunity and Substitute interactions
-- -------------------------------------------------------------------------

case("Fighting immunity and Foresight interaction", function()
  local battle = newBattle("MACH_PUNCH", { enemySpecies = "GASTLY" })
  local hp = battle.enemy.mon.hp
  perform(battle, "MACH_PUNCH")
  T.eq(battle.enemy.mon.hp, hp, "Mach Punch is immune against Ghost")
  perform(battle, "FORESIGHT")
  perform(battle, "MACH_PUNCH")
  T.check(battle.enemy.mon.hp < hp,
    "Foresight lets a Fighting move damage Ghost")
end)

case("Foresight preserves stages while neutralizing evasion advantage", function()
  local battle = newBattle("FORESIGHT", { enemySpecies="GASTLY" })
  battle.player.stages.accuracy = -2
  battle.enemy.stages.evasion = 3
  perform(battle, "FORESIGHT")
  T.eq(stage(battle.enemy, "evasion"), 3,
    "Foresight does not erase the target's stored Evasion stage")
  T.eq(stage(battle.player, "accuracy"), -2,
    "Foresight does not erase the user's stored Accuracy stage")
  local hp = battle.enemy.mon.hp
  battle.rng = seq(nil, 200)
  perform(battle, "MACH_PUNCH")
  T.check(battle.enemy.mon.hp < hp,
    "Foresight neutralizes the accuracy/evasion disadvantage for its user")
end)

case("Shadow Ball immunity suppresses its secondary", function()
  local move = data.moves.SHADOW_BALL
  withField(move, "effectChance", 255, function()
    local battle = newBattle("SHADOW_BALL", { enemySpecies = "SNORLAX" })
    local hp = battle.enemy.mon.hp
    perform(battle, "SHADOW_BALL")
    T.eq(battle.enemy.mon.hp, hp, "Shadow Ball is immune against Normal")
    T.eq(stage(battle.enemy, "specialDefense"), 0,
      "immune Shadow Ball cannot lower Special Defense")
  end)
end)

case("Substitute blocks damaging secondary status and stat effects", function()
  local poison = data.moves.SLUDGE_BOMB
  withField(poison, "effectChance", 255, function()
    local battle = newBattle("SLUDGE_BOMB")
    battle.enemy.substituteHP = 500
    perform(battle, "SLUDGE_BOMB")
    T.eq(battle.enemy.mon.status, nil,
      "Substitute blocks Sludge Bomb poison")
  end)
  local shadow = data.moves.SHADOW_BALL
  withField(shadow, "effectChance", 255, function()
    local battle = newBattle("SHADOW_BALL", { enemySpecies = "MEW" })
    battle.enemy.substituteHP = 500
    perform(battle, "SHADOW_BALL")
    T.eq(stage(battle.enemy, "specialDefense"), 0,
      "Substitute blocks Shadow Ball's stage drop")
  end)
end)

case("Substitute blocks confusion but not Mean Look or Spider Web", function()
  local kiss = newBattle("SWEET_KISS")
  kiss.enemy.substituteHP = 500
  perform(kiss, "SWEET_KISS")
  T.eq(kiss.enemy.confusedTurns, nil,
    "Substitute blocks Sweet Kiss")

  for _, moveId in ipairs({ "MEAN_LOOK", "SPIDER_WEB" }) do
    local battle = newBattle(moveId)
    battle.enemy.substituteHP = 500
    perform(battle, moveId)
    T.check(battle.enemy.cantEscape == true,
      moveId .. " traps through Substitute in Crystal")
  end
end)

case("Thief cannot steal through Substitute", function()
  local battle = newBattle("THIEF")
  battle.player.mon.heldItem = nil
  battle.enemy.mon.heldItem = "BERRY"
  battle.enemy.substituteHP = 500
  perform(battle, "THIEF")
  T.eq(battle.player.mon.heldItem, nil,
    "Thief does not steal through an intact Substitute")
  T.eq(battle.enemy.mon.heldItem, "BERRY",
    "Substitute owner retains its item")
end)

case("Protect Detect and Endure fail while user has a Substitute", function()
  for _, moveId in ipairs({ "PROTECT", "DETECT", "ENDURE" }) do
    local battle = newBattle(moveId)
    battle.player.substituteHP = 100
    perform(battle, moveId)
    T.eq(battle.player.protect, nil, moveId .. " does not protect behind Substitute")
    T.eq(battle.player.endure, nil, moveId .. " does not endure behind Substitute")
  end
end)

-- -------------------------------------------------------------------------
-- Secondary effects after fainting
-- -------------------------------------------------------------------------

case("secondary status and confusion do not run after a KO", function()
  for _, row in ipairs({
    { id="SLUDGE_BOMB", field="status" },
    { id="DYNAMICPUNCH", field="confusedTurns" },
  }) do
    local move = data.moves[row.id]
    withField(move, "effectChance", 255, function()
      local battle = newBattle(row.id)
      battle.enemy.mon.hp = 1
      perform(battle, row.id)
      if row.field == "status" then
        T.eq(battle.enemy.mon.status, nil, row.id .. " KO does not inflict status")
      else
        T.eq(battle.enemy.confusedTurns, nil, row.id .. " KO does not confuse")
      end
    end)
  end
end)

case("secondary stat changes do not run after a KO", function()
  for _, row in ipairs({
    { id="SHADOW_BALL", who="target", stat="specialDefense", species="MEW" },
    { id="STEEL_WING", who="user", stat="defense" },
    { id="ANCIENTPOWER", who="user", stat="attack" },
  }) do
    local move = data.moves[row.id]
    withField(move, "effectChance", 255, function()
      local battle = newBattle(row.id, { enemySpecies = row.species })
      battle.enemy.mon.hp = 1
      perform(battle, row.id)
      local battler = row.who == "user" and battle.player or battle.enemy
      T.eq(stage(battler, row.stat), 0,
        row.id .. " KO suppresses its stage effect")
    end)
  end
end)

-- -------------------------------------------------------------------------
-- HP, stage, PP, and invalid-last-move boundaries
-- -------------------------------------------------------------------------

case("Belly Drum exact HP and stage boundaries", function()
  local fail = newBattle("BELLY_DRUM")
  fail.player.mon.hp = 500
  perform(fail, "BELLY_DRUM")
  T.eq(fail.player.mon.hp, 500, "Belly Drum fails at exactly half HP")
  T.eq(stage(fail.player, "attack"), 2,
    "Crystal's Belly Drum bug applies the first sharp Attack boost before the HP check")

  local success = newBattle("BELLY_DRUM")
  success.player.mon.hp = 501
  perform(success, "BELLY_DRUM")
  T.eq(success.player.mon.hp, 1, "Belly Drum spends exactly half max HP")
  T.eq(stage(success.player, "attack"), 6,
    "Belly Drum maximizes Attack")

  local capped = newBattle("BELLY_DRUM")
  capped.player.stages.attack = 6
  capped.player.mon.hp = 1000
  perform(capped, "BELLY_DRUM")
  T.eq(capped.player.mon.hp, 1000,
    "Belly Drum fails without HP cost at maximum Attack")
  T.eq(stage(capped.player, "attack"), 6,
    "failed Belly Drum preserves maximum Attack")
end)

case("Spite validates last move and PP", function()
  local missing = newBattle("SPITE")
  perform(missing, "SPITE")
  T.check(hasText(missing, "failed"), "Spite fails without a last move")

  local absent = newBattle("SPITE")
  absent.enemy.lastMove = "TACKLE"
  absent.enemy.curMoves = { { id="GROWL", pp=40 } }
  perform(absent, "SPITE")
  T.eq(absent.enemy.curMoves[1].pp, 40,
    "Spite cannot drain an absent move slot")

  local empty = newBattle("SPITE")
  empty.enemy.lastMove = "TACKLE"
  empty.enemy.curMoves = { { id="TACKLE", pp=0 } }
  perform(empty, "SPITE")
  T.eq(empty.enemy.curMoves[1].pp, 0,
    "Spite cannot underflow zero PP")
end)

case("Encore validates the target's last move", function()
  local missing = newBattle("ENCORE")
  perform(missing, "ENCORE")
  T.eq(missing.enemy.encoreTurns, nil,
    "Encore fails without a last move")

  local absent = newBattle("ENCORE")
  absent.enemy.lastMove = "TACKLE"
  absent.enemy.curMoves = { { id="GROWL", pp=40 } }
  perform(absent, "ENCORE")
  T.eq(absent.enemy.encoreTurns, nil,
    "Encore fails when the last move is no longer known")

  local empty = newBattle("ENCORE")
  empty.enemy.lastMove = "TACKLE"
  empty.enemy.curMoves = { { id="TACKLE", pp=0 } }
  perform(empty, "ENCORE")
  T.eq(empty.enemy.encoreTurns, nil,
    "Encore fails when the last move has no PP")

  local struggle = newBattle("ENCORE")
  struggle.enemy.lastMove = "STRUGGLE"
  struggle.enemy.curMoves = { { id="STRUGGLE", pp=1 } }
  perform(struggle, "ENCORE")
  T.eq(struggle.enemy.encoreTurns, nil,
    "Encore cannot lock Struggle")
end)

case("Sketch rejects invalid last moves without replacing its slot", function()
  for _, last in ipairs({ false, "SKETCH", "STRUGGLE" }) do
    local battle = newBattle("SKETCH")
    battle.enemy.lastMove = last or nil
    local inst = { id="SKETCH", pp=1 }
    perform(battle, "SKETCH", inst)
    T.eq(inst.id, "SKETCH", "Sketch preserves its slot on invalid target move")
  end
end)

case("Return Frustration Flail and Reversal have exact power endpoints", function()
  T.eq(observedPower("RETURN", { happiness=0 }), 1,
    "Return power floor is 1")
  T.eq(observedPower("RETURN", { happiness=255 }), 102,
    "Return power ceiling is 102")
  T.eq(observedPower("FRUSTRATION", { happiness=255 }), 1,
    "Frustration power floor is 1")
  T.eq(observedPower("FRUSTRATION", { happiness=0 }), 102,
    "Frustration power ceiling is 102")

  local bands = {
    { hp=100, power=20 }, { hp=68, power=40 }, { hp=34, power=80 },
    { hp=20, power=100 }, { hp=8, power=150 }, { hp=2, power=200 },
  }
  for _, moveId in ipairs({ "FLAIL", "REVERSAL" }) do
    for _, row in ipairs(bands) do
      T.eq(observedPower(moveId, { hp=row.hp, maxHP=100 }), row.power,
        moveId .. " HP-band power at " .. row.hp .. "/100")
    end
  end
end)

case("healing moves cap at max HP and fail at full HP", function()
  for _, moveId in ipairs({ "MILK_DRINK", "MORNING_SUN", "SYNTHESIS", "MOONLIGHT" }) do
    local battle = newBattle(moveId)
    battle.player.mon.hp = 1000
    perform(battle, moveId)
    T.eq(battle.player.mon.hp, 1000, moveId .. " does not exceed max HP")
  end
end)

case("ordinary PP consumption never triggers Struggle recoil", function()
  local ordinary, lead = newBattle("TACKLE", {
    moves={ { id="TACKLE", pp=10 } }, rng=seq(nil, 0),
  })
  local hp = ordinary.player.mon.hp
  perform(ordinary, "TACKLE", lead.moves[1])
  T.eq(lead.moves[1].pp, 9, "ordinary move spends exactly one PP")
  T.eq(ordinary.player.mon.hp, hp, "ordinary move causes no recoil")
  T.eq(hasText(ordinary, "hit with recoil"), false,
    "ordinary move prints no Struggle recoil text")

  local struggle = newBattle("TACKLE", { rng=seq(nil, 0) })
  local struggleHP = struggle.player.mon.hp
  perform(struggle, "STRUGGLE", { id="STRUGGLE", pp=1, struggle=true })
  T.check(struggle.player.mon.hp < struggleHP,
    "actual Struggle still applies recoil")
end)

case("multi-hit and called moves spend PP only once", function()
  for _, moveId in ipairs({ "TRIPLE_KICK", "BEAT_UP" }) do
    local lead = makeMon("MEW", 50, { { id=moveId, pp=10 } })
    local bench = makeMon("RATTATA", 20)
    local battle = newBattle(moveId, { party={lead, bench} })
    perform(battle, moveId, lead.moves[1])
    T.eq(lead.moves[1].pp, 9, moveId .. " spends one PP for the whole sequence")
  end
end)

case("Crystal ordinary multi-hit checks accuracy once and recalculates each hit", function()
  local battle = newBattle("DOUBLESLAP")
  local damageCalls, accuracyCalls = 0, 0
  battle.rng = seq({ 1 }, 0) -- select three hits
  battle.accuracyRoll = function()
    accuracyCalls = accuracyCalls + 1
    return true
  end
  battle.computeDamage = function()
    damageCalls = damageCalls + 1
    return damageCalls * 10, { crit=false, typeMult=10 }
  end
  local hp = battle.enemy.mon.hp
  perform(battle, "DOUBLESLAP")
  T.eq(accuracyCalls, 1, "ordinary multi-hit performs one accuracy check")
  T.eq(damageCalls, 3, "ordinary multi-hit recalculates all three hits")
  T.eq(hp - battle.enemy.mon.hp, 60,
    "ordinary multi-hit applies each independent damage result")
  T.check(hasText(battle, "3 times"), "ordinary multi-hit reports its hit count")

  battle = newBattle("DOUBLESLAP")
  battle.rng = seq({ 0 }, 0) -- two hits
  battle.accuracyRoll = function() return true end
  battle.computeDamage = function()
    return 10, { crit=false, typeMult=10 }
  end
  battle.enemy.substituteHP = 1
  hp = battle.enemy.mon.hp
  perform(battle, "DOUBLESLAP")
  T.eq(battle.enemy.substituteHP, nil, "first hit breaks Substitute")
  T.eq(hp - battle.enemy.mon.hp, 10,
    "remaining multi-hit damage continues after Substitute")
end)

case("Crystal Rage uses a counter instead of Attack stages", function()
  local missBattle = newBattle("RAGE")
  missBattle.computeDamage = function()
    return 10, { crit=false, typeMult=10 }
  end
  missBattle.accuracyRoll = function() return false end
  perform(missBattle, "RAGE")
  T.eq(missBattle.player.rageMove, nil,
    "a failed first Rage does not lock the user")

  local inst = { id="RAGE", pp=20 }
  local battle = newBattle("RAGE", { moves={inst} })
  battle.computeDamage = function()
    return 10, { crit=false, typeMult=10 }
  end
  battle.accuracyRoll = function() return true end
  perform(battle, "RAGE", inst)
  T.eq(inst.pp, 19, "first Rage spends one PP")
  T.eq(stage(battle.player, "attack"), 0,
    "starting Crystal Rage does not raise Attack")

  battle.rng = seq({ 1 }, 0) -- enemy DoubleSlap lands three hits
  perform(battle, "DOUBLESLAP", { id="DOUBLESLAP", pp=10 },
    battle.enemy, battle.player)
  T.eq(battle.player.crystalRageCounter, 3,
    "each move hit increments the Rage counter")
  T.eq(stage(battle.player, "attack"), 0,
    "Rage counter growth remains separate from Attack stages")

  local counter = battle.player.crystalRageCounter
  battle:applyDamage(battle.player, 1)
  T.eq(battle.player.crystalRageCounter, counter,
    "residual damage does not build Rage")
  T.eq(stage(battle.player, "attack"), 0,
    "residual damage cannot trigger the Gen I Rage implementation")

  local hp = battle.enemy.mon.hp
  perform(battle, "RAGE", inst)
  T.eq(hp - battle.enemy.mon.hp, 40,
    "a counter of three makes the next Rage deal four times damage")
  T.eq(inst.pp, 18, "each selected Crystal Rage spends one PP")
end)

-- -------------------------------------------------------------------------
-- Switching either participant
-- -------------------------------------------------------------------------

case("normal switching clears volatile state instead of passing it", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead, bench} })
  battle.player.stages.attack = 4
  battle.player.perishTurns = 2
  battle.player.substituteHP = 50
  battle.player.confusedTurns = 3
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(battle.player.mon == bench, "normal switch selects the requested party member")
  T.eq(stage(battle.player, "attack"), 0, "normal switch clears stages")
  T.eq(battle.player.perishTurns, nil, "normal switch clears Perish Song")
  T.eq(battle.player.substituteHP, nil, "normal switch clears Substitute")
  T.eq(battle.player.confusedTurns, nil, "normal switch clears confusion")
end)

case("Baton Pass preserves Perish Song while normal switch clears it", function()
  local lead = makeMon("MEW", 50, { { id="BATON_PASS", pp=40 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("BATON_PASS", { party={lead, bench} })
  battle.player.perishTurns = 2
  perform(battle, "BATON_PASS", lead.moves[1])
  T.eq(battle.player.perishTurns, 2,
    "Baton Pass transfers the current Perish Song count")
end)

case("switching the Mean Look source releases the target", function()
  local lead = makeMon("MEW", 50, { { id="MEAN_LOOK", pp=5 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("MEAN_LOOK", { party={lead, bench} })
  perform(battle, "MEAN_LOOK", lead.moves[1])
  T.check(battle.enemy.cantEscape == true, "Mean Look starts trapping")
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(battle.enemy.cantEscape, nil,
    "target is released when Mean Look's source leaves normally")
end)

case("Attract and Foresight clear on the relevant switch", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead, bench} })
  battle.enemy.infatuatedWith = battle.player
  battle.player.infatuatedWith = battle.enemy
  battle.enemy.foresight = true
  local previous = battle.enemy
  local incomingMon = makeMon("BULBASAUR", 20)
  battle.enemy = BattleState.makeBattler(data, incomingMon, false)
  switched(battle, previous, battle.enemy, false)
  T.eq(previous.infatuatedWith, nil,
    "switching target clears its outgoing Attract relation")
  T.eq(battle.player.infatuatedWith, nil,
    "switching source clears the other battler's Attract relation")
  T.eq(battle.enemy.foresight, nil,
    "Foresight does not follow the identified target through a switch")
end)

case("Spikes applies on both player and enemy entry and ignores Flying", function()
  local battle = newBattle("SPIKES")
  battle.playerSpikes = true
  battle.enemySpikes = true

  local oldPlayer = battle.player
  local playerMon = makeMon("RATTATA", 20)
  battle.player = BattleState.makeBattler(data, playerMon, true, battle.game.save)
  stabilize(battle.player)
  local playerHP = battle.player.mon.hp
  switched(battle, oldPlayer, battle.player, false)
  T.eq(playerHP - battle.player.mon.hp, 125,
    "player entry takes one-eighth HP from Spikes")

  local oldEnemy = battle.enemy
  local enemyMon = makeMon("RATTATA", 20)
  battle.enemy = BattleState.makeBattler(data, enemyMon, false)
  stabilize(battle.enemy)
  local enemyHP = battle.enemy.mon.hp
  switched(battle, oldEnemy, battle.enemy, false)
  T.eq(enemyHP - battle.enemy.mon.hp, 125,
    "enemy entry takes one-eighth HP from Spikes")

  local oldFlying = battle.enemy
  local flyingMon = makeMon("PIDGEY", 20)
  battle.enemy = BattleState.makeBattler(data, flyingMon, false)
  stabilize(battle.enemy)
  local flyingHP = battle.enemy.mon.hp
  switched(battle, oldFlying, battle.enemy, false)
  T.eq(battle.enemy.mon.hp, flyingHP, "Flying entry ignores Spikes")
end)

case("Spikes bypasses Baton Pass Substitute and preserves the zero-HP bug", function()
  local lead = makeMon("MEW", 50, { {id="BATON_PASS",pp=40} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("BATON_PASS", { party={lead,bench} })
  battle.playerSpikes = true
  battle.player.substituteHP = 50
  bench.hp = 1
  perform(battle, "BATON_PASS", lead.moves[1])
  T.eq(battle.player.substituteHP, 50,
    "Spikes does not damage a passed Substitute")
  T.eq(battle.player.mon.hp, 0,
    "Spikes can leave the incoming battler at zero HP")
  T.eq(battle.player.faintQueued, nil,
    "Crystal does not immediately queue the Spikes faint")
end)

case("Mean Look and partial trapping prevent voluntary switching", function()
  local lead = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.cantEscape = true
  battle.enemyAction = function() return nil end
  local previous = battle.player
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(battle.player == previous,
    "a trapped battler cannot switch voluntarily")
end)

case("trainer switching resolves before an ordinary move", function()
  local player = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local oldEnemy = makeMon("RATTATA", 30, { {id="TACKLE",pp=35} })
  local incoming = makeMon("BULBASAUR", 30)
  local battle = newBattle("TACKLE", {
    kind="trainer", party={player}, enemyParty={oldEnemy,incoming}, enemyIndex=1,
  })
  battle.enemyAction = function() return {special="aiSwitch",index=2} end
  local oldHP = battle.enemy.mon.hp
  battle:resolveTurn(player.moves[1])
  drainQueue(battle)
  T.eq(oldEnemy.hp, oldHP, "ordinary move does not hit the withdrawn battler")
  T.check(incoming.hp < incoming.stats.hp,
    "ordinary move targets the incoming battler")
end)

case("Roar requires the target side to have acted first", function()
  local player = makeMon("MEW", 50, { {id="ROAR",pp=20} })
  local oldEnemy = makeMon("RATTATA", 30, { {id="TACKLE",pp=35} })
  local incoming = makeMon("BULBASAUR", 30)
  local battle = newBattle("ROAR", {
    kind="trainer", party={player}, enemyParty={oldEnemy,incoming}, enemyIndex=1,
    rng=seq(nil,1),
  })
  perform(battle, "ROAR", player.moves[1])
  T.check(battle.enemy.mon == oldEnemy,
    "Roar fails before the target side acts")
  battle.crystalActedSides = { enemy=battle.turnCount }
  perform(battle, "ROAR", player.moves[1])
  T.check(battle.enemy.mon == incoming,
    "Roar succeeds after the target side acts")
end)

case("Roar tracks the side after an earlier Baton Pass", function()
  local player = makeMon("MEW", 50, { {id="ROAR",pp=20} })
  local oldEnemy = makeMon("RATTATA", 30, { {id="BATON_PASS",pp=40} })
  local middle = makeMon("BULBASAUR", 30)
  local last = makeMon("CHARMANDER", 30)
  local battle = newBattle("ROAR", {
    kind="trainer", party={player}, enemyParty={oldEnemy,middle,last}, enemyIndex=1,
    rng=seq({1,2},2),
  })
  battle.batonPassChoice = function(user) return user.isPlayer and 1 or 2 end
  battle.enemyAction = function() return oldEnemy.moves[1] end
  battle:resolveTurn(player.moves[1])
  drainQueue(battle)
  T.check(battle.enemy.mon == last,
    "Roar can force the replacement after that side already acted")
end)

case("a slower move targets the Baton Pass replacement", function()
  local player = makeMon("MEW", 30, { {id="TACKLE",pp=35} })
  local oldEnemy = makeMon("RATTATA", 50, { {id="BATON_PASS",pp=40} })
  local incoming = makeMon("BULBASAUR", 50)
  local battle = newBattle("TACKLE", {
    kind="trainer", party={player}, enemyParty={oldEnemy,incoming}, enemyIndex=1,
  })
  battle.player.curStats.speed = 10
  battle.enemy.curStats.speed = 200
  battle.batonPassChoice = function(user) return user.isPlayer and 1 or 2 end
  battle.enemyAction = function() return oldEnemy.moves[1] end
  local oldHP = battle.enemy.mon.hp
  battle:resolveTurn(player.moves[1])
  drainQueue(battle)
  T.eq(oldEnemy.hp, oldHP, "Baton Pass removes the outgoing target")
  T.check(incoming.hp < incoming.stats.hp,
    "the slower attack hits the Baton Pass replacement")
end)

-- -------------------------------------------------------------------------
-- Sleep Talk, Metronome, and Mirror Move interactions
-- -------------------------------------------------------------------------

case("Sleep Talk can call a Generation II move without spending its PP", function()
  local sleepTalk = { id="SLEEP_TALK", pp=10 }
  local kiss = { id="SWEET_KISS", pp=10 }
  local lead = makeMon("MEW", 50, { sleepTalk, kiss })
  lead.status = "SLP"
  local battle = newBattle("SLEEP_TALK", { party={lead}, rng=seq(nil, 1) })
  perform(battle, "SLEEP_TALK", sleepTalk)
  T.check((battle.enemy.confusedTurns or 0) > 0,
    "Sleep Talk executes the selected Gen II effect")
  T.eq(kiss.pp, 10, "Sleep Talk does not spend the called move's PP")
end)

case("Sleep Talk fails when every candidate is excluded", function()
  local sleepTalk = { id="SLEEP_TALK", pp=10 }
  local rest = { id="REST", pp=10 }
  local lead = makeMon("MEW", 50, { sleepTalk, rest })
  lead.status = "SLP"
  local battle = newBattle("SLEEP_TALK", { party={lead} })
  perform(battle, "SLEEP_TALK", sleepTalk)
  T.check(hasText(battle, "failed"),
    "Sleep Talk fails with only Sleep Talk and Rest")
end)

case("Metronome can dispatch a Generation II move", function()
  local order = data.constants.moveOrder
  data.constants.moveOrder = { "SWEET_KISS" }
  local ok, err = pcall(function()
    local battle = newBattle("METRONOME")
    perform(battle, "METRONOME")
    T.check((battle.enemy.confusedTurns or 0) > 0,
      "Metronome dispatches the selected Crystal move handler")
  end)
  data.constants.moveOrder = order
  if not ok then error(err, 0) end
end)

case("Mirror Move can copy a Generation II move without spending copied PP", function()
  local battle = newBattle("MIRROR_MOVE")
  battle.enemy.lastMove = "SWEET_KISS"
  perform(battle, "MIRROR_MOVE")
  T.check((battle.enemy.confusedTurns or 0) > 0,
    "Mirror Move executes the copied Crystal move")
end)

case("Mirror Move can copy Future Sight", function()
  local battle = newBattle("MIRROR_MOVE")
  battle.enemy.lastMove = "FUTURE_SIGHT"
  perform(battle, "MIRROR_MOVE")
  T.check(battle.crystalFutureSight and battle.crystalFutureSight.enemy,
    "Mirror Move schedules the copied Future Sight in Crystal")
end)

-- -------------------------------------------------------------------------
-- Consecutive-use reset behavior
-- -------------------------------------------------------------------------

case("Protect Detect and Endure share one consecutive-use chain", function()
  local battle = newBattle("PROTECT")
  battle.rng = seq({ 1, 2 }, 1)
  battle.turnCount = 1
  perform(battle, "PROTECT")
  T.check(battle.player.protect == true, "first Protect succeeds")
  battle.player.protect = nil

  battle.turnCount = 2
  perform(battle, "DETECT")
  T.check(battle.player.protect == true, "Detect continues Protect's chain")
  battle.player.protect = nil

  battle.turnCount = 3
  perform(battle, "ENDURE")
  T.eq(battle.player.endure, nil,
    "third shared-chain use can fail at its one-in-four check")
end)

case("an unrelated move resets the Protect family chain", function()
  local battle = newBattle("PROTECT")
  battle.turnCount = 1
  perform(battle, "PROTECT")
  perform(battle, "TACKLE")
  battle.turnCount = 3
  battle.rng = function(a) return a end
  perform(battle, "DETECT")
  T.check(battle.player.protect == true,
    "unrelated move resets consecutive Protect odds")
  T.eq(battle.player.protectChain, 1,
    "reset chain restarts from its first use")
end)

case("Rollout resets on miss and Defense Curl doubles its power", function()
  local battle = newBattle("ROLLOUT")
  perform(battle, "ROLLOUT")
  T.check((battle.player.rolloutCount or 0) > 0,
    "successful Rollout starts its sequence")
  battle.accuracyRoll = function() return false end
  perform(battle, "ROLLOUT", battle.player.forcedMove or {id="ROLLOUT",pp=20})
  T.eq(battle.player.rolloutCount, nil, "Rollout miss resets the counter")
  T.eq(battle.player.forcedMove, nil, "Rollout miss releases the forced move")

  local plain = observedPower("ROLLOUT", { rolloutCount=0 })
  local curled = observedPower("ROLLOUT", { rolloutCount=0, defenseCurl=true })
  T.eq(curled, plain * 2, "Defense Curl doubles Rollout power")
end)

case("Fury Cutter resets and caps at 160 power", function()
  local battle = newBattle("FURY_CUTTER")
  perform(battle, "FURY_CUTTER")
  T.check((battle.player.furyCutterCount or 0) > 0,
    "Fury Cutter starts its counter")
  perform(battle, "TACKLE")
  T.eq(battle.player.furyCutterCount, nil,
    "unrelated move resets Fury Cutter")
  T.eq(observedPower("FURY_CUTTER", { furyCutterCount=5 }), 160,
    "Fury Cutter caps at 160 power")
end)

case("normal switching clears Rollout Fury Cutter and Defense Curl state", function()
  local lead = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.rolloutCount = 3
  battle.player.furyCutterCount = 4
  battle.player.defenseCurl = true
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(battle.player.rolloutCount, nil, "switch clears Rollout")
  T.eq(battle.player.furyCutterCount, nil, "switch clears Fury Cutter")
  T.eq(battle.player.defenseCurl, nil, "normal switch clears Defense Curl bonus")
end)

-- -------------------------------------------------------------------------
-- Wild, trainer, and link-battle differences
-- -------------------------------------------------------------------------

case("enemy Thief permanently removes a player item in ordinary battle", function()
  local battle = newBattle("THIEF")
  battle.player.mon.heldItem = "BERRY"
  battle.enemy.mon.heldItem = nil
  perform(battle, "THIEF", {id="THIEF",pp=10}, battle.enemy, battle.player)
  T.eq(battle.player.mon.heldItem, nil,
    "enemy Thief removes the player's held item")
  T.eq(battle.enemy.mon.heldItem, "BERRY",
    "enemy Thief receives the item")
  T.eq(battle.game.save.party[1].heldItem, nil,
    "ordinary battle updates the underlying player party item")
end)

case("link battle restores held-item ownership when battle ends", function()
  local player = makeMon("MEW", 50, { {id="THIEF",pp=10} })
  local enemy = makeMon("RATTATA", 50, { {id="TACKLE",pp=35} })
  player.heldItem = nil
  enemy.heldItem = "BERRY"
  local battle = newBattle("THIEF", {
    kind="link", party={player}, enemyParty={enemy}, enemyIndex=1,
  })
  perform(battle, "THIEF", player.moves[1])
  Runtime.emit("battle.ended", { battle=battle, result="win" })
  T.eq(player.heldItem, nil,
    "link battle restores the player's original item")
  T.eq(enemy.heldItem, "BERRY",
    "link battle restores the opponent's original item")
end)

case("Crystal import preserves species held-item slots", function()
  local heldMap = run.loader.exports.CRYSTAL_251
    and run.loader.exports.CRYSTAL_251.crystalHeldItems
  local held = heldMap and heldMap.SHUCKLE
  T.check(held ~= nil, "the mod exposes Shuckle's two Crystal held-item slots")
  if held then
    T.eq(held.common or held[1], "BERRY", "Shuckle common held item is Berry")
    T.eq(held.rare or held[2], "BERRY", "Shuckle rare held item is Berry")
  end
  local noItem = Pokemon.new(data, "SHUCKLE", 20, function(a, b)
    if a == 0 and b == 255 then return 255 end
    return b or a
  end, { wildHeldItem=true })
  T.eq(noItem.heldItem, nil,
    "identical item slots still preserve Crystal's 75 percent no-item roll")
  local hasItem = Pokemon.new(data, "SHUCKLE", 20, function(a, b)
    if a == 0 and b == 255 then return 0 end
    return b or a
  end, { wildHeldItem=true })
  T.eq(hasItem.heldItem, "BERRY",
    "Shuckle receives Berry when its wild held-item roll succeeds")
end)

case("Crystal held-item hooks affect live battle paths", function()
  local damageBattle = newBattle("SURF", { enemySpecies="MEW" })
  damageBattle.rng = seq(nil, 255)
  damageBattle.player.mon.heldItem = nil
  local plain = damageBattle:computeDamage(
    damageBattle.player, damageBattle.enemy, data.moves.SURF, { forceCrit=false })
  damageBattle.rng = seq(nil, 255)
  damageBattle.player.mon.heldItem = "MYSTIC_WATER"
  local boosted = damageBattle:computeDamage(
    damageBattle.player, damageBattle.enemy, data.moves.SURF, { forceCrit=false })
  T.check(boosted > plain, "Mystic Water boosts routed Water damage")

  local powderBattle = newBattle("TACKLE")
  powderBattle.enemy.mon.heldItem = "BRIGHTPOWDER"
  local hit = Runtime.call("battle.accuracy", function(ctx)
    return ctx.rng(0, 255) < 100
  end, { battle=powderBattle, user=powderBattle.player,
    target=powderBattle.enemy, move=data.moves.TACKLE,
    rng=function() return 80 end })
  T.eq(hit, false, "BrightPowder reduces live accuracy by twenty")

  local quickBattle = newBattle("TACKLE")
  quickBattle.player.mon.heldItem = "QUICK_CLAW"
  local first = Runtime.call("battle.turn_order", function() return false end,
    quickBattle.player, data.moves.TACKLE,
    quickBattle.enemy, data.moves.TACKLE,
    { rng=function() return 59 end })
  T.eq(first, true, "Quick Claw can override live turn order")

  local focusBattle = newBattle("TACKLE")
  focusBattle.enemy.mon.heldItem = "FOCUS_BAND"
  focusBattle.enemy.mon.hp = 80
  focusBattle._crystalMoveDamageDepth = 1
  focusBattle.rng = function() return 29 end
  local dealt = focusBattle:applyDamage(focusBattle.enemy, 80)
  focusBattle._crystalMoveDamageDepth = 0
  T.eq(dealt, 79, "Focus Band changes live move damage to leave one HP")
  T.eq(focusBattle.enemy.mon.hp, 1, "Focus Band preserves one HP in battle")

  local berryBattle = newBattle("TACKLE")
  berryBattle.player.mon.heldItem = "BERRY"
  berryBattle.player.mon.hp = 40
  berryBattle.player.mon.stats.hp = 100
  endTurn(berryBattle)
  T.eq(berryBattle.player.mon.hp, 50, "held Berry heals through turn-ended events")
  T.eq(berryBattle.player.mon.heldItem, nil, "live Berry use consumes the item")

  local smokeBattle = newBattle("TACKLE")
  smokeBattle.player.mon.heldItem = "SMOKE_BALL"
  smokeBattle.player.cantEscape = true
  T.eq(smokeBattle:runRoll(1, 999), true,
    "Smoke Ball overrides trapping in the live run hook")
  T.eq(smokeBattle.player.mon.heldItem, nil, "live Smoke Ball escape consumes it")
end)

-- -------------------------------------------------------------------------
-- Weather and residual-effect ordering
-- -------------------------------------------------------------------------

case("weather modifies routed damage without mutating move records", function()
  local function damage(moveId, weather)
    local battle = newBattle(moveId, { enemySpecies="MEW" })
    battle.weather = weather
    return battle:computeDamage(
      battle.player, battle.enemy, data.moves[moveId],
      { forceCrit=false, rng=seq(nil,255) })
  end

  local surfClear, surfRain, surfSun = damage("SURF"),
    damage("SURF", "rain"), damage("SURF", "sun")
  local fireClear, fireRain, fireSun = damage("FLAME_WHEEL"),
    damage("FLAME_WHEEL", "rain"), damage("FLAME_WHEEL", "sun")
  T.check(surfRain > surfClear and surfSun < surfClear,
    "Crystal weather strengthens and weakens Water damage")
  T.check(fireSun > fireClear and fireRain < fireClear,
    "Crystal weather strengthens and weakens Fire damage")

  for _, moveId in ipairs({ "SURF", "FLAME_WHEEL" }) do
    local base = data.moves[moveId].power
    T.eq(observedPower(moveId, { weather="rain" }), base,
      moveId .. " keeps its registered power in rain")
    T.eq(observedPower(moveId, { weather="sun" }), base,
      moveId .. " keeps its registered power in sun")
  end
end)

case("all ordinary moves use the mod-owned Crystal damage path", function()
  local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
  local exports = assert(run.loader.exports.CRYSTAL_251)
  local stats = assert(exports.crystalBaseStats)
  local crystalMoves = assert(exports.crystalMoves)
  T.eq(stats.ALAKAZAM.specialAttack, 135,
    "Crystal data keeps Alakazam's base Special Attack")
  T.eq(stats.ALAKAZAM.specialDefense, 85,
    "Crystal data keeps Alakazam's base Special Defense")
  T.eq(crystalMoves.BITE.type, "DARK",
    "the mod owns Bite's Generation II Dark record")
  T.eq(crystalMoves.WING_ATTACK.power, 60,
    "the mod owns Wing Attack's Generation II base power")

  local routed = 0
  for moveId, move in pairs(crystalMoves) do
    local expected = (move.power or 0) > 0 and move.category ~= "status"
      and not CrystalDamage.DEFERRED[moveId]
    T.eq(CrystalDamage.isRouted(moveId), expected,
      moveId .. " has the expected ordinary-damage routing")
    if expected then routed = routed + 1 end
  end
  T.check(routed > 100,
    "the standard Crystal pipeline covers the ordinary damaging move set")

  local probes = {
    TACKLE={ "attack", "defense", "NORMAL" },
    THUNDERBOLT={ "specialAttack", "specialDefense", "ELECTRIC" },
    BITE={ "specialAttack", "specialDefense", "DARK" },
    KARATE_CHOP={ "attack", "defense", "FIGHTING" },
    WING_ATTACK={ "attack", "defense", "FLYING" },
    SHADOW_BALL={ "attack", "defense", "GHOST" },
    CRUNCH={ "specialAttack", "specialDefense", "DARK" },
    SURF={ "specialAttack", "specialDefense", "WATER" },
  }
  for moveId, expected in pairs(probes) do
    local battle = newBattle(moveId, { enemySpecies="MEW" })
    local move = data.moves[moveId]
    local oldPower, oldType, oldCategory = move.power, move.type, move.category
    local _, info = battle:computeDamage(
      battle.player, battle.enemy, move,
      { forceCrit=false, rng=seq(nil,255) })
    T.check(info and info.crystal251 == true,
      moveId .. " is routed through the Crystal damage module")
    T.eq(info and info.attackStat, expected[1],
      moveId .. " selects the correct attacking stat")
    T.eq(info and info.defenseStat, expected[2],
      moveId .. " selects the correct defending stat")
    T.eq(info and info.moveType, expected[3],
      moveId .. " uses its Crystal battle type")
    T.eq(move.power, oldPower, moveId .. " restores registered power")
    T.eq(move.type, oldType, moveId .. " restores registered type")
    T.eq(move.category, oldCategory, moveId .. " restores registered category")
  end

  for _, moveId in ipairs({ "SONICBOOM", "COUNTER", "MIRROR_COAT",
      "FUTURE_SIGHT", "BEAT_UP", "PRESENT", "FISSURE" }) do
    T.eq(CrystalDamage.isRouted(moveId), false,
      moveId .. " remains on its command-specific damage path")
  end
end)

case("all 251 Crystal moves expose validated command scripts", function()
  local exports = assert(run.loader.exports.CRYSTAL_251)
  local scripts = assert(exports.crystalMoveScripts)
  local interpreter = assert(exports.crystalCommandInterpreter)
  T.eq(scripts.__count, 251, "the mod exports one command script per move")
  local ok, err = require("mods.CRYSTAL_251.battle.move_scripts")
    .validate(scripts, interpreter, 251)
  T.check(ok, err or "the complete Crystal script table validates")

  for moveId, effectName in pairs({
    TACKLE="NormalHit", GROWTH="SpecialAttackUp",
    AMNESIA="SpecialDefenseUp2", PSYCHIC_M="SpecialDefenseDownHit",
    SHADOW_BALL="SpecialDefenseDownHit", BIDE="Bide",
    FUTURE_SIGHT="FutureSight", BEAT_UP="BeatUp",
  }) do
    T.eq(scripts[moveId].effectName, effectName,
      moveId .. " resolves the expected Crystal effect family")
  end

  local battle = newBattle("TACKLE", { enemySpecies="MEW" })
  local _, info = battle:computeDamage(
    battle.player, battle.enemy, data.moves.TACKLE,
    { forceCrit=false, rng=seq(nil,255) })
  T.eq(table.concat(info.commandTrace or {}, ","),
    "critical,damagestats,damagecalc,stab,damagevariation,endmove",
    "ordinary damage follows the Crystal command interpreter")
end)

case("Crystal split-stat moves use independent stage fields", function()
  T.eq(data.moves.GROWTH.effect, "CRYSTAL_EFFECT_0D",
    "Growth uses the Crystal Special Attack effect")
  T.eq(data.moves.AMNESIA.effect, "CRYSTAL_EFFECT_36",
    "Amnesia uses the Crystal Special Defense effect")
  T.eq(data.moves.PSYCHIC_M.effect, "CRYSTAL_EFFECT_48",
    "Psychic uses Crystal's Special Defense secondary effect")

  local growth = newBattle("GROWTH")
  perform(growth, "GROWTH")
  T.eq(stage(growth.player, "specialAttack"), 1,
    "Growth raises Special Attack")
  T.eq(stage(growth.player, "specialDefense"), 0,
    "Growth does not raise Special Defense")
  T.eq(stage(growth.player, "special"), 0,
    "Growth does not recreate a shared Special stage")

  local amnesia = newBattle("AMNESIA")
  perform(amnesia, "AMNESIA")
  T.eq(stage(amnesia.player, "specialDefense"), 2,
    "Amnesia sharply raises Special Defense")
  T.eq(stage(amnesia.player, "specialAttack"), 0,
    "Amnesia does not raise Special Attack")

  local psychicMove = data.moves.PSYCHIC_M
  withField(psychicMove, "effectChance", 255, function()
    local psychic = newBattle("PSYCHIC_M", { enemySpecies="MEW" })
    perform(psychic, "PSYCHIC_M")
    T.eq(stage(psychic.enemy, "specialDefense"), -1,
      "Psychic lowers Special Defense")
    T.eq(stage(psychic.enemy, "specialAttack"), 0,
      "Psychic does not lower Special Attack")
  end)
end)

case("Psych Up and AncientPower cover both split Special stages", function()
  local psychUp = newBattle("PSYCH_UP")
  psychUp.enemy.stages = {
    attack=3, defense=-2, speed=1, specialAttack=4,
    specialDefense=-3, accuracy=2, evasion=-1,
  }
  perform(psychUp, "PSYCH_UP")
  for stat, expected in pairs({
    attack=3, defense=-2, speed=1, specialAttack=4,
    specialDefense=-3, accuracy=2, evasion=-1,
  }) do
    T.eq(stage(psychUp.player, stat), expected,
      "Psych Up copies " .. stat)
  end
  T.eq(psychUp.player.stages.special, nil,
    "Psych Up does not create a shared Special stage")

  local move = data.moves.ANCIENTPOWER
  withField(move, "effectChance", 255, function()
    local ancient = newBattle("ANCIENTPOWER")
    perform(ancient, "ANCIENTPOWER")
    for _, stat in ipairs({
      "attack", "defense", "speed", "specialAttack", "specialDefense",
    }) do
      T.eq(stage(ancient.player, stat), 1,
        "AncientPower raises " .. stat)
    end
  end)
end)

case("Crystal Haze resets stages without clearing status or screens", function()
  local battle = newBattle("HAZE")
  battle.player.stages = { attack=4, specialAttack=3, specialDefense=-2 }
  battle.enemy.stages = { defense=-4, specialAttack=-3, specialDefense=2 }
  battle.enemy.mon.status = "PSN"
  perform(battle, "REFLECT")
  perform(battle, "HAZE")
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    for _, stat in ipairs({
      "attack", "defense", "speed", "specialAttack", "specialDefense",
      "accuracy", "evasion",
    }) do
      T.eq(stage(battler, stat), 0, "Haze resets " .. stat)
    end
  end
  T.eq(battle.enemy.mon.status, "PSN", "Crystal Haze preserves major status")
  T.check(battle.player.reflect == true, "Crystal Haze preserves Reflect")
end)

case("Reflect and Light Screen last five turns and survive switching", function()
  local battle = newBattle("LIGHT_SCREEN")
  perform(battle, "LIGHT_SCREEN")
  T.eq(battle.player.lightScreenTurns, 5,
    "Light Screen starts a five-turn side counter")

  local previous = battle.player
  local incomingMon = makeMon("RATTATA", 20)
  battle.player = BattleState.makeBattler(data, incomingMon, true, battle.game.save)
  stabilize(battle.player)
  switched(battle, previous, battle.player, false)
  T.check(battle.player.lightScreen == true,
    "Light Screen remains on the player side after switching")
  T.eq(battle.player.lightScreenTurns, 5,
    "switching preserves the Light Screen counter")

  for turn = 1, 4 do endTurn(battle, turn) end
  T.check(battle.player.lightScreen == true,
    "Light Screen remains active through four decrements")
  endTurn(battle, 5)
  T.eq(battle.player.lightScreen, nil,
    "Light Screen expires on the fifth decrement")

  perform(battle, "REFLECT")
  T.eq(battle.player.reflectTurns, 5,
    "Reflect uses the same five-turn side counter")
end)

case("Transform copies split stats and all seven stages", function()
  local battle = newBattle("TRANSFORM", { enemySpecies="ALAKAZAM" })
  battle.enemy.stages = {
    attack=2, defense=-1, speed=3, specialAttack=4,
    specialDefense=-2, accuracy=1, evasion=-3,
  }
  perform(battle, "TRANSFORM")
  local playerState = assert(battle.player.crystal251Battle)
  local enemyState = assert(battle.enemy.crystal251Battle)
  T.eq(playerState.stats.specialAttack, enemyState.stats.specialAttack,
    "Transform copies current Special Attack")
  T.eq(playerState.stats.specialDefense, enemyState.stats.specialDefense,
    "Transform copies current Special Defense")
  for stat, expected in pairs(battle.enemy.stages) do
    T.eq(stage(battle.player, stat), expected,
      "Transform copies " .. stat .. " stage")
  end
  T.eq(battle.player.stages.special, nil,
    "Transform preserves independent split stages")
end)

case("Sandstorm deals one eighth and respects type immunity", function()
  local battle = newBattle("SANDSTORM", {
    playerSpecies="MEW", enemySpecies="GEODUDE",
  })
  battle.weather = "sandstorm"
  battle.weatherTurns = 2
  local playerHP, enemyHP = battle.player.mon.hp, battle.enemy.mon.hp
  endTurn(battle, 1)
  T.eq(playerHP - battle.player.mon.hp, 125,
    "Sandstorm removes one eighth from a vulnerable target")
  T.eq(battle.enemy.mon.hp, enemyHP,
    "Rock/Ground target is immune to Sandstorm")
end)

case("the final weather turn deals residual before clearing weather", function()
  local battle = newBattle("SANDSTORM")
  battle.weather = "sandstorm"
  battle.weatherTurns = 1
  local hp = battle.player.mon.hp
  endTurn(battle, 1)
  T.eq(hp - battle.player.mon.hp, 125,
    "final Sandstorm turn still deals damage")
  T.eq(battle.weather, nil, "weather clears after its final residual")
  T.eq(battle.weatherTurns, nil, "weather counter clears with weather")
end)

case("Protect and Endure do not block residual damage", function()
  local battle = newBattle("PROTECT")
  battle.player.protect = true
  battle.player.endure = true
  battle.player.cursed = true
  battle.weather = "sandstorm"
  battle.weatherTurns = 2
  local hp = battle.player.mon.hp
  endTurn(battle, 1)
  T.eq(hp - battle.player.mon.hp, 375,
    "Curse and Sandstorm bypass Protect and Endure")
end)

case("Safeguard expires after five end-of-turn decrements", function()
  local battle = newBattle("SAFEGUARD")
  perform(battle, "SAFEGUARD")
  for turn = 1, 4 do endTurn(battle, turn) end
  T.eq(battle.player.safeguardTurns, 1,
    "Safeguard remains through four decrements")
  endTurn(battle, 5)
  T.eq(battle.player.safeguardTurns, nil,
    "Safeguard expires after five turns")
end)

case("Perish Song count includes the turn it was used", function()
  local battle = newBattle("PERISH_SONG")
  perform(battle, "PERISH_SONG")
  endTurn(battle, 1)
  T.eq(battle.player.perishTurns, 2,
    "Perish count drops to two at the end of the use turn")
  endTurn(battle, 2)
  T.eq(battle.player.perishTurns, 1,
    "Perish count drops to one next turn")
  endTurn(battle, 3)
  T.eq(battle.player.mon.hp, 0,
    "Perish Song faints the user on the third end phase")
end)

case("Future Sight and weather both resolve on the same due end phase", function()
  local battle = newBattle("FUTURE_SIGHT")
  perform(battle, "FUTURE_SIGHT")
  battle.weather = "sandstorm"
  battle.weatherTurns = 3
  local hp = battle.enemy.mon.hp
  endTurn(battle, 1)
  endTurn(battle, 2)
  local beforeDue = battle.enemy.mon.hp
  endTurn(battle, 3)
  T.check(battle.enemy.mon.hp < beforeDue - 124,
    "due Future Sight and Sandstorm both apply")
  T.check(battle.enemy.mon.hp < hp,
    "combined residual ordering changes target HP")
end)

-- -------------------------------------------------------------------------
-- Baton Pass integration
-- -------------------------------------------------------------------------

case("Baton Pass honors the player's selected healthy replacement", function()
  local lead = makeMon("MEW", 50, { {id="BATON_PASS",pp=40} })
  local first = makeMon("RATTATA", 20)
  local chosen = makeMon("BULBASAUR", 20)
  local battle = newBattle("BATON_PASS", { party={lead,first,chosen} })
  battle.batonPassChoice = function() return 3 end
  perform(battle, "BATON_PASS", lead.moves[1])
  T.check(battle.player.mon == chosen,
    "Baton Pass uses the player's selected replacement, not the first healthy slot")
end)

case("wild enemy Baton Pass fails because wild Pokémon have no party", function()
  local battle = newBattle("TACKLE")
  battle.enemy.curMoves = { {id="BATON_PASS",pp=40} }
  local previous = battle.enemy
  perform(battle, "BATON_PASS", battle.enemy.curMoves[1], battle.enemy, battle.player)
  T.check(battle.enemy == previous,
    "wild Baton Pass leaves the wild battler active")
  T.check(hasText(battle, "failed"), "wild Baton Pass reports failure")
end)

case("enemy Baton Pass selects a healthy trainer-party replacement", function()
  local player = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local lead = makeMon("RATTATA", 30, { {id="BATON_PASS",pp=40} })
  local first = makeMon("BULBASAUR", 30)
  local chosen = makeMon("CHARMANDER", 30)
  local battle = newBattle("TACKLE", {
    kind="trainer", party={player}, enemyParty={lead,first,chosen}, enemyIndex=1,
  })
  battle.batonPassChoice = function(user)
    return user.isPlayer and 1 or 3
  end
  perform(battle, "BATON_PASS", lead.moves[1], battle.enemy, battle.player)
  T.check(battle.enemy.mon == chosen,
    "enemy Baton Pass can choose a non-first healthy backup")
end)

case("Baton Pass fails without another healthy party member", function()
  local lead = makeMon("MEW", 50, { {id="BATON_PASS",pp=40} })
  local fainted = makeMon("RATTATA", 20)
  fainted.hp = 0
  local battle = newBattle("BATON_PASS", { party={lead,fainted} })
  local previous = battle.player
  perform(battle, "BATON_PASS", lead.moves[1])
  T.check(battle.player == previous,
    "failed Baton Pass leaves the active battler unchanged")
  T.check(hasText(battle, "failed"), "failed Baton Pass reports failure")
end)

case("Baton Pass transfers passable state", function()
  local lead = makeMon("MEW", 50, { {id="BATON_PASS",pp=40} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("BATON_PASS", { party={lead,bench} })
  battle.player.stages = { attack=3, defense=-2, speed=1 }
  battle.player.substituteHP = 77
  battle.player.confusedTurns = 3
  battle.player.focusEnergy = true
  battle.player.leechSeeded = true
  battle.player.cursed = true
  battle.player.perishTurns = 2
  battle.player.cantEscape = true
  perform(battle, "BATON_PASS", lead.moves[1])
  T.eq(stage(battle.player, "attack"), 3, "Baton Pass transfers positive stages")
  T.eq(stage(battle.player, "defense"), -2, "Baton Pass transfers negative stages")
  T.eq(battle.player.substituteHP, 77, "Baton Pass transfers Substitute")
  T.eq(battle.player.confusedTurns, 3, "Baton Pass transfers confusion")
  T.check(battle.player.focusEnergy == true, "Baton Pass transfers Focus Energy")
  T.check(battle.player.leechSeeded == true, "Baton Pass transfers Leech Seed")
  T.check(battle.player.cursed == true, "Baton Pass transfers Ghost Curse")
  T.eq(battle.player.perishTurns, 2, "Baton Pass transfers Perish Song")
  T.check(battle.player.cantEscape == true,
    "Baton Pass transfers Mean Look or Spider Web restriction")
end)

case("Baton Pass preserves and later releases an enforced Mean Look", function()
  local lead = makeMon("MEW", 50, {
    {id="MEAN_LOOK",pp=5}, {id="BATON_PASS",pp=40},
  })
  local middle = makeMon("RATTATA", 20, { {id="TACKLE",pp=35} })
  local last = makeMon("BULBASAUR", 20)
  local battle = newBattle("MEAN_LOOK", { party={lead,middle,last} })
  perform(battle, "MEAN_LOOK", lead.moves[1])
  perform(battle, "BATON_PASS", lead.moves[2])
  T.check(battle.enemy.cantEscape == true,
    "Baton Pass replacement keeps enforcing Mean Look")
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(last)
  drainQueue(battle)
  T.eq(battle.enemy.cantEscape, nil,
    "target is released when the Baton Pass replacement later leaves")
end)

case("Baton Pass resets non-passable state", function()
  local lead = makeMon("MEW", 50, { {id="BATON_PASS",pp=40} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("BATON_PASS", { party={lead,bench} })
  battle.player.disabledSlot = 1
  battle.player.disableTurns = 4
  battle.player.infatuatedWith = battle.enemy
  battle.player.transformed = true
  battle.player.encoreMove = "TACKLE"
  battle.player.encoreTurns = 4
  battle.player.lastMove = "TACKLE"
  battle.player.trappingTurns = 3
  battle.player.protect = true
  battle.player.endure = true
  battle.player.destinyBond = true
  battle.player.rolloutCount = 3
  battle.player.furyCutterCount = 4
  battle.player.defenseCurl = true
  battle.player.nightmare = true
  perform(battle, "BATON_PASS", lead.moves[1])
  for _, field in ipairs({
    "disabledSlot", "disableTurns", "infatuatedWith", "transformed",
    "encoreMove", "encoreTurns", "lastMove", "trappingTurns", "nightmare",
  }) do
    T.eq(battle.player[field], nil,
      "Baton Pass clears non-passable state " .. field)
  end
  for _, field in ipairs({ "protect", "endure", "defenseCurl" }) do
    T.check(battle.player[field] ~= nil,
      "Baton Pass preserves Crystal state " .. field)
  end
  for _, field in ipairs({ "destinyBond", "rolloutCount", "furyCutterCount" }) do
    T.eq(battle.player[field], nil,
      "Baton Pass move selection clears Crystal state " .. field)
  end
end)

-- -------------------------------------------------------------------------
-- Pursuit integration
-- -------------------------------------------------------------------------

case("enemy Pursuit intercepts the outgoing player before a switch", function()
  local lead = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.enemy.curMoves = { {id="PURSUIT",pp=20} }
  battle.enemyAction = function() return battle.enemy.curMoves[1] end
  local outgoing = battle.player
  local hp = outgoing.mon.hp
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(outgoing.mon.hp < hp,
    "enemy Pursuit damages the outgoing battler")
  T.check(battle.player.mon == bench,
    "surviving outgoing battler completes its switch")
end)

case("Pursuit KO cancels the selected switch", function()
  local lead = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.mon.hp = 1
  battle.enemy.curMoves = { {id="PURSUIT",pp=20} }
  battle.enemyAction = function() return battle.enemy.curMoves[1] end
  local outgoing = battle.player
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(outgoing.mon.hp, 0, "Pursuit can KO the outgoing battler")
  T.check(battle.player == outgoing,
    "Pursuit KO prevents the chosen replacement from entering immediately")
end)

case("player Pursuit intercepts an enemy trainer switch", function()
  local player = makeMon("MEW", 50, { {id="PURSUIT",pp=20} })
  local enemyLead = makeMon("RATTATA", 30, { {id="TACKLE",pp=35} })
  local enemyBench = makeMon("BULBASAUR", 30)

  local normal = newBattle("PURSUIT", {
    kind="trainer", party={player}, enemyParty={enemyLead,enemyBench}, enemyIndex=1,
  })
  local normalHP = normal.enemy.mon.hp
  perform(normal, "PURSUIT", player.moves[1])
  local ordinaryDamage = normalHP - normal.enemy.mon.hp

  player.moves[1].pp = 20
  enemyLead.hp = enemyLead.stats.hp
  local battle = newBattle("PURSUIT", {
    kind="trainer", party={player}, enemyParty={enemyLead,enemyBench}, enemyIndex=1,
  })
  battle.enemyAction = function() return { special="aiSwitch", index=2 } end
  local outgoing = battle.enemy
  local hp = outgoing.mon.hp
  battle:resolveTurn(player.moves[1])
  drainQueue(battle)
  T.eq(hp - outgoing.mon.hp, ordinaryDamage * 2,
    "player Pursuit doubles against an enemy switch")
  T.check(battle.enemy.mon == enemyBench,
    "enemy replacement enters after surviving Pursuit")
end)

case("ordinary Pursuit keeps ordinary power", function()
  T.eq(observedPower("PURSUIT"), data.moves.PURSUIT.power,
    "Pursuit is not doubled without a switch")
end)

-- -------------------------------------------------------------------------
-- Future Sight integration
-- -------------------------------------------------------------------------

case("Future Sight recast fails without replacing the original attack", function()
  local battle = newBattle("FUTURE_SIGHT")
  perform(battle, "FUTURE_SIGHT")
  local pending = battle.crystalFutureSight and battle.crystalFutureSight.enemy
  T.check(pending ~= nil, "first Future Sight is scheduled")
  local damage, turns = pending and pending.damage, pending and pending.turns
  perform(battle, "FUTURE_SIGHT")
  local after = battle.crystalFutureSight and battle.crystalFutureSight.enemy
  T.check(after == pending, "recast preserves the original pending record")
  T.eq(after and after.damage, damage, "recast preserves stored damage")
  T.eq(after and after.turns, turns, "recast preserves the original countdown")
end)

case("Future Sight targets the side slot across switching", function()
  local battle = newBattle("FUTURE_SIGHT")
  perform(battle, "FUTURE_SIGHT")
  local old = battle.enemy
  local incomingMon = makeMon("BULBASAUR", 20)
  battle.enemy = BattleState.makeBattler(data, incomingMon, false)
  stabilize(battle.enemy)
  switched(battle, old, battle.enemy, false)
  local hp = battle.enemy.mon.hp
  endTurn(battle, 1)
  endTurn(battle, 2)
  endTurn(battle, 3)
  T.check(battle.enemy.mon.hp < hp,
    "Future Sight strikes the current occupant of the targeted side")
  T.eq(old.mon.hp, 1000, "switched-out original target is not struck")
end)

case("Future Sight survives source switching and fainting", function()
  local battle = newBattle("FUTURE_SIGHT")
  perform(battle, "FUTURE_SIGHT")
  battle.player.mon.hp = 0
  battle:onFaint(battle.player)
  local hp = battle.enemy.mon.hp
  endTurn(battle, 1)
  endTurn(battle, 2)
  endTurn(battle, 3)
  T.check(battle.enemy.mon.hp < hp,
    "Future Sight remains after its source faints")
end)

case("Future Sight interacts correctly with Substitute Protect and Endure", function()
  local substitute = newBattle("FUTURE_SIGHT")
  perform(substitute, "FUTURE_SIGHT")
  substitute.enemy.substituteHP = 500
  local monHP = substitute.enemy.mon.hp
  endTurn(substitute, 1); endTurn(substitute, 2); endTurn(substitute, 3)
  T.eq(substitute.enemy.mon.hp, monHP,
    "Future Sight damages Substitute before the target")
  T.check((substitute.enemy.substituteHP or 0) < 500,
    "Future Sight reduces Substitute HP")

  local selection = newBattle("FUTURE_SIGHT")
  selection.enemy.protect = true
  perform(selection, "FUTURE_SIGHT")
  T.check(selection.crystalFutureSight and selection.crystalFutureSight.enemy,
    "Protect on the selection turn does not prevent Future Sight from being scheduled")

  local protected = newBattle("FUTURE_SIGHT")
  perform(protected, "FUTURE_SIGHT")
  endTurn(protected, 1); endTurn(protected, 2)
  protected.enemy.protect = true
  local protectedHP = protected.enemy.mon.hp
  endTurn(protected, 3)
  T.eq(protected.enemy.mon.hp, protectedHP,
    "Protect on the due turn blocks Future Sight")

  local endured = newBattle("FUTURE_SIGHT")
  perform(endured, "FUTURE_SIGHT")
  endTurn(endured, 1); endTurn(endured, 2)
  endured.enemy.endure = true
  endured.enemy.mon.hp = 1
  endTurn(endured, 3)
  T.eq(endured.enemy.mon.hp, 1,
    "Endure on the due turn leaves the target at one HP")
end)

case("Future Sight reveals an accuracy failure on the delayed turn", function()
  local battle = newBattle("FUTURE_SIGHT")
  battle.accuracyRoll = function() return false end
  perform(battle, "FUTURE_SIGHT")
  T.check(battle.crystalFutureSight and battle.crystalFutureSight.enemy,
    "missed Future Sight still creates its delayed record")
  T.check(not hasText(battle, "missed"),
    "Future Sight miss is not announced on the selection turn")
  local hp = battle.enemy.mon.hp
  endTurn(battle, 1); endTurn(battle, 2); endTurn(battle, 3)
  T.eq(battle.enemy.mon.hp, hp,
    "missed Future Sight deals no delayed damage")
  T.check(hasText(battle, "missed") or hasText(battle, "failed"),
    "Future Sight miss is revealed when the attack comes due")
end)

case("Future Sight stores damage at selection time", function()
  local battle = newBattle("FUTURE_SIGHT")
  perform(battle, "FUTURE_SIGHT")
  local pending = battle.crystalFutureSight.enemy
  local stored = pending.damage
  battle.player.curStats.special = 1
  battle.enemy.curStats.special = 999
  battle.rng = seq(nil, 255)
  battle.accuracyRoll = function() return true end
  local hp = battle.enemy.mon.hp
  endTurn(battle, 1); endTurn(battle, 2); endTurn(battle, 3)
  T.eq(hp - battle.enemy.mon.hp, stored,
    "later stat changes do not recalculate Future Sight damage")
end)

-- -------------------------------------------------------------------------
-- Thief integration
-- -------------------------------------------------------------------------

case("Thief obeys Crystal's 255-in-256 effect chance", function()
  local move = data.moves.THIEF
  local battle = newBattle("THIEF")
  battle.player.mon.heldItem = nil
  battle.enemy.mon.heldItem = "BERRY"
  battle.accuracyRoll = function() return true end
  battle.rng = function(a, b)
    if a == 0 and b == 255 then return 255 end
    return b or a
  end
  perform(battle, "THIEF")
  T.eq(battle.player.mon.heldItem, nil,
    "Thief's one-in-256 effect failure does not steal")
  T.eq(battle.enemy.mon.heldItem, "BERRY",
    "target retains item on Thief's effect failure")
  T.eq(move.effectChance, 255, "Crystal imports Thief's 255 effect chance")
end)

case("Thief validates user item target item and Mail", function()
  local held = newBattle("THIEF")
  held.player.mon.heldItem = "POTION"
  held.enemy.mon.heldItem = "BERRY"
  perform(held, "THIEF")
  T.eq(held.player.mon.heldItem, "POTION",
    "Thief cannot steal while user holds an item")
  T.eq(held.enemy.mon.heldItem, "BERRY",
    "target retains item when user already holds one")

  local empty = newBattle("THIEF")
  empty.player.mon.heldItem = nil
  empty.enemy.mon.heldItem = nil
  perform(empty, "THIEF")
  T.eq(empty.player.mon.heldItem, nil,
    "Thief cannot manufacture an item")

  local oldMail = data.items.CRYSTAL_EDGE_MAIL
  data.items.CRYSTAL_EDGE_MAIL = { id="CRYSTAL_EDGE_MAIL", name="EDGE MAIL", isMail=true }
  local ok, err = pcall(function()
    local mail = newBattle("THIEF")
    mail.player.mon.heldItem = nil
    mail.enemy.mon.heldItem = "CRYSTAL_EDGE_MAIL"
    perform(mail, "THIEF")
    T.eq(mail.player.mon.heldItem, nil, "Thief cannot steal Mail")
    T.eq(mail.enemy.mon.heldItem, "CRYSTAL_EDGE_MAIL", "Mail remains with target")
  end)
  data.items.CRYSTAL_EDGE_MAIL = oldMail
  if not ok then error(err, 0) end
end)

-- -------------------------------------------------------------------------
-- Triple Kick integration
-- -------------------------------------------------------------------------

local function tripleKickWithAccuracy(results)
  local battle = newBattle("TRIPLE_KICK")
  local calls = 0
  battle.accuracyRoll = function()
    calls = calls + 1
    return results[calls] ~= false
  end
  local hp = battle.enemy.mon.hp
  perform(battle, "TRIPLE_KICK")
  return battle, hp - battle.enemy.mon.hp, calls
end

case("Triple Kick stops at the first second or third failed accuracy check", function()
  local first, firstDamage = tripleKickWithAccuracy({ false })
  T.eq(firstDamage, 0, "first-kick miss deals no damage")

  local second, secondDamage = tripleKickWithAccuracy({ true, false })
  T.check(secondDamage > 0, "second-kick miss preserves first-kick damage")
  T.check(not hasText(second, "3 times"), "second-kick miss does not report three hits")

  local third, thirdDamage = tripleKickWithAccuracy({ true, true, false })
  T.check(thirdDamage > secondDamage,
    "third-kick miss preserves the first two kicks")
  T.check(not hasText(third, "3 times"), "third-kick miss reports only two hits")
end)

case("Triple Kick recalculates damage and critical chance for every kick", function()
  local battle = newBattle("TRIPLE_KICK")
  local original = battle.computeDamage
  local calls = 0
  local rows = {
    { damage=10, crit=false },
    { damage=20, crit=true },
    { damage=30, crit=false },
  }
  battle.computeDamage = function()
    calls = calls + 1
    local row = rows[calls]
    return row.damage, { crit=row.crit, typeMult=10 }
  end
  battle.accuracyRoll = function() return true end
  local hp = battle.enemy.mon.hp
  perform(battle, "TRIPLE_KICK")
  battle.computeDamage = original
  T.eq(calls, 3, "Triple Kick performs three independent damage calculations")
  T.eq(hp - battle.enemy.mon.hp, 10 + 40 + 90,
    "each independently calculated kick is multiplied by kick number")
  T.eq(textCount(battle, "Critical hit"), 1,
    "only the independently critical kick reports a critical hit")
end)

case("Triple Kick continues after breaking Substitute", function()
  local battle = newBattle("TRIPLE_KICK")
  battle.enemy.substituteHP = 1
  local hp = battle.enemy.mon.hp
  perform(battle, "TRIPLE_KICK")
  T.eq(battle.enemy.substituteHP, nil, "first kick can break Substitute")
  T.check(battle.enemy.mon.hp < hp,
    "later kicks continue into the target after Substitute breaks")
  T.check(hasText(battle, "3 times"),
    "all successful kicks are counted across a broken Substitute")
end)

case("Triple Kick stops immediately when a kick faints the target", function()
  local battle = newBattle("TRIPLE_KICK")
  battle.enemy.mon.hp = 1
  local calls = 0
  local original = battle.computeDamage
  battle.computeDamage = function()
    calls = calls + 1
    return 50, { crit=false, typeMult=10 }
  end
  perform(battle, "TRIPLE_KICK")
  battle.computeDamage = original
  T.eq(calls, 1, "Triple Kick performs no later damage checks after a KO")
  T.eq(battle.enemy.mon.hp, 0, "first kick can end the sequence by KO")
end)

-- -------------------------------------------------------------------------
-- Beat Up integration
-- -------------------------------------------------------------------------

local function beatUpDamage(mon, targetSpecies, roll)
  local attacker = data.pokemon[mon.species]
  local defender = data.pokemon[targetSpecies]
  local attack = attacker.baseStats.attack
  local defense = defender.baseStats.defense
  local power = data.moves.BEAT_UP.power
  local damage = math.floor(2 * mon.level / 5) + 2
  damage = math.floor(math.floor(damage * power * attack / defense) / 50) + 2
  damage = math.floor(damage * (roll or 255) / 255)
  return math.max(1, damage)
end

case("Beat Up eligibility excludes fainted and statused party members", function()
  local a = makeMon("MEW", 50, { {id="BEAT_UP",pp=10} })
  local b = makeMon("RATTATA", 20)
  local c = makeMon("BULBASAUR", 20)
  local d = makeMon("CHARMANDER", 20)
  c.status = "PSN"
  d.hp = 0
  local battle = newBattle("BEAT_UP", { party={a,b,c,d} })
  perform(battle, "BEAT_UP", a.moves[1])
  T.check(hasText(battle, "2 times"),
    "Beat Up counts only healthy status-free contributors")
end)

case("a statused active user does not contribute to its own Beat Up", function()
  local a = makeMon("MEW", 50, { {id="BEAT_UP",pp=10} })
  local b = makeMon("RATTATA", 20)
  a.status = "PSN"
  local battle = newBattle("BEAT_UP", { party={a,b} })
  perform(battle, "BEAT_UP", a.moves[1])
  T.check(not hasText(battle, "2 times"),
    "statused active user is excluded from Beat Up contributors")
end)

case("Beat Up exact damage vector uses each contributor's level and base Attack", function()
  local a = makeMon("MEW", 50, { {id="BEAT_UP",pp=10} })
  local b = makeMon("RATTATA", 20)
  local c = makeMon("BULBASAUR", 35)
  local battle = newBattle("BEAT_UP", {
    party={a,b,c}, enemySpecies="SNORLAX", rng=seq(nil,255),
  })
  battle.accuracyRoll = function() return true end
  local expected = beatUpDamage(a, "SNORLAX", 255)
    + beatUpDamage(b, "SNORLAX", 255)
    + beatUpDamage(c, "SNORLAX", 255)
  local hp = battle.enemy.mon.hp
  perform(battle, "BEAT_UP", a.moves[1])
  T.eq(hp - battle.enemy.mon.hp, expected,
    "Beat Up total equals the three exact contributor damage values")
end)

case("enemy trainer Beat Up enumerates the enemy party", function()
  local player = makeMon("MEW", 50, { {id="TACKLE",pp=35} })
  local a = makeMon("HOUNDOOM", 50, { {id="BEAT_UP",pp=10} })
  local b = makeMon("RATTATA", 20)
  local c = makeMon("BULBASAUR", 20)
  c.status = "PAR"
  local battle = newBattle("TACKLE", {
    kind="trainer", party={player}, enemyParty={a,b,c}, enemyIndex=1,
  })
  perform(battle, "BEAT_UP", a.moves[1], battle.enemy, battle.player)
  T.check(hasText(battle, "2 times"),
    "enemy Beat Up counts eligible trainer-party members")
end)

case("Beat Up continues after breaking Substitute", function()
  local a = makeMon("MEW", 50, { {id="BEAT_UP",pp=10} })
  local b = makeMon("RATTATA", 20)
  local battle = newBattle("BEAT_UP", { party={a,b} })
  battle.enemy.substituteHP = 1
  local hp = battle.enemy.mon.hp
  perform(battle, "BEAT_UP", a.moves[1])
  T.eq(battle.enemy.substituteHP, nil, "first Beat Up hit breaks Substitute")
  T.check(battle.enemy.mon.hp < hp,
    "later Beat Up contributor hits continue after Substitute breaks")
  T.check(hasText(battle, "2 times"),
    "Beat Up reports all hits across a broken Substitute")
end)

case("Beat Up is typeless and ignores ordinary type immunity and STAB", function()
  local function damageAgainst(species)
    local a = makeMon("HOUNDOOM", 50, { {id="BEAT_UP",pp=10} })
    local battle = newBattle("BEAT_UP", {
      party={a}, enemySpecies=species, rng=seq(nil,255),
    })
    battle.accuracyRoll = function() return true end
    local hp = battle.enemy.mon.hp
    perform(battle, "BEAT_UP", a.moves[1])
    return hp - battle.enemy.mon.hp
  end
  T.check(damageAgainst("GASTLY") > 0,
    "Beat Up damages Ghost despite its displayed Dark type")
  T.check(damageAgainst("SNORLAX") > 0,
    "Beat Up damages Normal without type-effectiveness processing")
end)

case("Beat Up fails when no party member is eligible", function()
  local a = makeMon("MEW", 50, { {id="BEAT_UP",pp=10} })
  local b = makeMon("RATTATA", 20)
  a.status = "PSN"
  b.hp = 0
  local battle = newBattle("BEAT_UP", { party={a,b} })
  local hp = battle.enemy.mon.hp
  perform(battle, "BEAT_UP", a.moves[1])
  T.eq(battle.enemy.mon.hp, hp, "Beat Up with no contributors deals no damage")
  T.check(hasText(battle, "failed"), "Beat Up with no contributors reports failure")
end)

run.release()
T.finish("Crystal move edge parity")
