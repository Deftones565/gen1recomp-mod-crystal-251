package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n"):format(
      label, tostring(got), tostring(want)))
  end
end
local function ok(value, label) eq(not not value, true, label) end

local draws, rectangles = {}, 0
_G.love = { graphics={
  setColor=function() end,
  rectangle=function() rectangles = rectangles + 1 end,
} }
package.loaded["src.render.Font"] = {
  draw=function(text, x, y)
    draws[#draws + 1] = { text=text, x=x, y=y }
    local n = 0
    for _ in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n * 8
  end,
}

local BattleState = {
  drawHUDs=function(self)
    self.nativeHudDraws = (self.nativeHudDraws or 0) + 1
    local Font = require("src.render.Font")
    if self.enemy then
      Font.draw(self.enemy.name or "ENEMY", 8, 0)
      Font.draw(tostring(self.enemy.mon.level), 40, 8)
    end
    if self.player then
      Font.draw(self.player.name or "PLAYER", 80, 56)
      Font.draw(tostring(self.player.mon.level), 120, 64)
    end
  end,
}
local SummaryMenu = {
  draw=function(self)
    self.nativeSummaryDraws = (self.nativeSummaryDraws or 0) + 1
  end,
}
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.ui.SummaryMenu"] = SummaryMenu
package.loaded["mods.CRYSTAL_251.battle.crystal_gender"] = nil
package.loaded["mods.CRYSTAL_251.battle.crystal_summary"] = nil

local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
local Summary = require("mods.CRYSTAL_251.battle.crystal_summary")
Gender.resetForTests()
Gender.setRatio("FEMALE", 254)
Gender.setRatio("MALE", 0)
Gender.setRatio("GENDERLESS", 255)
Summary.configure({
  FEMALE={ hp=60, attack=70, defense=80, speed=90,
    specialAttack=100, specialDefense=110 },
  MALE={ hp=60, attack=70, defense=80, speed=90,
    specialAttack=120, specialDefense=130 },
  GENDERLESS={ hp=60, attack=70, defense=80, speed=90,
    specialAttack=80, specialDefense=90 },
})

local hooks, events = {}, {}
local mod = {
  find=function(id)
    if id == "gen3_battle_ui" then
      return { id=id, version="1.4.1", exports={} }
    end
  end,
  hooks={ wrap=function(_, name, callback, priority)
    hooks[name] = { callback=callback, priority=priority }
  end },
  events={ on=function(_, name, callback, priority)
    events[name] = events[name] or {}
    events[name][#events[name] + 1] = { callback=callback, priority=priority }
  end },
}

eq(Gender.installCompatibility(mod), true,
  "Gen 3 UI gender compatibility installs")
eq(Summary.installCompatibility(mod), true,
  "Gen 3 UI split-stat compatibility installs")
eq(hooks["gender.roll"].priority, 100,
  "Crystal gender provider has an explicit hook priority")
eq(hooks["battle.overlay"].priority, math.huge,
  "Crystal gender tracks hook-rendered battle UIs")

local female = {
  species="FEMALE", level=50,
  dvs={ attack=15, defense=10, speed=15, special=10 },
  statExp={}, stats={ hp=120, attack=1, defense=1, speed=1, special=1 },
}
local male = {
  species="MALE", level=50,
  dvs={ attack=0, defense=10, speed=0, special=10 },
  statExp={}, stats={ hp=120, attack=1, defense=1, speed=1, special=1 },
}
local genderless = {
  species="GENDERLESS", level=50, gender="female",
  dvs={ attack=0, defense=10, speed=0, special=10 },
  statExp={}, stats={ hp=120, attack=1, defense=1, speed=1, special=1 },
}
local game = {
  save={ party={female,genderless}, boxes={ { male } } },
  mods={ modOptions={} },
}
for _, listener in ipairs(events["game.ready"]) do
  listener.callback({ game=game })
end
eq(female.gender, "female", "Party receives Gen 3 UI's lowercase female value")
eq(male.gender, "male", "PC boxes receive Gen 3 UI's lowercase male value")
eq(genderless.gender, nil, "genderless species clear a stale presentation value")
ok(female.stats.specialAttack and female.stats.specialAttack ~= female.stats.special,
  "Party receives Crystal Special Attack for modern summaries")
ok(female.stats.specialDefense and female.stats.specialDefense ~= female.stats.special,
  "Party receives Crystal Special Defense for modern summaries")
ok(male.stats.specialAttack and male.stats.specialDefense,
  "PC boxes receive both split Special stats")

-- The real CONTINUE lifecycle emits {save=loaded} without a game field.
-- Existing Pokémon must still be prepared before Party/Summary/PC or battle.
female.gender, male.gender = nil, nil
female.stats.specialAttack, female.stats.specialDefense = nil, nil
for _, listener in ipairs(events["save.loaded"]) do
  listener.callback({ save=game.save })
end
eq(female.gender, "female", "save.loaded annotates an existing Party Pokémon")
eq(male.gender, "male", "save.loaded annotates an existing PC Pokémon")
ok(female.stats.specialAttack and female.stats.specialDefense,
  "save.loaded enriches an existing Pokémon's split stats")

female.gender, male.gender = nil, nil
local liveBattle = { player={ mon=female }, enemy={ mon=male } }
for _, listener in ipairs(events["battle.started"]) do
  listener.callback({ battle=liveBattle })
end
eq(female.gender, "female", "battle.started prepares the live player battler")
eq(male.gender, "male", "battle.started prepares the live enemy battler")

female.gender = nil
for _, listener in ipairs(events["battle.battler_switched"]) do
  listener.callback({ battle=liveBattle, battler={ mon=female } })
end
eq(female.gender, "female", "battle switch prepares the replacement battler")

local resolved = hooks["gender.roll"].callback(function() return "unknown" end, {
  species="FEMALE", def={ id="FEMALE", crystalGenderRatio=254 },
  dvs=female.dvs,
})
eq(resolved, "female", "battle gender.roll exposes Crystal gender to Gen 3 UI")
local delegated = hooks["gender.roll"].callback(function() return "male" end, {
  species="OTHER", def={ id="OTHER" }, dvs=male.dvs,
})
eq(delegated, "male", "non-Crystal gender providers remain in the hook chain")

eq(Gender.installRuntime(), true, "native gender runtime installs")
eq(Summary.installRuntime(), true, "native split-stat runtime installs")

local function glyphCount()
  local count = 0
  for _, draw in ipairs(draws) do
    if tostring(draw.text):find("♂",1,true) or tostring(draw.text):find("♀",1,true) then count=count+1 end
  end
  return count
end

local battle = {
  game=game, crystal251Active=true, introSlide=0,
  enemy={ name="ENEMY", mon=female }, player={ name="PLAYER", mon=male },
}
BattleState.drawHUDs(battle, 0)
eq(battle.nativeHudDraws, 1, "Gen 3 UI path preserves the wrapped native HUD lifecycle")
eq(glyphCount(), 0, "Crystal native gender glyph does not leak under the Gen 3 HUD")

local summary = { game=game, mon=female, page=1 }
SummaryMenu.draw(summary)
eq(summary.nativeSummaryDraws, 1,
  "Gen 3 UI path preserves the wrapped native Summary lifecycle")
eq(rectangles, 0, "Crystal native split-stat panel does not leak under Gen 3 Summary")
eq(glyphCount(), 0, "Crystal native Summary gender does not leak under Gen 3 Summary")

game.mods.modOptions.gen3_battle_ui = {
  revampedBattleUI=false, hideNativeBattleUI=false, revampedPokemonMenu=false,
}
BattleState.drawHUDs(battle, 0)
ok(glyphCount() >= 2, "turning off Gen 3 battle UI restores Crystal native gender")
local beforeRectangles = rectangles
SummaryMenu.draw(summary)
ok(rectangles > beforeRectangles,
  "turning off Gen 3 Pokemon UI restores Crystal split-stat panel")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal / Gen 3 UI compatibility)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal / Gen 3 UI compatibility)")
  :format(checks, checks))
