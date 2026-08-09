-- Kanto acquisition sources for Crystal-only items. The conversion keeps
-- Kanto's geography, so specialist marts carry items that fit their region;
-- EXP.SHARE is an early, visible one-time pickup beside Cerulean Gym.

local Progression = {}

Progression.items = {
  "HEAVY_BALL", "LEVEL_BALL", "LURE_BALL", "FAST_BALL", "FRIEND_BALL",
  "MOON_BALL", "LOVE_BALL", "EXP_SHARE", "LUCKY_EGG",
  "BRIGHTPOWDER", "LUCKY_PUNCH", "METAL_POWDER", "QUICK_CLAW",
  "PSNCUREBERRY", "SOFT_SAND", "SHARP_BEAK", "PRZCUREBERRY",
  "BURNT_BERRY", "ICE_BERRY", "POISON_BARB", "KINGS_ROCK",
  "BITTER_BERRY", "MINT_BERRY", "SILVERPOWDER", "AMULET_COIN",
  "CLEANSE_TAG", "MYSTIC_WATER", "TWISTEDSPOON", "BLACKBELT_I",
  "BLACKGLASSES", "PINK_BOW", "STICK", "SMOKE_BALL", "NEVERMELTICE",
  "MAGNET", "MIRACLEBERRY", "SPELL_TAG", "MIRACLE_SEED", "THICK_CLUB",
  "FOCUS_BAND", "HARD_STONE", "CHARCOAL", "BERRY_JUICE", "SCOPE_LENS",
  "METAL_COAT", "DRAGON_FANG", "LEFTOVERS", "MYSTERYBERRY",
  "DRAGON_SCALE", "BERSERK_GENE", "LIGHT_BALL", "POLKADOT_BOW", "BERRY",
  "GOLD_BERRY", "SUN_STONE", "UP_GRADE", "LINKING_CORD", "FLOWER_MAIL",
  "SURF_MAIL", "LITEBLUEMAIL", "PORTRAITMAIL", "LOVELY_MAIL", "EON_MAIL",
  "MORPH_MAIL", "BLUESKY_MAIL", "MUSIC_MAIL", "MIRAGE_MAIL",
}

-- Appended to the existing clerk inventories. Repeated entries across cities
-- are intentional: early regional stock remains useful after later shops open.
Progression.shops = {
  {
    map = "PewterMart", text = "TEXT_PEWTERMART_CLERK",
    items = { "SOFT_SAND", "HARD_STONE", "SHARP_BEAK", "STICK", "THICK_CLUB" },
  },
  {
    map = "CeruleanMart", text = "TEXT_CERULEANMART_CLERK",
    items = { "HEAVY_BALL", "LURE_BALL", "FRIEND_BALL", "BERRY",
      "PSNCUREBERRY", "PRZCUREBERRY", "MYSTIC_WATER", "MIRACLE_SEED",
      "SURF_MAIL" },
  },
  {
    map = "VermilionMart", text = "TEXT_VERMILIONMART_CLERK",
    items = { "FAST_BALL", "QUICK_CLAW", "MAGNET", "METAL_COAT",
      "SMOKE_BALL", "AMULET_COIN", "LITEBLUEMAIL", "BLUESKY_MAIL" },
  },
  {
    map = "LavenderMart", text = "TEXT_LAVENDERMART_CLERK",
    items = { "MOON_BALL", "CLEANSE_TAG", "SPELL_TAG", "BITTER_BERRY",
      "MINT_BERRY", "MIRACLEBERRY", "EON_MAIL", "MORPH_MAIL", "MUSIC_MAIL" },
  },
  {
    map = "CeladonMart2F", text = "TEXT_CELADONMART2F_CLERK1",
    items = { "LEVEL_BALL", "LOVE_BALL", "BRIGHTPOWDER",
      "KINGS_ROCK", "PINK_BOW", "POLKADOT_BOW", "BLACKGLASSES",
      "FLOWER_MAIL", "PORTRAITMAIL", "LOVELY_MAIL", "MIRAGE_MAIL" },
  },
  {
    map = "CeladonMart4F", text = "TEXT_CELADONMART4F_CLERK",
    items = { "SUN_STONE", "KINGS_ROCK", "METAL_COAT", "DRAGON_SCALE",
      "UP_GRADE", "LINKING_CORD" },
  },
  {
    map = "FuchsiaMart", text = "TEXT_FUCHSIAMART_CLERK",
    items = { "LUCKY_PUNCH", "POISON_BARB", "SILVERPOWDER", "MIRACLE_SEED",
      "SHARP_BEAK", "FRIEND_BALL", "LOVE_BALL", "GOLD_BERRY" },
  },
  {
    map = "SaffronMart", text = "TEXT_SAFFRONMART_CLERK",
    items = { "TWISTEDSPOON", "SCOPE_LENS", "FOCUS_BAND", "METAL_POWDER",
      "UP_GRADE", "EXP_SHARE" },
  },
  {
    map = "CinnabarMart", text = "TEXT_CINNABARMART_CLERK",
    items = { "CHARCOAL", "NEVERMELTICE", "BURNT_BERRY", "ICE_BERRY",
      "BERRY_JUICE", "MYSTERYBERRY", "BERSERK_GENE", "LIGHT_BALL",
      "DRAGON_FANG", "DRAGON_SCALE" },
  },
  {
    map = "IndigoPlateauLobby", text = "TEXT_INDIGOPLATEAULOBBY_CLERK",
    items = { "EXP_SHARE", "LUCKY_EGG", "LEFTOVERS", "BLACKBELT_I",
      "FOCUS_BAND", "SCOPE_LENS", "GOLD_BERRY", "MIRACLEBERRY" },
  },
}

Progression.pickups = {
  {
    map = "CERULEAN_CITY", item = "EXP_SHARE", x = 33, y = 22,
    name = "CRYSTAL251_CERULEAN_EXP_SHARE",
    text = "TEXT_CRYSTAL251_CERULEAN_EXP_SHARE",
    note = "Visible pickup beside Cerulean Gym",
  },
}

local function copyList(list)
  local out = {}
  for i, value in ipairs(list or {}) do out[i] = value end
  return out
end

local function nextObjectIndex(map)
  local highest = 0
  for _, object in ipairs((map and map.objects) or {}) do
    highest = math.max(highest, tonumber(object.index) or 0)
  end
  return highest + 1
end

function Progression.install(mod)
  local sources = {}
  for _, shop in ipairs(Progression.shops) do
    local pointers = assert(mod.content.text_pointers:get(shop.map),
      "missing item progression text map " .. shop.map)
    local clerk = assert(pointers[shop.text],
      "missing item progression clerk " .. shop.map .. "/" .. shop.text)
    local stock, present = copyList(clerk.mart), {}
    for _, id in ipairs(stock) do present[id] = true end
    for _, id in ipairs(shop.items) do
      assert(mod.content.items:get(id), "missing Crystal item " .. id)
      if not present[id] then stock[#stock + 1], present[id] = id, true end
      sources[id] = sources[id] or {}
      sources[id][#sources[id] + 1] = { method = "mart", map = shop.map }
    end
    mod.content.text_pointers:patch(shop.map, {
      [shop.text] = { mart = stock },
    })
  end

  for _, pickup in ipairs(Progression.pickups) do
    local map = assert(mod.content.maps:get(pickup.map),
      "missing item progression map " .. pickup.map)
    assert(mod.content.items:get(pickup.item),
      "missing Crystal pickup " .. pickup.item)
    mod.content.maps:patch(pickup.map, { objects = { __append = { {
      index = nextObjectIndex(map), x = pickup.x, y = pickup.y,
      sprite = "SPRITE_POKE_BALL", movement = "STAY", range = "NONE",
      item = pickup.item, text = pickup.text, name = pickup.name,
    } } } })
    sources[pickup.item] = sources[pickup.item] or {}
    sources[pickup.item][#sources[pickup.item] + 1] = {
      method = "item_ball", map = pickup.map, x = pickup.x, y = pickup.y,
    }
  end

  for _, id in ipairs(Progression.items) do
    assert(sources[id] and #sources[id] > 0,
      "Crystal-only item has no Kanto acquisition source: " .. id)
  end

  return { items = Progression.items, shops = Progression.shops,
    pickups = Progression.pickups, sources = sources }
end

return Progression
