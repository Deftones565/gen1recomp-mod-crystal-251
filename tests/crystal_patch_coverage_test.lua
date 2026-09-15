package.path = './?.lua;./?/init.lua;' .. package.path
require('tests.modkit')
local Patches = require('mods.CRYSTAL_251.lib.runtime_patches')
local targets = {
  'src.pokemon.Pokemon', 'src.battle.BattleState', 'src.battle.EffectRegistry',
  'src.battle.Status', 'src.battle.StatusRegistry', 'src.battle.TrainerAI',
  'src.link.Protocol', 'src.link.LinkBattle', 'src.battle.Experience',
  'src.inventory.ItemEffects', 'src.world.PikachuFollower', 'src.world.OverworldController',
  'src.ui.SummaryMenu', 'src.render.Assets', 'src.render.Renderer',
}
local itemBalls = require('src.inventory.ItemEffects').BALLS
local originalBalls = {}
for key, value in pairs(itemBalls) do originalBalls[key] = value end
local snapshots = {}
for _, name in ipairs(targets) do
  local target, snapshot = require(name), {}
  for key, value in pairs(target) do snapshot[key] = value end
  snapshots[name] = snapshot
end
local Bridge = require('mods.CRYSTAL_251.runtime_bridge')
local Special = require('mods.CRYSTAL_251.battle.special_damage')
local Presentation = require('mods.CRYSTAL_251.battle.crystal_presentation')
local Cache = require('mods.CRYSTAL_251.lib.cache')
local VisualTime = require('mods.CRYSTAL_251.visual_time')
local checks = 0
for cycle = 1, 3 do
  assert(Bridge.install() == true)
  assert(Bridge.install() == false)
  Special.installRuntime()
  Presentation.installRuntime()
  Cache.installAssetBridge()
  VisualTime.install()
  require("mods.CRYSTAL_251.core.gen2.HappinessBridge").install({events={on=function() end}})
  assert(require('src.pokemon.Pokemon').new ~= snapshots['src.pokemon.Pokemon'].new)
  assert(require('src.battle.BattleState').continueBide ~= snapshots['src.battle.BattleState'].continueBide)
  assert(require('src.render.Assets').image ~= snapshots['src.render.Assets'].image)
  assert(itemBalls.FRIEND_BALL == true)
  Patches.restore()
  local ballKeys = {}
  for key in pairs(originalBalls) do ballKeys[key] = true end
  for key in pairs(itemBalls) do ballKeys[key] = true end
  for key in pairs(ballKeys) do
    checks = checks + 1
    assert(itemBalls[key] == originalBalls[key], 'ItemEffects.BALLS.' .. key .. ' leaked in cycle ' .. cycle)
  end
  for name, snapshot in pairs(snapshots) do
    local target, keys = require(name), {}
    for key in pairs(snapshot) do keys[key] = true end
    for key in pairs(target) do keys[key] = true end
    for key in pairs(keys) do
      checks = checks + 1
      assert(target[key] == snapshot[key], name .. '.' .. key .. ' leaked in cycle ' .. cycle)
    end
  end
end
print(checks .. ' checks passed (Crystal engine patch coverage)')

-- Exercise the real entry and lifecycle binding even on the early-return path
-- where storage is unavailable. That path still installs the asset bridge.
local originalRead, originalContext = Cache.readContentStatus, Cache.context
Cache.readContentStatus = function() return nil, 'error', 'test', 'storage unavailable' end
Cache.context = function() return nil end
local noop = function() end
local mod = {
  exports={}, options={define=noop}, hooks={wrap=noop},
  content={screens={register=noop}}, log={info=noop,error=noop,warn=noop},
}
local Runtime = require('src.mods.Runtime')
local originalReset = Runtime.reset
local entry = require('mods.CRYSTAL_251.main')
for cycle = 1, 2 do
  entry(mod)
  assert(require('src.render.Assets').image ~= snapshots['src.render.Assets'].image)
  Runtime.reset()
  assert(require('src.render.Assets').image == snapshots['src.render.Assets'].image)
  assert(Runtime.reset == originalReset)
end
Cache.readContentStatus, Cache.context = originalRead, originalContext
print('Real entry cleanup and re-enable passed (storage failure path)')
