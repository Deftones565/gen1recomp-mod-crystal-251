package.path = "./?.lua;./?/init.lua;" .. package.path

local draws = {}
local colors = {}
local canvas = "screen"

_G.love = {
  graphics = {
    setColor=function(r,g,b,a)
      colors[#colors + 1] = {r,g,b,a}
    end,
    getCanvas=function() return canvas end,
    setCanvas=function(value) canvas = value or "screen" end,
  },
}

package.loaded["src.render.Font"] = {
  draw=function(text,x,y)
    draws[#draws + 1] = { text=text, x=x, y=y, canvas=canvas }
  end,
}

local BattleState = {
  drawHUDs=function(self, slide)
    self.baseHudDraws = (self.baseHudDraws or 0) + 1
    local Font = require("src.render.Font")
    if self.enemy and self.enemy.shownStatus then
      Font.draw(self.enemy.shownStatus, 40, 8)
    end
    if self.player and self.player.shownStatus then
      Font.draw(self.player.shownStatus, 120, 64)
    elseif self.player and self.player.mon and self.player.mon.level >= 100 then
      Font.draw(tostring(self.player.mon.level), 120, 64)
    end
    return slide
  end,
}
local SummaryMenu = {
  draw=function(self)
    self.baseSummaryDraws = (self.baseSummaryDraws or 0) + 1
  end,
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
    io.stderr:write(("FAIL %s (got %s, want %s)\n"):format(
      label, tostring(got), tostring(want)))
  end
end
local function ok(value, label) eq(not not value, true, label) end
local function mon(species, attack, speed)
  return { species=species, dvs={ attack=attack, speed=speed } }
end
local function findDraw(text, x, y, targetCanvas)
  for _, row in ipairs(draws) do
    if row.text == text and row.x == x and row.y == y
        and (targetCanvas == nil or row.canvas == targetCanvas) then
      return row
    end
  end
end

local freshCache = { species={} }
for i = 1, 251 do
  freshCache.species[i] = { crystalGenderRatio=127 }
end
ok(Gender.cacheHasRatios(freshCache), "complete gender cache is accepted")
freshCache.species[25].crystalGenderRatio = nil
eq(Gender.cacheHasRatios(freshCache), false,
  "cache missing a gender ratio is rejected")
freshCache.species[25].crystalGenderRatio = 256
eq(Gender.cacheHasRatios(freshCache), false,
  "cache with an invalid gender ratio is rejected")

Gender.setRatio("GENDERLESS", 255)
Gender.setRatio("MALE_ONLY", 0)
Gender.setRatio("FEMALE_ONLY", 254)
Gender.setRatio("ONE_EIGHTH", 31)
Gender.setRatio("HALF", 127)

eq(Gender.forMon(mon("GENDERLESS", 0, 0)), nil,
  "genderless ratio has no gender")
eq(Gender.forMon(mon("MALE_ONLY", 0, 0)), "M",
  "male-only ratio ignores DVs")
eq(Gender.forMon(mon("FEMALE_ONLY", 15, 15)), "F",
  "female-only ratio ignores DVs")
eq(Gender.dvByte(mon("ONE_EIGHTH", 1, 15)), 31,
  "gender byte combines Attack and Speed DVs")
eq(Gender.forMon(mon("ONE_EIGHTH", 1, 15)), "F",
  "ratio equality is female")
eq(Gender.forMon(mon("ONE_EIGHTH", 2, 0)), "M",
  "value above ratio is male")
eq(Gender.forMon(mon("HALF", 7, 15)), "F",
  "half ratio includes byte 127")
eq(Gender.forMon(mon("HALF", 8, 0)), "M",
  "half ratio excludes byte 128")
local stale = mon("ONE_EIGHTH", 2, 0)
stale.gender = "F"
eq(Gender.forMon(stale), "M", "stored gender does not override Crystal DVs")
eq(Gender.symbol(mon("MALE_ONLY", 0, 0)), "♂", "male symbol")
eq(Gender.symbol(mon("FEMALE_ONLY", 0, 0)), "♀", "female symbol")
package.loaded["src.core.Data"] = {
  pokemon={ MERGED_RATIO={ crystalGenderRatio=0 } },
}
eq(Gender.forMon(mon("MERGED_RATIO", 0, 0)), "M",
  "merged species data supplies a missing runtime ratio")

eq(Gender.installRuntime(), true, "gender runtime installs once")
eq(Gender.installRuntime(), false, "gender runtime is idempotent")

local battle = {
  crystal251Active=true, frame=10, introSlide=0,
  enemy={ mon=mon("FEMALE_ONLY",15,15) },
  player={ mon=mon("MALE_ONLY",0,0) },
}
battle.enemy.mon.level, battle.player.mon.level = 50, 50
BattleState.drawHUDs(battle, 0)
eq(battle.baseHudDraws, 1, "battle HUD wrapper preserves engine draw")
ok(findDraw("♀", 72, 8), "enemy gender uses Crystal HUD coordinate")
ok(findDraw("♂", 136, 64), "player gender uses Crystal HUD coordinate")

battle.enemy.shownStatus, battle.player.shownStatus = "PSN", "BRN"
BattleState.drawHUDs(battle, 0)
ok(findDraw("PSN", 48, 8), "enemy status shifts beside its gender symbol")
ok(findDraw("BRN", 112, 64), "player status shifts beside its gender symbol")
battle.enemy.shownStatus, battle.player.shownStatus = nil, nil
battle.player.mon.level = 100
BattleState.drawHUDs(battle, 0)
ok(findDraw("100", 112, 64), "level 100 leaves room for the player gender symbol")
battle.player.mon.level = 50

local before = #draws
battle.showEnemyTrainer = true
battle.showPlayerBack = true
BattleState.drawHUDs(battle, 0)
eq(#draws, before, "hidden battle HUDs omit gender symbols")

local summary = { mon=mon("FEMALE_ONLY",15,15) }
SummaryMenu.draw(summary)
eq(summary.baseSummaryDraws, 1, "summary wrapper preserves engine draw")
ok(findDraw("♀", 144, 0), "summary gender uses Crystal coordinate")

local OverworldBattle = {
  hudTexture=function(battle)
    local Font = require("src.render.Font")
    if battle.enemy and battle.enemy.shownStatus then
      Font.draw(battle.enemy.shownStatus, 40, 8)
    end
    if battle.player and battle.player.shownStatus then
      Font.draw(battle.player.shownStatus, 120, 64)
    end
    return "hud-layer"
  end,
}
local dramatic = {
  lib={ require=function(name)
    if name == "OverworldBattle" then return OverworldBattle end
  end },
}
eq(Gender.installDramatic(dramatic), true,
  "Dramatic Shape gender integration installs")
battle.showEnemyTrainer, battle.showPlayerBack = nil, nil
battle.frame = 11
OverworldBattle.hudTexture(battle, 0, true)
eq(battle._crystal251GenderHudSnappedFrame, 11,
  "snapped HUD records the rendered battle frame")
ok(findDraw("♀", 72, 8, "hud-layer"),
  "snapped enemy HUD receives its gender symbol")
ok(findDraw("♂", 136, 64, "hud-layer"),
  "snapped player HUD receives its gender symbol")
eq(canvas, "screen", "Dramatic Shape HUD restores the previous canvas")

local count = #draws
BattleState.drawHUDs(battle, 0)
eq(#draws, count, "snapped HUD suppresses duplicate center symbols")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal gender)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal gender)"):format(checks, checks))
