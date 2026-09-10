-- Generation II DetermineMoveOrder, adapted to the Gen I BattleState shape.
-- The battle shell still owns execution; this module owns only the cart's
-- priority, Quick Claw, effective-speed, and speed-tie rules.

local Damage = require("mods.CRYSTAL_251.battle.gen2.Damage")

local TurnOrder = {}

local PRIORITY = {
  QUICK_ATTACK = 1, MACH_PUNCH = 1, EXTREMESPEED = 1,
  PROTECT = 3, DETECT = 3, ENDURE = 3,
  COUNTER = -1, MIRROR_COAT = -1, VITAL_THROW = -1,
  ROAR = -1, WHIRLWIND = -1,
}

local function speedOf(battler)
  local mon = battler and battler.mon or battler or {}
  local stats = mon.stats or battler.curStats or {}
  local speed = stats.speed or 1
  local stages = battler.stages or {}
  speed = Damage.applyStage(speed, stages.speed or 0)
  -- Gen II's paralysis penalty is applied after stat-stage calculation.
  if mon.status == "PAR" then speed = math.floor(speed / 4) end
  return math.max(1, speed)
end

local function priority(move)
  if not move then return 0 end
  return move.priority or PRIORITY[move.id] or 0
end

local function roll(rng, low, high)
  local value = rng and rng(low, high) or low
  return math.max(low, math.min(high, value))
end

local function quickClaw(battler, rng)
  local mon = battler and battler.mon or battler or {}
  return mon.heldItem == "QUICK_CLAW"
    and roll(rng, 0, 255) < 60
end

function TurnOrder.effectiveSpeed(battler)
  return speedOf(battler)
end

function TurnOrder.firstMover(a, aMove, b, bMove, rng, invertTie)
  local pa, pb = priority(aMove), priority(bMove)
  if pa ~= pb then return pa > pb end

  -- DetermineMoveOrder checks Quick Claw before comparing speed.
  local aClaw, bClaw = quickClaw(a, rng), quickClaw(b, rng)
  if aClaw or bClaw then
    -- The non-link Gen II routine gives the enemy's successful roll the first
    -- chance; the mirrored/link path reverses that order for lockstep sync.
    return invertTie and aClaw or not bClaw
  end

  local sa, sb = speedOf(a), speedOf(b)
  if sa ~= sb then return sa > sb end
  local first = roll(rng, 0, 1) == 0
  return invertTie and not first or first
end

return TurnOrder
