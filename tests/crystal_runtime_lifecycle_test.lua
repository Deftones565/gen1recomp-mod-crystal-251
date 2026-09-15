-- Run from the engine root: luajit mods/CRYSTAL_251/tests/crystal_runtime_lifecycle_test.lua
package.path = './?.lua;./?/init.lua;' .. package.path
local Patches = require('mods.CRYSTAL_251.lib.runtime_patches')
local checks = 0
local function eq(actual, expected, message)
  checks = checks + 1
  assert(actual == expected, message .. ': got ' .. tostring(actual) .. ', expected ' .. tostring(expected))
end
local Runtime = { reset=function() return 'reset', nil, 3 end, install=function() return true end }
local Loader = {
  setEnabled=function(self, id, enabled) return not self.refuse end,
  _rollback=function() return 'rolled back' end,
}
local Launcher = {
  setEnabled=function() return true end,
  setAllEnabled=function() return true end,
  uninstall=function(id) return id ~= 'missing', 'result' end,
}
package.loaded['src.mods.Runtime'] = Runtime
package.loaded['src.mods.Loader'] = Loader
package.loaded['src.mods.LauncherMods'] = Launcher
package.loaded['src.core.GameVersion'] = { get=function() return 'red' end }
local originals = { reset=Runtime.reset, toggle=Loader.setEnabled, uninstall=Launcher.uninstall }
local vanilla = function(value) return value, nil, 'vanilla' end
local target = { call=vanilla }
local installer = {}
function installer.install()
  Patches.watch(target)
  if installer.installed then return false end
  installer.installed = true
  target.marker = true
  target.helper = function() return 'helper' end
  local original = target.call
  target.call = function(value) return original(value + 10) end
  return true
end
Patches.installers(installer)
local delayed
local enable = Patches.capture(function()
  Patches.bind({ exports={} })
  installer.install()
  delayed = Patches.callback(function()
    Patches.watch(target)
    target.late = true
  end)
end)
local function restored(reason)
  eq(target.call, vanilla, reason .. ' restores original function')
  eq(target.marker, nil, reason .. ' removes marker')
  eq(target.helper, nil, reason .. ' removes added API')
  eq(installer.installed, nil, reason .. ' resets installer guard')
  eq(Runtime.reset, originals.reset, reason .. ' restores lifecycle wrapper')
  eq(Loader.setEnabled, originals.toggle, reason .. ' restores toggle wrapper')
  eq(Launcher.uninstall, originals.uninstall, reason .. ' restores uninstall wrapper')
  delayed()
  eq(target.late, nil, reason .. ' prevents delayed reinstallation')
end
for _, action in ipairs({
  function() Loader.setEnabled({}, 'CRYSTAL_251', false) end,
  function() Launcher.setEnabled('CRYSTAL_251', false, 'red') end,
  function() Launcher.setAllEnabled({'other', 'CRYSTAL_251'}, false, 'red') end,
  function() Launcher.uninstall('CRYSTAL_251') end,
  function() Loader._rollback({}, 'CRYSTAL_251') end,
  function() Runtime.install({}, {}) end,
  function()
    local a,b,c = Runtime.reset()
    eq(a, 'reset', 'reset result'); eq(b, nil, 'nil result'); eq(c, 3, 'trailing result')
  end,
}) do
  enable()
  eq(target.call(1), 11, 're-enabled patch runs once')
  eq(installer.install(), false, 'duplicate install is a no-op')
  delayed()
  eq(target.late, true, 'delayed patch is installed')
  action()
  restored('lifecycle cleanup')
end

enable()
Launcher.setEnabled('CRYSTAL_251', false, 'yellow')
Launcher.setAllEnabled({'CRYSTAL_251'}, false, 'yellow')
Loader.setEnabled({refuse=true}, 'CRYSTAL_251', false)
Launcher.setEnabled('other', false, 'red')
Launcher.uninstall('missing')
Loader._rollback({}, 'other')
eq(target.call(2), 12, 'other games, other mods and refused changes preserve active patches')
local crystalWrapper = target.call
local laterMod = function(value) return crystalWrapper(value) * 2 end
target.call = laterMod
Runtime.reset()
eq(target.call, laterMod, 'cleanup preserves a later mod replacement')
eq(target.call(2), 4, 'retained Crystal wrapper becomes vanilla')
target.call = vanilla

-- A failed installer must undo all changes and still propagate the error.
local bad = Patches.capture(function()
  installer.install()
  error('installation failed')
end)
local success, err = pcall(bad)
eq(success, false, 'installer error propagates')
eq(err:find('installation failed', 1, true) ~= nil, true, 'original error is retained')
eq(target.call, vanilla, 'failed install restores function')
eq(installer.installed, nil, 'failed install restores guard')
enable()
eq(target.call(5), 15, 'install works after failure')
Runtime.reset()
print(checks .. ' checks passed (Crystal runtime lifecycle)')
