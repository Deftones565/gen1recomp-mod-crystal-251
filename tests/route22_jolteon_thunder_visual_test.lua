return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function move(id)
    local def = assert(game.data.moves[id], "missing move " .. id)
    return { id = id, pp = def.pp or 1 }
  end

  assert(GameVersion.get() == "yellow", "run this driver with POKEPORT_VERSION=yellow")

  local thunderDef = assert(game.data.moves.THUNDER, "missing THUNDER")
  if thunderDef.effect ~= "CRYSTAL_EFFECT_98"
      or not (game.data.move_effects and game.data.move_effects.CRYSTAL_EFFECT_98) then
    local records = {}
    local testMod = {
      content = {
        move_effects = {
          register = function(_, id, def) records[id] = def end,
        },
      },
      hooks = { wrap = function() end },
      events = { on = function() end },
    }
    require("mods.CRYSTAL_251.effects").install(testMod)
    local thunderEffect = assert(records.CRYSTAL_EFFECT_98,
      "CRYSTAL_251 effects.lua did not register CRYSTAL_EFFECT_98")
    game.data.move_effects = game.data.move_effects or {}
    game.data.move_effects.CRYSTAL_EFFECT_98 = thunderEffect
    thunderDef.effect = "CRYSTAL_EFFECT_98"
    thunderDef.effectChance = thunderDef.effectChance or 77
    U.log("CRYSTAL_251 was not active; installed its THUNDER effect directly for this test.")
  end

  game.save.inventory = game.save.inventory or {}
  for _, row in ipairs((game.data.constants and game.data.constants.badgeBoosts) or {}) do
    if row.badge then game.save.inventory[row.badge] = 1 end
  end

  local lead = Pokemon.new(game.data, "SNORLAX", 50)
  lead.moves = {
    move("TACKLE"),
    move("BODY_SLAM"),
    move("REST"),
    move("AMNESIA"),
  }
  game.save.party = { lead }
  game.save.player = game.save.player or {}
  game.save.player.name = "RED"
  game.save.player.rival = "BLUE"

  U.teleport(game, "ROUTE_22", 28, 4, "right")
  U.wait(10)

  local trainer = assert(game.data.trainers.OPP_RIVAL2, "missing OPP_RIVAL2")
  trainer.parties = trainer.parties or {}
  local partyDef = trainer.parties[8]
  local testParty = { { species = "JOLTEON", level = 53 } }
  for i = 1, 5 do
    local source = partyDef and partyDef[i]
    if source then
      local row = {}
      for key, value in pairs(source) do row[key] = value end
      testParty[#testParty + 1] = row
    else
      testParty[#testParty + 1] = { species = "RATTATA", level = 5 }
    end
  end
  trainer.parties[8] = testParty

  local ok, battle = pcall(BattleState.newTrainer, game, "OPP_RIVAL2", 8)
  trainer.parties[8] = partyDef
  if not ok then error(battle, 0) end

  local generated = battle.enemyParty
  local jolteon = generated[1]
  battle.enemyParty = {
    generated[2],
    generated[3],
    generated[4],
    generated[5],
    generated[6],
    generated[1],
  }
  for i = 1, 5 do battle.enemyParty[i].hp = 0 end
  jolteon.moves = {
    move("PIN_MISSILE"),
    move("THUNDER_WAVE"),
    move("AGILITY"),
    move("THUNDER"),
  }
  battle.enemyIndex = 6
  battle.weather = nil
  battle.onFinish = function() end
  battle.enemyAction = function(self)
    for _, m in ipairs(self.enemy.mon.moves or {}) do
      if m.id == "THUNDER" then return m end
    end
    error("Jolteon does not have THUNDER")
  end

  local originalPerformMove = battle.performMove
  local thunderVisualPlayed = false
  battle.performMove = function(self, user, target, moveInst, isCalled)
    if not thunderVisualPlayed and user == self.enemy and moveInst and moveInst.id == "THUNDER" then
      thunderVisualPlayed = true
      U.log("JOLTEON selected THUNDER; playing its animation before entering the crash path.")
      self:sayNext("Enemy JOLTEON used\nTHUNDER!")
      self:animNext("THUNDER", false)
      self:actNext(function()
        game.capturePath = DIR .. "/route22_jolteon_4_thunder_visual.png"
        U.log("THUNDER animation completed. Screenshot requested before reproducing the crash.")
      end)
      self:waitNext(30)
      self:actNext(function()
        U.log("Invoking CRYSTAL_251's real THUNDER path now; buggy builds should stack-overflow here.")
        originalPerformMove(self, user, target, moveInst, isCalled)
      end)
      return
    end
    return originalPerformMove(self, user, target, moveInst, isCalled)
  end

  game.overworld:pushBattle(battle)
  U.shot(game, DIR .. "/route22_jolteon_0_transition.png")

  local active = false
  for _ = 1, 600 do
    if game.stack:top() == battle then
      active = true
      break
    end
    U.wait(2)
  end
  assert(active, "battle did not become active")
  assert(battle.enemy and battle.enemy.mon == jolteon, "active enemy is not the Route 22 Jolteon")
  assert(battle.enemy.mon.species == "JOLTEON" and battle.enemy.mon.level == 53, "active enemy is not level 53 Jolteon")

  U.shot(game, DIR .. "/route22_jolteon_1_intro.png")

  local atMenu = false
  for _ = 1, 500 do
    if game.stack:top() == battle and battle.phase == "menu" then
      atMenu = true
      break
    end
    U.tap(game, "a")
    U.wait(5)
  end
  assert(atMenu, "battle command menu did not appear")

  U.shot(game, DIR .. "/route22_jolteon_2_command.png")
  U.tap(game, "a")

  local atMoves = false
  for _ = 1, 120 do
    if game.stack:top() == battle and battle.phase == "moveSelect" then
      atMoves = true
      break
    end
    U.wait(2)
  end
  assert(atMoves, "move select did not appear")

  U.shot(game, DIR .. "/route22_jolteon_3_before_thunder.png")
  U.log("Yellow Route 22 post-badge rival reproduction is ready.")
  U.log("BLUE has five fainted Pokemon and a level 53 JOLTEON active.")
  U.log("JOLTEON has PIN MISSILE / THUNDER WAVE / AGILITY / THUNDER.")
  U.log("Its next action is forced to THUNDER with normal weather.")
  U.log("Press A on TACKLE. JOLTEON is faster and will attempt THUNDER first.")
  U.log("This test now renders THUNDER before entering the known stack-overflow path.")
  U.log("On the buggy CRYSTAL_251 effects.lua this should reproduce stack overflow.")
  U.log("Screenshots are under " .. DIR)

  while true do
    coroutine.yield()
  end
end
