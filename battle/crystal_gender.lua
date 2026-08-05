local Gender = {}

local ratios = {}
local installed = false
local unpackValues = table.unpack or unpack

local function nibble(value)
  value = tonumber(value)
  if value == nil then return nil end
  value = math.floor(value)
  if value < 0 then return 0 end
  if value > 15 then return 15 end
  return value
end

function Gender.setRatio(species, ratio)
  if not species then return end
  ratio = tonumber(ratio)
  ratios[species] = ratio and math.floor(ratio) or nil
end

local function mergedRatio(species)
  local ok, data = pcall(require, "src.core.Data")
  local def = ok and data and data.pokemon and data.pokemon[species]
  local ratio = def and tonumber(def.crystalGenderRatio)
  if ratio == nil then return nil end
  return math.floor(ratio)
end

function Gender.ratio(species)
  if not species then return nil end
  local ratio = ratios[species]
  if ratio == nil then ratio = mergedRatio(species) end
  return ratio
end

function Gender.cacheHasRatios(cache)
  local species = cache and cache.species
  if type(species) ~= "table" or #species < 251 then return false end
  for _, row in ipairs(species) do
    local ratio = row and tonumber(row.crystalGenderRatio)
    if ratio == nil or ratio % 1 ~= 0 or ratio < 0 or ratio > 255 then
      return false
    end
  end
  return true
end

function Gender.dvByte(mon)
  local dvs = mon and mon.dvs
  local attack = dvs and nibble(dvs.attack)
  local speed = dvs and nibble(dvs.speed)
  if attack == nil or speed == nil then return nil end
  return attack * 16 + speed
end

function Gender.forSpeciesDVs(species, dvs)
  local ratio = Gender.ratio(species)
  if ratio == nil or ratio == 255 then return nil end
  if ratio == 0 then return "M" end
  if ratio == 254 then return "F" end
  local value = Gender.dvByte({ dvs = dvs })
  if value == nil then return nil end
  return value <= ratio and "F" or "M"
end

function Gender.forMon(mon)
  if not mon or mon.isEgg then return nil end
  return Gender.forSpeciesDVs(mon.species, mon.dvs)
end

function Gender.symbol(mon)
  local value = Gender.forMon(mon)
  if value == "M" then return "♂" end
  if value == "F" then return "♀" end
  return nil
end

local function enemyHudVisible(battle, slide)
  local enemy = battle and battle.enemy
  return enemy and not battle.showEnemyTrainer and not battle.enemySendingOut
    and not (battle.growInScale and battle:growInScale(enemy))
    and slide == 0 and not enemy.fainted
end

local function playerHudVisible(battle, slide)
  return battle and battle.player and not (battle.safari or battle.demo)
    and not battle.showPlayerBack and slide == 0
end

local function withHudLayout(battle, fn, ...)
  local Font = require("src.render.Font")
  local originalDraw = Font.draw
  Font.draw = function(text, x, y, ...)
    if battle and battle.crystal251Active then
      if battle.enemy and battle.enemy.shownStatus and x == 40 and y == 8 then
        x = 48
      elseif battle.player and battle.player.shownStatus
          and x == 120 and y == 64 then
        x = 112
      elseif battle.player and not battle.player.shownStatus
          and battle.player.mon and (battle.player.mon.level or 0) >= 100
          and x == 120 and y == 64 then
        x = 112
      end
    end
    return originalDraw(text, x, y, ...)
  end
  local ok, a, b, c = pcall(fn, ...)
  Font.draw = originalDraw
  if not ok then error(a, 0) end
  return a, b, c
end

function Gender.drawBattleHUD(battle, slide)
  local Font = require("src.render.Font")
  if enemyHudVisible(battle, slide) then
    local symbol = Gender.symbol(battle.enemy.mon)
    if symbol then Font.draw(symbol, 72, 8) end
  end
  if playerHudVisible(battle, slide) then
    local symbol = Gender.symbol(battle.player.mon)
    if symbol then Font.draw(symbol, 136, 64) end
  end
end

function Gender.drawSummary(menu)
  local mon = menu and menu.mon
  local symbol = Gender.symbol(mon)
  if not symbol then return end
  require("src.render.Font").draw(symbol, 144, 0)
end

function Gender.installRuntime()
  if installed then return false end
  installed = true

  local BattleState = require("src.battle.BattleState")
  local originalDrawHUDs = BattleState.drawHUDs
  BattleState.drawHUDs = function(self, slide)
    local result = withHudLayout(self, originalDrawHUDs, self, slide)
    local snapped = self._crystal251GenderHudSnappedFrame ~= nil
      and self._crystal251GenderHudSnappedFrame == self.frame
    if self.crystal251Active and not snapped then
      local ink = self.dramaticShapeShot and self.dramaticShapeDark and 1 or 0
      love.graphics.setColor(ink, ink, ink, 1)
      Gender.drawBattleHUD(self, slide)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return result
  end

  local SummaryMenu = require("src.ui.SummaryMenu")
  local originalSummaryDraw = SummaryMenu.draw
  SummaryMenu.draw = function(self)
    local result = originalSummaryDraw(self)
    if self.mon and Gender.ratio(self.mon.species) ~= nil then
      love.graphics.setColor(0, 0, 0, 1)
      Gender.drawSummary(self)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return result
  end

  return true
end

function Gender.installDramatic(exports)
  local lib = exports and exports.lib
  if not (lib and lib.require) then return false end
  local ok, OverworldBattle = pcall(lib.require, "OverworldBattle")
  if not ok or not OverworldBattle or OverworldBattle._crystal251GenderHook then
    return false
  end
  local originalHudTexture = OverworldBattle.hudTexture
  if type(originalHudTexture) ~= "function" then return false end
  OverworldBattle._crystal251GenderHook = true
  OverworldBattle.hudTexture = function(battle, slide, dark)
    local layer = withHudLayout(battle, originalHudTexture,
      battle, slide, dark)
    if not (layer and battle and battle.crystal251Active) then return layer end
    local graphics = love.graphics
    local previous = graphics.getCanvas()
    local color = graphics.getColor and { graphics.getColor() } or nil
    graphics.setCanvas(layer)
    local ink = dark and 1 or 0
    graphics.setColor(ink, ink, ink, 1)
    local drawn, err = pcall(Gender.drawBattleHUD, battle, slide)
    if previous then graphics.setCanvas(previous) else graphics.setCanvas() end
    if color then graphics.setColor(unpackValues(color))
    else graphics.setColor(1, 1, 1, 1) end
    if not drawn then error(err, 0) end
    battle._crystal251GenderHudSnappedFrame = battle.frame
    return layer
  end
  return true
end

function Gender.resetForTests()
  ratios = {}
  installed = false
end

return Gender
