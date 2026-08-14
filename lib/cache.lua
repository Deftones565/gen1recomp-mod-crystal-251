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

local function game()
  return modRef and modRef.game
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

local function read(key)
  local storage, owner = modRef and modRef.storage, game()
  if not (storage and owner) then return nil end
  local ok, value = pcall(storage.read, storage, owner, key)
  return ok and value or nil
end

local function write(key, value)
  local storage, owner = modRef and modRef.storage, game()
  if not (storage and owner) then
    return false, "sandbox storage unavailable before an identified playthrough"
  end
  local ok, wrote, code, message = pcall(storage.write, storage, owner, key, value)
  if not ok then return false, tostring(wrote) end
  if not wrote then return false, tostring(message or code or "storage write failed") end
  return true
end

function Cache.bind(mod)
  modRef = mod
  return Cache
end

function Cache.readContent()
  if memoryContent then return memoryContent end
  local record = read(CONTENT_KEY)
  return type(record) == "table" and record.content or nil
end

function Cache.writeContent(content)
  memoryContent = content
  return write(CONTENT_KEY, { content = content })
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
  local storage, owner = modRef and modRef.storage, game()
  if not (storage and owner) then return false, "sandbox storage unavailable" end
  local ok, keys = pcall(storage.list, storage, owner, "cache")
  if not ok or type(keys) ~= "table" then return false, tostring(keys) end
  for _, key in ipairs(keys) do pcall(storage.delete, storage, owner, key) end
  imageDataCache = setmetatable({}, { __mode = "v" })
  imageCache = setmetatable({}, { __mode = "v" })
  memoryAssets, memoryContent = {}, nil
  return true
end

-- Content registries freeze before game.ready, while mod.storage deliberately
-- requires an identified playthrough. A packaged ROM is therefore extracted
-- into memory during mod load; the ROM must remain in the mod's own folder.
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
        return content
      end
    end
  end
  return nil
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
