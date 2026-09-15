-- Own every permanent engine-table edit made by Crystal's installers. The
-- engine caches these tables across games; removing hooks alone cannot undo them.
local Patches = {}
local unpackValues = table.unpack or unpack
local entries, pending, depth = {}, nil, 0
local generation = { active=true }

local function pack(...) return { n=select('#', ...), ... } end

function Patches.watch(target)
  if pending and type(target) == 'table' and not pending[target] then
    local before = {}
    for key, value in pairs(target) do before[key] = value end
    pending[target] = before
  end
  return target
end

local function record(target, key, before, after, guarded)
  local installed = after
  if guarded and type(after) == 'function' and type(before) == 'function' then
    local owner = generation
    installed = function(...)
      -- A later mod may retain our wrapper in its own closure. Make that
      -- reference inert too, without overwriting the later mod's replacement.
      if not owner.active then return before(...) end
      return after(...)
    end
    target[key] = installed
  end
  entries[#entries + 1] = { target=target, key=key, before=before, after=installed }
end

local function commit()
  local changes = pending
  pending = nil
  for target, before in pairs(changes) do
    local keys = {}
    for key in pairs(before) do keys[key] = true end
    for key in pairs(target) do keys[key] = true end
    for key in pairs(keys) do
      if before[key] ~= target[key] then
        record(target, key, before[key], target[key], true)
      end
    end
  end
end

function Patches.restore()
  generation.active = false
  for i = #entries, 1, -1 do
    local entry = entries[i]
    if entry.target[entry.key] == entry.after then
      entry.target[entry.key] = entry.before
    end
  end
  entries = {}
end

function Patches.capture(fn, owner)
  return function(...)
    local outer = depth == 0
    if outer then
      pending = {}
      if not generation.active then generation = { active=true } end
    end
    depth = depth + 1
    Patches.watch(owner)
    local result = pack(pcall(fn, ...))
    depth = depth - 1
    if outer then
      commit()
      if not result[1] then Patches.restore() end
    end
    if not result[1] then error(result[2], 0) end
    return unpackValues(result, 2, result.n)
  end
end

-- Decorate exported installers so standalone installs and the main entry use
-- the same journal. Nested installers commit as one transaction.
function Patches.installers(owner)
  for key, fn in pairs(owner) do
    if type(fn) == 'function' and key:match('^install') then
      owner[key] = Patches.capture(fn, owner)
    end
  end
  return owner
end

local function intercept(target, key, wrapper)
  local original = target[key]
  if type(original) ~= 'function' then return end
  local installed = wrapper(original)
  target[key] = installed
  record(target, key, original, installed, false)
end

function Patches.bind(mod)
  local Runtime = require('src.mods.Runtime')
  local Loader = require('src.mods.Loader')
  local LauncherMods = require('src.mods.LauncherMods')
  local GameVersion = require('src.core.GameVersion')
  local version = GameVersion.get()
  local id = 'CRYSTAL_251'
  local bound = generation
  local function restore()
    if bound == generation then Patches.restore() end
  end
  local function sameGame(scope) return scope == nil or scope == version end
  intercept(Runtime, 'reset', function(original)
    return function(...) restore(); return original(...) end
  end)
  intercept(Runtime, 'install', function(original)
    return function(...) restore(); return original(...) end
  end)
  intercept(Loader, '_rollback', function(original)
    return function(self, modId, ...)
      if modId == id then restore() end
      return original(self, modId, ...)
    end
  end)
  intercept(Loader, 'setEnabled', function(original)
    return function(self, modId, enabled, ...)
      local result = pack(original(self, modId, enabled, ...))
      if result[1] and modId == id and not enabled then restore() end
      return unpackValues(result, 1, result.n)
    end
  end)
  intercept(LauncherMods, 'setEnabled', function(original)
    return function(modId, enabled, scope, ...)
      local result = pack(original(modId, enabled, scope, ...))
      if result[1] and modId == id and not enabled and sameGame(scope) then restore() end
      return unpackValues(result, 1, result.n)
    end
  end)
  intercept(LauncherMods, 'setAllEnabled', function(original)
    return function(ids, enabled, scope, ...)
      local result = pack(original(ids, enabled, scope, ...))
      if result[1] and not enabled and sameGame(scope) then
        for _, modId in ipairs(ids or {}) do if modId == id then restore(); break end end
      end
      return unpackValues(result, 1, result.n)
    end
  end)
  intercept(LauncherMods, 'uninstall', function(original)
    return function(modId, ...)
      local result = pack(original(modId, ...))
      if result[1] and modId == id then restore() end
      return unpackValues(result, 1, result.n)
    end
  end)
  -- The delayed daycare installer must not revive patches after a disable.
  mod.exports.restoreRuntimePatches = restore
end

function Patches.callback(fn)
  local owner = generation
  local captured = Patches.capture(fn)
  return function(...)
    if owner.active then return captured(...) end
  end
end

return Patches
