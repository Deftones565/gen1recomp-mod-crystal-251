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

package.loaded["mods.CRYSTAL_251.addresses"] = {
  revisions = {
    good = { id="crystal-us-11", title="Pokemon Crystal US 1.1" },
  },
}

local files = {
  ["baseroms/crystal.gbc"] = "wrong-rom",
  ["baseroms/renamed-copy.gbc"] = "good-rom",
}
_G.love = {
  data = {
    hash = function(_, raw) return raw == "good-rom" and "good" or "bad" end,
    encode = function(_, _, digest) return digest end,
  },
  filesystem = {
    getInfo = function(path)
      return files[path] and { type="file" } or nil
    end,
    getDirectoryItems = function(path)
      if path == "baseroms" then
        return { "crystal.gbc", "notes.txt", "renamed-copy.gbc" }
      end
      return {}
    end,
    read = function(path) return files[path] end,
    getSaveDirectory = function() return "/tmp/crystal251" end,
  },
}

local Screen = require("mods.CRYSTAL_251.import_screen")
Screen._resetAutoCandidate()
local found = Screen.findRom()
eq(found and found.path, "baseroms/renamed-copy.gbc",
  "automatic Crystal scan skips unsupported GBC files")
eq(found and found.revision.id, "crystal-us-11",
  "automatic Crystal scan accepts a supported revision under any filename")
ok(Screen.romPresent(), "supported Crystal ROM is reported present")
eq(Screen.romHint(), "/tmp/crystal251/baseroms",
  "manual import reports the writable baseroms folder")

local auto = Screen.newAuto({ input={} }, {})
ok(auto.autoRestart, "automatic Crystal import restarts after rebuilding content")
eq(auto.status, "IMPORTING CRYSTAL",
  "automatic Crystal screen begins extraction without another button press")
ok(type(auto.worker) == "thread",
  "automatic Crystal import creates the stepped extraction worker")

local logged
local diagnostic = Screen.new({ input={} }, {
  log = { error = function(_, _, message) logged = message end },
})
diagnostic:fail("writing generated sprite", "disk full", "test traceback")
eq(diagnostic.status, "CRYSTAL IMPORT FAILED",
  "Crystal import failures remain on a dedicated error screen")
ok(diagnostic.detail:find("disk full", 1, true) ~= nil,
  "Crystal error screen includes the actual failure reason")
ok(type(logged) == "string" and logged:find("disk full", 1, true) ~= nil,
  "Crystal import failure is printed through the mod logger")

files["baseroms/renamed-copy.gbc"] = nil
Screen._resetAutoCandidate()
ok(Screen.findRom() == nil,
  "automatic Crystal import remains idle when no supported ROM is present")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal auto import)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal auto import)"):format(checks, checks))
