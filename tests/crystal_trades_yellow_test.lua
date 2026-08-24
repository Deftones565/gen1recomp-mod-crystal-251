package.path = "./?.lua;./?/init.lua;" .. package.path

local Trades = require("mods.CRYSTAL_251.trades")

local maps = {
  CELADON_MART_5F = {},
  CERULEAN_POKECENTER = {},
  VERMILION_TRADE_HOUSE = {},
  FUCHSIA_MEETING_ROOM = {},
  PEWTER_POKECENTER = {},
  ROUTE_14 = {},
  ROCK_TUNNEL_POKECENTER = {},
}
local patches = {}
local mapRegistry = {}
function mapRegistry:get(id) return maps[id] end
function mapRegistry:patch(id, value)
  patches[id] = value
end

local fields = { trades = {}, tradeLocations = {} }
local fieldRegistry = {}
function fieldRegistry:get(id) return fields[id] end
function fieldRegistry:override(id, value) fields[id] = value end

local scripts = {}
local texts = {}
local installed = Trades.install({ content = {
  maps = mapRegistry,
  field = fieldRegistry,
  map_scripts = { register = function(_, id, value) scripts[id] = value end },
  text = { register = function(_, id, value) texts[id] = value end },
} })

assert(patches.CERULEAN_TRADE_HOUSE == nil,
  "Yellow must not resurrect its absent Cerulean trade house")
assert(patches.CERULEAN_POKECENTER,
  "Yellow relocates Kyle to its existing Cerulean Pokemon Center")
local object = patches.CERULEAN_POKECENTER.objects.__append[1]
assert(object.index == 6 and object.x == 12 and object.y == 3,
  "Yellow fallback uses the non-blocking Pokemon Center edge cell")
assert(installed[2].map == "CERULEAN_POKECENTER",
  "the exported trade location follows the Yellow fallback")
assert(scripts.CERULEAN_POKECENTER,
  "the trade script is registered on the fallback map")

print("5/5 checks passed (Crystal 251 Yellow trade/elevator regression)")
