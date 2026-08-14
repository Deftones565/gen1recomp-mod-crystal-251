package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

package.loaded["mods.CRYSTAL_251.addresses"] = {
  revisions = { good = { id="crystal-us-11", title="Pokemon Crystal US 1.1" } },
}

love = {
  data = {
    hash = function(_, raw) return raw == "good-rom" and "good" or "bad" end,
    encode = function(_, _, digest) return digest end,
  },
}

local files = {
  ["baseroms/crystal.gbc"] = "wrong-rom",
  ["baseroms/baserom.gbc"] = "good-rom",
}
local stored = {}
local mod = {
  read = function(_, path) return files[path] end,
  game = { save={ version="red", meta={playthroughId="test"} } },
  storage = {
    write = function(_, _, key, value) stored[key]=value return true end,
  },
  log = { error=function() end },
}

local Screen = require("mods.CRYSTAL_251.import_screen")
Screen.mod = mod
Screen._resetAutoCandidate()
local found = Screen.findRom()
T.eq(found and found.path, "baseroms/baserom.gbc",
  "sandbox discovery reads a supported named ROM through mod:read")
T.eq(found and found.revision.id, "crystal-us-11",
  "sandbox discovery identifies the supported revision")
T.check(Screen.romPresent(), "supported mod-owned Crystal ROM is present")
T.check(Screen.romHint():find("THIS MOD'S baseroms FOLDER", 1, true) ~= nil,
  "ROM hint names only the mod-owned baseroms folder")

local started
local originalStart = Screen.start
Screen.start = function(_, raw, name, identified)
  started = { raw=raw, name=name, identified=identified }
end
local chooser = Screen.new({ input={} }, mod)
chooser:choose()
T.eq(started and started.raw, "good-rom",
  "manual import uses the same scoped discovery path")
T.eq(started and started.name, "baserom.gbc",
  "manual import retains the packaged ROM name")
Screen.start = originalStart

files["baseroms/baserom.gbc"] = nil
Screen._resetAutoCandidate()
local missing = Screen.new({ input={} }, mod)
missing:choose()
T.eq(missing.status, "CRYSTAL ROM NOT FOUND",
  "missing packaged ROM leaves a clear status")
T.check(missing.detail:find("THIS MOD'S baseroms FOLDER", 1, true) ~= nil,
  "missing-ROM detail does not expose a host path")

missing:fail("validating ROM", "bad hash", "test trace")
T.eq(stored["cache/error"].text:find("bad hash", 1, true) ~= nil, true,
  "failure details persist through mod.storage")

T.finish("Crystal sandbox importer")
