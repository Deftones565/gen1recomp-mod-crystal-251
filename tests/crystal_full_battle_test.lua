package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local path = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP Crystal full battle integration (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local run, cache = require("mods.CRYSTAL_251.tests._real_rom_mod").load(T, raw)
T.eq(#run.errors, 0, "Crystal 251 loads before full-battle probes")

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local CrystalStatus = require("mods.CRYSTAL_251.battle.crystal_status")
local Switching = require("mods.CRYSTAL_251.battle.crystal_switching")

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
  mon.heldItem = nil
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
  hp = hp or 1000
  battler.mon.stats.hp = hp
  battler.mon.hp = hp
  battler.mon.stats.attack = 100
  battler.mon.stats.defense = 100
  battler.mon.stats.speed = 100
  battler.mon.stats.special = 100
  battler.mon.stats.specialAttack = 100
  battler.mon.stats.specialDefense = 100
  battler.curStats = battler.mon.stats
  battler.shownHP = hp
  battler.mon.heldItem = nil
end

local function newBattle(moveId, opts)
  opts = opts or {}
  local level = opts.level or 50
  local lead = opts.party and opts.party[1]
    or makeMon(opts.playerSpecies or "MEW", level,
      opts.moves or { { id = moveId or "TACKLE", pp = 40 } })
  if not lead.moves or #lead.moves == 0 then
    lead.moves = { { id = moveId or "TACKLE", pp = 40 } }
  end
  local party = opts.party or { lead }
  local game = makeGame(party)
  local battle = BattleState.newWild(game, opts.enemySpecies or "SNORLAX", level)
  battle.turnCount = opts.turnCount or 1
  battle.phase = "menu"
  battle.rng = opts.rng or seq(nil, 0)
  battle.kind = opts.kind or "wild"
  battle.queue = {}
  battle.nextInsert = 0

  if opts.enemyParty then
    battle.enemyParty = opts.enemyParty
    battle.enemyIndex = opts.enemyIndex or 1
    battle.enemy = BattleState.makeBattler(data,
      battle.enemyParty[battle.enemyIndex], false)
  end
  if battle.kind == "trainer" then
    battle.trainer = opts.trainer or {
      id = "CRYSTAL_FULL_TEST", name = "TEST", baseMoney = 0,
    }
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
  local texts, screens = {}, {}
  while #battle.queue > 0 do
    guard = guard + 1
    if guard > 5000 then error("battle queue did not drain") end
    local row = table.remove(battle.queue, 1)
    battle.nextInsert = 0
    if row.text then texts[#texts + 1] = row.text end
    if row.fn then row.fn() end
    if row.ui then screens[#screens + 1] = row.ui() end
  end
  battle.nextInsert = 0
  if battle.afterQueue and #screens == 0 then battle.phase = battle.afterQueue end
  return texts, screens
end

local function hasText(rows, fragment)
  for _, text in ipairs(rows or {}) do
    if text:find(fragment, 1, true) then return true end
  end
  return false
end

local function clearQueue(battle)
  battle.queue = {}
  battle.nextInsert = 0
end

local function case(name, fn)
  local ok, err = pcall(fn)
  T.check(ok, name .. (ok and "" or " (" .. tostring(err) .. ")"))
end

local function activeIs(battle, mon)
  return battle.player and battle.player.mon == mon
end

-- -------------------------------------------------------------------------
-- Reported move-routing regressions
-- -------------------------------------------------------------------------

case("Thunder Shock uses Crystal's secondary-effect chance", function()
  local move = data.moves.THUNDERSHOCK
  local record = data.move_effects[move.effect]
  T.eq(move.effect, "CRYSTAL_EFFECT_06",
    "Thunder Shock routes through Crystal's paralysis-hit record")
  T.eq(move.effectChance, 25,
    "Thunder Shock keeps Crystal's 25/256 paralysis chance")
  T.eq(record.useEffectChance, nil,
    "Thunder Shock's chance gate is owned by the mod")

  local function useWithSecondaryRoll(roll)
    local battle = newBattle("THUNDERSHOCK")
    battle.computeDamage = function()
      return 10, { crit=false, typeMult=10 }
    end
    -- Accuracy consumes the first byte; the damaging pipeline's secondary
    -- chance consumes the second.
    battle.rng = seq({ 0, roll }, 255)
    perform(battle, "THUNDERSHOCK")
    return battle.enemy.mon.status
  end

  T.eq(useWithSecondaryRoll(24), "PAR",
    "Thunder Shock paralyzes below its 25/256 boundary")
  T.eq(useWithSecondaryRoll(25), nil,
    "Thunder Shock does not paralyze at its 25/256 boundary")
  T.eq(useWithSecondaryRoll(255), nil,
    "Thunder Shock can deal damage without paralysis")
end)

case("enemy Poison Sting uses Crystal's secondary-effect chance", function()
  local move = data.moves.POISON_STING
  local record = data.move_effects[move.effect]
  T.eq(move.effect, "CRYSTAL_EFFECT_02",
    "Poison Sting routes through Crystal's poison-hit record")
  T.eq(move.effectChance, 76,
    "Poison Sting keeps Crystal's 76/256 poison chance")
  T.eq(record.useEffectChance, nil,
    "Poison Sting's chance gate is owned by the mod")

  local function enemyUseWithSecondaryRoll(roll)
    local battle = newBattle("TACKLE")
    battle.computeDamage = function()
      return 10, { crit=false, typeMult=10 }
    end
    battle.rng = seq({ 0, roll }, 255)
    perform(battle, "POISON_STING", { id="POISON_STING", pp=35 },
      battle.enemy, battle.player)
    return battle.player.mon.status
  end

  T.eq(enemyUseWithSecondaryRoll(75), "PSN",
    "enemy Poison Sting poisons below its 76/256 boundary")
  T.eq(enemyUseWithSecondaryRoll(76), nil,
    "enemy Poison Sting does not poison at its 76/256 boundary")
  T.eq(enemyUseWithSecondaryRoll(255), nil,
    "enemy Poison Sting can deal damage without poison")
end)

case("Double Kick and Bonemerang are fixed two-hit moves", function()
  for _, moveId in ipairs({ "DOUBLE_KICK", "BONEMERANG" }) do
    local battle = newBattle(moveId)
    local calculations = 0
    battle.computeDamage = function()
      calculations = calculations + 1
      return 10, { crit=false, typeMult=10 }
    end
    -- This produces five hits for the ordinary $1d family.  The fixed $2c
    -- family must not consume it as a hit-count roll.
    battle.rng = seq({ 3, 3, 3, 3 }, 3)
    local before = battle.enemy.mon.hp
    perform(battle, moveId)
    T.eq(calculations, 2, moveId .. " calculates exactly two strikes")
    T.eq(before - battle.enemy.mon.hp, 20,
      moveId .. " applies exactly two strikes")
  end
end)

local function assertBlockedSwitch(battle, bench, label, stale)
  local previous = battle.player
  local turn = battle.turnCount
  local hp = battle.enemy.mon.hp
  local enemyCalls = 0
  battle.enemyAction = function()
    enemyCalls = enemyCalls + 1
    return { id = "TACKLE", pp = 35 }
  end
  battle.queue = {}
  battle.nextInsert = stale or 0
  local ok, result = pcall(battle.resolveSwitch, battle, bench)
  T.check(ok, label .. " does not corrupt the queue")
  T.eq(result, false, label .. " rejects the switch")
  T.check(battle.player == previous, label .. " keeps the active battler")
  T.eq(battle.turnCount, turn, label .. " does not consume a turn")
  T.eq(enemyCalls, 0, label .. " does not choose an enemy action")
  T.eq(battle.enemy.mon.hp, hp, label .. " does not execute an enemy action")
  T.eq(battle.phase, "messages", label .. " enters the message phase")
  T.eq(battle.afterQueue, "menu", label .. " returns to the battle menu")
  T.eq(#battle.queue, 1, label .. " queues exactly one message")
  T.check(battle.queue[1] and battle.queue[1].text ~= nil,
    label .. " queues a text row rather than an action")
  T.check(battle.queue[1].text:find("recalled", 1, true) ~= nil,
    label .. " reports the Crystal recall restriction")
  T.eq(battle.nextInsert, 0, label .. " clears stale insertion state")
  local texts = drainQueue(battle)
  T.check(hasText(texts, "recalled"), label .. " message drains normally")
  T.eq(battle.phase, "menu", label .. " finishes back at the menu")
end

-- -------------------------------------------------------------------------
-- Voluntary switch rejection from the live party-menu callback
-- -------------------------------------------------------------------------

case("the live PartyMenu callback safely rejects a wrapped switch", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.cantEscape = true
  battle.player.cantEscapeFrom = battle.enemy
  battle:openParty()
  local _, screens = drainQueue(battle)
  T.eq(#screens, 1, "party command opens one PartyMenu")
  local screen = screens[1]
  T.check(screen and screen.onSwitch ~= nil, "PartyMenu retains the battle switch callback")
  battle.nextInsert = 4096
  local ok = pcall(screen.onSwitch, bench)
  T.check(ok, "wrapped PartyMenu selection does not corrupt the queue")
  T.check(activeIs(battle, lead), "wrapped PartyMenu selection keeps the active mon")
  T.eq(#battle.queue, 1, "wrapped PartyMenu selection queues one rejection")
  T.check(battle.queue[1].text:find("recalled", 1, true) ~= nil,
    "wrapped PartyMenu selection uses the Crystal recall message")
  local texts = drainQueue(battle)
  T.check(hasText(texts, "recalled"), "PartyMenu rejection drains normally")
  T.eq(battle.phase, "menu", "PartyMenu rejection returns to the battle menu")
end)

case("Mean Look switch rejection is safe for every stale queue index", function()
  for _, stale in ipairs({ 0, 1, 4, 31, 255, 4096 }) do
    local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
    local bench = makeMon("RATTATA", 20)
    local battle = newBattle("TACKLE", { party={lead,bench} })
    battle.player.cantEscape = true
    battle.player.cantEscapeFrom = battle.enemy
    assertBlockedSwitch(battle, bench, "Mean Look stale index " .. stale, stale)
  end
end)

case("partial trapping switch rejection is safe without the mirror flag", function()
  for _, turns in ipairs({ 1, 2, 3, 4, 5 }) do
    local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
    local bench = makeMon("RATTATA", 20)
    local battle = newBattle("TACKLE", { party={lead,bench} })
    battle.player.crystalTrapTurns = turns
    battle.player.crystalTrapSource = battle.enemy
    battle.player.crystalTrapMove = "WRAP"
    battle.player.cantEscape = nil
    assertBlockedSwitch(battle, bench, "partial trap count " .. turns, 1000 + turns)
  end
end)

case("repeated trapped party selections never grow or reorder the queue", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.cantEscape = true
  for attempt = 1, 32 do
    battle.nextInsert = attempt * 17
    local ok = pcall(battle.resolveSwitch, battle, bench)
    T.check(ok, "trapped selection attempt " .. attempt .. " is safe")
    T.eq(#battle.queue, 1, "trapped selection attempt " .. attempt .. " has one row")
    local texts = drainQueue(battle)
    T.check(hasText(texts, "recalled"),
      "trapped selection attempt " .. attempt .. " reports failure")
    T.check(activeIs(battle, lead),
      "trapped selection attempt " .. attempt .. " keeps the lead")
  end
end)

case("every Crystal trapping family blocks a voluntary switch", function()
  local families = {
    { "BIND", true }, { "WRAP", true }, { "FIRE_SPIN", true },
    { "CLAMP", true }, { "WHIRLPOOL", true },
    { "MEAN_LOOK", false }, { "SPIDER_WEB", false },
  }
  for _, row in ipairs(families) do
    local id, partial = row[1], row[2]
    local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
    local bench = makeMon("RATTATA", 20)
    local battle = newBattle("TACKLE", { party={lead,bench}, rng=seq(nil, 3) })
    battle.accuracyRoll = function() return true end
    perform(battle, id, { id=id, pp=20 }, battle.enemy, battle.player)
    drainQueue(battle)
    T.check(battle.player.cantEscape == true, id .. " sets the escape restriction")
    if partial then
      T.check((battle.player.crystalTrapTurns or 0) > 0,
        id .. " stores a partial-trap counter")
      T.eq(battle.player.crystalTrapSource, battle.enemy,
        id .. " stores the active source")
    else
      T.eq(battle.player.crystalTrapTurns, nil,
        id .. " does not create a partial-trap counter")
    end
    assertBlockedSwitch(battle, bench, id .. " voluntary switch", 777)
  end
end)

-- -------------------------------------------------------------------------
-- Release paths and switch methods that must bypass the restriction
-- -------------------------------------------------------------------------

case("Rapid Spin clears every switch-blocking partial-trap field", function()
  local lead = makeMon("MEW", 50, { { id="RAPID_SPIN", pp=40 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("RAPID_SPIN", { party={lead,bench} })
  battle.player.cantEscape = true
  battle.player.cantEscapeFrom = battle.enemy
  battle.player.crystalTrapTurns = 4
  battle.player.crystalTrapSource = battle.enemy
  battle.player.crystalTrapMove = "WRAP"
  battle.player.leechSeeded = true
  battle.playerSpikes = true
  perform(battle, "RAPID_SPIN", lead.moves[1])
  drainQueue(battle)
  T.eq(battle.player.cantEscape, nil, "Rapid Spin clears cantEscape")
  T.eq(battle.player.cantEscapeFrom, nil, "Rapid Spin clears cantEscapeFrom")
  T.eq(battle.player.crystalTrapTurns, nil, "Rapid Spin clears trap turns")
  T.eq(battle.player.crystalTrapSource, nil, "Rapid Spin clears trap source")
  T.eq(battle.player.crystalTrapMove, nil, "Rapid Spin clears trap move")
  T.eq(battle.player.leechSeeded, nil, "Rapid Spin clears Leech Seed")
  T.eq(battle.playerSpikes, nil, "Rapid Spin clears the user's Spikes")
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(activeIs(battle, bench), "Rapid Spin permits the next voluntary switch")
end)

case("the final partial-trap countdown releases the next menu switch", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.cantEscape = true
  battle.player.cantEscapeFrom = battle.enemy
  battle.player.crystalTrapTurns = 1
  battle.player.crystalTrapSource = battle.enemy
  battle.player.crystalTrapMove = "WRAP"
  local hp = battle.player.mon.hp
  local messages = CrystalStatus.wrapResidual(battle.player, battle)
  T.eq(battle.player.mon.hp, hp, "release countdown does not deal another Wrap tick")
  T.eq(battle.player.crystalTrapTurns, nil, "final Wrap residual clears turns")
  T.eq(battle.player.cantEscape, nil, "final Wrap residual restores switching")
  T.check(#messages > 0, "final Wrap residual reports release")
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(activeIs(battle, bench), "released target can switch immediately")
end)

case("switching the partial-trap source releases its target", function()
  local player = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local enemyLead = makeMon("SNORLAX", 50, { { id="WRAP", pp=20 } })
  local enemyBench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", {
    kind="trainer", party={player}, enemyParty={enemyLead,enemyBench}, enemyIndex=1,
  })
  perform(battle, "WRAP", enemyLead.moves[1], battle.enemy, battle.player)
  drainQueue(battle)
  T.check(battle.player.cantEscape == true, "Wrap source traps before leaving")
  local previous = battle.enemy
  Switching.replaceActive(battle, previous, enemyBench, 2, {})
  T.eq(battle.player.cantEscape, nil, "source switch clears escape restriction")
  T.eq(battle.player.crystalTrapTurns, nil, "source switch clears residual turns")
  T.eq(battle.player.crystalTrapSource, nil, "source switch clears source reference")
end)

case("forced switching and faint replacement bypass voluntary trapping", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench}, kind="trainer" })
  battle.player.cantEscape = true
  battle.player.cantEscapeFrom = battle.enemy
  battle.player.crystalTrapTurns = 3
  battle.player.crystalTrapSource = battle.enemy
  battle.crystalActedSides = { player=battle.turnCount }
  local result = Switching.forceSwitch({
    battle=battle, user=battle.enemy, target=battle.player,
    move={id="ROAR"}, rng=function() return 1 end,
  })
  T.check(activeIs(battle, bench), "Roar can force a trapped target out")
  T.check(result[1]:find("dragged out", 1, true) ~= nil,
    "forced switch reports the replacement")

  local faintLead = makeMon("MEW", 50)
  local faintBench = makeMon("BULBASAUR", 20)
  local faintBattle = newBattle("TACKLE", { party={faintLead,faintBench}, kind="trainer" })
  faintBattle.player.cantEscape = true
  faintBattle.player.crystalTrapTurns = 3
  faintBattle.player.mon.hp = 0
  faintBattle:openReplacementMenu()
  local _, screens = drainQueue(faintBattle)
  T.eq(#screens, 1, "fainted trapped battler opens one replacement menu")
  local screen = screens[1]
  T.check(screen and screen.onSwitch ~= nil, "replacement menu exposes its forced callback")
  screen.onSwitch(faintBench)
  drainQueue(faintBattle)
  T.check(activeIs(faintBattle, faintBench), "faint replacement ignores trapping")
end)

case("Baton Pass preserves Mean Look but clears partial trapping", function()
  local lead = makeMon("MEW", 50, { { id="BATON_PASS", pp=40 } })
  local bench = makeMon("RATTATA", 20)

  local mean = newBattle("BATON_PASS", { party={lead,bench} })
  mean.player.cantEscape = true
  mean.player.cantEscapeFrom = mean.enemy
  perform(mean, "BATON_PASS", lead.moves[1])
  drainQueue(mean)
  T.check(activeIs(mean, bench), "Baton Pass switches through Mean Look")
  T.check(mean.player.cantEscape == true, "Baton Pass transfers Mean Look")
  T.eq(mean.player.cantEscapeFrom, mean.enemy, "Mean Look keeps its source")

  local lead2 = makeMon("MEW", 50, { { id="BATON_PASS", pp=40 } })
  local bench2 = makeMon("BULBASAUR", 20)
  local partial = newBattle("BATON_PASS", { party={lead2,bench2} })
  partial.player.cantEscape = true
  partial.player.cantEscapeFrom = partial.enemy
  partial.player.crystalTrapTurns = 4
  partial.player.crystalTrapSource = partial.enemy
  partial.player.crystalTrapMove = "WRAP"
  perform(partial, "BATON_PASS", lead2.moves[1])
  drainQueue(partial)
  T.check(activeIs(partial, bench2), "Baton Pass switches through partial trapping")
  T.eq(partial.player.cantEscape, nil, "Baton Pass clears partial-trap restriction")
  T.eq(partial.player.cantEscapeFrom, nil, "Baton Pass clears partial-trap source")
  T.eq(partial.player.crystalTrapTurns, nil, "Baton Pass resets Wrap turns")
end)

-- -------------------------------------------------------------------------
-- Complete switch-turn sequences
-- -------------------------------------------------------------------------

case("Baton Pass updates or clears trapping source references", function()
  local player = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local enemyLead = makeMon("SMEARGLE", 50, { { id="BATON_PASS", pp=40 } })
  local enemyBench = makeMon("RATTATA", 20)
  local mean = newBattle("TACKLE", {
    kind="trainer", party={player}, enemyParty={enemyLead,enemyBench}, enemyIndex=1,
  })
  mean.player.cantEscape = true
  mean.player.cantEscapeFrom = mean.enemy
  local oldMeanSource = mean.enemy
  Switching.batonPass({
    battle=mean, user=mean.enemy, target=mean.player,
    say=function(text) mean:sayNext(text) end,
  })
  drainQueue(mean)
  T.check(mean.enemy ~= oldMeanSource, "Mean Look source Baton Pass replaces the source")
  T.check(mean.player.cantEscape == true, "Mean Look remains active after source Baton Pass")
  T.eq(mean.player.cantEscapeFrom, mean.enemy,
    "Mean Look source reference follows the Baton Pass replacement")

  local player2 = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local sourceLead = makeMon("SMEARGLE", 50, { { id="BATON_PASS", pp=40 } })
  local sourceBench = makeMon("BULBASAUR", 20)
  local partial = newBattle("TACKLE", {
    kind="trainer", party={player2}, enemyParty={sourceLead,sourceBench}, enemyIndex=1,
  })
  partial.player.cantEscape = true
  partial.player.cantEscapeFrom = partial.enemy
  partial.player.crystalTrapTurns = 3
  partial.player.crystalTrapSource = partial.enemy
  partial.player.crystalTrapMove = "WRAP"
  Switching.batonPass({
    battle=partial, user=partial.enemy, target=partial.player,
    say=function(text) partial:sayNext(text) end,
  })
  drainQueue(partial)
  T.eq(partial.player.cantEscape, nil,
    "partial trapping ends when its source uses Baton Pass")
  T.eq(partial.player.cantEscapeFrom, nil,
    "partial trapping drops its old source reference")
  T.eq(partial.player.crystalTrapTurns, nil,
    "partial trapping drops its residual countdown")
  T.eq(partial.player.crystalTrapSource, nil,
    "partial trapping drops its residual source")
end)

case("ordinary enemy moves target the incoming player battler", function()
  for _, id in ipairs({ "TACKLE", "THUNDER_WAVE", "WRAP" }) do
    local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
    local bench = makeMon("RATTATA", 20)
    local battle = newBattle("TACKLE", { party={lead,bench} })
    local outgoingHP, incomingHP = lead.hp, bench.hp
    battle.enemy.curMoves = { { id=id, pp=20 } }
    battle.enemyAction = function() return battle.enemy.curMoves[1] end
    battle.accuracyRoll = function() return true end
    battle:resolveSwitch(bench)
    drainQueue(battle)
    T.check(activeIs(battle, bench), id .. " switch completes")
    T.eq(lead.hp, outgoingHP, id .. " does not hit the withdrawn battler")
    if id == "TACKLE" then
      T.check(bench.hp < incomingHP, "Tackle damages the incoming battler")
    elseif id == "THUNDER_WAVE" then
      T.eq(bench.status, "PAR", "Thunder Wave statuses the incoming battler")
    else
      T.check(battle.player.cantEscape == true,
        "Wrap traps the incoming battler after the switch")
      T.check((battle.player.crystalTrapTurns or 0) > 0,
        "Wrap starts residual turns on the incoming battler")
    end
  end
end)

case("Pursuit alone intercepts the outgoing slot", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.enemy.curMoves = { { id="PURSUIT", pp=20 } }
  battle.enemyAction = function() return battle.enemy.curMoves[1] end
  local outgoingHP, incomingHP = lead.hp, bench.hp
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(lead.hp < outgoingHP, "Pursuit damages the outgoing battler")
  T.eq(bench.hp, incomingHP, "Pursuit does not damage the incoming battler")
  T.check(activeIs(battle, bench), "surviving outgoing battler completes the switch")
end)

case("Pursuit KO leaves the chosen bench mon out until replacement handling", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.mon.hp = 1
  battle.player.shownHP = 1
  battle.enemy.curMoves = { { id="PURSUIT", pp=20 } }
  battle.enemyAction = function() return battle.enemy.curMoves[1] end
  local outgoing = battle.player
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(outgoing.mon.hp, 0, "Pursuit KOs the outgoing battler")
  T.check(battle.player == outgoing, "Pursuit KO cancels the selected switch")
  T.check(not activeIs(battle, bench), "bench mon is not inserted before faint handling")
end)

case("simultaneous player and trainer switches replace both active slots once", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local enemyLead = makeMon("SNORLAX", 50, { { id="TACKLE", pp=35 } })
  local enemyBench = makeMon("BULBASAUR", 20)
  local battle = newBattle("TACKLE", {
    kind="trainer", party={lead,bench},
    enemyParty={enemyLead,enemyBench}, enemyIndex=1,
  })
  local oldPlayer, oldEnemy = battle.player, battle.enemy
  battle.enemyAction = function() return { special="aiSwitch", index=2 } end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(activeIs(battle, bench), "player switch selects its bench mon")
  T.check(battle.enemy.mon == enemyBench, "trainer switch selects its bench mon")
  T.eq(battle.enemyIndex, 2, "trainer switch updates its party index")
  T.check(battle.player ~= oldPlayer, "player active object changes once")
  T.check(battle.enemy ~= oldEnemy, "enemy active object changes once")
  T.eq(battle.sides[1].battlers[1], battle.player, "player side points at the replacement")
  T.eq(battle.sides[2].battlers[1], battle.enemy, "enemy side points at the replacement")
end)

case("a successful switch runs end-of-turn exactly once", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  local ends = 0
  battle.enemyAction = function() return nil end
  battle.endOfTurn = function() ends = ends + 1 end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(ends, 1, "successful switch runs one end-of-turn pass")

  local blockedLead = makeMon("MEW", 50)
  local blockedBench = makeMon("BULBASAUR", 20)
  local blocked = newBattle("TACKLE", { party={blockedLead,blockedBench} })
  blocked.player.cantEscape = true
  blocked.endOfTurn = function() ends = ends + 1 end
  blocked:resolveSwitch(blockedBench)
  drainQueue(blocked)
  T.eq(ends, 1, "rejected switch runs no end-of-turn pass")
end)

-- -------------------------------------------------------------------------
-- State cleanup, entry hazards, and reference integrity
-- -------------------------------------------------------------------------

case("normal switching clears every outgoing volatile family", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  local outgoing = battle.player
  local fields = {
    "substituteHP", "confusedTurns", "disabledTurns", "disabledSlot",
    "disabledMove", "encoreTurns", "encoreMove", "encoreSetTurn",
    "leechSeeded", "cursed", "nightmare", "perishTurns", "foresight",
    "focusEnergy", "mist", "defenseCurl", "minimized", "infatuatedWith",
    "protect", "endure", "protectChain", "protectLastTurn",
    "lockedTarget", "lockOnTurns", "destinyBond", "crystalTrapTurns",
    "crystalTrapSource", "crystalTrapMove",
  }
  for index, field in ipairs(fields) do outgoing[field] = index end
  outgoing.stages = { attack=6, defense=-6, speed=3, accuracy=-2 }
  outgoing.toxicCounter = 9
  battle.enemy.infatuatedWith = outgoing
  battle.enemy.cantEscape = true
  battle.enemy.cantEscapeFrom = outgoing
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  for _, field in ipairs(fields) do
    T.eq(outgoing[field], nil, "normal switch clears outgoing " .. field)
  end
  T.eq(outgoing.toxicCounter, nil, "normal switch clears Toxic counter")
  T.eq(battle.enemy.infatuatedWith, nil, "normal switch clears outgoing Attract source")
  T.eq(battle.enemy.cantEscape, nil, "normal switch releases outgoing Mean Look source")
  T.eq(battle.enemy.cantEscapeFrom, nil, "normal switch clears stale source reference")
  T.eq((battle.player.stages or {}).attack or 0, 0, "incoming Attack stage is neutral")
  T.eq((battle.player.stages or {}).defense or 0, 0, "incoming Defense stage is neutral")
end)

case("normal switching preserves party-owned state", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=7 } })
  local bench = makeMon("RATTATA", 20, { { id="QUICK_ATTACK", pp=13 } })
  bench.status = "PSN"
  bench.happiness = 123
  bench.heldItem = "LEFTOVERS"
  local battle = newBattle("TACKLE", { party={lead,bench} })
  local hp, pp = bench.hp, bench.moves[1].pp
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(battle.player.mon.status, "PSN", "switch preserves major status")
  T.eq(battle.player.mon.hp, hp, "switch preserves party HP")
  T.eq(battle.player.mon.moves[1].pp, pp, "switch preserves party PP")
  T.eq(battle.player.mon.happiness, 123, "switch preserves happiness")
  T.eq(battle.player.mon.heldItem, "LEFTOVERS", "switch preserves held item")
end)

case("switching out and back preserves status but resets Toxic progression", function()
  local lead = makeMon("MEW", 50, { { id="TACKLE", pp=35 } })
  local bench = makeMon("RATTATA", 20)
  lead.status = "PSN"
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.player.toxicCounter = 7
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.eq(lead.status, "PSN", "switch-out keeps the party mon poisoned")
  T.eq(battle.player.mon, bench, "bench mon occupies the active slot")
  battle:resolveSwitch(lead)
  drainQueue(battle)
  T.eq(battle.player.mon, lead, "original mon can return later")
  T.eq(battle.player.mon.status, "PSN", "returning mon keeps ordinary poison")
  T.eq(battle.player.toxicCounter, nil,
    "returning mon does not restore the old Toxic counter")
end)

case("Spikes applies to the actual incoming slot", function()
  local lead = makeMon("MEW", 50)
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  battle.playerSpikes = true
  battle.enemyAction = function() return nil end
  local hp = bench.hp
  battle:resolveSwitch(bench)
  drainQueue(battle)
  T.check(bench.hp < hp, "grounded incoming battler takes Spikes")
  T.check(activeIs(battle, bench), "Spikes damage applies after replacement")

  local lead2 = makeMon("MEW", 50)
  local flying = makeMon("PIDGEY", 20)
  local immune = newBattle("TACKLE", { party={lead2,flying} })
  immune.playerSpikes = true
  immune.enemyAction = function() return nil end
  local flyingHP = flying.hp
  immune:resolveSwitch(flying)
  drainQueue(immune)
  T.eq(flying.hp, flyingHP, "Flying incoming battler ignores Spikes")
end)

case("switch references never retain an outgoing battler object", function()
  local lead = makeMon("MEW", 50)
  local bench = makeMon("RATTATA", 20)
  local battle = newBattle("TACKLE", { party={lead,bench} })
  local outgoing = battle.player
  battle.enemy.infatuatedWith = outgoing
  battle.enemy.cantEscape = true
  battle.enemy.cantEscapeFrom = outgoing
  battle.enemy.crystalTrapSource = outgoing
  battle.enemy.crystalTrapTurns = 3
  battle.enemyAction = function() return nil end
  battle:resolveSwitch(bench)
  drainQueue(battle)
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    T.check(battler ~= outgoing, "active battler object is not outgoing")
    T.check(battler.infatuatedWith ~= outgoing, "Attract reference is not outgoing")
    T.check(battler.cantEscapeFrom ~= outgoing, "escape source is not outgoing")
    T.check(battler.crystalTrapSource ~= outgoing, "partial-trap source is not outgoing")
  end
end)

-- -------------------------------------------------------------------------
-- Deterministic switch-state stress matrix
-- -------------------------------------------------------------------------

case("switch-state matrix preserves queue and active-slot invariants", function()
  local kinds = { "wild", "trainer", "link" }
  local flags = {
    { name="free" },
    { name="mean", cantEscape=true },
    { name="partial", cantEscape=true, turns=3 },
    { name="partial-mirror-missing", turns=3 },
  }
  local staleIndexes = { 0, 2, 99, 4096 }
  for _, battleKind in ipairs(kinds) do
    for _, flag in ipairs(flags) do
      for _, stale in ipairs(staleIndexes) do
        local lead = makeMon("MEW", 50)
        local bench = makeMon("RATTATA", 20)
        local battle = newBattle("TACKLE", { party={lead,bench}, kind=battleKind })
        battle.player.cantEscape = flag.cantEscape
        battle.player.cantEscapeFrom = flag.cantEscape and battle.enemy or nil
        battle.player.crystalTrapTurns = flag.turns
        battle.player.crystalTrapSource = flag.turns and battle.enemy or nil
        battle.player.crystalTrapMove = flag.turns and "WRAP" or nil
        battle.enemyAction = function() return nil end
        battle.nextInsert = stale
        local ok = pcall(battle.resolveSwitch, battle, bench)
        local label = battleKind .. "/" .. flag.name .. "/" .. stale
        T.check(ok, label .. " resolveSwitch is safe")
        local trapped = flag.cantEscape or flag.turns
        if trapped then
          T.check(activeIs(battle, lead), label .. " keeps trapped active slot")
          T.eq(#battle.queue, 1, label .. " has one rejection row")
          T.check(battle.queue[1].text ~= nil, label .. " rejection row is text")
        else
          drainQueue(battle)
          T.check(activeIs(battle, bench), label .. " completes legal switch")
          T.eq(#battle.queue, 0, label .. " drains legal switch queue")
        end
      end
    end
  end
end)

run.release()
T.finish("Crystal full battle integration")
