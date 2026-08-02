return function(game)
  local file = assert(io.open(os.getenv("CRYSTAL_ROM"), "rb"))
  local raw = file:read("*a"); file:close()
  local screen = require("mods.CRYSTAL_251.import_screen").new(game, {})
  screen:start(raw, "visual-test Crystal ROM")
  while not screen.complete do
    screen:update()
    if screen.status == "IMPORT FAILED" then error(screen.detail) end
    coroutine.yield()
  end
  print("[driver] PASS Crystal visual-test reimport")
end
