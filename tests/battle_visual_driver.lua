return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local dir = os.getenv("SHOT_DIR") or "/tmp/crystal251-visual"

  assert(game.data.pokemon.MAGIKARP.battleScaleBack == 1,
    "Crystal Magikarp must render at native back-sprite scale")
  game.save.options.colors = "redpp"
  game:applyOptions(game.save.options)
  game.mods.modOptions.shiny_indicators = game.mods.modOptions.shiny_indicators or {}
  game.mods.modOptions.shiny_indicators.force_wild_shiny = true
  game.mods.modOptions.CRYSTAL_251 = game.mods.modOptions.CRYSTAL_251 or {}
  game.mods.modOptions.CRYSTAL_251.crystal_shinies = true
  game.save.party = { Pokemon.new(game.data, "MAGIKARP", 14) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  -- Let Dramatic Shape finish the nearby arena mesh so this capture exercises
  -- transparent sprites over the real 3D field, not the classic fallback.
  U.wait(120)
  game.mods.hooks:call("encounter.roll", function()
    return { species="MAGIKARP", level=14 }
  end, game.data.encounters.ROUTE_1,
    { mapId="ROUTE_1", terrain="grass", rng=function(a) return a end })
  local battle = BattleState.newWild(game, "MAGIKARP", 14)
  local shinyPath = require("src.pokemon.Sprites").path(game.data, "MAGIKARP",
    "front", { kind="battle", mon=battle.enemy.mon })
  local shinyPixels = love.image.newImageData(shinyPath)
  local _, _, _, cornerAlpha = shinyPixels:getPixel(0, 0)
  assert(cornerAlpha == 0,
    "Crystal shiny battle sprite retained its opaque color-0 rectangle")
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  for frame = 1, 360 do
    if battle.phase == "menu" then break end
    if frame % 8 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  assert(battle.phase == "menu", "battle did not reach its command menu")
  U.wait(5)
  assert(U.shot(game, dir .. "/crystal_shiny_magikarp_battle.png"),
    "Crystal battle screenshot was written")
  print("[driver] PASS Crystal front/back visual screenshot under " .. dir)
end
