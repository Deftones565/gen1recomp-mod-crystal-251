package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function ok(value, message)
  checks = checks + 1
  if not value then failures = failures + 1; io.stderr:write("FAIL " .. message .. "\n") end
end
local function read(path)
  local file = assert(io.open(path, "rb"))
  local value = file:read("*a")
  file:close()
  return value
end

local crystalMain = read("mods/CRYSTAL_251/main.lua")
local crystalManifest = read("mods/CRYSTAL_251/manifest.json")
local importerMain = read("mods/STADIUM2_IMPORTER/main.lua")
local battle = read("mods/STADIUM2_IMPORTER/lib/battle.lua")

ok(not crystalMain:find("stadium2_models", 1, true), "Crystal contains no Stadium 2 renderer adapter")
ok(not crystalMain:find("STADIUM2_IMPORTER", 1, true), "Crystal runtime does not locate or drive the importer")
ok(not crystalManifest:find('"STADIUM2_IMPORTER"', 1, true), "Crystal no longer needs an importer dependency")
local old = io.open("mods/CRYSTAL_251/battle/stadium2_models.lua", "rb")
ok(old == nil, "Crystal-side Stadium battle renderer is removed")
if old then old:close() end
ok(importerMain:find('require("mods.STADIUM2_IMPORTER.lib.battle")', 1, true) ~= nil, "importer owns the battle presentation module")
ok(importerMain:find("Battle.install()", 1, true) ~= nil, "importer installs its own battle path")
ok(importerMain:find("Battle.configureGame", 1, true) ~= nil, "importer configures itself from merged game data")
ok(battle:find("function Battle.configureGame", 1, true) ~= nil, "battle module detects the active dex range")
ok(battle:find("data.pokemon", 1, true) ~= nil, "battle module resolves species from normal merged battle data")
ok(battle:find("_stadium2Rigs", 1, true) ~= nil, "renderer rigs are importer-owned")
ok(battle:find("BattleState.drawBattlerPic", 1, true) ~= nil, "importer replaces the normal Pokemon picture layer")
ok(battle:find("BattleState.drawPicsLayer", 1, true) ~= nil and battle:find("BattleState.growInScale", 1, true) ~= nil, "importer owns send-out grow routing without a 2D Pokemon fallback")
ok(not battle:find("DRAMATIC_SHAPE", 1, true), "importer battle path has no Dramatic Shape dependency")
ok(not importerMain:find("battle_scene", 1, true), "rejected custom Stadium arena is removed")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal importer ownership)\n"):format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal importer ownership)"):format(checks, checks))
