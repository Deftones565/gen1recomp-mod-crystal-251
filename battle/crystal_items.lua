local CrystalItems = {}
local CrystalStats = require("mods.CRYSTAL_251.battle.crystal_stats")
local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
local Runtime = require("src.mods.Runtime")

local TYPE_BOOST = {
  PINK_BOW="NORMAL", POLKADOT_BOW="NORMAL",
  BLACKBELT_I="FIGHTING", SHARP_BEAK="FLYING",
  POISON_BARB="POISON", SOFT_SAND="GROUND", HARD_STONE="ROCK",
  SILVERPOWDER="BUG", SPELL_TAG="GHOST", CHARCOAL="FIRE",
  MYSTIC_WATER="WATER", MIRACLE_SEED="GRASS", MAGNET="ELECTRIC",
  TWISTEDSPOON="PSYCHIC_TYPE", NEVERMELTICE="ICE",
  DRAGON_SCALE="DRAGON", BLACKGLASSES="DARK", METAL_COAT="STEEL",
}
CrystalItems.TYPE_BOOST = TYPE_BOOST

local MAIL = {
  FLOWER_MAIL=true, SURF_MAIL=true, LITEBLUEMAIL=true, PORTRAITMAIL=true,
  LOVELY_MAIL=true, EON_MAIL=true, MORPH_MAIL=true, BLUESKY_MAIL=true,
  MUSIC_MAIL=true, MIRAGE_MAIL=true,
}
CrystalItems.MAIL = MAIL

local STATUS_CURE = {
  PSNCUREBERRY={ PSN=true },
  PRZCUREBERRY={ PAR=true },
  BURNT_BERRY={ FRZ=true },
  ICE_BERRY={ BRN=true },
  MINT_BERRY={ SLP=true },
  MIRACLEBERRY={ SLP=true, PSN=true, BRN=true, FRZ=true, PAR=true },
}

local HEALING = { BERRY=10, BERRY_JUICE=20, GOLD_BERRY=30 }
local ITEM_PARAM = {
  BRIGHTPOWDER=20, QUICK_CLAW=60, KINGS_ROCK=30, FOCUS_BAND=30,
}

local function held(battler)
  return battler and battler.mon and battler.mon.heldItem or nil
end


local function speciesOf(battler)
  local state = battler and battler.crystal251Battle
  return state and state.transformedSpecies
    or (battler and battler.mon and battler.mon.species)
end

local function itemName(battle, item)
  local def = battle and battle.data and battle.data.items
    and battle.data.items[item]
  return (def and def.name) or tostring(item)
end

local function displayName(battler)
  if not battler then return "POKEMON" end
  return battler.isPlayer and battler.name or ("Enemy " .. tostring(battler.name))
end

function CrystalItems.isMail(item, data)
  if MAIL[item] then return true end
  local def = data and data.items and data.items[item]
  return def and (def.isMail or def.mail) or false
end

function CrystalItems.rollWildHeldItem(slots, rng)
  if not slots then return nil end
  rng = rng or function(a, b) return math.random(a, b) end
  local roll = rng(0, 255)
  if roll < 5 then return slots.rare or slots[2] end
  if roll < 64 then return slots.common or slots[1] end
  return nil
end

function CrystalItems.consume(battle, battler)
  local item = held(battler)
  if not item then return nil end
  battler.mon.heldItem = nil
  Runtime.emit("battle.held_item_consumed", {
    battle=battle, battler=battler, item=item,
  })
  return item
end

function CrystalItems.criticalStage(user, move)
  local stage = 0
  local item = held(user)
  if item == "SCOPE_LENS" then stage = stage + 1 end
  local species = speciesOf(user)
  if species == "CHANSEY" and item == "LUCKY_PUNCH" then stage = stage + 2 end
  if species == "FARFETCHD" and item == "STICK" then stage = stage + 2 end
  return stage
end

function CrystalItems.modifyDamageStats(user, target, category, attack, defense)
  local userItem = held(user)
  local species = speciesOf(user)
  if category == "physical" and userItem == "THICK_CLUB"
     and (species == "CUBONE" or species == "MAROWAK") then
    attack = attack * 2
  elseif category == "special" and userItem == "LIGHT_BALL"
     and species == "PIKACHU" then
    attack = attack * 2
  end

  while attack > 255 or defense > 255 do
    attack = math.max(1, math.floor(attack / 4))
    defense = math.max(1, math.floor(defense / 4))
  end

  if held(target) == "METAL_POWDER"
     and speciesOf(target) == "DITTO"
     and not (target.crystal251Battle and target.crystal251Battle.transformed) then
    local boosted = defense + math.floor(defense / 2)
    if boosted > 255 then
      attack = math.max(1, math.floor(attack / 2))
      defense = math.floor(boosted / 2)
    else
      defense = boosted
    end
  end
  return attack, defense
end

function CrystalItems.modifyBaseDamage(user, move, damage)
  local item = held(user)
  if item and TYPE_BOOST[item] == move.type then
    damage = math.floor(damage * (100 + 10) / 100)
  end
  return damage
end

function CrystalItems.withBrightPowder(next, ctx)
  if held(ctx and ctx.target) ~= "BRIGHTPOWDER" then return next(ctx) end
  local original = ctx.rng
  ctx.rng = function(a, b)
    local roll = original(a, b)
    if a == 0 and b == 255 then
      return math.min(255, roll + ITEM_PARAM.BRIGHTPOWDER)
    end
    return roll
  end
  local ok, result = pcall(next, ctx)
  ctx.rng = original
  if not ok then error(result, 0) end
  return result
end

local function quickClawProc(battler, rng)
  return held(battler) == "QUICK_CLAW"
    and rng(0, 255) < ITEM_PARAM.QUICK_CLAW
end

function CrystalItems.firstMover(next, a, aMove, b, bMove, ctx)
  if not ((a and a.crystal251Active) or (b and b.crystal251Active)) then
    return next(a, aMove, b, bMove, ctx)
  end
  if not aMove or not bMove
     or (aMove.priority or 0) ~= (bMove.priority or 0) then
    return next(a, aMove, b, bMove, ctx)
  end
  local rng = ctx and ctx.rng or function(a0, b0) return math.random(a0, b0) end
  local aQuick = held(a) == "QUICK_CLAW"
  local bQuick = held(b) == "QUICK_CLAW"
  if aQuick and bQuick then
    if ctx and ctx.invertTie then
      if quickClawProc(a, rng) then return true end
      if quickClawProc(b, rng) then return false end
    else
      if quickClawProc(b, rng) then return false end
      if quickClawProc(a, rng) then return true end
    end
  elseif aQuick then
    if quickClawProc(a, rng) then return true end
  elseif bQuick then
    if quickClawProc(b, rng) then return false end
  end
  return next(a, aMove, b, bMove, ctx)
end


function CrystalItems.run(next, ctx)
  local battle = ctx and ctx.battle
  local player = battle and battle.player
  if held(player) == "SMOKE_BALL" then
    CrystalItems.consume(battle, player)
    return true
  end
  if player and player.cantEscape then return false end
  return next(ctx)
end

function CrystalItems.focusBandDamage(battle, target, damage)
  if not (battle and battle.crystal251Active and target and target.mon)
     or target.substituteHP or held(target) ~= "FOCUS_BAND"
     or damage < target.mon.hp or target.mon.hp <= 1 then
    return damage, false
  end
  if battle.rng(0, 255) >= ITEM_PARAM.FOCUS_BAND then return damage, false end
  battle:sayNext(displayName(target) .. " hung on with FOCUS BAND!")
  return target.mon.hp - 1, true
end

local function scriptHasKingsRock(move)
  if not move then return false end
  local script = MoveScripts.forMove(move)
  for _, command in ipairs(script.commands or {}) do
    local op = type(command) == "table" and (command.op or command[1]) or command
    if op == "kingsrock" then return true end
  end
  return false
end

function CrystalItems.afterDamagingMove(ctx)
  if not (ctx and ctx.battle and ctx.battle.crystal251Active)
     or (ctx.totalDealt or 0) <= 0 or ctx.brokeSub
     or not ctx.target or ctx.target.mon.hp <= 0
     or held(ctx.user) ~= "KINGS_ROCK"
     or not scriptHasKingsRock(ctx.move) then
    return false
  end
  if ctx.rng(0, 255) >= ITEM_PARAM.KINGS_ROCK then return false end
  ctx.target.flinched = true
  return true
end

local function cureStatus(battle, battler)
  local status = battler and battler.mon and battler.mon.status
  local item = held(battler)
  local cures = item and STATUS_CURE[item]
  if not (status and cures and cures[status]) then return false end
  CrystalItems.consume(battle, battler)
  battler.mon.status = nil
  battler.sleepTurns = nil
  battler.toxicCounter = nil
  battler.nightmare = nil
  if item == "MIRACLEBERRY" then battler.confusedTurns = nil end
  battle:sayNext(displayName(battler) .. " recovered using "
    .. itemName(battle, item) .. "!")
  return true
end

local function cureConfusion(battle, battler)
  if not battler or not battler.confusedTurns then return false end
  local item = held(battler)
  if item ~= "BITTER_BERRY" and item ~= "MIRACLEBERRY" then return false end
  CrystalItems.consume(battle, battler)
  battler.confusedTurns = nil
  battle:sayNext(displayName(battler) .. " recovered using "
    .. itemName(battle, item) .. "!")
  return true
end

local function restorePP(battle, battler)
  if held(battler) ~= "MYSTERYBERRY" then return false end
  for _, move in ipairs(battler.curMoves or battler.mon.moves or {}) do
    if (move.pp or 0) == 0 then
      local amount = move.id == "SKETCH" and 1 or 5
      move.pp = move.pp + amount
      CrystalItems.consume(battle, battler)
      battle:sayNext(displayName(battler) .. " restored PP using MYSTERYBERRY!")
      return true
    end
  end
  return false
end

local function healHP(battle, battler, amount, item)
  local maxhp = battler.mon.stats.hp
  local before = battler.mon.hp
  battler.mon.hp = math.min(maxhp, before + math.max(1, amount))
  if battler.mon.hp == before then return false end
  battle:sayNext(displayName(battler) .. " recovered HP using "
    .. itemName(battle, item) .. "!")
  if battle.drainNext then battle:drainNext() end
  return true
end

local function useHealingBerry(battle, battler)
  local item = held(battler)
  local amount = item and HEALING[item]
  if not amount or battler.mon.hp <= 0
     or battler.mon.hp * 2 >= battler.mon.stats.hp then return false end
  CrystalItems.consume(battle, battler)
  return healHP(battle, battler, amount, item)
end

local function useLeftovers(battle, battler)
  if held(battler) ~= "LEFTOVERS" or battler.mon.hp <= 0
     or battler.mon.hp >= battler.mon.stats.hp then return false end
  return healHP(battle, battler,
    math.max(1, math.floor(battler.mon.stats.hp / 16)), "LEFTOVERS")
end

function CrystalItems.beginBattle(battle)
  if not battle then return end
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler then battler.crystal251Active = true end
  end
end

function CrystalItems.beginTurn(battle)
  if not battle then return end
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler and battler.mon.hp > 0 and held(battler) == "BERSERK_GENE" then
      CrystalItems.consume(battle, battler)
      CrystalStats.change(battler, "attack", 2)
      battler.confusedTurns = battler.confusedTurns or 256
      battle:sayNext(displayName(battler) .. "'s BERSERK GENE activated!")
    end
  end
end

function CrystalItems.onStatusInflicted(battle, battler)
  return cureStatus(battle, battler)
end

function CrystalItems.onConfusionInflicted(battle, battler)
  return cureConfusion(battle, battler)
end

local function ordered(order, battle)
  return order or { battle.player, battle.enemy }
end

function CrystalItems.handleLeftovers(battle, order)
  if not battle then return end
  for _, battler in ipairs(ordered(order, battle)) do
    if battler and battler.mon.hp > 0 then useLeftovers(battle, battler) end
  end
end

function CrystalItems.handleMysteryBerry(battle, order)
  if not battle then return end
  for _, battler in ipairs(ordered(order, battle)) do
    if battler and battler.mon.hp > 0 then restorePP(battle, battler) end
  end
end

function CrystalItems.handleHealingItems(battle, order)
  if not battle then return end
  for _, battler in ipairs(ordered(order, battle)) do
    if battler and battler.mon.hp > 0 then
      -- HandleHealingItems runs HP berries before status and confusion cures.
      useHealingBerry(battle, battler)
      cureStatus(battle, battler)
      cureConfusion(battle, battler)
    end
  end
end

function CrystalItems.endTurn(battle)
  CrystalItems.handleLeftovers(battle)
  CrystalItems.handleMysteryBerry(battle)
  CrystalItems.handleHealingItems(battle)
end

function CrystalItems.steal(ctx)
  if not ctx or (ctx.totalDealt or 0) <= 0 or ctx.brokeSub
     or ctx.target.substituteHP or held(ctx.user) ~= nil then return false end
  local item = held(ctx.target)
  if not item or CrystalItems.isMail(item, ctx.data) then return false end
  ctx.target.mon.heldItem = nil
  ctx.user.mon.heldItem = item
  ctx.say(displayName(ctx.user) .. " stole " .. itemName(ctx.battle, item) .. "!")
  return true
end

return CrystalItems
