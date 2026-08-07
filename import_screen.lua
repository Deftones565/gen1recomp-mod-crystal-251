local Screen = {}
Screen.__index = Screen
local Picture = require("mods.CRYSTAL_251.lib.picture")

local CACHE = "crystal_251/content.json"
local GENERATED = "crystal_251/generated"
local ERROR_LOG = "crystal_251/import_error.log"

Screen.ROM_DIR = "baseroms"
Screen.PICKED = "picked_rom.gb"

local PREFERRED_ROMS = {
  Screen.ROM_DIR .. "/pokemon_crystal.gbc",
  Screen.ROM_DIR .. "/pokemon_crystal_version.gbc",
  Screen.ROM_DIR .. "/crystal.gbc",
  Screen.ROM_DIR .. "/baserom.gbc",
}

local cachedAutoRom = nil

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
  CacheFs.remove(ERROR_LOG)
  removeSaveTree(GENERATED)
  removeSaveTree(CACHE)
  removeSaveTree(ERROR_LOG)
end

local function oneLine(value)
  return tostring(value or "unknown error")
    :gsub("\r", "")
    :gsub("\n+", " | ")
    :gsub("%s+", " ")
    :gsub("^%s+", "")
    :gsub("%s+$", "")
end

local function traceback(worker, err)
  local message = tostring(err or "unknown error")
  if debug and debug.traceback then
    local ok, value = pcall(debug.traceback, worker, message)
    if ok and type(value) == "string" then return value end
  end
  return message
end

local function writeFailureLog(mod, text)
  text = tostring(text or "unknown error")
  if mod and mod.log then
    pcall(function() mod.log:error("Crystal import failed: %s", text) end)
  end
  pcall(function()
    if io and io.stderr then
      io.stderr:write("[CRYSTAL_251] Crystal import failed:\n" .. text .. "\n")
      if io.stderr.flush then io.stderr:flush() end
    end
  end)
  local okCache, CacheFs = pcall(require, "src.import.CacheFs")
  if okCache and CacheFs and CacheFs.write then
    local okWrite, wrote = pcall(CacheFs.write, ERROR_LOG, text .. "\n")
    if okWrite and wrote then return end
  end
  pcall(function()
    if love and love.filesystem and love.filesystem.write then
      love.filesystem.write(ERROR_LOG, text .. "\n")
    end
  end)
end

local function readExternal(path)
  local file, err = io.open(path, "rb")
  if not file then return nil, err end
  local raw = file:read("*a")
  file:close()
  return raw
end

local function identify(raw)
  if type(raw) ~= "string" then return nil end
  local ok, hash = pcall(function()
    return love.data.encode("string", "hex", love.data.hash("sha1", raw))
  end)
  if not ok then return nil end
  local revision = require("mods.CRYSTAL_251.addresses").revisions[hash]
  if not revision then return nil end
  return { raw=raw, hash=hash, revision=revision }
end

local function isFile(path)
  if not (love and love.filesystem and love.filesystem.getInfo) then return false end
  local ok, info = pcall(love.filesystem.getInfo, path, "file")
  return ok and info and true or false
end

local function commandOutput(command)
  local pipe
  local okHost, HostShell = pcall(require, "src.core.HostShell")
  if okHost and HostShell and type(HostShell.popen) == "function" then
    pipe = HostShell.popen(command, "r")
  elseif io and io.popen then
    local ok, opened = pcall(io.popen, command, "r")
    pipe = ok and opened or nil
  end
  if not pipe then return nil end
  local okRead, value = pcall(pipe.read, pipe, "*a")
  pcall(pipe.close, pipe)
  if not okRead then return nil end
  value = value and value:gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value or nil
end

local function sourceBaseDirectory()
  local fs = love and love.filesystem
  if not (fs and fs.getSourceBaseDirectory) then return nil end
  local ok, base = pcall(fs.getSourceBaseDirectory)
  return ok and type(base) == "string" and base ~= "" and base or nil
end

local function cleanDirectory(path)
  if type(path) ~= "string" then return nil end
  path = path:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[/\\]+$", "")
  return path ~= "" and path or nil
end

local function parentDirectory(path)
  path = cleanDirectory(path)
  return path and cleanDirectory(path:match("^(.*)[/\\][^/\\]+$")) or nil
end

local function macBundleParent(path)
  path = cleanDirectory(path)
  if not path then return nil end
  local normalized = path:gsub("\\", "/")
  return cleanDirectory(normalized:match("^(.*)/[^/]+%.app/")
    or normalized:match("^(.*)/[^/]+%.app$"))
end

local function hostDirectories()
  local fs = love and love.filesystem
  local osName = love and love.system and love.system.getOS and love.system.getOS() or nil
  if osName == "Android" or osName == "iOS" then return {} end
  local dirs, seen = {}, {}
  local function add(path)
    path = cleanDirectory(path)
    if path and not seen[path] then
      seen[path] = true
      dirs[#dirs + 1] = path
    end
  end
  if osName == "Linux" and os and os.getenv then
    add(parentDirectory(os.getenv("APPIMAGE")))
  end
  if osName == "OS X" then
    add(macBundleParent(sourceBaseDirectory()))
    if type(arg) == "table" then add(macBundleParent(arg[0])) end
  end
  add(sourceBaseDirectory())
  if type(arg) == "table" then add(parentDirectory(arg[0])) end
  if fs and fs.getWorkingDirectory then
    local ok, cwd = pcall(fs.getWorkingDirectory)
    if ok then add(cwd) end
  end
  return dirs
end

local function externalRomPaths()
  local osName = love and love.system and love.system.getOS and love.system.getOS() or nil
  if osName ~= "Windows" and osName ~= "Linux" and osName ~= "OS X" then
    return {}
  end
  if osName == "Windows" and os and os.getenv
      and os.getenv("APPX_PACKAGE_FAMILY_NAME") then
    return {}
  end
  local paths, seen = {}, {}
  local function append(path)
    if path ~= "" and not seen[path] then
      seen[path] = true
      paths[#paths + 1] = path
    end
  end
  for _, base in ipairs(hostDirectories()) do
    local output
    local found = {}
    if osName == "Windows" then
      local quoted = base:gsub("'", "''")
      output = commandOutput("powershell -NoProfile -Command \"$p='" .. quoted
        .. "'; Get-ChildItem -LiteralPath $p -File | Where-Object {$_.Extension -ieq '.gbc'} | ForEach-Object {$_.FullName}\"")
      for path in tostring(output or ""):gmatch("[^\r\n]+") do
        found[#found + 1] = path
      end
    else
      local quoted = "'" .. base:gsub("'", "'\\''") .. "'"
      output = commandOutput("find " .. quoted
        .. " -maxdepth 1 -type f -iname '*.gbc' -print0 2>/dev/null")
      for path in tostring(output or ""):gmatch("([^%z]+)%z") do
        found[#found + 1] = path
      end
    end
    table.sort(found)
    for _, path in ipairs(found) do append(path) end
  end
  return paths
end

function Screen.romHint()
  local fs = love and love.filesystem
  local save = fs and fs.getSaveDirectory
    and select(2, pcall(fs.getSaveDirectory)) or nil
  local dirs = hostDirectories()
  local base = dirs[1]
  local fallback = type(save) == "string" and save .. "/" .. Screen.ROM_DIR
    or "the game folder/" .. Screen.ROM_DIR
  return base and base .. " OR " .. fallback or fallback
end

function Screen.findRom()
  if cachedAutoRom then return cachedAutoRom end
  local fs = love and love.filesystem
  if not (fs and fs.read and fs.getDirectoryItems) then return nil end
  local candidates, seen = {}, {}
  local function add(path)
    if not seen[path] and isFile(path) then
      seen[path] = true
      candidates[#candidates + 1] = path
    end
  end
  local function addDirectory(path, prefix)
    local ok, items = pcall(fs.getDirectoryItems, path)
    if not (ok and items) then return end
    table.sort(items)
    for _, name in ipairs(items) do
      if name:lower():match("%.gbc$") then
        add(prefix .. name)
      end
    end
  end
  for _, path in ipairs(PREFERRED_ROMS) do add(path) end
  addDirectory(Screen.ROM_DIR, Screen.ROM_DIR .. "/")
  addDirectory("", "")
  for _, path in ipairs(candidates) do
    local okRead, raw = pcall(fs.read, path)
    local found = okRead and identify(raw) or nil
    if found then
      found.path = path
      found.name = path:match("[^/]+$") or path
      cachedAutoRom = found
      return found
    end
  end
  for _, path in ipairs(externalRomPaths()) do
    local raw = readExternal(path)
    local found = identify(raw)
    if found then
      found.path = path
      found.name = path:match("[^/\\]+$") or path
      cachedAutoRom = found
      return found
    end
  end
  return nil
end

function Screen.romPresent()
  return Screen.findRom() ~= nil
end

local function androidPickerAvailable()
  return love and love.system and love.system.getOS
    and love.system.getOS() == "Android"
    and type(love.system.pickFile) == "function"
end

function Screen:beginAndroidPick()
  if not androidPickerAvailable() then return false end
  local fs = love and love.filesystem
  if fs and fs.remove then pcall(fs.remove, Screen.PICKED) end
  local ok, opened = pcall(love.system.pickFile, "rom")
  if not (ok and opened) then return false end
  self.androidPickPending = true
  self.status = "CHOOSE CRYSTAL ROM"
  self.detail = "SELECT ROM IN ANDROID"
  return true
end

function Screen:pollAndroidPick()
  if not self.androidPickPending then return false end
  local fs = love and love.filesystem
  if not (fs and fs.getInfo and fs.read) then return false end
  local okInfo, info = pcall(fs.getInfo, Screen.PICKED, "file")
  if not (okInfo and info) then return false end
  local okRead, raw = pcall(fs.read, Screen.PICKED)
  if fs.remove then pcall(fs.remove, Screen.PICKED) end
  self.androidPickPending = false
  if not okRead or type(raw) ~= "string" then
    self:fail("reading Android Crystal ROM", raw or "could not read selected ROM",
      "File: " .. Screen.PICKED)
    return true
  end
  local found = identify(raw)
  if not found then
    self:fail("validating Android Crystal ROM", "selected file is not a supported Pokemon Crystal ROM",
      "File: " .. Screen.PICKED)
    return true
  end
  self:start(raw, Screen.PICKED, found)
  return true
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

local function u16(value)
  value = value % 0x10000
  return string.char(value % 0x100, math.floor(value / 0x100))
end

local function u32(value)
  return string.char(value % 0x100, math.floor(value / 0x100) % 0x100,
    math.floor(value / 0x10000) % 0x100,
    math.floor(value / 0x1000000) % 0x100)
end

local function soundDataWav(soundData)
  local samples = soundData:getSampleCount()
  local channels = soundData:getChannelCount()
  local rate = soundData:getSampleRate()
  local pcm = {}
  for sample = 0, samples - 1 do
    for channel = 1, channels do
      local value = math.max(-1, math.min(1, soundData:getSample(sample, channel)))
      local integer = math.floor(value * 32767 + (value >= 0 and 0.5 or -0.5))
      pcm[#pcm + 1] = u16(integer)
    end
  end
  pcm = table.concat(pcm)
  local block = channels * 2
  return "RIFF" .. u32(36 + #pcm) .. "WAVEfmt " .. u32(16)
    .. u16(1) .. u16(channels) .. u32(rate) .. u32(rate * block)
    .. u16(block) .. u16(16) .. "data" .. u32(#pcm) .. pcm
end

function Screen.new(game, mod)
  local self = setmetatable({ game=game, mod=mod, status="CHOOSE CRYSTAL ROM",
    detail="PRESS A TO SELECT", progress=0 }, Screen)
  return self
end

function Screen.newAuto(game, mod)
  local self = Screen.new(game, mod)
  self.autoRestart = true
  local found = Screen.findRom()
  if found then
    self:start(found.raw, found.name, found)
  else
    self.status = "CRYSTAL ROM NOT FOUND"
    self.detail = Screen.romHint()
  end
  return self
end

function Screen:fail(stage, err, fullTrace)
  local reason = oneLine(err)
  local where = oneLine(stage or self.stage or "Crystal import")
  local rom = self.romName and ("ROM: " .. tostring(self.romName) .. "\n") or ""
  local full = ("Stage: %s\n%sReason: %s\n\n%s")
    :format(where, rom, reason, tostring(fullTrace or err or "unknown error"))
  self.worker = nil
  self.complete = false
  self.restarting = false
  self.status = "CRYSTAL IMPORT FAILED"
  self.detail = where .. ": " .. reason
  self.errorFull = full
  self.errorLog = ERROR_LOG
  writeFailureLog(self.mod, full)
end

function Screen:start(raw, displayName, identified)
  if self.worker then return end
  self.romName = displayName or "Crystal ROM"
  self.errorFull, self.errorLog = nil, nil
  if type(raw) ~= "string" then
    self:fail("reading ROM", "ROM data is not a byte string")
    return
  end
  local found = identified or identify(raw)
  if not found then
    local ok, hash = pcall(function()
      return love.data.encode("string", "hex", love.data.hash("sha1", raw))
    end)
    local reason = ok and ("unsupported ROM; SHA-1 " .. tostring(hash))
      or "could not calculate ROM SHA-1"
    self:fail("validating ROM", reason)
    return
  end
  local hash, revision = found.hash, found.revision
  self.status, self.detail = "IMPORTING CRYSTAL", revision.title
  self.stage = "starting import"
  self.worker = coroutine.create(function()
    self.stage = "loading Crystal extractor"
    local Extractor = require("mods.CRYSTAL_251.lib.extractor")
    local ImageWriter = require("src.import.ImageWriter")
    local CacheFs = require("src.import.CacheFs")
    self.stage = "clearing old Crystal cache"
    clearOldImport()
    local importedFiles, importedSet = {}, {}
    local function recordFile(path)
      if type(path) == "string" and not importedSet[path] then
        importedSet[path] = true
        importedFiles[#importedFiles + 1] = path
      end
    end
    local CrystalCry = require("mods.CRYSTAL_251.lib.crystal_cry")
    local content = Extractor.extract(raw, revision, {
      writePicture = function(path, bytes, w, h, palette, layout, presentation)
        self.stage = "writing image " .. tostring(path)
        local image = pictureImage(bytes, w, h, palette, layout)
        if presentation == "dex" then
          local canvas = ImageWriter.blank(56, 56, 0, 0, 0, 0)
          local x = math.floor((56 - image:getWidth()) / 2)
          local y = 56 - image:getHeight()
          ImageWriter.blit(canvas, image, x, y)
          image = canvas
        end
        ImageWriter.save(image, path)
        recordFile(path)
      end,
      writeCry = function(path, definition)
        self.stage = "rendering cry " .. tostring(path)
        local sound = CrystalCry.render(raw, definition)
        local saved, err = CacheFs.write(path, soundDataWav(sound))
        assert(saved, err)
        recordFile(path)
      end,
      progress = function(done, total)
        self.stage = ("extracting Pokemon %d of %d"):format(done, total)
        self.progress = done / total
        self.detail = ("POKEMON %d / %d"):format(done, total)
        coroutine.yield()
      end,
    })
    content.sourceSha1 = hash
    content.importFiles = importedFiles
    self.stage = "writing Crystal content cache"
    local Json = require("mods.CRYSTAL_251.lib.json")
    local ok, err = CacheFs.write(CACHE, Json.encode(content))
    assert(ok, err)
    self.stage = "complete"
    self.progress, self.complete = 1, true
    self.restartDelay = self.autoRestart and 0.5 or nil
    self.status = "CRYSTAL IMPORT COMPLETE"
    self.detail = self.autoRestart and "RESTARTING" or "PRESS A TO RESTART"
  end)
end

function Screen:choose()
  local found = Screen.findRom()
  if found then
    self:start(found.raw, found.name, found)
    return
  end
  if self:beginAndroidPick() then return end
  local path = choosePath()
  if path then
    local raw, err = readExternal(path)
    if not raw then
      self:fail("reading selected Crystal ROM", err,
        "ROM: " .. tostring(path) .. "\n" .. tostring(err or "unknown error"))
      return
    end
    self:start(raw, path:match("[^/\\]+$") or path)
    return
  end
  self.status = "CRYSTAL ROM NOT FOUND"
  self.detail = "PUT CRYSTAL ROM IN " .. Screen.romHint()
end

function Screen:update(dt)
  if self:pollAndroidPick() then return end
  if self.worker and coroutine.status(self.worker) ~= "dead" then
    local ok, err = coroutine.resume(self.worker)
    if not ok then
      local worker = self.worker
      self:fail(self.stage or "Crystal import", err, traceback(worker, err))
    end
    return
  end
  if self.complete and self.autoRestart then
    self.restartDelay = (self.restartDelay or 0) - (dt or 1 / 60)
    if self.restartDelay <= 0 and not self.restarting then
      self.restarting = true
      require("src.core.HostShell").restart()
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
    local function push(value)
      if value ~= "" then lines[#lines + 1] = value end
    end
    for word in tostring(text or ""):gmatch("%S+") do
      while #word > width do
        if line ~= "" then push(line); line = "" end
        push(word:sub(1, width))
        word = word:sub(width + 1)
      end
      if #line == 0 then line = word
      elseif #line + #word + 1 <= width then line = line .. " " .. word
      else push(line); line = word end
    end
    push(line)
    return lines
  end
  local function drawWrapped(text, x, y, width, limit)
    local lines=wrapped(text,width)
    for i=1,math.min(limit or #lines,#lines) do Font.draw(lines[i],x,y+(i-1)*16) end
  end
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawBox(0, 0, 20, 18)
  if self.errorFull then
    Font.draw("CRYSTAL IMPORT", 24, 16)
    Font.draw("FAILED", 56, 28)
    drawWrapped(self.detail, 16, 44, 17, 6)
    Font.draw("FULL ERROR PRINTED", 8, 116)
    Font.draw("A: RETRY B: BACK", 8, 128)
  else
    Font.draw("CRYSTAL 251", 40, 24)
    drawWrapped(self.status, 16, 56, 17, 2)
    drawWrapped(self.detail, 16, 88, 17, 2)
    love.graphics.rectangle("line", 16, 124, 128, 8)
    love.graphics.rectangle("fill", 17, 125, math.floor(126 * self.progress), 6)
    Font.draw("A: SELECT B: BACK", 16, 136)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Screen._resetAutoCandidate()
  cachedAutoRom = nil
end

return Screen
