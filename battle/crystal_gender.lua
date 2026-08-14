local Gender = {}

local ratios = {}
local installed = false
local compatibilityInstalled = false
local gen3UiPresent = false
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

-- The engine and presentation mods use lowercase names, while Crystal's
-- cartridge-facing helpers keep the compact M/F values used by Attract and
-- breeding.  Publish both forms from one calculation so UI code never has to
-- reproduce the ROM ratio/DV rule.
function Gender.presentation(mon)
  local value = Gender.forMon(mon)
  if value == "M" then return "male" end
  if value == "F" then return "female" end
  return nil
end

-- Gen 3 UI reads mon.gender in Party, Summary and PC views.  It is derived
-- state, not a second source of truth: every refresh overwrites it from the
-- Crystal ratio and DVs, and genderless Crystal species clear a stale value.
function Gender.annotate(mon)
  if type(mon) ~= "table" or Gender.ratio(mon.species) == nil then return false end
  mon.gender = Gender.presentation(mon)
  return true
end

function Gender.annotateSave(save)
  if type(save) ~= "table" then return 0 end
  local count = 0
  local function roster(rows)
    for _, mon in pairs(type(rows) == "table" and rows or {}) do
      if Gender.annotate(mon) then count = count + 1 end
    end
  end
  roster(save.party)
  for _, box in pairs(type(save.boxes) == "table" and save.boxes or {}) do
    roster(box)
  end
  return count
end

-- Battle facades differ between the Gen I host, Gen II host and presentation
-- mods. Keep the compatibility seam on the live mon records, which all three
-- shapes expose, instead of wrapping somebody else's renderer.
function Gender.annotateBattle(battle)
  if type(battle) ~= "table" then return 0 end
  local count = 0
  local function battler(value)
    if type(value) ~= "table" then return end
    local mon = type(value.mon) == "table" and value.mon or value
    if Gender.annotate(mon) then count = count + 1 end
  end
  battler(battle.player)
  battler(battle.enemy)
  local core = battle.battle
  if type(core) == "table" and core ~= battle then
    battler(core.player)
    battler(core.enemy)
  end
  return count
end

local function gen3Option(game, key, default)
  if not gen3UiPresent then return false end
  local loader = game and game.mods
  local options = loader and loader.modOptions
  local bucket = options and options.gen3_battle_ui
  local value = bucket and bucket[key]
  if value == nil then return default end
  return value
end

function Gender.gen3BattleUiActive(battle)
  local game = battle and battle.game
  return gen3Option(game, "revampedBattleUI", true) ~= false
    or gen3Option(game, "hideNativeBattleUI", false) == true
end

function Gender.gen3PokemonUiActive(game)
  return gen3Option(game, "revampedPokemonMenu", true) ~= false
end

function Gender.installCompatibility(mod)
  if compatibilityInstalled then return false end
  compatibilityInstalled = true
  gen3UiPresent = mod and mod.find and mod.find("gen3_battle_ui") ~= nil or false

  if mod and mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("gender.roll", function(next, ctx)
      local def = ctx and ctx.def
      local species = (ctx and ctx.species) or (def and def.id)
      if not (def and def.crystalGenderRatio ~= nil)
          and Gender.ratio(species) == nil then
        return next(ctx)
      end
      local value = Gender.forSpeciesDVs(species, ctx and ctx.dvs)
      if value == "M" then return "male" end
      if value == "F" then return "female" end
      return "unknown"
    end, 100)
  end

  local function refresh(payload)
    local game = payload and payload.game or (mod and mod.game)
    -- save.loaded intentionally carries {save=...}, not {game=...}. Reading
    -- that payload directly is what updates an existing party/PC after
    -- CONTINUE rather than only Pokémon created during the current process.
    Gender.annotateSave((payload and payload.save) or (game and game.save))
    local mon = payload and (payload.mon or payload.pokemon)
    if mon then Gender.annotate(mon) end
    local battler = payload and payload.battler
    if battler then Gender.annotate(battler.mon or battler) end
    Gender.annotateBattle(payload and payload.battle)
  end
  if mod and mod.events and mod.events.on then
    mod.events:on("game.ready", refresh, 100)
    mod.events:on("save.loaded", refresh, 100)
    mod.events:on("pokemon.received", refresh, 100)
    mod.events:on("pokemon.evolved", refresh, 100)
    mod.events:on("battle.started", refresh, 100)
    mod.events:on("battle.battler_switched", refresh, 100)
  end
  return true
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
    -- Gen 3 UI loaded before Crystal and suppresses the native HUD inside its
    -- wrapper. Drawing our glyph after that call would escape its invisible
    -- scissor and leave a duplicate 160x144 symbol under the modern plate.
    if Gender.gen3BattleUiActive(self) then
      return originalDrawHUDs(self, slide)
    end
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
    if not Gender.gen3PokemonUiActive(self.game)
        and self.mon and Gender.ratio(self.mon.species) ~= nil then
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
  compatibilityInstalled = false
  gen3UiPresent = false
end

return Gender
