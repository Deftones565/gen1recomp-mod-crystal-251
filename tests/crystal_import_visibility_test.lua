package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local steps, pending = 0, true
package.loaded["mods.CRYSTAL_251.lib.picture"] = {}
package.loaded["mods.CRYSTAL_251.lib.cache"] = {
  bind = function() end,
  persistProgress = function()
    return pending and steps or 4, 4
  end,
  persistMemoryStep = function()
    steps = steps + 1
    if steps >= 4 then pending = false return true end
    return false
  end,
}

local popped = 0
local game = {
  stack = {
    top = function(self) return self.screen end,
    pop = function(self) popped = popped + 1; self.screen = nil end,
  },
}
local mod = { ui = { Font = {} } }
local Screen = require("mods.CRYSTAL_251.import_screen")
local screen = Screen.new(game, mod, { automatic=true })
game.stack.screen = screen

T.check(screen.isOpaque == true, "automatic importer covers the game")
T.eq(screen.status, "IMPORTING CRYSTAL", "automatic importer starts visibly")
T.eq(steps, 0, "constructing the screen does not advance hidden work")

for _ = 1, 3 do screen:update(1 / 60) end
T.eq(steps, 3, "visible screen owns incremental cache writes")
T.check(screen.progress > 0 and screen.progress < 1,
  "visible importer reports partial progress")

screen:update(1 / 60)
T.eq(screen.status, "CRYSTAL IMPORT COMPLETE", "visible importer reports completion")
for _ = 1, 45 do screen:update(1 / 60) end
T.eq(popped, 1, "completed automatic importer returns to the game")

local file = assert(io.open("mods/CRYSTAL_251/main.lua", "rb"))
local source = file:read("*a")
file:close()
T.check(source:find('mod.ui.push(liveGame, "Crystal251Import"', 1, true) ~= nil,
  "startup path pushes the registered importer screen")
T.check(not source:find("Cache.persistMemoryStep", 1, true),
  "startup hook cannot advance import work behind another screen")

T.finish("Crystal automatic importer visibility")
