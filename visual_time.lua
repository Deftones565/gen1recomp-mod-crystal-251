-- Gen 2-style time-of-day lighting for the Gen 1 overworld.
-- Gen 1 map art is DMG/SGB-colored, so the tint is applied after the world
-- palette pass and before the UI pass. This keeps menus and text crisp.
local VisualTime = {}
local testState
local optionSource

VisualTime.TINTS = {
  MORNING = { 1.00, 0.93, 0.80 }, -- warm dawn
  DAY = { 1.00, 1.00, 1.00 },     -- bright afternoon
  NIGHT = { 0.58, 0.67, 0.88 },   -- cool blue night
}

local function outdoors()
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or not Game or not Game.overworld then return false end
  local ow = Game.overworld
  local map = ow.map
  if not map or not map.def then return false end
  local okMap, Map = pcall(require, "src.world.Map")
  return okMap and Map.isOutdoor(map.def) or false
end

function VisualTime.current()
  if optionSource then
    local ok, value = pcall(optionSource)
    local forced = ok and ({
      morning = "MORNING", day = "DAY", night = "NIGHT",
    })[value] or nil
    if forced then return forced end
  end
  if testState then return testState end
  local ok, Game = pcall(require, "src.core.Game")
  if not ok or not Game then return "DAY" end
  local ow = Game.overworld
  local tod = ow and ow.tod
  if tod == "MORNING" or tod == "DAY" or tod == "NIGHT" then return tod end
  local Clock = require("mods.CRYSTAL_251.core.gen2.Clock")
  return Clock.forSave(Game.save)
end

function VisualTime.bindOptionSource(fn)
  optionSource = type(fn) == "function" and fn or nil
end

function VisualTime.setTestState(state)
  if state == "MORNING" or state == "DAY" or state == "NIGHT" then
    testState = state
  else
    testState = nil
  end
  return testState
end

function VisualTime.testState()
  return testState
end

function VisualTime.tint()
  if not outdoors() then return nil end
  local row = VisualTime.TINTS[VisualTime.current()]
  if not row or (row[1] == 1 and row[2] == 1 and row[3] == 1) then return nil end
  return row[1], row[2], row[3]
end

local function read(name, ...)
  local fn = love.graphics[name]
  if not fn then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  return ok and a or nil, ok and b or nil, ok and c or nil, ok and d or nil
end

function VisualTime.paint(r, g, b)
  local gfx = love.graphics
  local shader = read("getShader")
  local sx, sy, sw, sh = read("getScissor")
  local blend, alpha = read("getBlendMode")
  local pr, pg, pb, pa = read("getColor")
  local w, h = gfx.getDimensions()
  gfx.setShader()
  gfx.setScissor()
  gfx.setBlendMode("multiply", "premultiplied")
  gfx.setColor(r, g, b, 1)
  gfx.rectangle("fill", 0, 0, w, h)
  gfx.setBlendMode(blend or "alpha", alpha)
  gfx.setColor(pr or 1, pg or 1, pb or 1, pa or 1)
  if sx then gfx.setScissor(sx, sy, sw, sh) end
  if shader then gfx.setShader(shader) end
end

function VisualTime.install()
  local Renderer = require("src.render.Renderer")
  if Renderer.crystal251TimeLighting then return end
  Renderer.crystal251TimeLighting = true
  local original = Renderer.endFrame
  function Renderer:endFrame(zones, worldZones)
    local r, g, b = VisualTime.tint()
    if not (r and self.worldActive and not self.worldOverride) then
      return original(self, zones, worldZones)
    end
    local gfx, draw, ui = love.graphics, love.graphics.draw, self.canvas
    local painted = false
    gfx.draw = function(texture, ...)
      if not painted and texture == ui then
        painted = true
        gfx.draw = draw
        VisualTime.paint(r, g, b)
      end
      return draw(texture, ...)
    end
    local ok, result = pcall(original, self, zones, worldZones)
    gfx.draw = draw
    if not ok then error(result, 0) end
    return result
  end
end

return VisualTime
