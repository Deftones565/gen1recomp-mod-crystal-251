package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end
local function ok(value, message)
  checks = checks + 1
  if not value then fail(message) end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    fail(("%s (got %s, want %s)"):format(message, tostring(got), tostring(want)))
  end
end
local function read(path)
  local file = assert(io.open(path, "rb"))
  local value = file:read("*a")
  file:close()
  return value
end

local Bridge = require("mods.CRYSTAL_251.lib.stadium2_bridge")
local stadiumPackSource = read("mods/DRAMATIC_SHAPE/lib/StadiumPack.lua")
local stadiumFragmentSource = read("mods/DRAMATIC_SHAPE/lib/StadiumFragment.lua")

local battleValue = "flatB"
local forcedOG = false
local modules = {
  StadiumPack = {
    keep = function() end,
    forget = function() end,
    invalidate = function() end,
  },
  Stadium = { update = function() end },
  StadiumMon = {},
  StadiumRig = { new = function() return nil end },
  StadiumInstall = {},
  StadiumRom = {
    normalise = function(value) return value end,
    decompress = function(value) return value end,
  },
  StadiumBuild = { CONTEXTS = {}, pack = function() return "DSM3" end },
  StadiumFx = { attach = function() end },
  StadiumRomPick = {},
  StadiumScreen = {
    new = function() return {} end,
    newNote = function() return {} end,
  },
  OverworldBattle = {},
}
for index = 1, 20 do modules.StadiumBuild.CONTEXTS[index] = "slot" .. index end
modules.OverworldBattle.setting = {
  values = { true, "flatB", "stadium", "stadiumB", false },
  labels = { "2D-3D A", "2D-3D B", "STADIUM A", "STADIUM B", "OFF" },
  get = function() return battleValue end,
  setValue = function(_, value) battleValue = value; return value end,
}
modules.OverworldBattle.forceOG = function() forcedOG = true end

local dramaticMod = { log = { info=function() end, warn=function() end, error=function() end } }
function dramaticMod:read(path)
  if path == "lib/StadiumPack.lua" then return stadiumPackSource end
  if path == "lib/StadiumFragment.lua" then return stadiumFragmentSource end
end
local V = { mod = dramaticMod, path = "mods/DRAMATIC_SHAPE" }
function V.require(name) return assert(modules[name], name) end

_G.love = { filesystem = {
  getInfo = function(path)
    if path == Bridge.MARKER or path:match("%.dsm$") then return { type="file" } end
  end,
  read = function(path)
    if path == Bridge.MARKER then return Bridge.FORMAT .. " 251 2 testmd5\n" end
  end,
} }

ok(Bridge.install({ log=dramaticMod.log }, { species={} }, { exports={ lib=V } }),
  "Stadium 2 selector installs through DRAMATIC_SHAPE exports")
eq(modules.OverworldBattle.setting.labels[3], "STADIUM 2 A",
  "map-stage model rung is visibly labelled Stadium 2")
eq(modules.OverworldBattle.setting.labels[4], "STADIUM 2 B",
  "disc-stage model rung is visibly labelled Stadium 2")

local row = assert(Bridge.modelRow())
eq(row.label, "STADIUM 2 MODELS", "Crystal exposes a model selector row")
eq(row.value(), "OFF", "selector starts on the current 2D-card choice")
row.step({})
eq(battleValue, "stadiumB", "enabling models preserves disc stage B")
eq(row.value(), "ON", "selector reports Stadium 2 as active")
ok(forcedOG, "enabling Stadium 2 models pins the compatible battle layout")
row.step({})
eq(battleValue, "flatB", "disabling models restores 2D cards on stage B")
battleValue = true
row.step({})
eq(battleValue, "stadium", "map stage A switches directly to Stadium 2")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal Stadium 2 selection)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal Stadium 2 selection)"):format(checks, checks))
