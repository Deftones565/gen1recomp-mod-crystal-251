local Screen = {}
Screen.__index = Screen
local Picture = require("mods.CRYSTAL_251.lib.picture")
local Cache = require("mods.CRYSTAL_251.lib.cache")

Screen.ROM_DIR = "baseroms"
local PREFERRED_ROMS = {
  "baseroms/pokemon_crystal.gbc",
  "baseroms/pokemon_crystal_version.gbc",
  "baseroms/crystal.gbc",
  "baseroms/baserom.gbc",
  "pokemon_crystal.gbc",
  "pokemon_crystal_version.gbc",
  "crystal.gbc",
  "baserom.gbc",
}

local cachedRom

local function oneLine(value)
  return tostring(value or "unknown error")
    :gsub("\r", ""):gsub("\n+", " | "):gsub("%s+", " ")
    :gsub("^%s+", ""):gsub("%s+$", "")
end

local function traceback(_, err)
  return tostring(err or "unknown error")
end

local function writeFailureLog(mod, value)
  local text = tostring(value or "unknown error")
  if mod and mod.log then
    pcall(function() mod.log:error("Crystal import failed: %s", text) end)
  end
  if mod and mod.storage and mod.game then
    pcall(mod.storage.write, mod.storage, mod.game, "cache/error", { text=text })
  end
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

function Screen.romHint()
  return "THIS MOD'S " .. Screen.ROM_DIR .. " FOLDER"
end

function Screen.findRom()
  if cachedRom then return cachedRom end
  local mod = Screen.mod
  if not (mod and type(mod.read) == "function") then return nil end
  for _, path in ipairs(PREFERRED_ROMS) do
    local ok, raw = pcall(mod.read, mod, path)
    local found = ok and identify(raw) or nil
    if found then
      found.path, found.name = path, path:match("[^/]+$") or path
      cachedRom = found
      return found
    end
  end
  return nil
end

function Screen.romPresent()
  return Screen.findRom() ~= nil
end

function Screen.new(game, mod, options)
  Screen.mod = mod
  Cache.bind(mod)
  options = options or {}
  if options.automatic then
    local done, total = Cache.persistProgress()
    return setmetatable({ game=game, mod=mod, automatic=true,
      status="IMPORTING CRYSTAL", detail="PREPARING CRYSTAL 251",
      progress=total > 0 and done / total or 0, hold=0 }, Screen)
  end
  local self = setmetatable({ game=game, mod=mod, status="CHOOSE CRYSTAL ROM",
    detail="PRESS A TO CHECK", progress=0 }, Screen)
  return self
end

Screen.isOpaque = true

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
  self.errorLog = "mod.storage:cache/error"
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
    self.stage = "clearing old Crystal cache"
    local cleared, clearErr = Cache.clear()
    assert(cleared, clearErr)
    local importedFiles, importedSet = {}, {}
    local function recordFile(path)
      if type(path) == "string" and not importedSet[path] then
        importedSet[path] = true
        importedFiles[#importedFiles + 1] = path
      end
    end
    local content = Extractor.extract(raw, revision, {
      writePicture = function(path, bytes, w, h, palette, layout, presentation)
        self.stage = "writing image " .. tostring(path)
        local saved, saveErr = Cache.stageAsset(path, {
          raster=Picture.shadeRaster(bytes, w, h, layout),
          width=w * 8, height=h * 8, palette=palette,
          presentation=presentation,
        })
        assert(saved, saveErr)
        recordFile(path)
      end,
      progress = function(done, total)
        self.stage = ("extracting Pokemon %d of %d"):format(done, total)
        self.progress = done / total
        self.detail = ("POKEMON %d / %d"):format(done, total)
        -- Extraction itself is sub-second; yielding once per Pokemon forced
        -- an otherwise finished import to occupy at least 251 display frames.
        -- Sixteen-species batches keep the progress screen responsive while
        -- removing that artificial four-second floor.
        if done == total or done % 16 == 0 then coroutine.yield() end
      end,
    })
    content.sourceSha1 = hash
    content.importFiles = importedFiles
    self.stage = "preparing compressed Crystal cache"
    assert(Cache.stageContent(content))
    while Cache.hasPendingPersist() do
      local done, err = Cache.persistMemoryStep(1)
      assert(not err, err)
      local complete, total = Cache.persistProgress()
      self.progress = total > 0 and complete / total or 1
      self.detail = ("CACHE %d / %d"):format(complete, total)
      if not done then coroutine.yield() end
    end
    self.stage = "complete"
    self.progress, self.complete = 1, true
    self.status = "CRYSTAL IMPORT COMPLETE"
    self.detail = "CLOSE AND REOPEN GAME"
  end)
end

function Screen:choose()
  local found = Screen.findRom()
  if found then
    self:start(found.raw, found.name, found)
    return
  end
  self.status = "CRYSTAL ROM NOT FOUND"
  self.detail = "PUT CRYSTAL ROM IN " .. Screen.romHint()
end

function Screen:update(dt)
  if self.automatic then
    local done, err = Cache.persistMemoryStep(16)
    local complete, total = Cache.persistProgress()
    self.progress = total > 0 and complete / total or 1
    self.detail = ("FILES %d / %d"):format(complete, total)
    if err then
      self.automatic = false
      self:fail("saving Crystal cache", err)
    elseif done then
      self.status, self.detail, self.progress = "CRYSTAL IMPORT COMPLETE", "READY", 1
      self.hold = (self.hold or 0) + (tonumber(dt) or 1 / 60)
      if self.hold >= 0.75 and self.game.stack:top() == self then
        self.game.stack:pop()
      end
    end
    return
  end
  if self.worker and coroutine.status(self.worker) ~= "dead" then
    local ok, err = coroutine.resume(self.worker)
    if not ok then
      local worker = self.worker
      self:fail(self.stage or "Crystal import", err, traceback(worker, err))
    end
    return
  end
  local input = self.game.input
  if input:wasPressed("b") then self.game.stack:pop()
  elseif input:wasPressed("a") then
    if self.complete then
      self.status, self.detail = "RESTART REQUIRED", "CLOSE AND REOPEN GAME"
    else
      self:choose()
    end
  end
end

function Screen:draw()
  local Font = assert(self.mod and self.mod.ui and self.mod.ui.Font,
    "Crystal importer needs mod.ui.Font")
  local function wrapped(text, width)
    local lines, line = {}, ""
    local function push(value)
      if value ~= "" then lines[#lines + 1] = value end
    end
    for matched in tostring(text or ""):gmatch("%S+") do
      local word = matched
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
    Font.draw(self.automatic and "PLEASE WAIT" or "A: CHECK B: BACK", 16, 136)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Screen._resetRomCandidate()
  cachedRom = nil
end

-- Kept for the existing importer contract/tests; both names reset the same
-- mod-owned required-import candidate.
Screen._resetAutoCandidate = Screen._resetRomCandidate

return Screen
