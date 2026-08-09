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

local root = "mods/CRYSTAL_251/"
local effectsSource = read(root .. "effects.lua")
local mainSource = read(root .. "main.lua")
local manifestSource = read(root .. "manifest.json")
local importSource = read(root .. "import_screen.lua")
local crySource = read(root .. "lib/crystal_cry.lua")
local summarySource = read(root .. "battle/crystal_summary.lua")
local stadium2Source = read(root .. "lib/stadium2_bridge.lua")

ok(not effectsSource:find("implemented=false", 1, true),
  "final effects registry has no unimplemented placeholders")
ok(not effectsSource:find('runtime_bridge").install', 1, true),
  "effect registration no longer installs global runtime hooks")
local configureAt = assert(mainSource:find("bridge.setHeldItems", 1, true))
local installAt = assert(mainSource:find("bridge.install()", 1, true))
ok(installAt > configureAt,
  "runtime hooks install only after imported held-item data is configured")
ok(mainSource:find("local supported = { [24]=true }", 1, true) ~= nil,
  "loader accepts the auto-import schema 24 cache")
ok(not mainSource:find("local supported = { [22]=true }", 1, true)
   and not mainSource:find("local supported = { [23]=true }", 1, true),
  "loader rejects caches without the current import manifest")
ok(manifestSource:find('"version": "0.10.1"', 1, true) ~= nil,
  "boot-safe automatic Crystal import has version 0.10.1")
ok(manifestSource:find('"kanto_ascended"', 1, true) ~= nil,
  "manifest rejects Kanto Ascended because both mods own Generation II registries")
ok(mainSource:find("cacheFilesPresent", 1, true) ~= nil
   and mainSource:find("content.importFiles", 1, true) ~= nil,
  "loader rejects a cache whose generated Crystal files are missing")
ok(mainSource:find("Crystal251AutoImport", 1, true) ~= nil
   and mainSource:find('mod.events:on("screen.pushed"', 1, true) ~= nil
   and mainSource:find("ev.state.screenId == splash", 1, true) ~= nil
   and mainSource:find("ImportScreen.romPresent()", 1, true) ~= nil,
  "missing or obsolete Crystal data waits for the boot screen before auto-importing")
ok(mainSource:find('label = "CRYSTAL ROM"', 1, true) ~= nil,
  "OPTIONS exposes the manual Crystal ROM importer")
ok(importSource:find('Screen.ROM_DIR = "baseroms"', 1, true) ~= nil
   and importSource:find("function Screen.findRom()", 1, true) ~= nil
   and importSource:find("getSourceBaseDirectory", 1, true) ~= nil
   and importSource:find('addDirectory("", "")', 1, true) ~= nil,
  "Crystal auto-import scans baseroms and beside the game")
ok(importSource:find("content.importFiles = importedFiles", 1, true) ~= nil,
  "Crystal cache records every generated sprite and cry")
ok(importSource:find('local ERROR_LOG = "crystal_251/import_error.log"', 1, true) ~= nil
   and importSource:find("writeFailureLog", 1, true) ~= nil,
  "Crystal import writes the exact failure to terminal and a persistent log")
ok(importSource:find("traceback(worker, err)", 1, true) ~= nil,
  "Crystal coroutine failures retain a traceback and failing stage")
ok(importSource:find('Screen.PICKED = "picked_rom.gb"', 1, true) ~= nil
   and importSource:find('love.system.pickFile, "rom"', 1, true) ~= nil,
  "Crystal Android import uses Gen1Recomp's native ROM picker handoff")
ok(stadium2Source:find('Bridge.ANDROID_PICKED = "picked_rom.gb"', 1, true) ~= nil
   and stadium2Source:find('love.system.pickFile, "rom"', 1, true) ~= nil,
  "Stadium 2 Android import uses the native ROM picker handoff")
ok(stadium2Source:find("Bridge.ERROR_LOG", 1, true) ~= nil
   and stadium2Source:find("writeStadiumFailure", 1, true) ~= nil,
  "Stadium 2 import writes detailed failure diagnostics")
ok(stadium2Source:find("pcall(active.step, active)", 1, true) ~= nil,
  "unexpected Stadium 2 model-step exceptions become visible failures")
ok(mainSource:find("CrystalSummary.configure(crystalBaseStats)", 1, true) ~= nil,
  "summary receives the imported Crystal base-stat table")
ok(summarySource:find('{ "S.ATK", stats.specialAttack }', 1, true) ~= nil,
  "summary draws Special Attack separately")
ok(summarySource:find('{ "S.DEF", stats.specialDefense }', 1, true) ~= nil,
  "summary draws Special Defense separately")
ok(mainSource:find('require("mods.CRYSTAL_251.lib.stadium2_bridge")', 1, true) ~= nil,
  "Crystal installs the Stadium 2 bridge from its own mod")
ok(stadium2Source:find('Bridge.COUNT = 251', 1, true) ~= nil,
  "Stadium 2 bridge covers all 251 Pokemon")
ok(stadium2Source:find('species <= 251', 1, true) ~= nil,
  "the cloned DRAMATIC_SHAPE/DRAMALESS_SHAPE pack reader accepts the expanded dex")
ok(stadium2Source:find('Bridge.NORMAL_DIR', 1, true) ~= nil
   and stadium2Source:find('Bridge.SHINY_DIR', 1, true) ~= nil,
  "normal and shiny Stadium 2 packs are stored separately")
ok(not stadium2Source:find('mods/DRAMATIC_SHAPE', 1, true),
   or not stadium2Source:find('mods/DRAMALESS_SHAPE', 1, true),
  "compatibility does not patch DRAMATIC_SHAPE/DRAMALESS_SHAPE files on disk")
ok(importSource:find("CrystalCry.render(raw, definition)", 1, true) ~= nil,
  "Crystal imports use the mod-local cry renderer")
ok(not importSource:find("ChipSynth", 1, true),
  "Crystal cry import no longer routes through the Gen I command parser")
ok(not importSource:find("fallbackCry", 1, true),
  "Crystal cry failures can no longer silently become generic sounds")
ok(crySource:find("command < 0xd0", 1, true) ~= nil,
  "Crystal raw note-length bytes are decoded")
ok(crySource:find("command == 0xfd", 1, true) ~= nil,
  "Crystal sound loops use the Generation II opcode")
ok(crySource:find("command == 0xfe", 1, true) ~= nil,
  "Crystal sound calls use the Generation II opcode")

local installCounts = {}
local function installer(name)
  return {
    installRuntime = function()
      installCounts[name] = (installCounts[name] or 0) + 1
    end,
  }
end

local Pokemon = {
  new = function() return {} end,
}
local BattleState = {
  newWild = function() return { enemy={mon={}} } end,
  newTrainer = function() return { enemy={mon={}} } end,
  applyDamage = function(_, _, damage) return damage end,
  statusInterrupt = function() return false end,
}
local EffectRegistry = {
  runDamaging = function(_, ctx, record)
    return record and record.run and record.run(ctx)
  end,
}
local Status = {
  beforeMove = function() return false end,
  residual = function() return 0 end,
}
local StatusRegistry = {
  inflict = function() return true end,
}
local CrystalItems = {
  rollWildHeldItem = function() return nil end,
  beginBattle = function() end,
  afterDamagingMove = function() end,
  focusBandDamage = function(_, _, damage) return damage end,
}
local CrystalStatus = {
  beginBattle = function() end,
  beforeMove = function() return false end,
  residual = function() return 0 end,
  inflict = function() return true end,
}

package.loaded["src.pokemon.Pokemon"] = Pokemon
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.battle.EffectRegistry"] = EffectRegistry
package.loaded["src.battle.Status"] = Status
package.loaded["src.battle.StatusRegistry"] = StatusRegistry
package.loaded["mods.CRYSTAL_251.battle.crystal_items"] = CrystalItems
package.loaded["mods.CRYSTAL_251.battle.crystal_status"] = CrystalStatus
for _, name in ipairs({
  "crystal_switching", "crystal_actions", "crystal_scheduler",
  "crystal_ai", "crystal_modes", "crystal_progression", "crystal_summary", "crystal_gender",
}) do
  package.loaded["mods.CRYSTAL_251.battle." .. name] = installer(name)
end
package.loaded["mods.CRYSTAL_251.runtime_bridge"] = nil
local Bridge = require("mods.CRYSTAL_251.runtime_bridge")

local firstPokemonNew = Pokemon.new
local firstWild = BattleState.newWild
local firstDamaging = EffectRegistry.runDamaging
local firstStatusInterrupt = BattleState.statusInterrupt

eq(Bridge.install(), true, "runtime bridge installs once")
local wrappedPokemonNew = Pokemon.new
local wrappedWild = BattleState.newWild
local wrappedDamaging = EffectRegistry.runDamaging
local wrappedStatusInterrupt = BattleState.statusInterrupt
ok(wrappedPokemonNew ~= firstPokemonNew, "Pokemon constructor is wrapped")
ok(wrappedWild ~= firstWild, "wild battle constructor is wrapped")
ok(wrappedDamaging ~= firstDamaging, "damaging pipeline is wrapped")
ok(wrappedStatusInterrupt ~= firstStatusInterrupt, "status pipeline is wrapped")
eq(Bridge.install(), false, "second runtime installation is a no-op")
eq(Pokemon.new, wrappedPokemonNew, "Pokemon constructor is not wrapped twice")
eq(BattleState.newWild, wrappedWild, "wild constructor is not wrapped twice")
eq(EffectRegistry.runDamaging, wrappedDamaging,
  "damaging pipeline is not wrapped twice")
eq(BattleState.statusInterrupt, wrappedStatusInterrupt,
  "status pipeline is not wrapped twice")
for _, name in ipairs({
  "crystal_switching", "crystal_actions", "crystal_scheduler",
  "crystal_ai", "crystal_modes", "crystal_progression", "crystal_summary", "crystal_gender",
}) do
  eq(installCounts[name], 1, name .. " runtime installer runs once")
end

local originalRun = function() return "original" end
local sharedRecord = { kind="secondary", run=originalRun }
local battle = { crystal251Active=true }
local ctx = {
  move={index=200,effect="CRYSTAL_EFFECT_02"},
  target={substituteHP=10},
}
EffectRegistry.runDamaging(battle, ctx, sharedRecord)
eq(sharedRecord.run, originalRun,
  "Substitute filtering does not mutate the shared effect record")
eq(battle._crystalMoveDamageDepth, 0,
  "damaging pipeline depth is restored after execution")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal integration cleanup)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal integration cleanup)"):format(checks, checks))
