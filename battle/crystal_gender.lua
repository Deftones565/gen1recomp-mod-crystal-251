local Gender = {}

local ratios = {}
local installed = false
local compatibilityInstalled = false
local gen3UiPresent = false
local compatibilityMod = nil
local presentationNameDepth = 0
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
  local seen = {}
  local function battler(value)
    if type(value) ~= "table" then return end
    local mon = type(value.mon) == "table" and value.mon or value
    if not seen[mon] then
      seen[mon] = true
      if Gender.annotate(mon) then count = count + 1 end
    end
    if value ~= mon and Gender.ratio(mon.species) ~= nil then
      value.gender = mon.gender
    end
  end
  battler(battle.player)
  battler(battle.enemy)
  local shown = battle.shownMon
  if type(shown) == "table" then
    battler(shown.player)
    battler(shown.enemy)
    battler(shown[1])
    battler(shown[2])
  end
  local core = battle.battle
  if type(core) == "table" and core ~= battle then
    battler(core.player)
    battler(core.enemy)
  end
  return count
end

function Gender.activeBattle(game)
  local stack = game and game.stack
  local states = stack and stack.states
  if type(states) == "table" then
    for index = #states, 1, -1 do
      local state = states[index]
      if type(state) == "table" then
        if state.crystal251Active then return state end
        local nested = state.battle
        if type(nested) == "table" and nested.crystal251Active then
          return nested
        end
      end
    end
  end
  local top = stack and stack.top
  if type(top) == "function" then
    local ok, state = pcall(top, stack)
    if ok and type(state) == "table" then
      if state.crystal251Active then return state end
      local nested = state.battle
      if type(nested) == "table" and nested.crystal251Active then
        return nested
      end
    end
  end
  return nil
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
  compatibilityMod = mod
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
    mod.hooks:wrap("battle.overlay", function(next, battle)
      return Gender.withBattleHudTracking(battle, next, battle)
    end, math.huge)
    mod.hooks:wrap("render.zones", function(next, game, zones)
      Gender.annotateBattle(Gender.activeBattle(game))
      return next(game, zones)
    end, math.huge)
    mod.hooks:wrap("render.hud", function(next, game, viewport)
      local battle = Gender.activeBattle(game)
      if battle then Gender.annotateBattle(battle) end
      if battle and Gender.modernBattleUiActive(game) then
        return Gender.withPresentationGenderNames(battle, next, game, viewport)
      end
      return next(game, viewport)
    end, 101)
  end

  local function refresh(payload)
    local game = payload and payload.game or (mod and mod.game)
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

local trackingDepth = 0

local function statusText(battle, battler)
  if not (battle and battler and battler.shownStatus) then return nil end
  if type(battle.statusLabel) == "function" then
    local ok, value = pcall(battle.statusLabel, battle,
      { status=battler.shownStatus })
    if ok and value ~= nil then return tostring(value) end
  end
  return tostring(battler.shownStatus)
end

local function hudText(battle, side)
  local battler = battle and battle[side]
  if not (battler and battler.mon) then return nil end
  return statusText(battle, battler) or tostring(battler.mon.level or "")
end

local function nameMatches(text, name)
  text, name = tostring(text or ""), tostring(name or "")
  if text == name then return true end
  if text:sub(-1) == "." then
    local prefix = text:sub(1, -2)
    return prefix ~= "" and name:sub(1, #prefix) == prefix
  end
  return false
end

local function uiWidth(battle)
  local fn = battle and battle.uiSize
  if type(fn) == "function" then
    local ok, width = pcall(fn, battle)
    width = ok and tonumber(width) or nil
    if width and width > 0 then return width end
  end
  return tonumber(battle and (battle.w or battle.width)) or 160
end

local function matchHudSide(battle, tracker, text, x)
  if tracker.pending then
    local expected = hudText(battle, tracker.pending)
    if expected ~= nil and tostring(text) == expected then
      return tracker.pending
    end
  end
  local matches = {}
  for _, side in ipairs({ "enemy", "player" }) do
    local expected = hudText(battle, side)
    if expected ~= nil and tostring(text) == expected then
      matches[#matches + 1] = side
    end
  end
  if #matches == 1 then return matches[1] end
  if #matches == 2 then
    return (tonumber(x) or 0) < uiWidth(battle) / 2 and "enemy" or "player"
  end
  return nil
end

local function markHudName(battle, tracker, text)
  for _, side in ipairs({ "enemy", "player" }) do
    local battler = battle and battle[side]
    if battler and nameMatches(text, battler.name) then
      tracker.pending = side
      return
    end
  end
end

local function adjustedX(battle, side, x, y)
  local battler = battle and battle[side]
  if side == "enemy" and battler and battler.shownStatus
      and x == 40 and y == 8 then
    return 48
  end
  if side == "player" and battler and x == 120 and y == 64
      and (battler.shownStatus
        or ((battler.mon and battler.mon.level) or 0) >= 100) then
    return 112
  end
  return x
end

local function symbolX(side, originalX, drawX, y, width)
  if side == "enemy" and originalX == 40 and y == 8 then return 72 end
  if side == "player" and originalX == 120 and y == 64 then return 136 end
  return drawX + width
end

local function packedCall(fn, ...)
  local function capture(...) return { n=select("#", ...), ... } end
  return capture(pcall(fn, ...))
end

local function modHandle(id)
  local find = compatibilityMod and compatibilityMod.find
  if type(find) ~= "function" then return nil end
  local ok, handle = pcall(find, id)
  if not ok then
    ok, handle = pcall(find, compatibilityMod, id)
  end
  return ok and handle or nil
end

function Gender.modernBattleUiActive(game)
  local handle = modHandle("gen1_modern_ui")
  if not handle then return false end
  local mods = game and game.mods
  local options = mods and mods.modOptions
  local bucket = options and options.gen1_modern_ui
  if type(bucket) == "table" then return bucket.battleUiWip == true end
  local source = handle.options
  if source and type(source.get) == "function" then
    local ok, value = pcall(source.get, source, "battleUiWip")
    if ok then return value == true end
  end
  return false
end

local function hasGenderSuffix(name)
  name = tostring(name or "")
  return name:sub(-3) == "♂" or name:sub(-3) == "♀"
end

function Gender.withPresentationGenderNames(battle, fn, ...)
  if type(fn) ~= "function" or not (battle and battle.crystal251Active)
      or presentationNameDepth > 0 then
    return fn(...)
  end
  local changed = {}
  for _, side in ipairs({ "enemy", "player" }) do
    local battler = battle[side]
    local mon = battler and (battler.mon or battler)
    local symbol = Gender.symbol(mon)
    if type(battler) == "table" and type(battler.name) == "string"
        and symbol and not hasGenderSuffix(battler.name) then
      changed[#changed + 1] = { battler=battler, name=battler.name }
      battler.name = battler.name .. symbol
    end
  end
  presentationNameDepth = presentationNameDepth + 1
  local result = packedCall(fn, ...)
  presentationNameDepth = presentationNameDepth - 1
  for index = #changed, 1, -1 do
    local row = changed[index]
    row.battler.name = row.name
  end
  if not result[1] then error(result[2], 0) end
  return unpackValues(result, 2, result.n)
end

function Gender.withBattleHudTracking(battle, fn, ...)
  if type(fn) ~= "function" or not (battle and battle.crystal251Active)
      or Gender.gen3BattleUiActive(battle) or trackingDepth > 0 then
    return fn(...)
  end
  local Font = require("src.render.Font")
  if type(Font.draw) ~= "function" then return fn(...) end
  local originalDraw = Font.draw
  local tracker = { pending=nil }
  trackingDepth = trackingDepth + 1
  Font.draw = function(text, x, y, ...)
    local side = matchHudSide(battle, tracker, text, x)
    local drawX = side and adjustedX(battle, side, x, y) or x
    local width = originalDraw(text, drawX, y, ...)
    if side then
      local battler = battle[side]
      local symbol = battler and Gender.symbol(battler.mon)
      if symbol then
        originalDraw(symbol, symbolX(side, x, drawX, y, width or 0), y)
      end
      tracker.pending = nil
    else
      markHudName(battle, tracker, text)
    end
    return width
  end
  local result = packedCall(fn, ...)
  Font.draw = originalDraw
  trackingDepth = trackingDepth - 1
  if not result[1] then error(result[2], 0) end
  return unpackValues(result, 2, result.n)
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
  local originalDraw = BattleState.draw
  if type(originalDraw) == "function" then
    BattleState.draw = function(self, ...)
      return Gender.withBattleHudTracking(self, originalDraw, self, ...)
    end
  end
  local originalDrawHUDs = BattleState.drawHUDs
  if type(originalDrawHUDs) == "function" then
    BattleState.drawHUDs = function(self, ...)
      return Gender.withBattleHudTracking(self, originalDrawHUDs, self, ...)
    end
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

function Gender.resetForTests()
  ratios = {}
  installed = false
  compatibilityInstalled = false
  compatibilityMod = nil
  gen3UiPresent = false
  trackingDepth = 0
  presentationNameDepth = 0
end

return Gender
