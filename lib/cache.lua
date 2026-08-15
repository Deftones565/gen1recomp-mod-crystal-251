-- Sandboxed Crystal import cache. Content and generated picture rasters live
-- in playthrough-scoped mod.storage; no filesystem path is exposed to the mod.
local Cache = {}

local CONTENT_KEY = "cache/content"
local ASSET_PREFIX = "cache/assets/"
local VIRTUAL_PREFIX = "crystal_251/generated/"

local modRef
local imageDataCache = setmetatable({}, { __mode = "v" })
local imageCache = setmetatable({}, { __mode = "v" })
local memoryAssets = {}
local memoryContent
local memoryNeedsPersist = false
local persistPaths, persistIndex
local selectedOwner
local selectedOwnerCode, selectedOwnerMessage

local function game()
  return modRef and modRef.game
end

local function gameplayActive(owner)
  if not (owner and owner.save) then return false end
  local stack = owner.stack
  if owner.overworld and stack and type(stack.top) == "function"
      and stack:top() == owner.overworld then
    return true
  end
  -- Keep compatibility with engine states/adapters that explicitly identify
  -- gameplay even when the overworld itself is covered by a battle state.
  local states = stack and stack.states
  if type(states) == "table" then
    for _, state in ipairs(states) do
      if type(state) == "table" and (state.isOverworld or state.isBattle) then
        return true
      end
    end
  end
  return false
end

-- Crystal's registries are built before game.ready, but the extracted cache is
-- playthrough-scoped. Resolve the launcher's already-selected playthrough
-- through the engine-internal identity helper so a cold start can read the
-- durable cache without minting an id on the temporary boot save.
local function earlySelectedOwner()
  if selectedOwner then return selectedOwner end
  if selectedOwnerCode then return nil, selectedOwnerCode, selectedOwnerMessage end

  local okSave, SaveData = pcall(require, "src.core.SaveData")
  local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
  if not okSave or type(SaveData) ~= "table" then
    selectedOwnerCode = "identity_unavailable"
    selectedOwnerMessage = "SaveData is unavailable: " .. tostring(SaveData)
    return nil, selectedOwnerCode, selectedOwnerMessage
  end
  if not okVersion or type(GameVersion) ~= "table"
      or type(GameVersion.get) ~= "function" then
    selectedOwnerCode = "unknown_game"
    selectedOwnerMessage = "GameVersion is unavailable: " .. tostring(GameVersion)
    return nil, selectedOwnerCode, selectedOwnerMessage
  end

  local okGet, version = pcall(GameVersion.get)
  if not okGet or type(version) ~= "string" or version == "" then
    selectedOwnerCode = "unknown_game"
    selectedOwnerMessage = "current game version is unavailable"
    return nil, selectedOwnerCode, selectedOwnerMessage
  end

  -- Newer engines expose a direct non-allocating selected-playthrough helper.
  -- Use it when present, but DO NOT require it: Crystal supports engines whose
  -- mod.storage implementation predates that helper.
  if type(SaveData.selectedPlaythroughId) == "function" then
    local okId, id = pcall(SaveData.selectedPlaythroughId,
      { version=version, meta={} })
    if okId and type(id) == "string" and id ~= "" then
      selectedOwner = { save={ version=version, meta={ playthroughId=id } } }
      return selectedOwner
    end
  end

  -- Compatibility path: load the engine-selected existing save and give that
  -- save object back to mod.storage. Storage:_scope owns playthrough identity
  -- resolution and will reuse the durable slot -> playthrough mapping through
  -- SaveData.ensurePlaythroughId when the save itself has not yet been stamped.
  -- This avoids allocating against Game's temporary boot skeleton and works on
  -- the same engine builds where Stadium's live mod.storage already persists.
  if type(SaveData.load) == "function" then
    local okLoad, loaded = pcall(SaveData.load, version)
    if okLoad and type(loaded) == "table" then
      loaded.version = loaded.version or version
      selectedOwner = { save=loaded }
      return selectedOwner
    end
    if not okLoad then
      selectedOwnerCode = "save_load_failed"
      selectedOwnerMessage = tostring(loaded)
      return nil, selectedOwnerCode, selectedOwnerMessage
    end
  end

  selectedOwnerCode = "no_selected_playthrough"
  selectedOwnerMessage = "no existing selected save is available for Crystal cache storage"
  return nil, selectedOwnerCode, selectedOwnerMessage
end

-- Return a storage facade plus an optional owner. A nil owner means the facade
-- is mod.storage:selected(game), whose methods are already bound to the selected
-- playthrough. During gameplay the real game.save is authoritative.
local function storageTarget()
  local storage, owner = modRef and modRef.storage, game()
  if not storage then
    return nil, nil, "storage_unavailable", "mod.storage is unavailable"
  end

  if gameplayActive(owner) then return storage, owner end

  if owner and type(storage.selected) == "function" then
    local ok, selected, code, message = pcall(storage.selected, storage, owner)
    if ok and type(selected) == "table" then return selected, nil end
    -- Before the title state exists, selected() is expected to refuse. Fall
    -- through to the engine's durable selected-playthrough identity instead.
    if not ok then
      code, message = "storage_exception", tostring(selected)
    end
  end

  local early, code, message = earlySelectedOwner()
  if early then return storage, early end

  -- Never fall through to the temporary boot/title save. Normal mod.storage
  -- would allocate a new playthrough id there and persist the cache into the
  -- wrong namespace.
  return nil, nil, code or "no_selected_playthrough",
    message or "no durable selected playthrough is available"
end

local function storageCall(method, ...)
  local target, owner, bindCode, bindMessage = storageTarget()
  local fn = target and target[method]
  if type(fn) ~= "function" then
    return false, bindMessage or "sandbox storage unavailable",
      bindCode or "storage_unavailable", bindMessage
  end
  if owner then return pcall(fn, target, owner, ...) end
  return pcall(fn, target, ...)
end

local function safeAssetKey(path)
  if type(path) ~= "string" or path:sub(1, #VIRTUAL_PREFIX) ~= VIRTUAL_PREFIX then
    return nil
  end
  local relative = path:sub(#VIRTUAL_PREFIX + 1)
  if relative == "" or relative:find("..", 1, true)
      or relative:sub(1, 1) == "/" or relative:find("\\", 1, true) then
    return nil
  end
  -- Storage keys deliberately have a smaller alphabet than asset paths.
  return ASSET_PREFIX .. relative:gsub("[^%w_/-]", "_")
end

local function readStatus(key)
  local ok, value, code, message = storageCall("read", key)
  if not ok then
    if code == "no_selected_playthrough" or code == "not_in_playthrough"
        or code == "not_at_title" then
      return nil, "unbound", code, tostring(message or value)
    end
    return nil, "error", code or "storage_exception", tostring(message or value)
  end
  if value ~= nil then return value, "found", nil, nil end
  if code == "not_found" then return nil, "missing", code, message end
  if code == "no_selected_playthrough" or code == "not_in_playthrough"
      or code == "not_at_title" then
    return nil, "unbound", code, message
  end
  return nil, "error", code or "read_failed",
    tostring(message or "Crystal cache read failed")
end

local function read(key)
  local value = readStatus(key)
  return value
end

local function write(key, value)
  local ok, wrote, code, message = storageCall("write", key, value)
  if not ok then return false, tostring(wrote) end
  if not wrote then return false, tostring(message or code or "storage write failed") end
  return true
end

function Cache.bind(mod)
  modRef = mod
  selectedOwner = nil
  selectedOwnerCode, selectedOwnerMessage = nil, nil
  return Cache
end

function Cache.readContentStatus()
  if memoryContent then
    return memoryContent, "memory", nil, nil
  end
  local record, state, code, message = readStatus(CONTENT_KEY)
  if type(record) == "table" and type(record.content) == "table" then
    return record.content, "found", nil, nil
  end
  if record ~= nil then
    return nil, "error", "invalid_record", "Crystal cache content record is malformed"
  end
  return nil, state, code, message
end

function Cache.readContent()
  local content = Cache.readContentStatus()
  return content
end

function Cache.context()
  local target, owner, code, message = storageTarget()
  if not target then return nil, code, message end
  local fn = target.context
  if type(fn) ~= "function" then return nil, "storage_unavailable", "storage context unavailable" end
  local ok, value, ctxCode, ctxMessage
  if owner then ok, value, ctxCode, ctxMessage = pcall(fn, target, owner)
  else ok, value, ctxCode, ctxMessage = pcall(fn, target) end
  if not ok then return nil, "storage_exception", tostring(value) end
  if type(value) ~= "table" then return nil, ctxCode, ctxMessage end
  return value
end

function Cache.writeContent(content)
  memoryContent = content
  local ok, err = write(CONTENT_KEY, { content = content })
  if ok then
    memoryNeedsPersist = false
    persistPaths, persistIndex = nil, nil
  end
  return ok, err
end

function Cache.writeAsset(path, spec)
  local key = safeAssetKey(path)
  if not key then return false, "invalid Crystal generated-asset path" end
  memoryAssets[path] = spec
  imageDataCache[path] = nil
  return write(key, { spec = spec })
end

function Cache.readAsset(path)
  if memoryAssets[path] then return memoryAssets[path] end
  local key = safeAssetKey(path)
  local record = key and read(key) or nil
  return type(record) == "table" and record.spec or nil
end

function Cache.clear()
  local ok, keys, code, message = storageCall("list", "cache")
  if not ok then return false, tostring(keys) end
  if type(keys) ~= "table" then
    if code == "not_found" then keys = {}
    else return false, tostring(message or code or keys or "storage unavailable") end
  end
  for _, key in ipairs(keys) do storageCall("delete", key) end
  imageDataCache = setmetatable({}, { __mode = "v" })
  imageCache = setmetatable({}, { __mode = "v" })
  memoryAssets, memoryContent = {}, nil
  memoryNeedsPersist = false
  persistPaths, persistIndex = nil, nil
  return true
end

-- Content registries freeze before game.ready. readContent() now resolves the
-- engine-selected durable playthrough during early mod load, so a successfully
-- imported cache can be reused after restart without keeping the ROM packaged.
-- importPackaged remains the fallback for a first import or an invalid cache.
function Cache.importPackaged()
  if memoryContent then return memoryContent end
  if not (modRef and type(modRef.read) == "function") then return nil end
  local names = {
    "baseroms/pokemon_crystal.gbc", "baseroms/pokemon_crystal_version.gbc",
    "baseroms/crystal.gbc", "baseroms/baserom.gbc",
    "pokemon_crystal.gbc", "pokemon_crystal_version.gbc",
    "crystal.gbc", "baserom.gbc",
  }
  local revisions = require("mods.CRYSTAL_251.addresses").revisions
  for _, path in ipairs(names) do
    local ok, raw = pcall(modRef.read, modRef, path)
    if ok and type(raw) == "string" then
      local hashed, hash = pcall(function()
        return love.data.encode("string", "hex", love.data.hash("sha1", raw))
      end)
      local revision = hashed and revisions[hash] or nil
      if revision then
        local Picture = require("mods.CRYSTAL_251.lib.picture")
        local files = {}
        local content = require("mods.CRYSTAL_251.lib.extractor").extract(raw, revision, {
          writePicture = function(assetPath, bytes, w, h, palette, layout, presentation)
            memoryAssets[assetPath] = {
              raster=Picture.shadeRaster(bytes, w, h, layout),
              width=w * 8, height=h * 8, palette=palette,
              presentation=presentation,
            }
            files[#files + 1] = assetPath
          end,
        })
        content.sourceSha1, content.importFiles = hash, files
        memoryContent = content
        memoryNeedsPersist = true
        persistPaths, persistIndex = nil, nil
        return content
      end
    end
  end
  return nil
end

function Cache.hasPendingPersist()
  return memoryNeedsPersist and memoryContent ~= nil
end

-- Commit an in-memory packaged-ROM extraction to the real playthrough a few
-- assets at a time. The content record is written last and acts as the commit
-- marker: a restart during this copy simply falls back to the required ROM and
-- retries, while a completed cache is safe to consume before registry freeze.
function Cache.persistMemoryStep(limit)
  if not Cache.hasPendingPersist() then return true end
  if not gameplayActive(game()) then return false end

  if not persistPaths then
    persistPaths = {}
    for path in pairs(memoryAssets) do persistPaths[#persistPaths + 1] = path end
    table.sort(persistPaths)
    persistIndex = 1
  end

  limit = math.max(1, math.floor(tonumber(limit) or 16))
  local stop = math.min(#persistPaths, persistIndex + limit - 1)
  while persistIndex <= stop do
    local path = persistPaths[persistIndex]
    local key = safeAssetKey(path)
    if not key then return false, "invalid Crystal generated-asset path" end
    local ok, wrote, code, message = storageCall("write", key, { spec=memoryAssets[path] })
    if not ok then return false, tostring(wrote) end
    if not wrote then
      return false, tostring(message or code or "Crystal asset cache write failed")
    end
    persistIndex = persistIndex + 1
  end

  if persistIndex <= #persistPaths then return false end

  local ok, wrote, code, message = storageCall("write", CONTENT_KEY, { content=memoryContent })
  if not ok then return false, tostring(wrote) end
  if not wrote then
    return false, tostring(message or code or "Crystal content cache write failed")
  end

  memoryNeedsPersist = false
  persistPaths, persistIndex = nil, nil
  return true
end

local function imageData(path)
  local cached = imageDataCache[path]
  if cached then return cached end
  local spec = Cache.readAsset(path)
  assert(spec and type(spec.raster) == "string", "missing Crystal asset " .. tostring(path))
  local width, height = assert(spec.width), assert(spec.height)
  local image = love.image.newImageData(width, height)
  local palette = spec.palette
  local fallback = { {1,1,1,1}, {2/3,2/3,2/3,1}, {1/3,1/3,1/3,1}, {0,0,0,1} }
  local transparent = require("mods.CRYSTAL_251.lib.picture")
    .boundaryTransparency(spec.raster, width, height)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local shade = spec.raster:byte(index)
      local color = palette and palette[shade + 1] or fallback[shade + 1]
      local alpha = transparent[index] and 0 or 1
      if alpha == 0 then image:setPixel(x, y, 0, 0, 0, 0)
      elseif palette then image:setPixel(x, y, color[1]/255, color[2]/255, color[3]/255, 1)
      else image:setPixel(x, y, color[1], color[2], color[3], 1) end
    end
  end
  -- Preserve the old PNG importer's alpha-safe edge bleed so filtered sprites
  -- fade into their own edge colour instead of transparent black.
  local seen, queue, head = {}, {}, 1
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local _, _, _, a = image:getPixel(x, y)
      if a > 0 then seen[index] = true; queue[#queue + 1] = {x, y} end
    end
  end
  while head <= #queue do
    local point = queue[head]
    head = head + 1
    local x, y = point[1], point[2]
    local r, g, b = image:getPixel(x, y)
    for _, step in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
      local nx, ny = x + step[1], y + step[2]
      if nx >= 0 and ny >= 0 and nx < width and ny < height then
        local index = ny * width + nx + 1
        if not seen[index] then
          seen[index] = true
          image:setPixel(nx, ny, r, g, b, 0)
          queue[#queue + 1] = {nx, ny}
        end
      end
    end
  end
  if spec.presentation == "dex" then
    local canvas = love.image.newImageData(56, 56)
    canvas:mapPixel(function() return 0, 0, 0, 0 end)
    local ox, oy = math.floor((56 - width) / 2), 56 - height
    for y = 0, height - 1 do
      for x = 0, width - 1 do canvas:setPixel(ox + x, oy + y, image:getPixel(x, y)) end
    end
    image = canvas
  end
  imageDataCache[path] = image
  return image
end

function Cache.installAssetBridge()
  local Assets = require("src.render.Assets")
  if Assets._crystal251StorageBridge then return end
  Assets._crystal251StorageBridge = true
  local oldImage, oldImageData, oldExists = Assets.image, Assets.imageData, Assets.exists
  Assets.imageData = function(path)
    if safeAssetKey(path) then return imageData(path) end
    return oldImageData(path)
  end
  Assets.image = function(path)
    if safeAssetKey(path) then
      if not imageCache[path] then imageCache[path] = love.graphics.newImage(imageData(path)) end
      return imageCache[path]
    end
    return oldImage(path)
  end
  Assets.exists = function(path)
    if safeAssetKey(path) then return Cache.readAsset(path) ~= nil end
    return oldExists(path)
  end
end

return Cache
