-- Visual regression: walk through the Celadon Mart and Rocket Hideout
-- elevator doorways with Crystal 251 enabled and capture both interiors.
--
-- Run from the engine repository root:
--   SHOT_DIR=/tmp/crystal251-elevators \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/elevator_visual_driver.lua \
--   POKEPORT_VERSION=red POKEPORT_TOUCH=0 love .

local U = require("tests.drivers.util")

local function waitForStableOverworld(game)
  local stable = 0
  for _ = 1, 4800 do
    if game.overworld and game.stack:top() == game.overworld then
      stable = stable + 1
      if stable >= 120 then return end
    else
      stable = 0
    end
    U.wait(1)
  end
  error("timed out waiting for a stable overworld")
end

local function waitForMap(game, mapId)
  for _ = 1, 240 do
    if game.overworld and game.overworld.map
        and game.overworld.map.id == mapId
        and game.stack:top() == game.overworld then
      U.wait(8)
      return
    end
    U.wait(1)
  end
  error("timed out entering " .. mapId)
end

return function(game)
  local shotDir = os.getenv("SHOT_DIR") or "/tmp/crystal251-elevators"
  U.wait(5)

  U.teleport(game, "CELADON_MART_3F", 1, 2, "up")
  waitForStableOverworld(game)
  assert(U.shot(game, shotDir .. "/celadon-before.png"))
  U.hold(game, "up", 24)
  waitForMap(game, "CELADON_MART_ELEVATOR")
  assert(U.shot(game, shotDir .. "/celadon-inside.png"))
  U.log("PASS player entered Celadon Mart elevator")

  game.save.inventory.LIFT_KEY = 1
  U.teleport(game, "ROCKET_HIDEOUT_B2F", 24, 18, "down")
  waitForStableOverworld(game)
  assert(U.shot(game, shotDir .. "/rocket-before.png"))
  U.hold(game, "down", 24)
  waitForMap(game, "ROCKET_HIDEOUT_ELEVATOR")
  assert(U.shot(game, shotDir .. "/rocket-inside.png"))
  U.log("PASS player entered Rocket Hideout elevator")

  love.event.quit()
end
