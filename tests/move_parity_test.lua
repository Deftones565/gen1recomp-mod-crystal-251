package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Specs = require("mods.CRYSTAL_251.tests._move_parity_spec")

local path = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP Crystal move parity (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local run, cache = require("mods.CRYSTAL_251.tests._real_rom_mod").load(T, raw)
T.eq(#run.errors, 0, "Crystal 251 loads before move parity probes")

local BattleState = require("src.battle.BattleState")
local EffectRegistry = require("src.battle.EffectRegistry")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")

local data = run.data
local cacheById = {}
for _, move in ipairs(cache.moves) do cacheById[move.id] = move end

local function seq(values, fallback)
  local i = 0
  return function(a, b)
    i = i + 1
    local value
    if values and values[i] ~= nil then value = values[i]
    elseif fallback ~= nil then value = fallback
    else value = a or 0 end
    -- Test doubles must obey the same inclusive range contract as
    -- love.math.random.  An out-of-range zero previously collapsed every
    -- damage randomizer call (217..255) to the one-damage floor.
    if type(value) == "number" then
      if a ~= nil and value < a then value = a end
      if b ~= nil and value > b then value = b end
    end
    return value
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

local function newBattle(moveId, opts)
  opts = opts or {}
  local species = opts.playerSpecies or "MEW"
  local enemySpecies = opts.enemySpecies or "SNORLAX"
  local level = opts.level or 50
  local mon = Pokemon.new(data, species, level, function() return 15 end)
  mon.moves = opts.moves or { { id = moveId, pp = 40 } }
  if opts.party then mon = opts.party[1] end
  local party = opts.party or { mon }
  local game = makeGame(party)
  local battle = BattleState.newWild(game, enemySpecies, level)
  battle.turnCount = opts.turnCount or 1
  battle.phase = "menu"
  battle.rng = opts.rng or seq(nil, 0)

  -- Large, stable HP pools keep secondary effects observable without an
  -- unrelated KO ending the damaging pipeline.
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    battler.mon.stats.hp = opts.maxHP or 1000
    battler.mon.hp = opts.hp or battler.mon.stats.hp
    battler.mon.stats.attack = 100
    battler.mon.stats.defense = 100
    battler.mon.stats.speed = 100
    battler.mon.stats.special = 100
    battler.curStats = battler.mon.stats
    battler.shownHP = battler.mon.hp
  end
  return battle, mon
end

local function perform(battle, moveId, moveInst)
  moveInst = moveInst or { id = moveId, pp = 40 }
  battle:performMove(battle.player, battle.enemy, moveInst)
  return moveInst
end

local function hasText(battle, fragment)
  for _, row in ipairs(battle.queue or {}) do
    if row.text and row.text:find(fragment, 1, true) then return true end
  end
  return false
end

local function stage(battler, stat)
  return (battler.stages and battler.stages[stat]) or 0
end

local function effectRecord(moveId)
  local move = assert(data.moves[moveId], moveId)
  return data.move_effects and data.move_effects[move.effect]
end

local function checkDamage(spec)
  local battle = newBattle(spec.id)
  local before = battle.enemy.mon.hp
  perform(battle, spec.id)
  T.check(battle.enemy.mon.hp < before, spec.id .. " deals damage")
end

local function checkStage(spec, secondary)
  local function one(chance, expectedDelta)
    local move = data.moves[spec.id]
    local oldChance = move.effectChance
    if secondary then move.effectChance = chance end
    local battle = newBattle(spec.id, { enemySpecies = spec.enemySpecies })
    local who = spec.who == "user" and battle.player or battle.enemy
    local before = stage(who, spec.stat)
    perform(battle, spec.id)
    local after = stage(who, spec.stat)
    move.effectChance = oldChance
    T.eq(after - before, expectedDelta,
      spec.id .. (secondary and (chance == 0 and " suppresses" or " applies") or " applies")
      .. " its " .. spec.stat .. " stage effect")
  end
  one(secondary and 255 or nil, spec.delta)
  if secondary then one(0, 0) end
end

local function checkSecondaryStatus(spec)
  local move = data.moves[spec.id]
  local oldChance = move.effectChance
  move.effectChance = 255
  local hit = newBattle(spec.id)
  perform(hit, spec.id)
  T.eq(hit.enemy.mon.status, spec.status,
    spec.id .. " applies " .. spec.status .. " when its secondary chance succeeds")
  move.effectChance = 0
  local miss = newBattle(spec.id)
  perform(miss, spec.id)
  T.eq(miss.enemy.mon.status, nil,
    spec.id .. " does not apply status when its secondary chance is zero")
  move.effectChance = oldChance
end

local function checkSecondaryConfusion(spec)
  local move = data.moves[spec.id]
  local oldChance = move.effectChance
  move.effectChance = 255
  local hit = newBattle(spec.id)
  perform(hit, spec.id)
  T.check((hit.enemy.confusedTurns or 0) > 0,
    spec.id .. " confuses when its secondary chance succeeds")
  move.effectChance = 0
  local miss = newBattle(spec.id)
  perform(miss, spec.id)
  T.eq(miss.enemy.confusedTurns, nil,
    spec.id .. " does not confuse when its secondary chance is zero")
  move.effectChance = oldChance
end

local Probes = {}

Probes.damage = checkDamage
Probes.high_crit_damage = function(spec)
  T.check(data.moves[spec.id].highCrit == true, spec.id .. " has Crystal's high-crit flag")
  checkDamage(spec)
end
Probes.priority_damage = function(spec)
  T.eq(data.moves[spec.id].priority, spec.priority, spec.id .. " priority")
  checkDamage(spec)
end
Probes.always_hit = function(spec)
  local move = data.moves[spec.id]
  local old = move.accuracy
  move.accuracy = 0
  local battle = newBattle(spec.id, { rng = seq(nil, 255) })
  local before = battle.enemy.mon.hp
  perform(battle, spec.id)
  move.accuracy = old
  T.check(battle.enemy.mon.hp < before, spec.id .. " ignores ordinary accuracy failure")
end
Probes.always_hit_priority = function(spec)
  T.eq(data.moves[spec.id].priority, spec.priority, spec.id .. " priority")
  Probes.always_hit(spec)
end
Probes.stage = function(spec) checkStage(spec, false) end
Probes.secondary_stage = function(spec) checkStage(spec, true) end
Probes.secondary_status = checkSecondaryStatus
Probes.secondary_confusion = checkSecondaryConfusion
Probes.confusion = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.check((battle.enemy.confusedTurns or 0) > 0, spec.id .. " confuses the target")
end
Probes.multi_hit = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.check(hasText(battle, "times!"), spec.id .. " reports more than one hit")
end
Probes.heal_half = function(spec)
  local battle = newBattle(spec.id)
  battle.player.mon.hp = 200
  local before = battle.player.mon.hp
  perform(battle, spec.id)
  T.eq(battle.player.mon.hp - before, 500, spec.id .. " heals half maximum HP")
end
Probes.drain = function(spec)
  local battle = newBattle(spec.id)
  battle.player.mon.hp = 300
  local userBefore, targetBefore = battle.player.mon.hp, battle.enemy.mon.hp
  perform(battle, spec.id)
  T.check(battle.enemy.mon.hp < targetBefore, spec.id .. " damages the target")
  T.check(battle.player.mon.hp > userBefore, spec.id .. " restores user HP")
end
Probes.trap = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  local turns = battle.enemy.crystalTrapTurns or 0
  T.check(turns >= 2 and turns <= 5,
    spec.id .. " starts a two-to-five-turn trapping sequence")
end
Probes.rampage = function(spec)
  local battle = newBattle(spec.id)
  local inst = { id = spec.id, pp = 20 }
  perform(battle, spec.id, inst)
  T.check((battle.player.thrashTurns or 0) > 0 and battle.player.thrashMove == inst,
    spec.id .. " locks the user into a rampage")
end

Probes.sketch = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.lastMove = "TACKLE"
  local inst = { id = spec.id, pp = 1 }
  perform(battle, spec.id, inst)
  T.eq(inst.id, "TACKLE", "Sketch replaces its own move slot")
  T.eq(inst.pp, data.moves.TACKLE.pp, "Sketch gives the copied move its base PP")
end

Probes.triple_kick = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.check(hasText(battle, "3 times!"), "Triple Kick lands three ordered hits when all checks pass")
end

Probes.thief = function(spec)
  local battle = newBattle(spec.id)
  battle.player.mon.heldItem = nil
  battle.enemy.mon.heldItem = "BERRY"
  perform(battle, spec.id)
  T.eq(battle.player.mon.heldItem, "BERRY", "Thief transfers the target's held item")
  T.eq(battle.enemy.mon.heldItem, nil, "Thief clears the target's held item")
end

Probes.mean_look = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.check(battle.enemy.cantEscape == true, spec.id .. " traps the target's active slot")
end

Probes.lock_on = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.check(battle.player.lockedTarget == battle.enemy
    and (battle.player.lockOnTurns or 0) > 0, spec.id .. " records its aimed target")
end

Probes.nightmare = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.mon.heldItem = nil
  battle.enemy.mon.status = "SLP"
  perform(battle, spec.id)
  local before = battle.enemy.mon.hp
  Runtime.emit("battle.turn_ended", { battle = battle, turn = battle.turnCount })
  T.eq(before - battle.enemy.mon.hp, 250, "Nightmare removes one quarter max HP")
end

local function thawAndBurn(spec)
  local move = data.moves[spec.id]
  local oldChance = move.effectChance
  move.effectChance = 255
  local battle = newBattle(spec.id)
  battle.player.mon.status = "FRZ"
  perform(battle, spec.id)
  move.effectChance = oldChance
  T.eq(battle.player.mon.status, nil, spec.id .. " thaws a frozen user")
  T.eq(battle.enemy.mon.status, "BRN", spec.id .. " applies its burn side effect")
end
Probes.flame_wheel = thawAndBurn
Probes.sacred_fire = thawAndBurn

Probes.snore = function(spec)
  local asleep = newBattle(spec.id)
  asleep.player.mon.status = "SLP"
  asleep.player.sleepTurns = 3
  local before = asleep.enemy.mon.hp
  perform(asleep, spec.id)
  T.check(asleep.enemy.mon.hp < before, "Snore works while the user is asleep")
  local awake = newBattle(spec.id)
  local awakeBefore = awake.enemy.mon.hp
  perform(awake, spec.id)
  T.eq(awake.enemy.mon.hp, awakeBefore, "Snore fails while the user is awake")
end

Probes.curse = function(spec)
  local normal = newBattle(spec.id, { playerSpecies = "SNORLAX" })
  local hp = normal.player.mon.hp
  perform(normal, spec.id)
  T.eq(stage(normal.player, "attack"), 1, "non-Ghost Curse raises Attack")
  T.eq(stage(normal.player, "defense"), 1, "non-Ghost Curse raises Defense")
  T.eq(stage(normal.player, "speed"), -1, "non-Ghost Curse lowers Speed")
  T.eq(normal.player.mon.hp, hp, "non-Ghost Curse costs no HP")

  local ghost = newBattle(spec.id, { playerSpecies = "GASTLY" })
  local ghostHP = ghost.player.mon.hp
  perform(ghost, spec.id)
  T.eq(ghostHP - ghost.player.mon.hp, 500, "Ghost Curse costs half maximum HP")
  T.check(ghost.enemy.cursed == true, "Ghost Curse marks the target")
end

Probes.hp_scaled_damage = function(spec)
  local full = newBattle(spec.id)
  local fullBefore = full.enemy.mon.hp
  perform(full, spec.id)
  local fullDamage = fullBefore - full.enemy.mon.hp

  local low = newBattle(spec.id)
  low.player.mon.hp = 1
  local lowBefore = low.enemy.mon.hp
  perform(low, spec.id)
  local lowDamage = lowBefore - low.enemy.mon.hp
  T.check(lowDamage > fullDamage, spec.id .. " gets stronger at low HP")
end

Probes.conversion2 = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.lastMove = "EMBER"
  local before = table.concat(battle.player.curTypes, ",")
  perform(battle, spec.id)
  T.neq(table.concat(battle.player.curTypes, ","), before,
    "Conversion 2 changes the user's type")
end

Probes.spite = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.curMoves = { { id = "TACKLE", pp = 20 } }
  battle.enemy.lastMove = "TACKLE"
  perform(battle, spec.id)
  local lost = 20 - battle.enemy.curMoves[1].pp
  T.check(lost >= 2 and lost <= 5, "Spite removes 2-5 PP")
end

Probes.protect = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  local before = battle.player.mon.hp
  battle:performMove(battle.enemy, battle.player, { id = "TACKLE", pp = 35 })
  T.eq(battle.player.mon.hp, before, spec.id .. " blocks an incoming attack")
end

Probes.belly_drum = function(spec)
  local battle = newBattle(spec.id)
  local before = battle.player.mon.hp
  perform(battle, spec.id)
  T.eq(before - battle.player.mon.hp, 500, "Belly Drum costs half maximum HP")
  T.eq(stage(battle.player, "attack"), 6, "Belly Drum maximizes Attack")
end

Probes.spikes = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.check(battle.enemySpikes == true, "Spikes marks the opposing side")
  local incoming = BattleState.makeBattler(data,
    Pokemon.new(data, "RATTATA", 20, function() return 15 end), false)
  incoming.mon.stats.hp, incoming.mon.hp = 800, 800
  incoming.curStats = incoming.mon.stats
  local before = incoming.mon.hp
  Runtime.emit("battle.battler_switched", {
    battle = battle, battler = incoming, previous = battle.enemy,
  })
  T.eq(before - incoming.mon.hp, 100, "Spikes removes one eighth max HP on entry")
end

Probes.foresight = function(spec)
  local battle = newBattle(spec.id, { enemySpecies = "GASTLY" })
  battle.enemy.stages.evasion = 3
  perform(battle, spec.id)
  T.eq(stage(battle.enemy, "evasion"), 3,
    "Foresight preserves the stored Evasion stage")
  local before = battle.enemy.mon.hp
  battle:performMove(battle.player, battle.enemy, { id = "TACKLE", pp = 35 })
  T.check(battle.enemy.mon.hp < before, "Foresight lets Normal attacks hit Ghosts")
end

Probes.destiny_bond = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  battle.player.mon.hp = 1
  battle.enemy.mon.stats.attack = 999
  battle.enemy.curStats = battle.enemy.mon.stats
  battle:performMove(battle.enemy, battle.player, { id = "TACKLE", pp = 35 })
  T.eq(battle.player.mon.hp, 0, "Destiny Bond user is knocked out")
  T.eq(battle.enemy.mon.hp, 0, "Destiny Bond knocks out the attacker")
end

Probes.perish_song = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.eq(battle.player.perishTurns, 3, "Perish Song starts the user's count at 3")
  T.eq(battle.enemy.perishTurns, 3, "Perish Song starts the target's count at 3")
  for turn = 1, 3 do
    Runtime.emit("battle.turn_ended", { battle = battle, turn = turn })
  end
  T.eq(battle.player.mon.hp, 0, "Perish Song faints the user after the countdown")
  T.eq(battle.enemy.mon.hp, 0, "Perish Song faints the target after the countdown")
end

Probes.sandstorm = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.eq(battle.weather, "sandstorm", "Sandstorm sets weather")
  T.eq(battle.weatherTurns, 5, "Sandstorm lasts five turns")
  local p, e = battle.player.mon.hp, battle.enemy.mon.hp
  Runtime.emit("battle.turn_ended", { battle = battle, turn = 1 })
  T.check(battle.player.mon.hp < p and battle.enemy.mon.hp < e,
    "Sandstorm damages non-immune battlers")
end

Probes.endure = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  battle.player.mon.hp = 10
  battle.enemy.mon.stats.attack = 999
  battle.enemy.curStats = battle.enemy.mon.stats
  battle:performMove(battle.enemy, battle.player, { id = "TACKLE", pp = 35 })
  T.eq(battle.player.mon.hp, 1, "Endure leaves the user at 1 HP")
end

Probes.rollout = function(spec)
  local battle = newBattle(spec.id)
  local inst = { id = spec.id, pp = 20 }
  local before1 = battle.enemy.mon.hp
  perform(battle, spec.id, inst)
  local damage1 = before1 - battle.enemy.mon.hp
  battle.enemy.mon.hp = 1000
  local before2 = battle.enemy.mon.hp
  perform(battle, spec.id, inst)
  local damage2 = before2 - battle.enemy.mon.hp
  T.check(damage2 > damage1, "Rollout power increases on consecutive hits")
  T.check(battle.player.forcedMove == inst, "Rollout locks the user into the move")
end

Probes.false_swipe = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.mon.hp = 1
  perform(battle, spec.id)
  T.eq(battle.enemy.mon.hp, 1, "False Swipe cannot faint the target")
end

Probes.swagger = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.eq(stage(battle.enemy, "attack"), 2, "Swagger raises target Attack by two")
  T.check((battle.enemy.confusedTurns or 0) > 0, "Swagger confuses the target")
end

Probes.fury_cutter = function(spec)
  local battle = newBattle(spec.id)
  local before1 = battle.enemy.mon.hp
  perform(battle, spec.id)
  local damage1 = before1 - battle.enemy.mon.hp
  battle.enemy.mon.hp = 1000
  local before2 = battle.enemy.mon.hp
  perform(battle, spec.id)
  local damage2 = before2 - battle.enemy.mon.hp
  T.check(damage2 > damage1, "Fury Cutter grows on consecutive hits")
  battle:performMove(battle.player, battle.enemy, { id = "TACKLE", pp = 35 })
  T.eq(battle.player.furyCutterCount, nil, "another move resets Fury Cutter")
end

Probes.attract = function(spec)
  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  Gender.setRatio("EEVEE", 31)
  local opposite = newBattle(spec.id, {
    playerSpecies="EEVEE", enemySpecies="EEVEE",
  })
  opposite.player.mon.dvs.attack, opposite.player.mon.dvs.speed = 2, 0
  opposite.enemy.mon.dvs.attack, opposite.enemy.mon.dvs.speed = 1, 15
  perform(opposite, spec.id)
  T.check(opposite.enemy.infatuatedWith == opposite.player,
    "Attract works against the opposite gender")

  local same = newBattle(spec.id, {
    playerSpecies="EEVEE", enemySpecies="EEVEE",
  })
  same.player.mon.dvs.attack, same.player.mon.dvs.speed = 2, 0
  same.enemy.mon.dvs.attack, same.enemy.mon.dvs.speed = 3, 0
  perform(same, spec.id)
  T.eq(same.enemy.infatuatedWith, nil, "Attract fails against the same gender")
end

Probes.sleep_talk = function(spec)
  local mon = Pokemon.new(data, "MEW", 50, function() return 15 end)
  mon.moves = { { id = "SLEEP_TALK", pp = 10 }, { id = "TACKLE", pp = 35 } }
  mon.status = "SLP"
  local battle = newBattle(spec.id, { party = { mon } })
  battle.player.sleepTurns = 3
  local targetBefore = battle.enemy.mon.hp
  local tacklePP = mon.moves[2].pp
  perform(battle, spec.id, mon.moves[1])
  T.check(battle.enemy.mon.hp < targetBefore, "Sleep Talk calls an eligible move")
  T.eq(mon.moves[2].pp, tacklePP, "Sleep Talk does not spend the called move's PP")
end

Probes.heal_bell = function(spec)
  local a = Pokemon.new(data, "MEW", 50, function() return 15 end)
  local b = Pokemon.new(data, "RATTATA", 20, function() return 15 end)
  a.moves = { { id = spec.id, pp = 5 } }
  a.status, b.status = "PAR", "PSN"
  local battle = newBattle(spec.id, { party = { a, b } })
  perform(battle, spec.id, a.moves[1])
  T.eq(a.status, nil, "Heal Bell cures the active Pokemon")
  T.eq(b.status, nil, "Heal Bell cures benched party members")
end

Probes.happiness_damage = function(spec)
  local high = newBattle(spec.id)
  high.player.mon.happiness = 255
  local hb = high.enemy.mon.hp
  perform(high, spec.id)
  local highDamage = hb - high.enemy.mon.hp

  local low = newBattle(spec.id)
  low.player.mon.happiness = 0
  local lb = low.enemy.mon.hp
  perform(low, spec.id)
  local lowDamage = lb - low.enemy.mon.hp

  if spec.direction == "up" then
    T.check(highDamage > lowDamage, "Return grows with happiness")
  else
    T.check(lowDamage > highDamage, "Frustration grows as happiness falls")
  end
end

Probes.present = function(spec)
  local heal = newBattle(spec.id, { rng = seq({ 0, 255, 255 }, 255) })
  heal.enemy.mon.hp = 500
  perform(heal, spec.id)
  T.eq(heal.enemy.mon.hp, 750, "Present's heal outcome restores one quarter max HP")

  local hit = newBattle(spec.id, { rng = seq({ 0, 255, 50, 255 }, 255) })
  local before = hit.enemy.mon.hp
  perform(hit, spec.id)
  T.check(hit.enemy.mon.hp < before, "Present's damaging outcomes deal damage")
end

Probes.safeguard = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  battle:performMove(battle.enemy, battle.player, { id = "THUNDER_WAVE", pp = 20 })
  T.eq(battle.player.mon.status, nil, "Safeguard blocks major status")
  battle:performMove(battle.enemy, battle.player, { id = "SWEET_KISS", pp = 10 })
  T.eq(battle.player.confusedTurns, nil, "Safeguard blocks confusion")
end

Probes.pain_split = function(spec)
  local battle = newBattle(spec.id)
  battle.player.mon.hp, battle.enemy.mon.hp = 200, 800
  perform(battle, spec.id)
  T.eq(battle.player.mon.hp, 500, "Pain Split averages user HP")
  T.eq(battle.enemy.mon.hp, 500, "Pain Split averages target HP")
end

Probes.magnitude = function(spec)
  local function powerAt(roll)
    local move = data.moves[spec.id]
    return run.loader.hooks:call("battle.damage", function(ctx)
      return ctx.move.power, { crit = false, typeMult = 10 }
    end, {
      battle = { weather = nil }, move = move,
      rng = function() return roll end,
      user = { mon = { hp = 100, stats = { hp = 100 } } },
      target = { mon = { hp = 100, stats = { hp = 100 } }, curTypes = { "NORMAL" } },
    })
  end
  T.eq(powerAt(1), 10, "Magnitude 4 has power 10")
  T.eq(powerAt(255), 150, "Magnitude 10 has power 150")
end

Probes.baton_pass = function(spec)
  local lead = Pokemon.new(data, "MEW", 50, function() return 15 end)
  local bench = Pokemon.new(data, "RATTATA", 20, function() return 15 end)
  lead.moves = { { id = spec.id, pp = 40 } }
  local battle = newBattle(spec.id, { party = { lead, bench } })
  battle.player.stages.attack = 2
  perform(battle, spec.id, lead.moves[1])
  T.check(battle.player.mon == bench, "Baton Pass switches to a party member")
  T.eq(stage(battle.player, "attack"), 2, "Baton Pass transfers stat stages")
end

Probes.encore = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.lastMove = "TACKLE"
  battle.enemy.curMoves = { { id = "TACKLE", pp = 10 }, { id = "GROWL", pp = 40 } }
  perform(battle, spec.id)
  local locked = battle:menuLockedAction(battle.enemy)
  T.check(locked and locked.id == "TACKLE", "Encore locks the target to its last move")
  T.check((battle.enemy.encoreTurns or 0) >= 3 and battle.enemy.encoreTurns <= 6,
    "Encore lasts 3-6 turns")
end

Probes.pursuit = function(spec)
  local record = effectRecord(spec.id)
  T.check(record and type(record.onSwitchAttempt) == "function",
    "Pursuit exposes a pre-switch interception callback")
end

Probes.rapid_spin = function(spec)
  local battle = newBattle(spec.id)
  battle.player.leechSeeded = true
  battle.player.crystalTrapTurns = 3
  battle.player.crystalTrapSource = battle.enemy
  battle.player.crystalTrapMove = "WHIRLPOOL"
  battle.player.cantEscape = true
  battle.player.cantEscapeFrom = battle.enemy
  battle.playerSpikes = true
  perform(battle, spec.id)
  T.eq(battle.player.leechSeeded, nil, "Rapid Spin removes Leech Seed")
  T.eq(battle.playerSpikes, nil, "Rapid Spin removes Spikes from the user's side")
  T.eq(battle.player.crystalTrapTurns, nil, "Rapid Spin removes trapping")
end

Probes.weather_heal = function(spec)
  local function healed(weather)
    local battle = newBattle(spec.id)
    battle.weather = weather
    battle.player.mon.hp = 100
    perform(battle, spec.id)
    return battle.player.mon.hp - 100
  end
  local clear, sun, rain = healed(nil), healed("sun"), healed("rain")
  T.check(sun > clear and clear > rain and rain > 0,
    spec.id .. " healing follows sun > clear > adverse weather")
end

Probes.hidden_power = function(spec)
  local move = data.moves[spec.id]
  local seenType, seenPower
  run.loader.hooks:call("battle.damage", function(ctx)
    seenType, seenPower = ctx.move.type, ctx.move.power
    return ctx.move.power, { crit = false, typeMult = 10 }
  end, {
    battle = { weather = nil }, move = move, rng = function(a) return a end,
    user = { mon = { hp = 50, stats = { hp = 50 },
      dvs = { attack = 15, defense = 15, speed = 15, special = 15 } } },
    target = { mon = { hp = 100, stats = { hp = 100 } }, curTypes = { "NORMAL" } },
  })
  T.eq(seenType, "STEEL", "Hidden Power derives its Crystal type from DVs")
  T.eq(seenPower, 70, "Hidden Power derives its Crystal power from DVs")
end

Probes.twister = function(spec)
  local normal = newBattle(spec.id)
  local nb = normal.enemy.mon.hp
  perform(normal, spec.id)
  local normalDamage = nb - normal.enemy.mon.hp

  local flying = newBattle(spec.id)
  flying.enemy.invulnerable = true
  flying.enemy.invulnerableMove = "FLY"
  local fb = flying.enemy.mon.hp
  perform(flying, spec.id)
  local flyingDamage = fb - flying.enemy.mon.hp
  T.check(flyingDamage > normalDamage, "Twister hits Fly and doubles damage")
end

Probes.weather = function(spec)
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  T.eq(battle.weather, spec.weather, spec.id .. " sets its weather")
  T.eq(battle.weatherTurns, 5, spec.id .. " weather lasts five turns")
end

Probes.mirror_coat = function(spec)
  local battle = newBattle(spec.id)
  battle.player.crystalLastDamageTaken = {
    damage = 100, from = battle.enemy, turn = battle.turnCount,
    category = "special", power = 95, moveId = "SURF",
  }
  local before = battle.enemy.mon.hp
  perform(battle, spec.id)
  T.eq(before - battle.enemy.mon.hp, 200, "Mirror Coat returns double special damage")
end

Probes.psych_up = function(spec)
  local battle = newBattle(spec.id)
  battle.enemy.stages = {
    attack=3, defense=-2, speed=1, specialAttack=4,
    specialDefense=-3, accuracy=2, evasion=-1,
  }
  perform(battle, spec.id)
  T.eq(stage(battle.player, "attack"), 3, "Psych Up copies positive stages")
  T.eq(stage(battle.player, "defense"), -2, "Psych Up copies negative stages")
  T.eq(stage(battle.player, "specialAttack"), 4,
    "Psych Up copies Special Attack")
  T.eq(stage(battle.player, "specialDefense"), -3,
    "Psych Up copies Special Defense")
  T.eq(battle.player.stages.special, nil,
    "Psych Up keeps the split Special stages independent")
end

Probes.ancientpower = function(spec)
  local move = data.moves[spec.id]
  local oldChance = move.effectChance
  move.effectChance = 255
  local battle = newBattle(spec.id)
  perform(battle, spec.id)
  move.effectChance = oldChance
  for _, statName in ipairs({ "attack", "defense", "speed", "specialAttack", "specialDefense" }) do
    T.eq(stage(battle.player, statName), 1,
      "AncientPower raises " .. statName .. " when its effect succeeds")
  end
end

Probes.future_sight = function(spec)
  local battle = newBattle(spec.id)
  -- Isolate delayed-damage timing from Snorlax's generated Leftovers.
  battle.enemy.mon.heldItem = nil
  local before = battle.enemy.mon.hp
  perform(battle, spec.id)
  T.eq(battle.enemy.mon.hp, before, "Future Sight does not damage immediately")
  Runtime.emit("battle.turn_ended", { battle = battle, turn = 1 })
  Runtime.emit("battle.turn_ended", { battle = battle, turn = 2 })
  T.eq(battle.enemy.mon.hp, before, "Future Sight remains pending for two turns")
  Runtime.emit("battle.turn_ended", { battle = battle, turn = 3 })
  T.check(battle.enemy.mon.hp < before, "Future Sight lands on the delayed turn")
end

Probes.beat_up = function(spec)
  local a = Pokemon.new(data, "MEW", 50, function() return 15 end)
  local b = Pokemon.new(data, "RATTATA", 20, function() return 15 end)
  local c = Pokemon.new(data, "BULBASAUR", 20, function() return 15 end)
  a.moves = { { id = spec.id, pp = 10 } }
  c.status = "PSN"
  local battle = newBattle(spec.id, { party = { a, b, c } })
  perform(battle, spec.id, a.moves[1])
  T.check(hasText(battle, "2 times!"),
    "Beat Up hits once for each healthy, status-free party member")
end

-- -------------------------------------------------------------------------
-- Registry/data coverage: every Crystal move is specified once, is loaded
-- from the ROM unchanged, and has a real effect record rather than a silent
-- placeholder.  The behavior probes below then check the intended mechanic.
-- -------------------------------------------------------------------------

T.eq(#Specs, 86, "the parity manifest covers all 86 Generation II moves")
local seen = {}
for offset, spec in ipairs(Specs) do
  T.eq(spec.index, 165 + offset, spec.id .. " keeps its canonical move index")
  T.check(not seen[spec.id], spec.id .. " appears once in the parity manifest")
  seen[spec.id] = true

  local live = data.moves[spec.id]
  local imported = cacheById[spec.id]
  T.check(live ~= nil, spec.id .. " exists in the merged move registry")
  T.check(imported ~= nil, spec.id .. " exists in the Crystal extraction")
  if live and imported then
    for _, field in ipairs({ "index", "power", "type", "accuracy", "pp",
      "effectChance", "crystalAnim" }) do
      T.eq(live[field], imported[field], spec.id .. " preserves ROM " .. field)
    end
    local record = data.move_effects and data.move_effects[live.effect]
    T.check(record ~= nil, spec.id .. " resolves to an effect record")
    T.check(not record or record.implemented ~= false,
      spec.id .. " is not backed by an unimplemented placeholder")
  end

  local probe = Probes[spec.probe]
  T.check(type(probe) == "function", spec.id .. " has a behavioral probe")
  if probe then
    local ok, err = pcall(probe, spec)
    T.check(ok, spec.id .. " intended effect: " .. spec.summary
      .. (ok and "" or " (" .. tostring(err) .. ")"))
  end
end

for id, move in pairs(data.moves) do
  if move.index and move.index >= 166 and move.index <= 251 then
    T.check(seen[id], id .. " is represented in the Crystal move parity manifest")
  end
end

run.release()
T.finish("Crystal move parity")
