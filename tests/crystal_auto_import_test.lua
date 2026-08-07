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
  ["Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"] = "good-rom",
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
      elseif path == "" then
        return { "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc", "mods" }
      end
      return {}
    end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil; return true end,
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
ok(Screen.romHint():find("/tmp/crystal251/baseroms", 1, true) ~= nil,
  "manual import reports the writable baseroms folder among valid drop locations")

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
found = Screen.findRom()
eq(found and found.path, "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc",
  "automatic Crystal scan accepts an arbitrary filename beside the game")

local pickerChecks = 0
love.system = { getOS = function() pickerChecks = pickerChecks + 1; return "Unknown" end }
local selectedAuto
local chooser = Screen.new({ input={} }, {})
chooser.start = function(_, raw, name, identified)
  selectedAuto = { raw=raw, name=name, identified=identified }
end
chooser:choose()
eq(selectedAuto and selectedAuto.identified and selectedAuto.identified.path,
  "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc",
  "manual Crystal import uses automatic discovery before the file picker")
eq(pickerChecks, 0,
  "Crystal file picker is not consulted when automatic discovery succeeds")

files["Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"] = nil
local realGetenv = os.getenv
local realOpen = io.open
local realHostShell = package.loaded["src.core.HostShell"]
local appImageRom = "/games/Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
os.getenv = function(name)
  if name == "APPIMAGE" then return "/games/gen1recomp-x86_64.AppImage" end
  return realGetenv and realGetenv(name) or nil
end
io.open = function(path, mode)
  if path == appImageRom then
    return { read=function() return "good-rom" end, close=function() end }
  end
  return realOpen(path, mode)
end
package.loaded["src.core.HostShell"] = {
  popen = function(command)
    local value = command:find("/games", 1, true) and (appImageRom .. "\0") or ""
    return { read=function() return value end, close=function() end }
  end,
}
love.system = { getOS=function() return "Linux" end }
love.filesystem.getSourceBaseDirectory = function() return "/tmp/.mount_gen1/usr/bin" end
love.filesystem.getWorkingDirectory = function() return "/home/user" end
Screen._resetAutoCandidate()
found = Screen.findRom()
eq(found and found.path, appImageRom,
  "AppImage auto-detection uses the directory containing the AppImage")
ok(Screen.romHint():find("/games", 1, true) ~= nil,
  "AppImage ROM hint names the directory beside the AppImage")
os.getenv = realGetenv
io.open = realOpen
package.loaded["src.core.HostShell"] = realHostShell
love.filesystem.getSourceBaseDirectory = nil
love.filesystem.getWorkingDirectory = nil
love.system = { getOS = function() pickerChecks = pickerChecks + 1; return "Unknown" end }
Screen._resetAutoCandidate()
ok(Screen.findRom() == nil,
  "automatic Crystal import remains idle when no supported ROM is present")

local androidPickerCalls = 0
love.system = {
  getOS = function() return "Android" end,
  pickFile = function(kind)
    androidPickerCalls = androidPickerCalls + 1
    eq(kind, "rom", "Crystal Android picker requests a ROM")
    files[Screen.PICKED] = "good-rom"
    return true
  end,
}
local androidSelected
local android = Screen.new({ input={ wasPressed=function() return false end } }, {})
android.start = function(_, raw, name, identified)
  androidSelected = { raw=raw, name=name, identified=identified }
end
android:choose()
eq(androidPickerCalls, 1,
  "Crystal falls back to Android's native picker when auto-detection fails")
ok(android.androidPickPending,
  "Crystal waits for the Android picker handoff asynchronously")
ok(android:pollAndroidPick(),
  "Crystal consumes the Android picker handoff when it arrives")
eq(androidSelected and androidSelected.raw, "good-rom",
  "Crystal imports the ROM bytes delivered by Android")
eq(androidSelected and androidSelected.name, Screen.PICKED,
  "Crystal labels the Android picker handoff consistently")
ok(files[Screen.PICKED] == nil,
  "Crystal removes the transient Android picker handoff after consuming it")

love.system = { getOS = function() pickerChecks = pickerChecks + 1; return "Unknown" end }
local fallback = Screen.new({ input={} }, {})
fallback:choose()
eq(fallback.status, "CRYSTAL ROM NOT FOUND",
  "Crystal manual import falls back to the desktop/manual hint when no picker exists")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal auto import)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal auto import)"):format(checks, checks))
