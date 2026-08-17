package.path = "./?.lua;./?/init.lua;" .. package.path

local draws = {}
local colors = {}
local canvas = "screen"

_G.love = {
  graphics = {
    setColor=function(r,g,b,a) colors[#colors + 1] = {r,g,b,a} end,
    getCanvas=function() return canvas end,
    setCanvas=function(value) canvas = value or "screen" end,
  },
}

package.loaded["src.render.Font"] = {
  draw=function(text,x,y)
    draws[#draws + 1] = { text=text, x=x, y=y, canvas=canvas }
    local n = 0
    for _ in tostring(text):gmatch("[\0-\127\194-\244][\128-\191]*") do n = n + 1 end
    return n * 8
  end,
}

local BattleState = {}
function BattleState:drawHUDs(slide)
  self.baseHudDraws = (self.baseHudDraws or 0) + 1
  local Font = require("src.render.Font")
  if self.enemy and not self.showEnemyTrainer then
    Font.draw(self.enemy.name, 8, 0)
    if self.enemy.shownStatus then
      Font.draw(self.enemy.shownStatus, 40, 8)
    else
      Font.draw(tostring(self.enemy.mon.level), 40, 8)
    end
  end
  if self.player and not self.showPlayerBack then
    Font.draw(self.player.name, 80, 56)
    if self.player.shownStatus then
      Font.draw(self.player.shownStatus, 120, 64)
    else
      Font.draw(tostring(self.player.mon.level), 120, 64)
    end
  end
  return slide
end
function BattleState:draw()
  if self.customUi then return self:customUi() end
  return self:drawHUDs(0)
end
local SummaryMenu = {
  draw=function(self) self.baseSummaryDraws = (self.baseSummaryDraws or 0) + 1 end,
}
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.ui.SummaryMenu"] = SummaryMenu
package.loaded["mods.CRYSTAL_251.battle.crystal_gender"] = nil

local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n"):format(label, tostring(got), tostring(want)))
  end
end
local function ok(value, label) eq(not not value, true, label) end
local function mon(species, attack, speed)
  return { species=species, dvs={ attack=attack, speed=speed } }
end
local function findDraw(text, x, y, targetCanvas, from)
  for i = from or 1, #draws do
    local row = draws[i]
    if row.text == text and row.x == x and row.y == y
        and (targetCanvas == nil or row.canvas == targetCanvas) then
      return row
    end
  end
end

local freshCache = { species={} }
for i = 1, 251 do freshCache.species[i] = { crystalGenderRatio=127 } end
ok(Gender.cacheHasRatios(freshCache), "complete gender cache is accepted")
freshCache.species[25].crystalGenderRatio = nil
eq(Gender.cacheHasRatios(freshCache), false, "cache missing a gender ratio is rejected")
freshCache.species[25].crystalGenderRatio = 256
eq(Gender.cacheHasRatios(freshCache), false, "cache with an invalid gender ratio is rejected")

Gender.setRatio("GENDERLESS", 255)
Gender.setRatio("MALE_ONLY", 0)
Gender.setRatio("FEMALE_ONLY", 254)
Gender.setRatio("ONE_EIGHTH", 31)
Gender.setRatio("HALF", 127)

eq(Gender.forMon(mon("GENDERLESS", 0, 0)), nil, "genderless ratio has no gender")
eq(Gender.forMon(mon("MALE_ONLY", 0, 0)), "M", "male-only ratio ignores DVs")
eq(Gender.forMon(mon("FEMALE_ONLY", 15, 15)), "F", "female-only ratio ignores DVs")
eq(Gender.dvByte(mon("ONE_EIGHTH", 1, 15)), 31, "gender byte combines Attack and Speed DVs")
eq(Gender.forMon(mon("ONE_EIGHTH", 1, 15)), "F", "ratio equality is female")
eq(Gender.forMon(mon("ONE_EIGHTH", 2, 0)), "M", "value above ratio is male")
eq(Gender.forMon(mon("HALF", 7, 15)), "F", "half ratio includes byte 127")
eq(Gender.forMon(mon("HALF", 8, 0)), "M", "half ratio excludes byte 128")
local stale = mon("ONE_EIGHTH", 2, 0)
stale.gender = "F"
eq(Gender.forMon(stale), "M", "stored gender does not override Crystal DVs")
eq(Gender.symbol(mon("MALE_ONLY", 0, 0)), "♂", "male symbol")
eq(Gender.symbol(mon("FEMALE_ONLY", 0, 0)), "♀", "female symbol")
package.loaded["src.core.Data"] = { pokemon={ MERGED_RATIO={ crystalGenderRatio=0 } } }
eq(Gender.forMon(mon("MERGED_RATIO", 0, 0)), "M", "merged species data supplies a missing runtime ratio")

local hooks = {}
local modernLoaded = false
local compatibilityMod = {
  find=function(id)
    if id == "gen1_modern_ui" and modernLoaded then return { id=id } end
    return nil
  end,
  hooks={ wrap=function(_, name, callback, priority)
    hooks[name] = { callback=callback, priority=priority }
  end },
  events={ on=function() end },
}
eq(Gender.installCompatibility(compatibilityMod), true, "gender compatibility installs once")
eq(hooks["gender.roll"].priority, 100, "gender provider keeps explicit priority")
eq(hooks["battle.overlay"].priority, math.huge, "battle overlay tracker surrounds UI hook rendering")
eq(hooks["render.zones"].priority, math.huge, "render zones refreshes semantic gender before UI presentation")
eq(hooks["render.hud"].priority, 101, "modern UI fallback wraps the retired presenter without owning later UI hooks")

eq(Gender.installRuntime(), true, "gender runtime installs once")
eq(Gender.installRuntime(), false, "gender runtime is idempotent")

local battle = {
  crystal251Active=true, frame=10, introSlide=0,
  enemy={ name="ENEMY", mon=mon("FEMALE_ONLY",15,15) },
  player={ name="PLAYER", mon=mon("MALE_ONLY",0,0) },
}
battle.enemy.mon.level, battle.player.mon.level = 50, 50
local game = {
  mods={ modOptions={} },
  stack={ states={ battle } },
}
function game.stack:top() return self.states[#self.states] end
battle.game = game

battle.enemy.mon.gender, battle.player.mon.gender = nil, nil
battle.enemy.gender, battle.player.gender = nil, nil
hooks["render.zones"].callback(function(_, zones) return zones end, game, {})
eq(battle.enemy.mon.gender, "female", "render refresh publishes enemy mon gender")
eq(battle.player.mon.gender, "male", "render refresh publishes player mon gender")
eq(battle.enemy.gender, "female", "render refresh publishes enemy battler facade gender")
eq(battle.player.gender, "male", "render refresh publishes player battler facade gender")

BattleState.drawHUDs(battle, 0)
eq(battle.baseHudDraws, 1, "detached native HUD draw remains callable")
ok(findDraw("♀", 72, 8), "native enemy gender stays inside the HUD source")
ok(findDraw("♂", 136, 64), "native player gender stays inside the HUD source")

battle.enemy.shownStatus, battle.player.shownStatus = "PSN", "BRN"
local statusStart = #draws + 1
BattleState.drawHUDs(battle, 0)
ok(findDraw("PSN", 48, 8, nil, statusStart), "native enemy status leaves room for gender")
ok(findDraw("♀", 72, 8, nil, statusStart), "native enemy status and gender share one HUD draw")
ok(findDraw("BRN", 112, 64, nil, statusStart), "native player status leaves room for gender")
ok(findDraw("♂", 136, 64, nil, statusStart), "native player status and gender share one HUD draw")
battle.enemy.shownStatus, battle.player.shownStatus = nil, nil

local customStart = #draws + 1
battle.customUi = function(self)
  local Font = require("src.render.Font")
  Font.draw(self.enemy.name, 220, 12)
  Font.draw(tostring(self.enemy.mon.level), 252, 20)
  Font.draw(self.player.name, 12, 70)
  Font.draw(tostring(self.player.mon.level), 52, 78)
end
BattleState.draw(battle)
ok(findDraw("♀", 268, 20, nil, customStart), "enemy gender follows an arbitrary UI level position")
ok(findDraw("♂", 68, 78, nil, customStart), "player gender follows an arbitrary UI level position")

local hookStart = #draws + 1
hooks["battle.overlay"].callback(function(live)
  local Font = require("src.render.Font")
  Font.draw(live.enemy.name, 31, 33)
  Font.draw(tostring(live.enemy.mon.level), 95, 33)
  Font.draw(live.player.name, 180, 91)
  Font.draw(tostring(live.player.mon.level), 260, 91)
end, battle)
ok(findDraw("♀", 111, 33, nil, hookStart), "hook-rendered enemy HUD carries its gender")
ok(findDraw("♂", 276, 91, nil, hookStart), "hook-rendered player HUD carries its gender")

local capturedStart = #draws + 1
canvas = "hud-layer"
BattleState.drawHUDs(battle, 0)
canvas = "screen"
ok(findDraw("♀", 72, 8, "hud-layer", capturedStart), "captured enemy HUD contains gender before relocation")
ok(findDraw("♂", 136, 64, "hud-layer", capturedStart), "captured player HUD contains gender before relocation")

local before = #draws
battle.showEnemyTrainer = true
battle.showPlayerBack = true
BattleState.drawHUDs(battle, 0)
eq(#draws, before, "hidden native HUDs emit no gender")
battle.showEnemyTrainer, battle.showPlayerBack = false, false

modernLoaded = true
game.mods.modOptions.gen1_modern_ui = { battleUiWip=true }
local duringEnemy, duringPlayer
hooks["render.hud"].callback(function()
  duringEnemy, duringPlayer = battle.enemy.name, battle.player.name
end, game, {})
eq(duringEnemy, "ENEMY♀", "Modern UI sees gender attached to the enemy display name")
eq(duringPlayer, "PLAYER♂", "Modern UI sees gender attached to the player display name")
eq(battle.enemy.name, "ENEMY", "Modern UI enemy display-name fallback restores battle state")
eq(battle.player.name, "PLAYER", "Modern UI player display-name fallback restores battle state")

game.mods.modOptions.gen1_modern_ui.battleUiWip = false
local disabledEnemy, disabledPlayer
hooks["render.hud"].callback(function()
  disabledEnemy, disabledPlayer = battle.enemy.name, battle.player.name
end, game, {})
eq(disabledEnemy, "ENEMY", "disabled Modern battle UI does not rewrite enemy presentation")
eq(disabledPlayer, "PLAYER", "disabled Modern battle UI does not rewrite player presentation")

local summary = { mon=mon("FEMALE_ONLY",15,15) }
SummaryMenu.draw(summary)
eq(summary.baseSummaryDraws, 1, "summary wrapper preserves engine draw")
ok(findDraw("♀", 144, 0), "summary gender uses Crystal coordinate")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal gender)\n"):format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal gender)"):format(checks, checks))
