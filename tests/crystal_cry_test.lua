package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    fail(("%s (got %s, want %s)"):format(message, tostring(got), tostring(want)))
  end
end
local function ok(value, message)
  checks = checks + 1
  if not value then fail(message) end
end

local bytes = {}
for index = 1, 0x4300 do bytes[index] = "\0" end
local function put(address, ...)
  local values = {...}
  local offset = 0x4000 + address % 0x4000
  for index, value in ipairs(values) do
    bytes[offset + index] = string.char(value)
  end
end

put(0x4000, 0x44, 0x00, 0x41, 0x07, 0x00, 0x42)
put(0x4100,
  0xdb, 0x01,
  0xe6, 0x00, 0x20,
  0xdd, 0xf9,
  0x01, 0xf8, 0x00, 0x07,
  0xfe, 0x20, 0x41,
  0xff)
put(0x4120,
  0xde, 0x6c,
  0x00, 0xa1, 0x00, 0x06,
  0xff)
put(0x4200,
  0x02, 0xb2, 0x5f,
  0xfd, 0x02, 0x00, 0x42,
  0xff)

local raw = table.concat(bytes)
local definition = {
  header = { bank=1, address=0x4000 },
  pitch = 100,
  length = 128,
}

local Cry = require("mods.CRYSTAL_251.lib.crystal_cry")
local trace = Cry.trace(raw, definition)
eq(#trace, 2, "header channel count is decoded")
eq(trace[1].number, 5, "pulse channel identity is retained")
eq(trace[2].number, 8, "noise channel identity is retained")
eq(#trace[1].events, 2, "sound_call returns to the caller")
eq(#trace[2].events, 2, "sound_loop repeats the requested count")
eq(trace[1].events[1].frames, 1, "Crystal tonal duration uses the direct 16-bit tempo")
eq(trace[2].events[1].frames, 3, "Crystal noise duration keeps the default tempo")
eq(trace[1].events[1].register, 0x720, "pitch_offset replaces the species pitch")
eq(trace[1].events[1].duty, 1, "fixed duty-cycle commands are decoded")
eq(trace[1].events[2].dutyPattern[1], 1, "duty-cycle patterns are decoded")
eq(trace[1].events[2].dutyPattern[2], 2, "duty-cycle pattern order is retained")
eq(trace[1].events[1].sweep.pace, 7, "pitch sweep pace is decoded")
eq(trace[1].events[1].sweep.subtract, true, "pitch sweep direction is decoded")
eq(trace[2].events[1].parameter, 0xc3, "species pitch offsets the noise polynomial")
eq(trace[2].totalFrames, 6, "looped noise duration is accumulated")

local writes, badIndex, badChannel, badValue = 0, false, false, false
love = {
  sound = {
    newSoundData = function(samples, rate, bits, channels)
      local sound = {
        samples=samples, rate=rate, bits=bits, channels=channels,
      }
      function sound:setSample(index, channel, value)
        writes = writes + 1
        if index < 0 or index >= self.samples then badIndex = true end
        if channel ~= 1 and channel ~= 2 then badChannel = true end
        if value < -1 or value > 1 then badValue = true end
      end
      function sound:getSampleCount() return self.samples end
      function sound:getChannelCount() return self.channels end
      function sound:getSampleRate() return self.rate end
      return sound
    end,
  },
}

local sound = Cry.render(raw, definition)
eq(sound:getSampleCount(), 6 * 735, "renderer lasts for the longest Crystal channel")
eq(sound:getChannelCount(), 2, "renderer creates non-spatialized stereo cries")
eq(sound:getSampleRate(), 44100, "renderer uses the engine sample rate")
eq(writes, sound:getSampleCount() * 2, "renderer fills both output channels")
ok(not badIndex, "render writes within the sample buffer")
ok(not badChannel, "render writes stereo channels")
ok(not badValue, "rendered samples remain normalized")

local romPath = os.getenv("CRYSTAL_ROM")
if romPath and romPath ~= "" then
  local file = assert(io.open(romPath, "rb"))
  local crystal = file:read("*a")
  file:close()
  local addresses = require("mods.CRYSTAL_251.addresses").revisions[
    "f2f52230b536214ef7c9924f483392993e226cfb"].addresses
  local function offset(pointer)
    return pointer.bank * 0x4000 + pointer.address % 0x4000
  end
  local function u8(position)
    return assert(crystal:byte(position + 1))
  end
  local function u16(position)
    return u8(position) + u8(position + 1) * 0x100
  end
  local function s16(position)
    local value = u16(position)
    return value >= 0x8000 and value - 0x10000 or value
  end
  local cryPointers = offset(addresses.cryPointers)
  local pokemonCries = offset(addresses.pokemonCries)
  for dex = 1, 251 do
    local row = pokemonCries + (dex - 1) * 6
    local index = u16(row)
    local pointer = cryPointers + index * 3
    local current = {
      header = { bank=u8(pointer), address=u16(pointer + 1) },
      pitch = s16(row + 2),
      length = u16(row + 4),
    }
    local parsed, result = pcall(Cry.trace, crystal, current)
    ok(parsed, ("Crystal species %d cry parses: %s")
      :format(dex, tostring(result)))
    if parsed then
      ok(#result >= 1 and #result <= 3,
        ("Crystal species %d has valid cry channels"):format(dex))
      local audible = false
      for _, channel in ipairs(result) do
        if #channel.events > 0 then
          audible = true
          ok(channel.totalFrames > 0,
            ("Crystal species %d channel %d has positive duration")
              :format(dex, channel.number))
        end
      end
      ok(audible, ("Crystal species %d has an audible channel"):format(dex))
    end
  end
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal cry renderer)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal cry renderer)"):format(checks, checks))
