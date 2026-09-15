local RuntimePatches = require("mods.CRYSTAL_251.lib.runtime_patches")
-- Crystal item behavior that has no Gen I equivalent.  Everything in this
-- module is installed by CRYSTAL_251; the base item and encounter engines stay
-- untouched when the mod is disabled.

local Strings = require("src.core.Strings")

local Behaviors = {}

local HP_BERRIES = { BERRY=10, BERRY_JUICE=20, GOLD_BERRY=30 }
local STATUS_BERRIES = {
  PSNCUREBERRY={ PSN=true }, PRZCUREBERRY={ PAR=true },
  BURNT_BERRY={ FRZ=true }, ICE_BERRY={ BRN=true },
  MINT_BERRY={ SLP=true },
  MIRACLEBERRY={ PSN=true, PAR=true, FRZ=true, BRN=true, SLP=true },
}

local function monName(data, mon)
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  return (mon and mon.nickname) or (def and def.name)
    or (mon and mon.species) or "POKéMON"
end

local function activeBattler(battle, mon)
  if not battle or not mon then return nil end
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler and battler.mon == mon then return battler end
  end
end

local function clearBattleStatus(battler)
  if not battler then return end
  battler.sleepTurns = nil
  battler.toxicCounter = nil
  battler.nightmare = nil
end

function Behaviors.needsTarget(id)
  return HP_BERRIES[id] ~= nil or STATUS_BERRIES[id] ~= nil
    or id == "BITTER_BERRY" or id == "MYSTERYBERRY"
end

function Behaviors.healsHP(id)
  return HP_BERRIES[id] ~= nil
end

function Behaviors.use(data, itemId, target, battle, moveIndex)
  if not Behaviors.needsTarget(itemId) then return nil end
  if not target or target.isEgg then
    return "failed", { "It won't have\nany effect." }
  end

  local name = monName(data, target)
  local amount = HP_BERRIES[itemId]
  if amount then
    if target.hp <= 0 or target.hp >= target.stats.hp then
      return "failed", { "It won't have\nany effect." }
    end
    local before = target.hp
    target.hp = math.min(target.stats.hp, target.hp + amount)
    return "consumed", { Strings("%s's HP\nwas restored!", name) },
      { healedFrom=before }
  end

  local battler = activeBattler(battle, target)
  local confused = battler and battler.confusedTurns ~= nil
  if itemId == "BITTER_BERRY" then
    if not confused then return "failed", { "It won't have\nany effect." } end
    battler.confusedTurns = nil
    return "consumed", { Strings("%s's\nstatus returned\nto normal!", name) }
  end

  local cures = STATUS_BERRIES[itemId]
  if cures then
    local curesMajor = target.status and cures[target.status]
    local curesConfusion = itemId == "MIRACLEBERRY" and confused
    if not curesMajor and not curesConfusion then
      return "failed", { "It won't have\nany effect." }
    end
    if curesMajor then
      target.status = nil
      clearBattleStatus(battler)
    end
    if curesConfusion then battler.confusedTurns = nil end
    return "consumed", { Strings("%s's\nstatus returned\nto normal!", name) }
  end

  if itemId == "MYSTERYBERRY" then
    local move = target.moves and target.moves[moveIndex or 0]
    local def = move and data and data.moves and data.moves[move.id]
    local maxPP = def and (def.pp
      + (move.ppUps or 0) * math.floor(def.pp / 5))
    if not maxPP or move.pp >= maxPP then
      return "failed", { "It won't have\nany effect." }
    end
    move.pp = math.min(maxPP, move.pp + 5)
    return "consumed", { Strings("%s's PP\nwas restored!", def.name or move.id) }
  end
end

-- Cleanse Tag halves the encounter rate when anyone in the party holds it,
-- matching ApplyCleanseTagEffectOnEncounterRate.  Make a
-- shallow replacement so later encounter hooks never see their source table
-- mutated.  ctx.save is convenient for tests; the live overworld uses Game.
function Behaviors.cleanseEncounter(next, encDef, ctx)
  local save = ctx and ctx.save
  if not save then
    local ok, game = pcall(require, "src.core.Game")
    save = ok and game and game.save or nil
  end
  local hasCleanseTag = false
  for _, mon in ipairs((save and save.party) or {}) do
    if mon.heldItem == "CLEANSE_TAG" then hasCleanseTag = true break end
  end
  local group = encDef and encDef.grass
  if not (hasCleanseTag and group and group.rate) then
    return next(encDef, ctx)
  end
  local replacement = {}
  for key, value in pairs(encDef) do replacement[key] = value end
  replacement.grass = {}
  for key, value in pairs(group) do replacement.grass[key] = value end
  replacement.grass.rate = math.floor(group.rate / 2)
  return next(replacement, ctx)
end

local function refreshBagRow(game, list, id)
  for index, row in ipairs(list.items or {}) do
    if row.value == id then
      local left = game.save.inventory[id]
      if left then row.right = "x" .. left else table.remove(list.items, index) end
      break
    end
  end
  list.index = math.min(list.index, math.max(1, #list.items))
end

-- MysteryBerry needs Crystal's two-stage party -> move picker.  BagMenu's
-- Gen I flow only knows that UI for Ether, so wrap the constructed screen and
-- replace only MysteryBerry's USE callback.
local function installMysteryBerryUI()
  local BagMenu = RuntimePatches.watch(require("src.ui.BagMenu"))
  if BagMenu._crystal251MysteryBerry then return end
  BagMenu._crystal251MysteryBerry = true
  local originalNew = BagMenu.new

  local function useMystery(game, battle, bag)
    require("src.ui.Screens").push(game, "PartyMenu", {
      pickOnly=true, battle=battle,
      onSwitch=function(mon)
        local rows = {}
        for index, move in ipairs(mon.moves or {}) do
          local def = game.data.moves[move.id]
          rows[#rows + 1] = { value=index,
            label=(def and def.name) or move.id, right=tostring(move.pp or 0) }
        end
        game.stack:push(require("src.ui.ListMenu").new(game, "Which move?", rows, {
          onChoose=function(row, moves)
            moves:close()
            local result, messages = require("src.inventory.ItemEffects").use(
              game.data, game.save, "MYSTERYBERRY", mon, battle, row.value,
              game.overworld)
            if result == "consumed" then
              require("src.inventory.Bag").remove(game.save, "MYSTERYBERRY", 1)
              refreshBagRow(game, bag, "MYSTERYBERRY")
              if battle then bag:close() end
            end
            game.stack:push(require("src.render.TextBox").new(game,
              table.concat(messages or {}, "\f"), function()
                if result == "consumed" and battle then battle:itemUsed({}) end
              end))
          end,
        }))
      end,
    })
  end

  BagMenu.new = function(game, opts)
    local bag = originalNew(game, opts)
    local battle = opts and opts.battle
    local originalChoose = bag.onChoose
    bag.onChoose = function(row, list)
      if not row or row.value ~= "MYSTERYBERRY" then
        return originalChoose(row, list)
      end
      if battle then return useMystery(game, battle, bag) end
      originalChoose(row, list)
      local menu = game.stack:top()
      if menu and menu.items and menu.items[1]
         and menu.items[1].label == Strings("USE") then
        menu.items[1].onSelect = function() useMystery(game, nil, bag) end
      end
    end
    return bag
  end
end

function Behaviors.install(mod)
  mod.hooks:wrap("encounter.roll", Behaviors.cleanseEncounter, 15)
  installMysteryBerryUI()
  return Behaviors
end

return RuntimePatches.installers(Behaviors)
