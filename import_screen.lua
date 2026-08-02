local Screen = {}
Screen.__index = Screen
local Picture = require("mods.CRYSTAL_251.lib.picture")

local CACHE = "crystal_251/content.json"
local GENERATED = "crystal_251/generated"

-- CacheFs owns portable installs, while love.filesystem owns the ordinary
-- per-user save directory. Clear both possible locations, but only recurse
-- through a tree that PhysFS confirms belongs to the save directory; this
-- must never remove files bundled with the game or checked into a source tree.
local function removeSaveTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if love.filesystem.getRealDirectory
      and love.filesystem.getRealDirectory(path)
        ~= love.filesystem.getSaveDirectory() then
    return
  end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeSaveTree(path .. "/" .. child)
    end
    -- PhysFS may expose an overlaid/mounted directory that cannot itself be
    -- removed even after all writable files are gone. Empty shells do not
    -- retain old import data and are safe to reuse.
    return
  end
  local ok, err = love.filesystem.remove(path)
  if ok == false then error("could not remove old Crystal import: " .. tostring(err)) end
end

local function clearOldImport()
  local CacheFs = require("src.import.CacheFs")
  CacheFs.removeTree(GENERATED)
  CacheFs.remove(CACHE)
  removeSaveTree(GENERATED)
  removeSaveTree(CACHE)
end

local function readExternal(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local raw = file:read("*a")
  file:close()
  return raw
end

local function commandOutput(command)
  local HostShell = require("src.core.HostShell")
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local value = pipe:read("*a")
  pipe:close()
  value = value and value:gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value or nil
end

local function choosePath()
  local osName = love.system.getOS()
  if osName == "Linux" then
    return commandOutput([[zenity --file-selection --title="Choose Pokemon Crystal ROM" --file-filter="Game Boy Color ROM | *.gbc" 2>/dev/null]])
      or commandOutput([[kdialog --getopenfilename "$HOME" "*.gbc|Game Boy Color ROM" 2>/dev/null]])
  elseif osName == "OS X" then
    return commandOutput([[osascript -e 'POSIX path of (choose file with prompt "Choose Pokemon Crystal ROM" of type {"gbc"})' 2>/dev/null]])
  elseif osName == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='Choose Pokemon Crystal ROM';",
      "$d.Filter='Game Boy Color ROM (*.gbc)|*.gbc|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.Encoding]::UTF8;[Console]::Write($d.FileName)}",
    })
    return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
  end
end

local function pictureImage(raw, tilesWide, tilesHigh, palette, layout)
  local width, height = tilesWide * 8, tilesHigh * 8
  local image = love.image.newImageData(width, height)
  local fallback = { {1,1,1,1}, {2/3,2/3,2/3,1}, {1/3,1/3,1/3,1}, {0,0,0,1} }
  local raster = Picture.shadeRaster(raw, tilesWide, tilesHigh, layout)
  local transparent = Picture.boundaryTransparency(raster, width, height)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local shade = raster:byte(index)
      local color = palette and palette[shade + 1] or fallback[shade + 1]
      local alpha = transparent[index] and 0 or 1
      -- Do not retain Crystal's paper colour underneath a transparent pixel.
      -- It is invisible with a nearest, unprocessed draw, but presentation
      -- filters sample RGB before alpha and expose it as a faint rectangular
      -- gray fringe in the flat 2D battle view.
      if alpha == 0 then
        image:setPixel(x, y, 0, 0, 0, 0)
      elseif palette then
        image:setPixel(x, y, color[1]/255, color[2]/255, color[3]/255, alpha)
      else
        image:setPixel(x, y, color[1], color[2], color[3], alpha)
      end
    end
  end

  -- Alpha-safe edge bleed. Presentation filters interpolate RGB separately
  -- from alpha; transparent black therefore darkens the first visible sample
  -- into a gray halo. Propagate the nearest opaque sprite colour underneath
  -- every transparent texel while leaving its alpha at zero. Nearest-neighbour
  -- rendering is unchanged, while linear scaling and post-processing now fade
  -- the sprite edge into itself instead of black or Crystal's paper colour.
  local seen, queue, head = {}, {}, 1
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x + 1
      local _, _, _, a = image:getPixel(x, y)
      if a > 0 then
        seen[index] = true
        queue[#queue + 1] = { x, y }
      end
    end
  end
  while head <= #queue do
    local point = queue[head]
    head = head + 1
    local x, y = point[1], point[2]
    local r, g, b = image:getPixel(x, y)
    for _, step in ipairs({ {-1,0}, {1,0}, {0,-1}, {0,1} }) do
      local nx, ny = x + step[1], y + step[2]
      if nx >= 0 and ny >= 0 and nx < width and ny < height then
        local index = ny * width + nx + 1
        if not seen[index] then
          seen[index] = true
          image:setPixel(nx, ny, r, g, b, 0)
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
  end
  return image
end

function Screen.new(game, mod)
  local self = setmetatable({ game=game, mod=mod, status="CHOOSE CRYSTAL ROM",
    detail="PRESS A TO SELECT", progress=0 }, Screen)
  return self
end

function Screen:start(raw, displayName)
  if self.worker then return end
  if type(raw) ~= "string" then self.status="COULD NOT READ ROM"; return end
  local hash = love.data.encode("string", "hex", love.data.hash("sha1", raw))
  local manifest = require("mods.CRYSTAL_251.addresses")
  local revision = manifest.revisions[hash]
  if not revision then
    self.status = "UNSUPPORTED CRYSTAL ROM"
    self.detail = "SHA-1 " .. hash
    return
  end
  self.status, self.detail = "IMPORTING CRYSTAL", revision.title
  self.worker = coroutine.create(function()
    local Extractor = require("mods.CRYSTAL_251.lib.extractor")
    local ImageWriter = require("src.import.ImageWriter")
    clearOldImport()
    local content = Extractor.extract(raw, revision, {
      writePicture = function(path, bytes, w, h, palette, layout, presentation)
        local image = pictureImage(bytes, w, h, palette, layout)
        if presentation == "dex" then
          local canvas = ImageWriter.blank(56, 56, 0, 0, 0, 0)
          local x = math.floor((56 - image:getWidth()) / 2)
          local y = 56 - image:getHeight()
          ImageWriter.blit(canvas, image, x, y)
          image = canvas
        end
        ImageWriter.save(image, path)
      end,
      progress = function(done, total)
        self.progress = done / total
        self.detail = ("POKEMON %d / %d"):format(done, total)
        coroutine.yield()
      end,
    })
    content.sourceSha1 = hash
    local Json = require("mods.CRYSTAL_251.lib.json")
    local CacheFs = require("src.import.CacheFs")
    local ok, err = CacheFs.write(CACHE, Json.encode(content))
    assert(ok, err)
    self.progress, self.complete = 1, true
    self.status, self.detail = "CRYSTAL IMPORT COMPLETE", "PRESS A TO RESTART"
  end)
end

function Screen:choose()
  local path = choosePath()
  if path then
    local raw, err = readExternal(path)
    if not raw then self.status, self.detail = "COULD NOT READ ROM", tostring(err); return end
    self:start(raw, path:match("[^/\\]+$") or path)
    return
  end
  for _, file in ipairs(love.filesystem.getDirectoryItems("")) do
    if file:lower():match("%.gbc$") then
      local raw = love.filesystem.read(file)
      if raw then self:start(raw, file); return end
    end
  end
  self.status = "NO FILE PICKER AVAILABLE"
  self.detail = "COPY YOUR CRYSTAL ROM BESIDE THE GAME"
end

function Screen:update()
  if self.worker and coroutine.status(self.worker) ~= "dead" then
    local ok, err = coroutine.resume(self.worker)
    if not ok then
      self.worker = nil
      self.status, self.detail = "IMPORT FAILED", tostring(err)
    end
    return
  end
  local input = self.game.input
  if input:wasPressed("b") then self.game.stack:pop()
  elseif input:wasPressed("a") then
    if self.complete then require("src.core.HostShell").restart() else self:choose() end
  end
end

function Screen:draw()
  local Font = require("src.render.Font")
  local function wrapped(text, width)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
      if #line == 0 then line=word
      elseif #line + #word + 1 <= width then line=line .. " " .. word
      else lines[#lines+1]=line; line=word end
    end
    if line~="" then lines[#lines+1]=line end
    return lines
  end
  local function drawWrapped(text, x, y, width, limit)
    local lines=wrapped(text,width)
    for i=1,math.min(limit or #lines,#lines) do Font.draw(lines[i],x,y+(i-1)*16) end
  end
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 0, 20, 18)
  Font.draw("CRYSTAL 251", 40, 24)
  drawWrapped(self.status, 16, 56, 17, 2)
  drawWrapped(self.detail, 16, 88, 17, 2)
  love.graphics.rectangle("line", 16, 124, 128, 8)
  love.graphics.rectangle("fill", 17, 125, math.floor(126 * self.progress), 6)
  Font.draw("A: SELECT   B: BACK", 16, 144)
  love.graphics.setColor(1, 1, 1, 1)
end

return Screen
