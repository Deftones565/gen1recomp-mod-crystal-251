-- Pokemon Crystal major-status and volatile-state model.
--
-- The base engine intentionally keeps Generation I status semantics.  This
-- module owns the Generation II differences while CRYSTAL_251 is active:
-- wake-and-move sleep, Gen II poison/burn/leech damage, substitute and
-- safeguard gates, Disable/Encore counters, partial trapping, and switch
-- cleanup.  Runtime adaptation is installed from runtime_bridge.lua.

local Runtime = require("src.mods.Runtime")
local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")

local CrystalStatus = {}

local function clamp(value, low, high)
  value = math.floor(tonumber(value) or low)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function name(battler)
  if not battler then return "Pokemon" end
  return battler.isPlayer and tostring(battler.name)
    or ("Enemy " .. tostring(battler.name))
end
CrystalStatus.displayName = name

local function hasType(battler, wanted)
  for _, typeId in ipairs((battler and battler.curTypes) or {}) do
    if typeId == wanted then return true end
  end
  return false
end
CrystalStatus.hasType = hasType

local function sideFor(battle, battler)
  battle.crystalStatusSides = battle.crystalStatusSides
    or { player={}, enemy={} }
  return battler.isPlayer and battle.crystalStatusSides.player
    or battle.crystalStatusSides.enemy
end
CrystalStatus.sideFor = sideFor

function CrystalStatus.syncSide(battle, battler)
  if not (battle and battler) then return end
  local side = sideFor(battle, battler)
  battler.safeguardTurns = side.safeguardTurns
end

function CrystalStatus.beginBattle(battle)
  if not battle then return end
  battle.crystal251Active = true
  battle.crystalStatusSides = battle.crystalStatusSides
    or { player={}, enemy={} }
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler then
      battler.crystal251Active = true
      CrystalStatus.syncSide(battle, battler)
    end
  end
end

local STATUS_EFFECT_ALIASES = {
  SLEEP_EFFECT=0x01,
  POISON_SIDE_EFFECT1=0x02,
  BURN_SIDE_EFFECT1=0x04,
  FREEZE_SIDE_EFFECT1=0x05,
  PARALYZE_SIDE_EFFECT1=0x06,
  FLINCH_SIDE_EFFECT1=0x1f,
  TRAPPING_EFFECT=0x2a,
  MIST_EFFECT=0x2e,
  FOCUS_ENERGY_EFFECT=0x2f,
  CONFUSION_EFFECT=0x31,
  PARALYZE_EFFECT=0x43,
  CONFUSION_SIDE_EFFECT=0x4c,
  SUBSTITUTE_EFFECT=0x4f,
  LEECH_SEED_EFFECT=0x54,
  DISABLE_EFFECT=0x56,
}
CrystalStatus.STATUS_EFFECT_ALIASES = STATUS_EFFECT_ALIASES

local function rawEffect(code)
  return ("CRYSTAL_EFFECT_%02X"):format(code)
end

-- Old Kanto moves are registered with Generation I effect aliases.  Route
-- only status/volatile families to the Crystal records; ordinary damage and
-- unrelated old effects remain owned by the base registry.
function CrystalStatus.patchMoves(mod, crystalMoves)
  local patched = 0
  for id, row in pairs(crystalMoves or {}) do
    local code = STATUS_EFFECT_ALIASES[row.effect]
    if row.effect == "POISON_EFFECT" then
      code = id == "TOXIC" and 0x21 or 0x42
    elseif id == "REST" then
      code = 0x20
    end
    if code then
      local effect = rawEffect(code)
      row.effect = effect
      if mod.content.moves:get(id) then
        mod.content.moves:patch(id, {
          effect=effect,
          effectChance=row.effectChance,
        })
      end
      patched = patched + 1
    end
  end
  return patched
end

local function statusMessage(target, status, toxic)
  if status == "SLP" then return name(target) .. " fell asleep!" end
  if status == "PSN" then
    return toxic and (name(target) .. " was badly poisoned!")
      or (name(target) .. " was poisoned!")
  end
  if status == "BRN" then return name(target) .. " was burned!" end
  if status == "FRZ" then return name(target) .. " was frozen solid!" end
  if status == "PAR" then return name(target) .. " was paralyzed!" end
  return name(target) .. " was afflicted!"
end

-- Replacement for StatusRegistry.inflict while a Crystal battle is active.
function CrystalStatus.inflict(battle, target, status, opts)
  opts = opts or {}
  if not (target and target.mon) or target.mon.status then return {} end
  CrystalStatus.syncSide(battle, target)
  if (target.safeguardTurns or 0) > 0 and not opts.ignoreSafeguard then
    return {}
  end
  -- Generation II Substitute blocks external major status regardless of
  -- whether it came from a primary move or a damaging side effect.
  if target.substituteHP and not opts.ignoreSubstitute then return {} end

  if status == "PSN" and (hasType(target, "POISON") or hasType(target, "STEEL")) then
    return {}
  elseif status == "BRN" and hasType(target, "FIRE") then
    return {}
  elseif status == "FRZ" and hasType(target, "ICE") then
    return {}
  elseif status == "PAR" and opts.moveType == "ELECTRIC"
      and hasType(target, "GROUND") then
    return {}
  end

  target.mon.status = status
  if status == "SLP" then
    -- Crystal stores a 1..7 counter. It is decremented before the move
    -- gate, so the application turn counts and a counter of 1 wakes and
    -- moves at the next opportunity.
    if opts.rest then
      target.sleepTurns = 3
    else
      local rng = battle and battle.rng or function(low) return low end
      target.sleepTurns = clamp(rng(1, 7), 1, 7)
    end
    target.nightmare = nil
  elseif status == "PSN" then
    target.toxicCounter = opts.toxic and 1 or nil
  else
    target.toxicCounter = nil
    if status == "FRZ" then target.crystalJustFrozen = true end
  end

  Runtime.emit("battle.status_inflicted", {
    battle=battle, target=target, status=status, source=opts.source,
  })
  return { statusMessage(target, status, opts.toxic) }
end

local function append(out, text)
  if text then out[#out + 1] = text end
end

-- Crystal CheckTurn order for ordinary moves.  Snore/Sleep Talk thaw/sleep
-- exceptions are prepared by BattleState.statusInterrupt before this call.
function CrystalStatus.beforeMove(battler, rng, battle, action)
  rng = rng or function(low) return low end
  local out = {}
  local mon = battler.mon

  if battler.skipMove then
    battler.skipMove = nil
    return false, out
  end
  if mon.status == "SLP" then
    battler.sleepTurns = (battler.sleepTurns or 2) - 1
    if battler.sleepTurns <= 0 then
      mon.status, battler.sleepTurns, battler.nightmare = nil, nil, nil
      append(out, name(battler) .. " woke up!")
      -- Generation II continues into the selected move after waking.
    else
      append(out, name(battler) .. " is fast asleep!")
      return false, out
    end
  end

  if mon.status == "FRZ" then
    append(out, name(battler) .. " is frozen solid!")
    return false, out
  end

  -- Crystal checks sleep and freeze before consuming a pending flinch.
  if battler.flinched then
    battler.flinched = false
    append(out, name(battler) .. " flinched!")
    return false, out
  end

  if battler.disabledTurns then
    battler.disabledTurns = battler.disabledTurns - 1
    if battler.disabledTurns <= 0 then
      battler.disabledTurns, battler.disabledSlot, battler.disabledMove = nil, nil, nil
      append(out, name(battler) .. " is disabled no more!")
    end
  end
  local actionId = action and action.id
  if battler.disabledMove and actionId == battler.disabledMove then
    append(out, tostring(actionId) .. " is disabled!")
    return false, out
  end

  if battler.confusedTurns then
    battler.confusedTurns = battler.confusedTurns - 1
    if battler.confusedTurns <= 0 then
      battler.confusedTurns = nil
      append(out, name(battler) .. " snapped out of confusion!")
    else
      append(out, name(battler) .. " is confused!")
      if rng(0, 255) < 128 then return false, out, true end
    end
  end

  if mon.status == "PAR" and rng(0, 255) < 63 then
    append(out, name(battler) .. " is fully paralyzed!")
    return false, out
  end
  return true, out
end

local function directDamage(battler, amount)
  amount = math.max(1, math.floor(amount or 1))
  amount = math.min(amount, battler.mon.hp)
  battler.mon.hp = battler.mon.hp - amount
  return amount
end

function CrystalStatus.clearTrap(target)
  if not target then return end
  local source = target.crystalTrapSource
  target.crystalTrapTurns, target.crystalTrapSource = nil, nil
  target.crystalTrapMove = nil
  if target.cantEscapeFrom == source then
    target.cantEscape, target.cantEscapeFrom = nil, nil
  end
end

-- Replacement for Status.residual.  Crystal uses 1/8 for ordinary poison,
-- burn and Leech Seed; Toxic alone advances in 1/16 steps.  Partial trapping
-- is residual damage and does not stop the target from acting.
function CrystalStatus.actionResidual(battler, opponent, battle)
  local out = {}
  local mon = battler.mon
  battler.skipMove = nil
  if mon.hp <= 0 then return out end

  if mon.status == "PSN" then
    local damage
    if battler.toxicCounter then
      damage = math.max(1, math.floor(mon.stats.hp / 16)) * battler.toxicCounter
      battler.toxicCounter = math.min(15, battler.toxicCounter + 1)
    else
      damage = math.max(1, math.floor(mon.stats.hp / 8))
    end
    directDamage(battler, damage)
    append(out, name(battler) .. "\nis hurt by poison!")
  elseif mon.status == "BRN" then
    directDamage(battler, math.floor(mon.stats.hp / 8))
    append(out, name(battler) .. "\nis hurt by its burn!")
  end

  if battler.leechSeeded and mon.hp > 0 and opponent and opponent.mon
      and opponent.mon.hp > 0 then
    local damage = directDamage(battler, math.floor(mon.stats.hp / 8))
    opponent.mon.hp = math.min(opponent.mon.stats.hp, opponent.mon.hp + damage)
    append(out, "LEECH SEED\nsapped " .. name(battler) .. "!")
  end

  if mon.status ~= "SLP" then battler.nightmare = nil end
  if battler.nightmare and mon.hp > 0 then
    directDamage(battler, math.floor(mon.stats.hp / 4))
    append(out, name(battler) .. "\nis locked in a\nNIGHTMARE!")
  end
  if battler.cursed and mon.hp > 0 then
    directDamage(battler, math.floor(mon.stats.hp / 4))
    append(out, name(battler) .. "\nis afflicted by\nthe CURSE!")
  end
  return out
end

function CrystalStatus.wrapResidual(battler, battle)
  local out = {}
  if not (battler and battler.mon and battler.mon.hp > 0
      and battler.crystalTrapTurns and battler.crystalTrapTurns > 0) then
    return out
  end
  -- HandleWrap returns immediately while the trapped battler has a
  -- Substitute; the count neither advances nor deals damage.
  if battler.substituteHP then return out end
  battler.crystalTrapTurns = battler.crystalTrapTurns - 1
  if battler.crystalTrapTurns <= 0 then
    append(out, name(battler) .. "\nwas released from\n"
      .. tostring(battler.crystalTrapMove or "the binding move") .. "!")
    CrystalStatus.clearTrap(battler)
    return out
  end
  directDamage(battler, math.floor(battler.mon.stats.hp / 16))
  append(out, name(battler) .. "'s\nhurt by\n"
    .. tostring(battler.crystalTrapMove or "the binding move") .. "!")
  return out
end

-- Compatibility helper for direct unit tests and callers that still request
-- the old combined residual routine. Live Crystal battles use the scheduler's
-- actionResidual and wrapResidual phases separately.
function CrystalStatus.residual(battler, opponent, battle)
  local out = CrystalStatus.actionResidual(battler, opponent, battle)
  for _, message in ipairs(CrystalStatus.wrapResidual(battler, battle)) do
    out[#out + 1] = message
  end
  return out
end

function CrystalStatus.confuse(ctx, target, secondary)
  target = target or ctx.target
  CrystalStatus.syncSide(ctx.battle, target)
  if (target.safeguardTurns or 0) > 0 or target.substituteHP then
    return secondary and {} or { "But, it failed!" }
  end
  if target.confusedTurns then return secondary and {} or { "But, it failed!" } end
  target.confusedTurns = clamp(ctx.rng(2, 5), 2, 5)
  Runtime.emit("battle.confusion_inflicted", {
    battle=ctx.battle, target=target, source=ctx.user,
  })
  return { name(target) .. " became confused!" }
end

function CrystalStatus.disable(ctx)
  local target = ctx.target
  if target.substituteHP or target.disabledTurns then return { "But, it failed!" } end
  local last = target.lastMove
  if not last or last == "STRUGGLE" then return { "But, it failed!" } end
  local slot
  for index, moveInst in ipairs(target.curMoves or {}) do
    if moveInst.id == last and (moveInst.pp or 0) > 0 then
      slot = index
      break
    end
  end
  if not slot then return { "But, it failed!" } end
  target.disabledMove, target.disabledSlot = last, slot
  target.disabledTurns = clamp(ctx.rng(2, 8), 2, 8)
  return { tostring(last) .. " was disabled!" }
end

function CrystalStatus.encore(ctx)
  local target = ctx.target
  if target.substituteHP or target.encoreTurns then return { "But, it failed!" } end
  local last = target.lastMove
  if not last or last == "STRUGGLE" or last == "ENCORE" or last == "MIRROR_MOVE" then
    return { "But, it failed!" }
  end
  local slot
  for _, moveInst in ipairs(target.curMoves or {}) do
    if moveInst.id == last and (moveInst.pp or 0) > 0 then slot = moveInst break end
  end
  if not slot then return { "But, it failed!" } end
  target.encoreMove = last
  target.encoreTurns = clamp(ctx.rng(3, 6), 3, 6)
  target.encoreSetTurn = ctx.battle.turnCount or 0
  return { name(target) .. " got an ENCORE!" }
end

function CrystalStatus.substitute(ctx)
  local user = ctx.user
  if user.substituteHP then return { name(user) .. " already has a SUBSTITUTE!" } end
  local cost = math.max(1, math.floor(user.mon.stats.hp / 4))
  if user.mon.hp <= cost then return { "Too weak to make a SUBSTITUTE!" } end
  user.mon.hp = user.mon.hp - cost
  user.substituteHP = cost
  return { name(user) .. " made a SUBSTITUTE!" }
end

function CrystalStatus.rest(ctx)
  local user, mon = ctx.user, ctx.user.mon
  if mon.hp >= mon.stats.hp then return { "But, it failed!" } end
  mon.hp = mon.stats.hp
  mon.status = nil
  user.toxicCounter, user.nightmare = nil, nil
  CrystalStatus.inflict(ctx.battle, user, "SLP", {
    rest=true, ignoreSafeguard=true, ignoreSubstitute=true, source="REST",
  })
  if ctx.drain then ctx.drain() end
  return { name(user) .. " went to sleep and became healthy!" }
end

function CrystalStatus.leechSeed(ctx)
  local target = ctx.target
  if target.substituteHP or target.leechSeeded or hasType(target, "GRASS") then
    return { "But, it failed!" }
  end
  target.leechSeeded = true
  return { name(target) .. " was seeded!" }
end

function CrystalStatus.startSafeguard(ctx)
  local side = sideFor(ctx.battle, ctx.user)
  if (side.safeguardTurns or 0) > 0 then return { "But, it failed!" } end
  side.safeguardTurns = 5
  CrystalStatus.syncSide(ctx.battle, ctx.user)
  return { name(ctx.user) .. " is protected by SAFEGUARD!" }
end

function CrystalStatus.startMist(ctx)
  if ctx.user.mist then return { "But, it failed!" } end
  ctx.user.mist = true
  return { name(ctx.user) .. " became shrouded in mist!" }
end

function CrystalStatus.startFocusEnergy(ctx)
  if ctx.user.focusEnergy then return { "But, it failed!" } end
  ctx.user.focusEnergy = true
  return { name(ctx.user) .. " is getting pumped!" }
end

function CrystalStatus.flinch(ctx)
  if not ctx.target.substituteHP then ctx.target.flinched = true end
  return {}
end

function CrystalStatus.trapAfterDamage(ctx, totalDealt)
  if not totalDealt or totalDealt <= 0 or ctx.target.substituteHP then return end
  local target = ctx.target
  if (tonumber(target.crystalTrapTurns) or 0) > 0 then return end
  target.crystalTrapTurns = clamp(ctx.rng(2, 5), 2, 5)
  target.crystalTrapSource = ctx.user
  target.crystalTrapMove = ctx.move.id
  target.cantEscape, target.cantEscapeFrom = true, ctx.user
end

function CrystalStatus.meanLook(ctx)
  if ctx.target.cantEscape then return { "But, it failed!" } end
  ctx.target.cantEscape, ctx.target.cantEscapeFrom = true, ctx.user
  return { name(ctx.target) .. " can't escape now!" }
end

function CrystalStatus.nightmare(ctx)
  if ctx.target.substituteHP or ctx.target.mon.status ~= "SLP" or ctx.target.nightmare then
    return { "But, it failed!" }
  end
  ctx.target.nightmare = true
  return { name(ctx.target) .. " began having a NIGHTMARE!" }
end

function CrystalStatus.attract(ctx)
  local target = ctx.target
  local userGender = Gender.forMon(ctx.user.mon)
  local targetGender = Gender.forMon(target.mon)
  if target.substituteHP or not userGender or not targetGender
      or userGender == targetGender or target.infatuatedWith then
    return { "But, it failed!" }
  end
  target.infatuatedWith = ctx.user
  return { name(target) .. " fell in love!" }
end

function CrystalStatus.perishSong(ctx)
  local user, target = ctx.user, ctx.target
  if user.perishTurns and target.perishTurns then return { "But, it failed!" } end
  if not user.perishTurns then user.perishTurns = 3 end
  if not target.perishTurns then target.perishTurns = 3 end
  return { "Both Pokemon will faint in 3 turns!" }
end

function CrystalStatus.rapidSpin(ctx)
  local user, target, battle = ctx.user, ctx.target, ctx.battle
  user.leechSeeded = nil
  CrystalStatus.clearTrap(user)
  if user.isPlayer then battle.playerSpikes = nil else battle.enemySpikes = nil end
  -- Clear the user's own binding attack if one is still attached to the foe.
  if target and target.crystalTrapSource == user then CrystalStatus.clearTrap(target) end
  return { name(user) .. " blew away trapping effects!" }
end

local CLEAR_ON_SWITCH = {
  "substituteHP", "confusedTurns", "disabledTurns", "disabledSlot",
  "disabledMove", "encoreTurns", "encoreMove", "encoreSetTurn",
  "leechSeeded", "cursed", "nightmare", "perishTurns", "foresight",
  "focusEnergy", "mist", "defenseCurl", "minimized", "infatuatedWith",
  "protect", "endure", "protectChain", "protectLastTurn",
  "lockedTarget", "lockOnTurns", "destinyBond",
}

function CrystalStatus.onSwitch(battle, incoming, previous, batonPass)
  if incoming then CrystalStatus.syncSide(battle, incoming) end
  if not previous then return end
  if not batonPass then
    for _, field in ipairs(CLEAR_ON_SWITCH) do previous[field] = nil end
    previous.toxicCounter = nil -- Gen II switch-in starts Toxic as plain poison.
    CrystalStatus.clearTrap(previous)
  end
  for _, other in ipairs({ battle.player, battle.enemy }) do
    if other and other ~= incoming then
      if other.infatuatedWith == previous then other.infatuatedWith = nil end
      if other.crystalTrapSource == previous then
        CrystalStatus.clearTrap(other)
      elseif other.cantEscapeFrom == previous then
        if batonPass then other.cantEscapeFrom = incoming
        else other.cantEscape, other.cantEscapeFrom = nil, nil end
      end
    end
  end
end

function CrystalStatus.beginTurn(battle)
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler then
      battler.protect, battler.endure, battler.flinched = nil, nil, nil
    end
  end
end

function CrystalStatus.tickSafeguard(battle, order)
  local sideState = battle.crystalStatusSides
  order = order or { battle.player, battle.enemy }
  if sideState then
    for _, battler in ipairs(order) do
      if battler then
        local side = battler.isPlayer and sideState.player or sideState.enemy
        if side.safeguardTurns then
          side.safeguardTurns = side.safeguardTurns - 1
          if side.safeguardTurns <= 0 then side.safeguardTurns = nil end
        end
      end
    end
  end
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler then CrystalStatus.syncSide(battle, battler) end
  end
end

function CrystalStatus.tickPerish(battle, order)
  order = order or { battle.player, battle.enemy }
  for _, battler in ipairs(order) do
    if battler and battler.mon.hp > 0 and battler.perishTurns then
      battler.perishTurns = battler.perishTurns - 1
      if battle.sayNext then
        battle:sayNext(name(battler) .. "'s perish count fell to "
          .. tostring(math.max(0, battler.perishTurns)) .. "!")
      end
      if battler.perishTurns <= 0 then
        battle:applyDamage(battler, battler.mon.hp)
      end
    end
  end
end

function CrystalStatus.handleDefrost(battle, order)
  order = order or { battle.player, battle.enemy }
  for _, battler in ipairs(order) do
    if battler and battler.mon.hp > 0 and battler.mon.status == "FRZ"
       and not battler.crystalJustFrozen
       and battle.rng(0, 255) < 25 then
      battler.mon.status = nil
      if battle.sayNext then battle:sayNext(name(battler) .. " was defrosted!") end
    end
    if battler then battler.crystalJustFrozen = nil end
  end
end

function CrystalStatus.tickEncore(battle, order)
  order = order or { battle.player, battle.enemy }
  for _, battler in ipairs(order) do
    if battler and battler.mon.hp > 0 and battler.encoreTurns
       and (battle.turnCount or 0) > (battler.encoreSetTurn or -1) then
      battler.encoreTurns = battler.encoreTurns - 1
      if battler.encoreTurns <= 0 then
        battler.encoreTurns, battler.encoreMove, battler.encoreSetTurn = nil, nil, nil
        if battle.sayNext then battle:sayNext(name(battler) .. "'s ENCORE ended!") end
      end
    end
  end
end

function CrystalStatus.endTurn(battle)
  -- Compatibility path for direct callers. Live battles use
  -- crystal_scheduler and therefore run these residuals after each action.
  if battle.player and battle.enemy then
    if battle.player.mon.hp > 0 and battle.enemy.mon.hp > 0 then
      CrystalStatus.actionResidual(battle.player, battle.enemy, battle)
    end
    if battle.enemy.mon.hp > 0 and battle.player.mon.hp > 0 then
      CrystalStatus.actionResidual(battle.enemy, battle.player, battle)
    end
  end
  CrystalStatus.tickPerish(battle)
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if battler and battler.mon.hp <= 0 and battle.onFaint then battle:onFaint(battler) end
  end
  CrystalStatus.tickSafeguard(battle)
  CrystalStatus.tickEncore(battle)
end

return CrystalStatus
