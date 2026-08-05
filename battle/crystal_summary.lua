local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")

local Summary = {}

local configuredBaseStats = {}

function Summary.configure(baseStats)
  configuredBaseStats = baseStats or {}
end

function Summary.statsFor(menu)
  local mon = menu and menu.mon
  if not mon then return nil end
  local base = configuredBaseStats[mon.species]
  if base then return CrystalDamage.calculateStats(mon, base) end
  local stats = mon.stats
  if stats and stats.specialAttack and stats.specialDefense then
    return stats
  end
  return nil
end

function Summary.drawSplitStats(menu)
  if not (menu and menu.page == 1 and menu.mon and not menu.mon.isEgg) then
    return false
  end
  local stats = Summary.statsFor(menu)
  if not stats then return false end

  local Font = require("src.render.Font")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 8, 72, 64, 64)
  love.graphics.setColor(0, 0, 0, 1)

  local rows = {
    { "ATK", stats.attack },
    { "DEF", stats.defense },
    { "S.ATK", stats.specialAttack },
    { "S.DEF", stats.specialDefense },
    { "SPEED", stats.speed },
  }
  for index, row in ipairs(rows) do
    local y = 72 + (index - 1) * 12
    Font.draw(row[1], 8, y)
    Font.draw(("%3d"):format(math.floor(tonumber(row[2]) or 0)), 48, y)
  end

  love.graphics.setColor(1, 1, 1, 1)
  return true
end

function Summary.installRuntime()
  local SummaryMenu = require("src.ui.SummaryMenu")
  if SummaryMenu._crystal251SpecialSplit then return false end
  SummaryMenu._crystal251SpecialSplit = true
  local originalDraw = SummaryMenu.draw
  SummaryMenu.draw = function(self)
    local result = originalDraw(self)
    Summary.drawSplitStats(self)
    return result
  end
  return true
end

return Summary
