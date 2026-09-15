-- Kanto call sites for the Crystal friendship service. These adapters own only
-- friendship; the engine still applies the item, poison tick and teaching UI.
local Patches = require("mods.CRYSTAL_251.lib.runtime_patches")
local Happiness = require("mods.CRYSTAL_251.core.gen2.Happiness")
local Bridge = {}
local GYM = { OPP_BROCK=true, OPP_MISTY=true, OPP_LT_SURGE=true,
  OPP_ERIKA=true, OPP_KOGA=true, OPP_SABRINA=true, OPP_BLAINE=true,
  OPP_GIOVANNI=true, OPP_LORELEI=true, OPP_BRUNO=true, OPP_AGATHA=true,
  OPP_LANCE=true, OPP_RIVAL3=true }
local ITEMS = { HP_UP="USEDITEM", PROTEIN="USEDITEM", IRON="USEDITEM",
  CARBOS="USEDITEM", CALCIUM="USEDITEM", RARE_CANDY="GAINLEVEL",
  X_ATTACK="USEDXITEM", X_DEFEND="USEDXITEM", X_SPEED="USEDXITEM",
  X_SPECIAL="USEDXITEM", X_ACCURACY="USEDXITEM", DIRE_HIT="USEDXITEM",
  GUARD_SPEC="USEDXITEM" }

function Bridge.install(mod)
  if Bridge._installed then return end
  Bridge._installed = true
  mod.events:on("battle.started", function(ev)
    local battle = ev and ev.battle
    if not battle or not battle.crystal251Active or battle._crystalFriendshipGym
        or battle.kind == "link" or not GYM[battle.oppClass] then return end
    battle._crystalFriendshipGym = true
    Happiness.changeParty(battle.game and battle.game.save and battle.game.save.party, "GYMBATTLE")
  end)
  mod.events:on("battle.fainted", function(ev)
    local battle, battler = ev and ev.battle, ev and ev.battler
    if not battle or not battle.crystal251Active or battle.kind == "link"
        or not battler or not battler.isPlayer then return end
    local mon = battler.mon
    local enemy = battle.enemy and battle.enemy.mon
    Happiness.change(mon, enemy and (enemy.level or 0) >= (mon.level or 0) + 30
      and "BEATENBYSTRONGFOE" or "FAINTED")
  end)

  local ItemEffects = Patches.watch(require("src.inventory.ItemEffects"))
  local Follower = Patches.watch(require("src.world.PikachuFollower"))
  local Overworld = Patches.watch(require("src.world.OverworldController"))
  local pendingTM = setmetatable({}, {__mode="k"})
  local originalUse = ItemEffects.use
  ItemEffects.use = function(data, save, id, target, battle, ...)
    if target then pendingTM[target] = nil end
    local result, message, extra = originalUse(data, save, id, target, battle, ...)
    if result == "consumed" and ITEMS[id] then
      Happiness.change(target or (battle and battle.player and battle.player.mon), ITEMS[id])
    elseif result == "learn" and target then
      pendingTM[target] = message
    end
    return result, message, extra
  end
  local originalModify = Follower.modifyHappiness
  Follower.modifyHappiness = function(save, event, mon, ...)
    -- This notification occurs only after the Bag's teaching callback succeeds,
    -- including both an empty move slot and the four-move replacement screen.
    if event == "USEDTMHM" and mon and pendingTM[mon] then
      for _, move in ipairs(mon.moves or {}) do
        if move.id == pendingTM[mon] then
          pendingTM[mon] = nil
          Happiness.change(mon, "LEARNMOVE")
          break
        end
      end
    end
    return originalModify(save, event, mon, ...)
  end
  local originalPoison = Overworld.applyFieldPoison
  Overworld.applyFieldPoison = function(self, ...)
    local Game = require("src.core.Game")
    local exposed = {}
    for _, mon in ipairs(Game.save and Game.save.party or {}) do
      if mon.status == "PSN" and mon.hp > 0 then exposed[#exposed+1] = mon end
    end
    local result = originalPoison(self, ...)
    for _, mon in ipairs(exposed) do
      if mon.hp <= 0 then Happiness.change(mon, "POISONFAINT") end
    end
    return result
  end
end
return Patches.installers(Bridge)
