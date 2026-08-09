-- Umbrella audit for every active Crystal-only item in CRYSTAL_251.
--
-- This deliberately runs the focused suites in separate LuaJIT processes:
-- their runtime bridges patch shared modules, so isolation makes the result
-- independent of suite order and matches running each test on its own.

package.path = "./?.lua;./?/init.lua;" .. package.path

local Progression = require("mods.CRYSTAL_251.item_progression")

local MAIL = {
  FLOWER_MAIL=true, SURF_MAIL=true, LITEBLUEMAIL=true, PORTRAITMAIL=true,
  LOVELY_MAIL=true, EON_MAIL=true, MORPH_MAIL=true, BLUESKY_MAIL=true,
  MUSIC_MAIL=true, MIRAGE_MAIL=true,
}

-- Each entry names the focused behavioral suite responsible for the item.
-- Acquisition and held-item acceptance are additionally checked for the
-- entire list by the progression and live-runtime suites.
local coverage = {}
local function cover(suite, items)
  for _, item in ipairs(items) do
    assert(not coverage[item], "duplicate all-item coverage entry: " .. item)
    coverage[item] = suite
  end
end

cover("capture", {
  "HEAVY_BALL", "LEVEL_BALL", "LURE_BALL", "FAST_BALL",
  "FRIEND_BALL", "MOON_BALL", "LOVE_BALL",
})
cover("experience and money", {
  "EXP_SHARE", "LUCKY_EGG", "AMULET_COIN",
})
cover("damage and type boosts", {
  "SOFT_SAND", "SHARP_BEAK", "POISON_BARB", "SILVERPOWDER",
  "MYSTIC_WATER", "TWISTEDSPOON", "BLACKBELT_I", "BLACKGLASSES",
  "PINK_BOW", "NEVERMELTICE", "MAGNET", "SPELL_TAG", "MIRACLE_SEED",
  "HARD_STONE", "CHARCOAL", "DRAGON_FANG", "POLKADOT_BOW",
})
cover("battle held effects", {
  "BRIGHTPOWDER", "LUCKY_PUNCH", "METAL_POWDER", "QUICK_CLAW",
  "STICK", "SMOKE_BALL", "THICK_CLUB", "FOCUS_BAND", "SCOPE_LENS",
  "LEFTOVERS", "BERSERK_GENE", "LIGHT_BALL",
})
cover("held and Pack berries", {
  "PSNCUREBERRY", "PRZCUREBERRY", "BURNT_BERRY", "ICE_BERRY",
  "BITTER_BERRY", "MINT_BERRY", "MIRACLEBERRY", "BERRY_JUICE",
  "MYSTERYBERRY", "BERRY", "GOLD_BERRY",
})
cover("encounters", { "CLEANSE_TAG" })
cover("battle and evolution", { "KINGS_ROCK", "METAL_COAT", "DRAGON_SCALE" })
cover("evolution", { "SUN_STONE", "UP_GRADE", "LINKING_CORD" })

local expected, active = {}, {}
for _, item in ipairs(Progression.items) do
  if not MAIL[item] then
    assert(item ~= "PARK_BALL", "Park Ball must remain excluded")
    assert(not expected[item], "duplicate active Crystal item: " .. item)
    expected[item] = true
    active[#active + 1] = item
  end
end

assert(#active == 57,
  ("active Crystal item count changed: got %d, expected 57"):format(#active))
for _, item in ipairs(active) do
  assert(coverage[item], "active Crystal item has no behavior audit: " .. item)
end
for item, suite in pairs(coverage) do
  assert(expected[item], item .. " is audited by " .. suite
    .. " but is not in the active Crystal item catalog")
end

local suites = {
  "mods/CRYSTAL_251/tests/crystal_item_behaviors_test.lua",
  "mods/CRYSTAL_251/tests/crystal_held_items_test.lua",
  "mods/CRYSTAL_251/tests/crystal_progression_test.lua",
  "mods/CRYSTAL_251/tests/crystal_item_progression_test.lua",
  "mods/CRYSTAL_251/tests/move_parity_edge_test.lua",
}

local function succeeded(a, _, c)
  -- LuaJIT/Lua 5.1 returns a numeric shell status.  Lua 5.2+ returns
  -- true,"exit",0; accepting both keeps the audit convenient elsewhere.
  if type(a) == "number" then return a == 0 end
  return a == true and (c == nil or c == 0)
end

for _, path in ipairs(suites) do
  local file = assert(io.open(path, "rb"), "missing item audit suite: " .. path)
  file:close()
  io.write(("\n==> %s\n"):format(path))
  io.flush()
  local a, b, c = os.execute("luajit " .. path)
  assert(succeeded(a, b, c), "Crystal item audit suite failed: " .. path)
end

print(("\n57/57 active Crystal items covered; %d/%d suites passed")
  :format(#suites, #suites))
