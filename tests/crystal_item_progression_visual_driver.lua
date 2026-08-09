-- Visual smoke test for the early Cerulean EXP.SHARE pickup.
--
--   SHOT_DIR=/tmp/crystal-item-progression \
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_item_progression_visual_driver.lua \
--   POKEPORT_TOUCH=0 POKEPORT_SPEED=20 love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/crystal-item-progression"
  local originalInventory = game.save.inventory
  local originalBagOrder = game.save.bagOrder
  local originalFlags = game.save.flags

  local function restore()
    game.save.inventory = originalInventory
    game.save.bagOrder = originalBagOrder
    game.save.flags = originalFlags
  end
  local function fail(message)
    U.log("FAIL", message)
    U.shot(game, DIR .. "/FAIL.png")
    restore()
    error(message, 0)
  end
  local function check(value, message) if not value then fail(message) end end

  game.save.inventory, game.save.bagOrder, game.save.flags = {}, {}, {}
  U.teleport(game, "CERULEAN_CITY", 33, 23, "up")
  local ow = game.overworld
  local pickup
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == "CRYSTAL251_CERULEAN_EXP_SHARE" then
      pickup = npc break
    end
  end
  check(pickup and pickup.cellX == 33 and pickup.cellY == 22,
    "Cerulean EXP.SHARE item ball is not visible at (33,22)")
  check(U.shot(game, DIR .. "/01_cerulean_exp_share_pickup.png"),
    "could not capture Cerulean pickup")

  U.tap(game, "a")
  for _ = 1, 120 do
    if game.save.inventory.EXP_SHARE == 1 then break end
    U.tap(game, "a")
    U.wait(1)
  end
  check(game.save.inventory.EXP_SHARE == 1,
    "interacting with the Cerulean item ball did not award EXP.SHARE")
  check(ow:npcAtCell(33, 22) == nil,
    "EXP.SHARE item ball did not disappear after pickup")

  local top = game.stack:top()
  if getmetatable(top) == TextBox then
    game.input.state.a = true
    for _ = 1, 120 do
      if top.done or top.waiting then break end
      U.wait(1)
    end
    game.input.state.a = false
    U.wait(2)
  end
  check(U.shot(game, DIR .. "/02_cerulean_exp_share_obtained.png"),
    "could not capture EXP.SHARE obtained state")
  restore()
  print("[driver] PASS Cerulean EXP.SHARE visible pickup and award")
  love.event.quit()
end
