-- Canonical Generation II battle stat-stage helpers for CRYSTAL_251.
--
-- The base engine exposes one legacy `special` stage. Crystal has separate
-- Special Attack and Special Defense stages, so the mod owns the canonical
-- seven-stage table and never aliases the two split stats after migration.

local CrystalStats = {}

CrystalStats.STAGE_KEYS = {
  "attack", "defense", "speed",
  "specialAttack", "specialDefense",
  "accuracy", "evasion",
}

local VALID = {}
for _, key in ipairs(CrystalStats.STAGE_KEYS) do VALID[key] = true end
CrystalStats.VALID = VALID

local function clamp(value)
  value = tonumber(value) or 0
  if value < -6 then return -6 end
  if value > 6 then return 6 end
  return value
end

function CrystalStats.ensure(battler)
  battler.stages = battler.stages or {}
  local stages = battler.stages
  local legacy = stages.special
  if stages.specialAttack == nil then stages.specialAttack = clamp(legacy) end
  if stages.specialDefense == nil then stages.specialDefense = clamp(legacy) end
  -- Once the split fields exist, keeping a writable shared field would let a
  -- later native effect silently couple them again.
  stages.special = nil
  return stages
end

function CrystalStats.get(battler, stat)
  local stages = CrystalStats.ensure(battler)
  return clamp(stages[stat])
end

function CrystalStats.set(battler, stat, value)
  assert(VALID[stat], "unknown Crystal stat stage: " .. tostring(stat))
  local stages = CrystalStats.ensure(battler)
  stages[stat] = clamp(value)
  battler.hazeStatReset = nil
  return stages[stat]
end

function CrystalStats.change(battler, stat, delta)
  local old = CrystalStats.get(battler, stat)
  local new = CrystalStats.set(battler, stat, old + (delta or 0))
  return old, new, new ~= old
end

function CrystalStats.copy(target, source)
  local sourceStages = CrystalStats.ensure(source)
  local copied = {}
  for _, stat in ipairs(CrystalStats.STAGE_KEYS) do
    copied[stat] = clamp(sourceStages[stat])
  end
  target.stages = copied
  target.hazeStatReset = nil
  return copied
end

function CrystalStats.reset(battler)
  local stages = {}
  for _, stat in ipairs(CrystalStats.STAGE_KEYS) do stages[stat] = 0 end
  battler.stages = stages
  battler.hazeStatReset = nil
  return stages
end

return CrystalStats
