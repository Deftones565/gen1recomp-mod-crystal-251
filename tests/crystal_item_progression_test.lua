package.path = "./?.lua;./?/init.lua;" .. package.path

local Progression = require("mods.CRYSTAL_251.item_progression")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n")
      :format(label, tostring(got), tostring(want)))
  end
end
local function ok(value, label) eq(not not value, true, label) end

local unique, source = {}, {}
for _, id in ipairs(Progression.items) do
  ok(not unique[id], id .. " appears once in the Crystal-only catalog")
  unique[id] = true
end
for _, shop in ipairs(Progression.shops) do
  ok(type(shop.map) == "string" and type(shop.text) == "string",
    "shop has a concrete Kanto clerk")
  for _, id in ipairs(shop.items) do source[id] = true end
end
for _, pickup in ipairs(Progression.pickups) do source[pickup.item] = true end
for _, id in ipairs(Progression.items) do
  ok(source[id], id .. " has a Kanto acquisition source")
end
ok(not unique.PARK_BALL, "Park Ball is excluded from the item catalog")
ok(not source.PARK_BALL, "Park Ball has no Kanto acquisition source")

local evolutionItems = require("mods.CRYSTAL_251.lib.evolutions").requiredItems
for _, id in ipairs(evolutionItems) do
  ok(source[id], id .. " required evolution item is obtainable in Kanto")
end
ok(not unique.LINKING_CORD, "Linking Cord is unnecessary and not sold")

local expPickup
for _, pickup in ipairs(Progression.pickups) do
  if pickup.item == "EXP_SHARE" then expPickup = pickup break end
end
ok(expPickup, "EXP.SHARE has a visible pickup")
eq(expPickup and expPickup.map, "CERULEAN_CITY",
  "EXP.SHARE is in Misty's town")
eq(expPickup and expPickup.x, 33, "EXP.SHARE has a fixed Cerulean X")
eq(expPickup and expPickup.y, 22, "EXP.SHARE has a fixed Cerulean Y")

-- Validate the authored coordinate against the actual generated collision map
-- and ensure it does not overlap an existing warp, sign, or NPC.
local maps = require("data.generated.maps")
local tilesets = require("data.generated.tilesets")
local Map = require("src.world.Map")
local cerulean = maps.CERULEAN_CITY
ok(Map.defIsWalkableCell(cerulean, tilesets[cerulean.tileset],
  expPickup.x, expPickup.y), "EXP.SHARE item ball occupies a walkable cell")
for _, object in ipairs(cerulean.objects or {}) do
  ok(object.x ~= expPickup.x or object.y ~= expPickup.y,
    "EXP.SHARE does not overlap native object " .. tostring(object.name))
end
for _, warp in ipairs(cerulean.warps or {}) do
  ok(warp.x ~= expPickup.x or warp.y ~= expPickup.y,
    "EXP.SHARE does not overlap a Cerulean warp")
end
for _, sign in ipairs(cerulean.signs or {}) do
  ok(sign.x ~= expPickup.x or sign.y ~= expPickup.y,
    "EXP.SHARE does not overlap a Cerulean sign")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal item progression)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal item progression)"):format(checks, checks))
