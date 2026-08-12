package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function ok(value, message)
  checks = checks + 1
  if not value then failures = failures + 1; io.stderr:write("FAIL " .. message .. "\n") end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then failures = failures + 1; io.stderr:write(("FAIL %s (got %s, want %s)\n"):format(message, tostring(got), tostring(want))) end
end

local total = 151
local fake = {
  battleEnabled=function() return true end,
  modelsEnabled=function() return true end,
  available=function(count) return count == total end,
  status=function() return { total=total } end,
  configure=function(opts) total = math.max(total, tonumber(opts.count) or total) end,
}
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"] = fake
package.loaded["mods.STADIUM2_IMPORTER.lib.battle"] = nil
local Battle = require("mods.STADIUM2_IMPORTER.lib.battle")

local pokemon = {
  BULBASAUR={dex=1,index=1},
  MEW={dex=151,index=151},
  CHIKORITA={dex=152,index=152},
  ESPEON={dex=196,index=196},
  TYRANITAR={dex=248,index=248},
  CELEBI={dex=251,index=251},
}
eq(Battle.configureGame({data={pokemon=pokemon}}), 251, "importer discovers Crystal's full 251-species dex")
eq(total, 251, "importer expands its own cache target to 251")
local crystalMon = { species="ESPEON", dvs={attack=2,defense=10,speed=10,special=10} }
local battler = { mon=crystalMon, isPlayer=true }
local battle = { data={pokemon=pokemon} }
eq(Battle.dexFor(battle, battler), 196, "Crystal species resolves directly through merged game data")
ok(Battle.isShiny(crystalMon), "Crystal shiny DVs are understood by the importer itself")
crystalMon.dvs.attack = 1
ok(not Battle.isShiny(crystalMon), "non-shiny Crystal DVs remain normal")
ok(Battle.enabled(), "normal 3D battle mode is importer-owned and enabled")
ok(Battle.ready(), "251-model readiness is evaluated by the importer")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal Stadium 2 auto-detection)\n"):format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal Stadium 2 auto-detection)"):format(checks, checks))
