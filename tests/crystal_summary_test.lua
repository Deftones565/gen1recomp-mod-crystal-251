package.path = "./?.lua;./?/init.lua;" .. package.path

local draws, rectangles, colors = {}, {}, {}
_G.love = {
  graphics = {
    setColor=function(r,g,b,a)
      colors[#colors + 1] = {r,g,b,a}
    end,
    rectangle=function(mode,x,y,w,h)
      rectangles[#rectangles + 1] = {mode=mode,x=x,y=y,w=w,h=h}
    end,
  },
}

package.loaded["src.render.Font"] = {
  draw=function(text,x,y)
    draws[#draws + 1] = {text=text,x=x,y=y}
  end,
}

local calculatedWith
package.loaded["mods.CRYSTAL_251.battle.crystal_damage"] = {
  calculateStats=function(mon, base)
    calculatedWith = {mon=mon,base=base}
    return {
      attack=70,
      defense=65,
      specialAttack=150,
      specialDefense=100,
      speed=125,
    }
  end,
}

local SummaryMenu = {
  draw=function(self)
    self.baseDraws = (self.baseDraws or 0) + 1
    return "base"
  end,
}
package.loaded["src.ui.SummaryMenu"] = SummaryMenu
package.loaded["mods.CRYSTAL_251.battle.crystal_summary"] = nil

local Summary = require("mods.CRYSTAL_251.battle.crystal_summary")

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
local function findDraw(text, x, y)
  for _, draw in ipairs(draws) do
    if draw.text == text and draw.x == x and draw.y == y then return draw end
  end
end

local base = {attack=55,defense=50,specialAttack=135,specialDefense=85,speed=120}
Summary.configure({ALAKAZAM=base})
eq(Summary.installRuntime(), true, "summary runtime installs once")
eq(Summary.installRuntime(), false, "summary runtime is idempotent")

local menu = {
  page=1,
  mon={species="ALAKAZAM",level=50,dvs={special=10},statExp={special=0}},
}
eq(SummaryMenu.draw(menu), "base", "summary wrapper preserves engine draw result")
eq(menu.baseDraws, 1, "summary wrapper preserves engine draw")
eq(calculatedWith.mon, menu.mon, "summary uses the displayed monster")
eq(calculatedWith.base, base, "summary uses configured Crystal base stats")

local clear = rectangles[#rectangles]
eq(clear.mode, "fill", "legacy stat panel is cleared")
eq(clear.x, 8, "stat panel clear x")
eq(clear.y, 72, "stat panel clear y")
eq(clear.w, 64, "stat panel clear width")
eq(clear.h, 64, "stat panel clear height")

ok(findDraw("ATK", 8, 72), "Attack label is shown")
ok(findDraw("DEF", 8, 84), "Defense label is shown")
ok(findDraw("S.ATK", 8, 96), "Special Attack label is shown")
ok(findDraw("S.DEF", 8, 108), "Special Defense label is shown")
ok(findDraw("SPEED", 8, 120), "Speed label is shown")
ok(findDraw("150", 48, 96), "Special Attack value is shown")
ok(findDraw("100", 48, 108), "Special Defense value is shown")

local beforeDraws, beforeRects = #draws, #rectangles
SummaryMenu.draw({page=2,mon=menu.mon})
eq(#draws, beforeDraws, "move page does not receive the split-stat overlay")
eq(#rectangles, beforeRects, "move page is not cleared")

SummaryMenu.draw({page=1,mon={species="ALAKAZAM",isEgg=true}})
eq(#draws, beforeDraws, "Egg summary does not show hidden stats")
eq(#rectangles, beforeRects, "Egg summary stat panel is untouched")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal summary)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal summary)"):format(checks, checks))
