return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local dir = os.getenv("SHOT_DIR") or "/tmp/crystal251-dex-visual"
  game.save.options.colors = "redpp"
  game:applyOptions(game.save.options)

  for _, row in ipairs({
    { "PIKACHU", "dex_5x5_pikachu.png" },
    { "MAGIKARP", "dex_6x6_magikarp.png" },
    { "CHARIZARD", "dex_7x7_charizard.png" },
  }) do
    while game.stack:top() do game.stack:pop() end
    Screens.push(game, "DexEntryMenu", { species=row[1], forceOwned=true })
    U.wait(4)
    local top = game.stack:top()
    assert(top and top.sprite and top.sprite:getWidth() == 56
      and top.sprite:getHeight() == 56,
      row[1] .. " Pokédex sprite is not centered in a 7x7 tile canvas")
    local path = require("src.pokemon.Sprites").path(game.data, row[1], "front",
      { kind="dex" })
    local pixels = love.image.newImageData(path)
    local _, _, _, a1 = pixels:getPixel(0, 0)
    local _, _, _, a2 = pixels:getPixel(55, 55)
    assert(a1 == 0 and a2 == 0,
      row[1] .. " Pokédex canvas retained its opaque color-0 rectangle")
    assert(U.shot(game, dir .. "/" .. row[2]), row[1] .. " screenshot failed")
  end
  print("[driver] PASS Crystal 5x5, 6x6 and 7x7 Pokédex visual pages under " .. dir)
end
