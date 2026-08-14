package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n")
      :format(message, tostring(got), tostring(want)))
  end
end

local Registry = require("mods.CRYSTAL_251.lib.registry")
local EngineRegistry = require("src.mods.Registry")

local function fakeRegistry(seed)
  local values, calls = seed or {}, { register=0, override=0 }
  return {
    get = function(_, id) return values[id] end,
    register = function(_, id, value)
      calls.register = calls.register + 1
      assert(values[id] == nil, id .. " already registered")
      values[id] = value
    end,
    override = function(_, id, value)
      calls.override = calls.override + 1
      assert(values[id] ~= nil, id .. " is not registered")
      values[id] = value
    end,
  }, values, calls
end

local empty, emptyValues, emptyCalls = fakeRegistry()
eq(Registry.upsert(empty, "STEEL", { name="Steel" }), "register",
  "missing content registers")
eq(emptyCalls.register, 1, "missing content uses register exactly once")
eq(emptyCalls.override, 0, "missing content does not override")
eq(emptyValues.STEEL.name, "Steel", "registered content is retained")

local occupied, occupiedValues, occupiedCalls = fakeRegistry({
  BULBASAUR = { image="other-mod.png" },
})
eq(Registry.upsert(occupied, "BULBASAUR", { image="crystal.png" }), "override",
  "existing content overrides without a duplicate registration")
eq(occupiedCalls.register, 0, "occupied content never calls register")
eq(occupiedCalls.override, 1, "occupied content overrides exactly once")
eq(occupiedValues.BULBASAUR.image, "crystal.png",
  "intentional replacement wins deterministically")

local ok, err = pcall(Registry.upsert, {}, "BROKEN", {})
eq(ok, false, "invalid registry is rejected immediately")
eq(tostring(err):find("get/register/override", 1, true) ~= nil, true,
  "invalid registry error names its required contract")

-- Exercise the production registry, not only the deliberately strict fake.
-- This reproduces the original cross-mod failure: one owner has already
-- registered the id before Crystal initializes.
local engineIcons = EngineRegistry.new("icons")
engineIcons:register("BULBASAUR", { image="unique-menu-icons.png" },
  "unique_menu_icons")
eq(Registry.upsert(engineIcons, "BULBASAUR", { image="crystal.png" }),
  "override", "production duplicate icon becomes an explicit override")
eq(engineIcons:get("BULBASAUR").image, "crystal.png",
  "production registry folds the override without throwing")

local engineTypes = EngineRegistry.new("type_chart")
engineTypes:register("STEEL", { name="Steel", category="physical" },
  "other_type_mod")
eq(Registry.upsert(engineTypes, "STEEL",
  { name="Steel", category="physical", index=9 }), "override",
  "production duplicate type becomes an explicit override")
eq(engineTypes:get("STEEL").index, 9,
  "production type override retains Crystal's complete definition")

if failures > 0 then
  io.stderr:write(("%d/%d registry compatibility checks failed\n")
    :format(failures, checks))
  os.exit(1)
end
print(("PASS %d registry compatibility checks"):format(checks))
