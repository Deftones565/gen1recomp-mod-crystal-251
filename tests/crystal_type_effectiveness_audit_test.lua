-- Exhaustive ROM-backed audit of Crystal's type-effectiveness system.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local romPath = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(romPath, "rb")
if not file then
  print("SKIP Crystal type audit (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local run, cache = require("mods.CRYSTAL_251.tests._real_rom_mod").load(T, raw)
local Data = run.data
T.eq(#run.errors, 0, "Crystal 251 loads for the type audit")

local TypeChart = require("src.battle.TypeChart")
local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local data = run.data
TypeChart.load(data)

local TYPES = {
  "NORMAL", "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE",
  "FIGHTING", "POISON", "GROUND", "FLYING", "PSYCHIC_TYPE",
  "BUG", "ROCK", "GHOST", "DRAGON", "DARK", "STEEL",
}

-- Canonical Generation II non-neutral rows. Missing pairs are exactly 1x.
local ROWS = {
  NORMAL={ ROCK=5, GHOST=0, STEEL=5 },
  FIRE={ FIRE=5, WATER=5, GRASS=20, ICE=20, BUG=20, ROCK=5,
    DRAGON=5, STEEL=20 },
  WATER={ FIRE=20, WATER=5, GRASS=5, GROUND=20, ROCK=20, DRAGON=5 },
  ELECTRIC={ WATER=20, ELECTRIC=5, GRASS=5, GROUND=0, FLYING=20,
    DRAGON=5 },
  GRASS={ FIRE=5, WATER=20, GRASS=5, POISON=5, GROUND=20, FLYING=5,
    BUG=5, ROCK=20, DRAGON=5, STEEL=5 },
  ICE={ FIRE=5, WATER=5, GRASS=20, ICE=5, GROUND=20, FLYING=20,
    DRAGON=20, STEEL=5 },
  FIGHTING={ NORMAL=20, ICE=20, POISON=5, FLYING=5, PSYCHIC_TYPE=5,
    BUG=5, ROCK=20, GHOST=0, DARK=20, STEEL=20 },
  POISON={ GRASS=20, POISON=5, GROUND=5, ROCK=5, GHOST=5, STEEL=0 },
  GROUND={ FIRE=20, ELECTRIC=20, GRASS=5, POISON=20, FLYING=0,
    BUG=5, ROCK=20, STEEL=20 },
  FLYING={ ELECTRIC=5, GRASS=20, FIGHTING=20, BUG=20, ROCK=5, STEEL=5 },
  PSYCHIC_TYPE={ FIGHTING=20, POISON=20, PSYCHIC_TYPE=5, DARK=0,
    STEEL=5 },
  BUG={ FIRE=5, GRASS=20, FIGHTING=5, POISON=5, FLYING=5,
    PSYCHIC_TYPE=20, GHOST=5, DARK=20, STEEL=5 },
  ROCK={ FIRE=20, ICE=20, FIGHTING=5, GROUND=5, FLYING=20, BUG=20,
    STEEL=5 },
  GHOST={ NORMAL=0, PSYCHIC_TYPE=20, GHOST=20, DARK=5, STEEL=5 },
  DRAGON={ DRAGON=20, STEEL=5 },
  DARK={ FIGHTING=5, PSYCHIC_TYPE=20, GHOST=20, DARK=5, STEEL=5 },
  STEEL={ FIRE=5, WATER=5, ELECTRIC=5, ICE=20, ROCK=20, STEEL=5 },
}

local function expectedOne(attacking, defending)
  return (ROWS[attacking] and ROWS[attacking][defending]) or 10
end

local singles, duals = 0, 0
for _, attacking in ipairs(TYPES) do
  T.eq(TypeChart.category(attacking),
    ({ DARK="special", STEEL="physical" })[attacking]
      or ((attacking == "FIRE" or attacking == "WATER"
        or attacking == "ELECTRIC" or attacking == "GRASS"
        or attacking == "ICE" or attacking == "PSYCHIC_TYPE"
        or attacking == "DRAGON") and "special" or "physical"),
    attacking .. " has its Generation II damage category")
  for _, defending in ipairs(TYPES) do
    local want = expectedOne(attacking, defending)
    T.eq(TypeChart.effectiveness(attacking, { defending }), want,
      attacking .. " > " .. defending .. " single-type multiplier")

    local damage, multiplier, immune = CrystalDamage.applyStabType({
      battle={}, user={ curTypes={} }, target={ curTypes={ defending } },
      move={ id="AUDIT", type=attacking },
    }, 100)
    T.eq(multiplier, want, attacking .. " > " .. defending .. " damage metadata")
    T.eq(immune, want == 0, attacking .. " > " .. defending .. " immunity flag")
    T.eq(damage, want == 0 and 0 or math.floor(100 * want / 10),
      attacking .. " > " .. defending .. " damage scaling")
    singles = singles + 1
  end

  for first = 1, #TYPES do
    for second = first + 1, #TYPES do
      local type1, type2 = TYPES[first], TYPES[second]
      local one, two = expectedOne(attacking, type1), expectedOne(attacking, type2)
      local want = math.floor(one * two / 10)
      T.eq(TypeChart.effectiveness(attacking, { type1, type2 }), want,
        attacking .. " > " .. type1 .. "/" .. type2 .. " dual multiplier")

      local expectedDamage = 0
      if want > 0 then
        expectedDamage = math.max(1, math.floor(100 * one / 10))
        expectedDamage = math.max(1, math.floor(expectedDamage * two / 10))
      end
      local damage, multiplier, immune = CrystalDamage.applyStabType({
        battle={}, user={ curTypes={} }, target={ curTypes={ type1, type2 } },
        move={ id="AUDIT", type=attacking },
      }, 100)
      T.eq(multiplier, want,
        attacking .. " > " .. type1 .. "/" .. type2 .. " metadata")
      T.eq(immune, want == 0,
        attacking .. " > " .. type1 .. "/" .. type2 .. " immunity")
      T.eq(damage, expectedDamage,
        attacking .. " > " .. type1 .. "/" .. type2 .. " sequential scaling")
      duals = duals + 1
    end
  end
end

-- STAB, Struggle, and weather are ordered before effectiveness in Crystal.
for _, attacking in ipairs(TYPES) do
  local damage = CrystalDamage.applyStabType({
    battle={}, user={ curTypes={ attacking } }, target={ curTypes={} },
    move={ id="AUDIT", type=attacking },
  }, 100)
  T.eq(damage, 150, attacking .. " receives 1.5x same-type attack bonus")
end
local struggle = CrystalDamage.applyStabType({
  battle={}, user={ curTypes={ "NORMAL" } }, target={ curTypes={} },
  move={ id="STRUGGLE", type="NORMAL" },
}, 100)
T.eq(struggle, 100, "Struggle never receives STAB")
local rainFire = CrystalDamage.applyStabType({
  battle={ weather="rain" }, user={ curTypes={ "FIRE" } },
  target={ curTypes={ "GRASS" } }, move={ id="EMBER", type="FIRE" },
}, 100)
T.eq(rainFire, 150, "rain then STAB then super-effectiveness use Crystal ordering")

local function makeGame(party)
  local save = SaveData.newGame()
  save.party = party
  save.options = save.options or {}
  save.options.ruleset = "gen1_faithful"
  local stack = { states={} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return { data=data, save=save, stack=stack,
    input={ wasPressed=function() return true end } }
end

local function battleText(moveId, enemySpecies)
  local mon = Pokemon.new(data, "MEW", 50, function() return 15 end)
  mon.moves = { { id=moveId, pp=40 } }
  local battle = BattleState.newWild(makeGame({ mon }), enemySpecies, 50)
  battle.phase, battle.turnCount = "menu", 1
  battle.rng = function(low, high)
    -- Land the 1-in-256 accuracy check while leaving damage variation at its
    -- maximum. Other byte rolls are irrelevant to effectiveness messaging.
    if low == 0 and high == 255 then return 0 end
    return high
  end
  battle:performMove(battle.player, battle.enemy, mon.moves[1])
  local text = {}
  for _, row in ipairs(battle.queue or {}) do
    if row.text then text[#text + 1] = row.text:gsub("\n", " ") end
  end
  return table.concat(text, " | "), battle
end

local superText = battleText("THUNDERBOLT", "GYARADOS")
T.check(superText:find("super effective", 1, true) ~= nil,
  "4x live matchup prints the super-effective message: " .. superText)
local resistText = battleText("MEGA_DRAIN", "DRAGONITE")
T.check(resistText:find("not very effective", 1, true) ~= nil,
  "quarter-effective live matchup prints the resistance message: " .. resistText)
local neutralText = battleText("EMBER", "LAPRAS")
T.check(neutralText:find("super effective", 1, true) == nil
    and neutralText:find("not very effective", 1, true) == nil,
  "dual-type neutralization prints no effectiveness message")
local immuneText, immuneBattle = battleText("TACKLE", "GASTLY")
T.check(immuneText:find("doesn't affect", 1, true) ~= nil,
  "immune live matchup prints the immunity message: " .. immuneText)
T.eq(immuneBattle.enemy.mon.hp, immuneBattle.enemy.mon.stats.hp,
  "immune live matchup deals zero damage")

run.release()
T.finish(("Crystal type-effectiveness audit (%d singles, %d duals)")
  :format(singles, duals))
