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
ok(manifestSource:find('"version": "0.11.1"', 1, true) ~= nil,
  "compatibility release has version 0.11.1")
ok(manifestSource:find('"trainer_rematch"', 1, true) ~= nil,
  "manifest rejects Kanto Ascended because both mods own Generation II registries")
ok(manifestSource:find('"Kanto%-Reforged"') ~= nil,
  "manifest rejects Kanto Reforged because both mods own Pokemon and battle data")
ok(mainSource:find("Registry.upsert(mod.content.type_chart", 1, true) ~= nil,
  "type installation cannot duplicate another mod's type-chart ids")
ok(mainSource:find(".upsert(mod.content.icons, id, source.icon)", 1, true) ~= nil,
  "icon installation cannot duplicate another mod's species icon ids")
local progressionSource = read(root .. "machine_progression.lua")
ok(progressionSource:find('upsert(screens, "MoveLearnMenu"', 1, true) ~= nil
   and progressionSource:find("previousNew(game, mon, newMoveId, onDone)", 1, true) ~= nil,
  "move-learning compatibility decorates the effective screen factory")
ok(manifestSource:find('"gen3_battle_ui"', 1, true) ~= nil,
  "Gen 3 UI loads before Crystal's compatibility adapter")
local genderSource = read(root .. "battle/crystal_gender.lua")
ok(genderSource:find('mod.hooks:wrap("gender.roll"', 1, true) ~= nil,
  "Crystal publishes its ROM-derived gender through the engine hook")
ok(genderSource:find("gen3BattleUiActive", 1, true) ~= nil,
  "Crystal yields native battle gender drawing to Gen 3 UI")
ok(summarySource:find("gen3PokemonUiActive", 1, true) ~= nil,
  "Crystal yields its native split-stat panel to Gen 3 UI")
ok(mainSource:find("Cache.readContent() or Cache.importPackaged()", 1, true) ~= nil,
  "loader uses scoped storage or a mod-owned packaged ROM")
ok(mainSource:find("Crystal251AutoImport", 1, true) ~= nil
   and mainSource:find('mod.events:on("screen.pushed"', 1, true) ~= nil
   and mainSource:find("ev.state.screenId == splash", 1, true) ~= nil
   and mainSource:find("ImportScreen.romPresent()", 1, true) ~= nil,
  "missing or obsolete Crystal data waits for the boot screen before auto-importing")
ok(mainSource:find('label = "CRYSTAL ROM"', 1, true) ~= nil,
  "OPTIONS exposes the manual Crystal ROM importer")
ok(importSource:find('Screen.ROM_DIR = "baseroms"', 1, true) ~= nil
   and importSource:find("function Screen.findRom()", 1, true) ~= nil
   and importSource:find("pcall(mod.read, mod, path)", 1, true) ~= nil
   and not importSource:find("love.filesystem", 1, true),
  "Crystal auto-import reads only named files inside its own folder")
ok(importSource:find("content.importFiles = importedFiles", 1, true) ~= nil,
  "Crystal cache records every generated sprite and cry")
ok(importSource:find('"cache/error", { text=text }', 1, true) ~= nil
   and importSource:find("writeFailureLog", 1, true) ~= nil,
  "Crystal import writes its exact failure to scoped storage and the mod log")
ok(importSource:find("traceback(worker, err)", 1, true) ~= nil,
  "Crystal coroutine failures retain a traceback and failing stage")
ok(not importSource:find("love.system", 1, true)
   and importSource:find("THIS MOD'S ", 1, true) ~= nil,
  "Crystal does not use the sandboxed native picker bridge")
ok(not manifestSource:find('"STADIUM2_IMPORTER"', 1, true),
  "Crystal no longer depends on a Stadium renderer provider")
ok(not mainSource:find("stadium2_models", 1, true)
   and not mainSource:find("STADIUM2_IMPORTER", 1, true)
   and not mainSource:find("stadium2_bridge", 1, true),
  "Crystal contains no Stadium battle presentation path; the importer owns it")
ok(mainSource:find("CrystalSummary.configure(crystalBaseStats)", 1, true) ~= nil,
  "summary receives the imported Crystal base-stat table")
ok(summarySource:find('{ "S.ATK", stats.specialAttack }', 1, true) ~= nil,
  "summary draws Special Attack separately")
ok(summarySource:find('{ "S.DEF", stats.specialDefense }', 1, true) ~= nil,
  "summary draws Special Defense separately")
ok(not importSource:find("CrystalCry.render(raw, definition)", 1, true)
   and read(root .. "battle/crystal_presentation.lua"):find("chip=assert(row.chip)", 1, true),
  "Crystal cries remain data-only chip definitions")
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
