package.path = "./?.lua;./?/init.lua;" .. package.path

local Runtime = require("src.mods.Runtime")
Runtime.events = Runtime.events or { emit=function() end }

local Items = require("mods.CRYSTAL_251.battle.crystal_items")

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

local function move(id, pp)
  return { id=id, pp=pp == nil and 10 or pp }
end

local function battler(species, isPlayer, item, hp, maxhp)
  maxhp = maxhp or 160
  return {
    isPlayer=isPlayer,
    name=species,
    crystal251Active=true,
    stages={},
    curTypes={ "NORMAL" },
    mon={
      species=species,
      heldItem=item,
      hp=hp or maxhp,
      level=50,
      status=nil,
      stats={ hp=maxhp },
      moves={},
    },
  }
end

local function battle(player, enemy, rolls)
  local at = 0
  local b = {
    player=player,
    enemy=enemy,
    crystal251Active=true,
    messages={},
    data={ items={} },
  }
  function b.rng(low, high)
    at = at + 1
    local value = rolls and rolls[at]
    return value == nil and low or value
  end
  function b:sayNext(text) self.messages[#self.messages + 1] = text end
  function b:drainNext() self.drained = true end
  return b
end

local slots = { common="BERRY", rare="GOLD_BERRY" }
eq(Items.rollWildHeldItem(slots, function() return 0 end), "GOLD_BERRY",
  "wild held rare slot starts at zero")
eq(Items.rollWildHeldItem(slots, function() return 4 end), "GOLD_BERRY",
  "wild held rare slot includes four")
eq(Items.rollWildHeldItem(slots, function() return 5 end), "BERRY",
  "wild held common slot starts at five")
eq(Items.rollWildHeldItem(slots, function() return 63 end), "BERRY",
  "wild held common slot includes sixty-three")
eq(Items.rollWildHeldItem(slots, function() return 64 end), nil,
  "wild held no-item range starts at sixty-four")
eq(Items.rollWildHeldItem(slots, function() return 255 end), nil,
  "wild held no-item range includes two-fifty-five")
eq(Items.rollWildHeldItem(nil, function() return 0 end), nil,
  "wild species without slots has no item")

local chansey = battler("CHANSEY", true, "LUCKY_PUNCH")
eq(Items.criticalStage(chansey, {}), 2, "Lucky Punch adds two critical stages")
chansey.mon.species = "BLISSEY"
eq(Items.criticalStage(chansey, {}), 0, "Lucky Punch is Chansey-specific")
local farfetchd = battler("FARFETCHD", true, "STICK")
eq(Items.criticalStage(farfetchd, {}), 2, "Stick adds two Farfetch'd critical stages")
farfetchd.mon.heldItem = "SCOPE_LENS"
eq(Items.criticalStage(farfetchd, {}), 1, "Scope Lens adds one critical stage")
farfetchd.crystal251Battle = { transformedSpecies="CHANSEY" }
farfetchd.mon.heldItem = "LUCKY_PUNCH"
eq(Items.criticalStage(farfetchd, {}), 2,
  "transformed battle species drives species critical items")

local cubone = battler("CUBONE", true, "THICK_CLUB")
local target = battler("DITTO", false, nil)
local attack, defense = Items.modifyDamageStats(cubone, target, "physical", 100, 100)
eq(attack, 200, "Thick Club doubles Cubone physical Attack")
eq(defense, 100, "Thick Club leaves Defense unchanged")
attack = Items.modifyDamageStats(cubone, target, "special", 100, 100)
eq(attack, 100, "Thick Club does not boost special damage")
cubone.mon.species = "PIKACHU"
cubone.mon.heldItem = "LIGHT_BALL"
attack = Items.modifyDamageStats(cubone, target, "special", 100, 100)
eq(attack, 200, "Light Ball doubles Pikachu Special Attack")
attack = Items.modifyDamageStats(cubone, target, "physical", 100, 100)
eq(attack, 100, "Light Ball does not boost physical damage")
cubone.mon.species = "RAICHU"
attack = Items.modifyDamageStats(cubone, target, "special", 100, 100)
eq(attack, 100, "Light Ball is Pikachu-specific")

local attacker = battler("MEW", true, nil)
local ditto = battler("DITTO", false, "METAL_POWDER")
attack, defense = Items.modifyDamageStats(attacker, ditto, "physical", 200, 200)
eq(attack, 100, "Metal Powder overflow halves Attack with Defense")
eq(defense, 150, "Metal Powder preserves the one-and-a-half Defense ratio")
ditto.crystal251Battle = { transformed=true, transformedSpecies="MEW" }
attack, defense = Items.modifyDamageStats(attacker, ditto, "physical", 100, 100)
eq(defense, 100, "transformed Ditto loses Metal Powder's boost")

local boosters = {
  PINK_BOW="NORMAL", BLACKBELT_I="FIGHTING", SHARP_BEAK="FLYING",
  POISON_BARB="POISON", SOFT_SAND="GROUND", HARD_STONE="ROCK",
  SILVERPOWDER="BUG", SPELL_TAG="GHOST", CHARCOAL="FIRE",
  MYSTIC_WATER="WATER", MIRACLE_SEED="GRASS", MAGNET="ELECTRIC",
  TWISTEDSPOON="PSYCHIC_TYPE", NEVERMELTICE="ICE",
  DRAGON_SCALE="DRAGON", BLACKGLASSES="DARK", METAL_COAT="STEEL",
}
for item, typeId in pairs(boosters) do
  local user = battler("MEW", true, item)
  eq(Items.modifyBaseDamage(user, { type=typeId }, 100), 110,
    item .. " boosts its Crystal type by ten percent")
end
local dragon = battler("DRATINI", true, "DRAGON_FANG")
eq(Items.modifyBaseDamage(dragon, { type="DRAGON" }, 100), 100,
  "Dragon Fang does not boost Dragon in Crystal")

local brightTarget = battler("MEW", false, "BRIGHTPOWDER")
local brightCtx = { target=brightTarget, rng=function() return 79 end }
local hit = Items.withBrightPowder(function(ctx) return ctx.rng(0, 255) < 100 end,
  brightCtx)
eq(hit, true, "BrightPowder leaves a roll below the reduced boundary hitting")
brightCtx.rng = function() return 80 end
hit = Items.withBrightPowder(function(ctx) return ctx.rng(0, 255) < 100 end,
  brightCtx)
eq(hit, false, "BrightPowder subtracts twenty from accuracy")

local slow = battler("SLOW", true, "QUICK_CLAW")
local fast = battler("FAST", false, nil)
local first = Items.firstMover(function() return false end, slow, {}, fast, {},
  { rng=function() return 59 end })
eq(first, true, "Quick Claw activates below sixty")
first = Items.firstMover(function() return false end, slow, {}, fast, {},
  { rng=function() return 60 end })
eq(first, false, "Quick Claw fails at the sixty boundary")
first = Items.firstMover(function() return false end, slow, {priority=0},
  fast, {priority=1}, { rng=function() return 0 end })
eq(first, false, "Quick Claw cannot override move priority")
fast.mon.heldItem = "QUICK_CLAW"
local sequence, pos = { 59 }, 0
first = Items.firstMover(function() return true end, slow, {}, fast, {}, {
  rng=function() pos=pos+1 return sequence[pos] or 255 end,
})
eq(first, false, "when both hold Quick Claw the enemy-side check runs first")
pos = 0
first = Items.firstMover(function() return false end, slow, {}, fast, {}, {
  invertTie=true,
  rng=function() pos=pos+1 return sequence[pos] or 255 end,
})
eq(first, true, "link player two reverses the both-Quick-Claw checks")

local smoke = battler("MEW", true, "SMOKE_BALL")
local smokeBattle = battle(smoke, battler("MEWTWO", false, nil))
smoke.cantEscape = true
eq(Items.run(function() return false end, { battle=smokeBattle }), true,
  "Smoke Ball guarantees escape even while trapped")
eq(smoke.mon.heldItem, "SMOKE_BALL", "Smoke Ball remains held after escape")

local focus = battler("MEW", true, "FOCUS_BAND", 80, 80)
local focusBattle = battle(focus, battler("DITTO", false), { 29 })
local damage, proc = Items.focusBandDamage(focusBattle, focus, 80)
eq(damage, 79, "Focus Band leaves one HP")
eq(proc, true, "Focus Band reports activation")
focusBattle = battle(focus, battler("DITTO", false), { 30 })
damage, proc = Items.focusBandDamage(focusBattle, focus, 80)
eq(damage, 80, "Focus Band fails at thirty")
eq(proc, false, "failed Focus Band reports no activation")
focus.substituteHP = 10
focusBattle = battle(focus, battler("DITTO", false), { 0 })
damage = Items.focusBandDamage(focusBattle, focus, 80)
eq(damage, 80, "Focus Band does not protect a Substitute")

local king = battler("MEW", true, "KINGS_ROCK")
local victim = battler("DITTO", false, nil)
local kingBattle = battle(king, victim)
local kingCtx = {
  battle=kingBattle, user=king, target=victim, totalDealt=20,
  brokeSub=false, rng=function() return 29 end,
  move={ id="TACKLE", index=33, effect="NO_ADDITIONAL_EFFECT",
    power=35, type="NORMAL", category="physical" },
}
eq(Items.afterDamagingMove(kingCtx), true, "King's Rock flinches below thirty")
eq(victim.flinched, true, "King's Rock sets the target flinch")
victim.flinched = nil
kingCtx.rng = function() return 30 end
eq(Items.afterDamagingMove(kingCtx), false, "King's Rock fails at thirty")
kingCtx.rng = function() return 0 end
kingCtx.brokeSub = true
eq(Items.afterDamagingMove(kingCtx), false, "King's Rock cannot flinch through Substitute")

local statusCases = {
  { "PSNCUREBERRY", "PSN" }, { "PRZCUREBERRY", "PAR" },
  { "BURNT_BERRY", "FRZ" }, { "ICE_BERRY", "BRN" },
  { "MINT_BERRY", "SLP" }, { "MIRACLEBERRY", "PSN" },
}
for _, row in ipairs(statusCases) do
  local user = battler("MEW", true, row[1])
  user.mon.status = row[2]
  user.sleepTurns, user.toxicCounter, user.nightmare = 3, 4, true
  local b = battle(user, battler("DITTO", false))
  eq(Items.onStatusInflicted(b, user), true, row[1] .. " cures its status")
  eq(user.mon.status, nil, row[1] .. " clears major status")
  eq(user.mon.heldItem, nil, row[1] .. " is consumed")
end
local wrong = battler("MEW", true, "PSNCUREBERRY")
wrong.mon.status = "BRN"
local wrongBattle = battle(wrong, battler("DITTO", false))
eq(Items.onStatusInflicted(wrongBattle, wrong), false,
  "a status berry ignores the wrong status")
eq(wrong.mon.heldItem, "PSNCUREBERRY", "wrong status does not consume the berry")

local confused = battler("MEW", true, "BITTER_BERRY")
confused.confusedTurns = 3
local confusionBattle = battle(confused, battler("DITTO", false))
eq(Items.onConfusionInflicted(confusionBattle, confused), true,
  "Bitter Berry cures confusion")
eq(confused.confusedTurns, nil, "Bitter Berry clears the confusion counter")
eq(confused.mon.heldItem, nil, "Bitter Berry is consumed")

local berry = battler("MEW", true, "BERRY", 79, 160)
local berryBattle = battle(berry, battler("DITTO", false))
Items.endTurn(berryBattle)
eq(berry.mon.hp, 89, "Berry restores ten HP below half")
eq(berry.mon.heldItem, nil, "Berry is consumed after healing")
berry = battler("MEW", true, "BERRY", 80, 160)
berryBattle = battle(berry, battler("DITTO", false))
Items.endTurn(berryBattle)
eq(berry.mon.hp, 80, "Berry does not trigger at exactly half")
eq(berry.mon.heldItem, "BERRY", "exact-half Berry is retained")
local juice = battler("MEW", true, "BERRY_JUICE", 40, 160)
Items.endTurn(battle(juice, battler("DITTO", false)))
eq(juice.mon.hp, 60, "Berry Juice restores twenty HP")
local gold = battler("MEW", true, "GOLD_BERRY", 40, 160)
Items.endTurn(battle(gold, battler("DITTO", false)))
eq(gold.mon.hp, 70, "Gold Berry restores thirty HP")
local leftovers = battler("MEW", true, "LEFTOVERS", 100, 160)
Items.endTurn(battle(leftovers, battler("DITTO", false)))
eq(leftovers.mon.hp, 110, "Leftovers restores one sixteenth max HP")
eq(leftovers.mon.heldItem, "LEFTOVERS", "Leftovers is not consumed")

local mystery = battler("MEW", true, "MYSTERYBERRY")
mystery.curMoves = { move("SURF", 0), move("TACKLE", 0) }
Items.endTurn(battle(mystery, battler("DITTO", false)))
eq(mystery.curMoves[1].pp, 5, "MysteryBerry restores five PP to the first empty move")
eq(mystery.curMoves[2].pp, 0, "MysteryBerry restores only one move")
eq(mystery.mon.heldItem, nil, "MysteryBerry is consumed")
local sketch = battler("SMEARGLE", true, "MYSTERYBERRY")
sketch.curMoves = { move("SKETCH", 0) }
Items.endTurn(battle(sketch, battler("DITTO", false)))
eq(sketch.curMoves[1].pp, 1, "MysteryBerry restores one PP to Sketch")

local gene = battler("MEW", true, "BERSERK_GENE")
local geneBattle = battle(gene, battler("DITTO", false))
Items.beginTurn(geneBattle)
eq(gene.stages.attack, 2, "Berserk Gene raises Attack two stages")
eq(gene.confusedTurns, 256, "Berserk Gene creates the Crystal 256-turn counter")
eq(gene.mon.heldItem, nil, "Berserk Gene is consumed")
Items.beginTurn(geneBattle)
eq(gene.stages.attack, 2, "consumed Berserk Gene cannot activate twice")
local prior = battler("MEW", true, "BERSERK_GENE")
prior.confusedTurns = 3
Items.beginTurn(battle(prior, battler("DITTO", false)))
eq(prior.confusedTurns, 3, "Berserk Gene preserves the previous confusion count bug")

check(Items.isMail("FLOWER_MAIL"), "Flower Mail is recognized as mail")
check(Items.isMail("MUSIC_MAIL"), "Music Mail is recognized as mail")
eq(Items.isMail("LEFTOVERS"), false, "ordinary held items are not mail")

local thief = battler("MEW", true, nil)
local holder = battler("DITTO", false, "LEFTOVERS")
local thiefBattle = battle(thief, holder)
local said
local thiefCtx = {
  battle=thiefBattle, user=thief, target=holder, totalDealt=20,
  brokeSub=false, data=thiefBattle.data,
  say=function(text) said=text end,
}
eq(Items.steal(thiefCtx), true, "Thief transfers an item after damage")
eq(thief.mon.heldItem, "LEFTOVERS", "Thief gives the item to the user")
eq(holder.mon.heldItem, nil, "Thief removes the target item")
check(said and said:find("stole", 1, true), "Thief emits its success text")
thief.mon.heldItem, holder.mon.heldItem = "BERRY", "LEFTOVERS"
eq(Items.steal(thiefCtx), false, "Thief fails while the user holds an item")
thief.mon.heldItem, holder.mon.heldItem = nil, "FLOWER_MAIL"
eq(Items.steal(thiefCtx), false, "Thief cannot steal mail")
holder.mon.heldItem, holder.substituteHP = "LEFTOVERS", 10
eq(Items.steal(thiefCtx), false, "Thief cannot steal through Substitute")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal held items)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal held items)"):format(checks, checks))
