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

-- Modern presentation mods read the standard split-stat keys directly from
-- mon.stats.  Crystal's Gen I host normally has only `special`, so enrich the
-- existing table without replacing engine-owned HP or the original fields.
function Summary.enrich(mon)
  if type(mon) ~= "table" then return false end
  local stats = Summary.statsFor({ mon=mon })
  if not stats then return false end
  mon.stats = mon.stats or {}
  mon.stats.specialAttack = stats.specialAttack
  mon.stats.specialDefense = stats.specialDefense
  return true
end

function Summary.enrichSave(save)
  if type(save) ~= "table" then return 0 end
  local count = 0
  local function roster(rows)
    for _, mon in pairs(type(rows) == "table" and rows or {}) do
      if Summary.enrich(mon) then count = count + 1 end
    end
  end
  roster(save.party)
  for _, box in pairs(type(save.boxes) == "table" and save.boxes or {}) do
    roster(box)
  end
  return count
end

function Summary.installCompatibility(mod)
  if Summary._compatibilityInstalled then return false end
  Summary._compatibilityInstalled = true
  local function refresh(payload)
    local game = payload and payload.game or (mod and mod.game)
    Summary.enrichSave((payload and payload.save) or (game and game.save))
    local mon = payload and (payload.mon or payload.pokemon)
    if mon then Summary.enrich(mon) end
  end
  if mod and mod.events and mod.events.on then
    mod.events:on("game.ready", refresh, 90)
    mod.events:on("save.loaded", refresh, 90)
    mod.events:on("pokemon.received", refresh, 90)
    mod.events:on("pokemon.evolved", refresh, 90)
    mod.events:on("pokemon.level_up", refresh, 90)
  end
  return true
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
    local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
    if not Gender.gen3PokemonUiActive(self.game) then Summary.drawSplitStats(self) end
    return result
  end
  return true
end

return Summary
