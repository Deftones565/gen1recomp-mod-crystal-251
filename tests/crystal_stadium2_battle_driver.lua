return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Importer = require("mods.STADIUM2_IMPORTER.lib.importer")
  local dir = os.getenv("SHOT_DIR") or "/tmp/crystal251-stadium2"

  game.mods.modOptions.CRYSTAL_251 = game.mods.modOptions.CRYSTAL_251 or {}
  game.mods.modOptions.STADIUM2_IMPORTER = game.mods.modOptions.STADIUM2_IMPORTER or {}
  game.mods.modOptions.STADIUM2_IMPORTER.stadium2_models = true
  game.mods.modOptions.STADIUM2_IMPORTER.stadium2_battle = true
  if game.mods.modOptions.DRAMATIC_SHAPE then
    game.mods.modOptions.DRAMATIC_SHAPE.battles = false
  end

  for _ = 1, 3600 do
    if Importer.available(251) then break end
    local status = Importer.status()
    assert(not status or status.state ~= "failed", status and status.error or "Stadium 2 import failed")
    U.wait(1)
  end
  assert(Importer.available(251), "Stadium 2 251-model cache did not become ready")
  assert(Importer.modelsEnabled(), "Stadium 2 models option is not enabled")
  assert(Importer.battleEnabled(), "Stadium 2 normal 3D battle option is not enabled")

  game.save.party = { Pokemon.new(game.data, "ESPEON", 50) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local battle = BattleState.newWild(game, "TYRANITAR", 50)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)
  for frame = 1, 420 do
    if battle.phase == "menu" then break end
    if frame % 8 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  assert(battle.phase == "menu", "Crystal Stadium 2 battle did not reach command menu")
  U.wait(15)

  local rigs = assert(battle._stadium2Rigs,
    "STADIUM2_IMPORTER did not create its battle renderer state")
  local player = assert(rigs[battle.player], "player Stadium 2 renderer missing")
  local enemy = assert(rigs[battle.enemy], "enemy Stadium 2 renderer missing")
  assert(player.dex == 196, "Espeon did not map to Stadium 2 record 196")
  assert(enemy.dex == 248, "Tyranitar did not map to Stadium 2 record 248")
  assert(player.rig and enemy.rig, "importer battle renderer rigs are incomplete")

  assert(U.shot(game, dir .. "/crystal_stadium2_espeon_vs_tyranitar.png"),
    "Crystal Stadium 2 battle screenshot was written")
  print("[driver] PASS Crystal 251 normal battle + STADIUM2_IMPORTER 3D models: Espeon vs Tyranitar")
end
