-- Visual smoke test for the two static sanctuaries. Run with Crystal 251
-- enabled and imported:
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/sanctuary_visual_driver.lua \
--   SHOT_DIR=/tmp/crystal251-sanctuaries love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local dir = os.getenv("SHOT_DIR") or "/tmp/crystal251-sanctuaries"
  local badges = { "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE",
    "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE",
    "EARTHBADGE" }
  game.save.inventory = game.save.inventory or {}
  game.save.flags = game.save.flags or {}

  -- Seven badges: the island is reachable, but there is no cave door yet.
  for _,badge in ipairs(badges) do game.save.inventory[badge]=nil end
  for i=1,7 do game.save.inventory[badges[i]]=true end
  U.teleport(game,"CRYSTAL_251_NAVEL_ISLE",10,6,"up")
  assert(U.shot(game,dir.."/navel_isle_no_door.png"))

  -- Badge eight reveals the cave door in the same cliff face.
  game.save.inventory.EARTHBADGE=true
  U.teleport(game,"CRYSTAL_251_NAVEL_ISLE",10,6,"up")
  assert(U.shot(game,dir.."/navel_isle_open.png"))

  U.teleport(game,"CRYSTAL_251_TIDAL_CAVE",10,5,"up")
  assert(U.shot(game,dir.."/tidal_cave_lugia.png"))

  game.save.flags.EVENT_RESCUED_MR_FUJI=true
  -- Stand directly below Ho-Oh's unique cell; this is also the real A-button
  -- interaction position used by the regression screenshot.
  U.teleport(game,"POKEMON_TOWER_7F",11,4,"up")
  assert(U.shot(game,dir.."/tower_ho_oh.png"))
  print("[driver] PASS Crystal 251 sanctuary visuals under "..dir)
end
