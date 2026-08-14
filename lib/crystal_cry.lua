local bit = require("bit")

local Cry = {}

local SAMPLE_RATE = 44100
local FRAME_SAMPLES = SAMPLE_RATE / 60
local GB_CLOCK = 4194304

local DUTY = {
  [0] = {0, 0, 0, 0, 0, 0, 0, 1},
  [1] = {1, 0, 0, 0, 0, 0, 0, 1},
  [2] = {1, 0, 0, 0, 0, 1, 1, 1},
  [3] = {0, 1, 1, 1, 1, 1, 1, 0},
}

local NOISE_DIVISORS = {
  [0] = 8, [1] = 16, [2] = 32, [3] = 48,
  [4] = 64, [5] = 80, [6] = 96, [7] = 112,
}

local function romOffset(bank, address)
  return bank * 0x4000 + address % 0x4000
end

local function byteAt(raw, bank, address)
  local value = raw:byte(romOffset(bank, address) + 1)
  assert(value, ("Crystal cry read outside ROM at %02X:%04X"):format(bank, address))
  return value
end

local function wordAt(raw, bank, address)
  return byteAt(raw, bank, address) + byteAt(raw, bank, address + 1) * 0x100
end

local function signed16(value)
  return value >= 0x8000 and value - 0x10000 or value
end

local function fadeValue(nibble)
  if bit.band(nibble, 8) ~= 0 then return -bit.band(nibble, 7) end
  return nibble
end

local function envelopeVolume(volume, fade, elapsed)
  if fade == 0 then return volume end
  local steps = math.floor(elapsed * 64 / math.abs(fade))
  if fade > 0 then return math.max(0, volume - steps) end
  return math.min(15, volume + steps)
end

local function sweepCalculation(register, sweep)
  local delta = math.floor(register / (2 ^ sweep.shift))
  if sweep.subtract then return register - delta end
  return register + delta
end

local function sweptRegister(register, sweep, elapsed)
  if not sweep or sweep.shift == 0 then return register end
  local nextRegister = sweepCalculation(register, sweep)
  if nextRegister > 0x7ff or nextRegister < 0 then return nil end
  if sweep.pace == 0 then return register end
  local iterations = math.floor(elapsed * 128 / sweep.pace)
  for _ = 1, iterations do
    register = nextRegister
    nextRegister = sweepCalculation(register, sweep)
    if nextRegister > 0x7ff or nextRegister < 0 then return nil end
  end
  return register
end

local function headerChannels(raw, header)
  local first = byteAt(raw, header.bank, header.address)
  local count = bit.rshift(first, 6) + 1
  local channels = {}
  for index = 0, count - 1 do
    local address = header.address + index * 3
    local descriptor = byteAt(raw, header.bank, address)
    local number = bit.band(descriptor, 0x0f) + 1
    assert(number == 5 or number == 6 or number == 8,
      "unsupported Crystal cry channel " .. tostring(number))
    channels[#channels + 1] = {
      number = number,
      address = wordAt(raw, header.bank, address + 1),
    }
  end
  return channels
end

local Channel = {}
Channel.__index = Channel

function Channel.new(raw, bank, spec, definition)
  local hardware = (spec.number - 1) % 4 + 1
  return setmetatable({
    raw = raw,
    bank = bank,
    number = spec.number,
    hardware = hardware,
    address = spec.address,
    tempo = hardware == 4 and 0x100 or definition.length,
    pitchOffset = definition.pitch or 0,
    durationModifier = 0,
    duty = 0,
    dutyPattern = nil,
    dutyFrame = 0,
    sweep = nil,
    callStack = {},
    loopCounts = {},
    events = {},
    totalFrames = 0,
  }, Channel)
end

function Channel:byte()
  local value = byteAt(self.raw, self.bank, self.address)
  self.address = self.address + 1
  return value
end

function Channel:word()
  local value = wordAt(self.raw, self.bank, self.address)
  self.address = self.address + 2
  return value
end

function Channel:bigWord()
  local value = self:byte() * 0x100 + self:byte()
  return value
end

function Channel:durationFrames(length)
  local value = self.durationModifier + (length + 1) * self.tempo
  self.durationModifier = value % 0x100
  return math.max(1, math.floor(value / 0x100))
end

function Channel:addEvent(length, packed, parameter)
  local frames = self:durationFrames(length)
  local event = {
    startSample = self.totalFrames * FRAME_SAMPLES,
    endSample = (self.totalFrames + frames) * FRAME_SAMPLES,
    frames = frames,
    volume = bit.rshift(packed, 4),
    fade = fadeValue(bit.band(packed, 0x0f)),
    noise = self.hardware == 4,
    parameter = self.hardware == 4
      and bit.band(parameter + self.pitchOffset, 0xff) or nil,
    sweep = self.sweep and {
      pace = self.sweep.pace,
      subtract = self.sweep.subtract,
      shift = self.sweep.shift,
    } or nil,
  }
  if self.dutyPattern then
    event.dutyPattern = {
      self.dutyPattern[1], self.dutyPattern[2],
      self.dutyPattern[3], self.dutyPattern[4],
    }
    event.dutyOffset = self.dutyFrame % 4
    self.dutyFrame = self.dutyFrame + frames
  else
    event.duty = self.duty
  end
  if not event.noise then
    event.register = bit.band(self:word() + self.pitchOffset, 0x7ff)
  end
  self.events[#self.events + 1] = event
  self.totalFrames = self.totalFrames + frames
end

function Channel:parse()
  for _ = 1, 100000 do
    local commandAddress = self.address
    local command = self:byte()
    if command < 0xd0 then
      local packed = self:byte()
      if self.hardware == 4 then
        self:addEvent(command, packed, self:byte())
      else
        self:addEvent(command, packed)
      end
    elseif command == 0xdb then
      self.duty = bit.band(self:byte(), 3)
    elseif command == 0xdd then
      local packed = self:byte()
      self.sweep = {
        pace = bit.band(bit.rshift(packed, 4), 7),
        subtract = bit.band(packed, 8) ~= 0,
        shift = bit.band(packed, 7),
      }
    elseif command == 0xde then
      local packed = self:byte()
      self.dutyPattern = {
        bit.band(bit.rshift(packed, 6), 3),
        bit.band(bit.rshift(packed, 4), 3),
        bit.band(bit.rshift(packed, 2), 3),
        bit.band(packed, 3),
      }
      self.dutyFrame = 0
    elseif command == 0xe6 then
      self.pitchOffset = signed16(self:bigWord())
    elseif command == 0xfc then
      self.address = self:word()
    elseif command == 0xfd then
      local count, target = self:byte(), self:word()
      assert(count ~= 0, "infinite Crystal cry loop")
      local remaining = self.loopCounts[commandAddress]
      if remaining == nil then remaining = count end
      remaining = remaining - 1
      if remaining > 0 then
        self.loopCounts[commandAddress] = remaining
        self.address = target
      else
        self.loopCounts[commandAddress] = nil
      end
    elseif command == 0xfe then
      self.callStack[#self.callStack + 1] = self.address + 2
      self.address = self:word()
    elseif command == 0xff then
      local returnAddress = table.remove(self.callStack)
      if returnAddress then
        self.address = returnAddress
      else
        return self.events
      end
    else
      error(("unsupported Crystal cry command %02X at %02X:%04X")
        :format(command, self.bank, commandAddress))
    end
  end
  error("Crystal cry program exceeded command limit")
end

local function parse(raw, definition)
  local channels = {}
  for _, spec in ipairs(headerChannels(raw, definition.header)) do
    local channel = Channel.new(raw, definition.header.bank, spec, definition)
    channel:parse()
    channels[#channels + 1] = channel
  end
  return channels
end

local function resetNoise(state)
  state.noiseLfsr = 0x7fff
  state.noiseClock = 0
end

local function clockNoise(state, width7)
  local feedback = bit.bxor(
    bit.band(state.noiseLfsr, 1),
    bit.band(bit.rshift(state.noiseLfsr, 1), 1))
  state.noiseLfsr = bit.bor(
    bit.rshift(state.noiseLfsr, 1),
    bit.lshift(feedback, 14))
  if width7 then
    state.noiseLfsr = bit.bor(
      bit.band(state.noiseLfsr, bit.bnot(0x40)),
      bit.lshift(feedback, 6))
  end
end

local function sampleNoise(state, parameter)
  local divisor = NOISE_DIVISORS[bit.band(parameter, 7)]
  local shift = bit.rshift(parameter, 4)
  if shift < 14 then
    local remaining = GB_CLOCK / divisor / (2 ^ shift) / SAMPLE_RATE
    local width7 = bit.band(parameter, 8) ~= 0
    while remaining > 0 do
      local span = math.min(remaining, 1 - state.noiseClock)
      state.noiseClock = state.noiseClock + span
      remaining = remaining - span
      if state.noiseClock >= 1 - 1e-12 then
        state.noiseClock = 0
        clockNoise(state, width7)
      end
    end
  end
  return bit.band(state.noiseLfsr, 1) == 0 and 1 or -1
end

local function renderer(channel)
  local state = {
    channel = channel,
    eventIndex = 1,
    event = nil,
    phase = 0,
  }
  resetNoise(state)
  return state
end

local function currentEvent(state, sampleIndex)
  local event = state.event
  if event and sampleIndex < event.endSample then return event end
  while state.eventIndex <= #state.channel.events do
    event = state.channel.events[state.eventIndex]
    state.eventIndex = state.eventIndex + 1
    if sampleIndex < event.endSample then
      state.event = event
      state.phase = 0
      resetNoise(state)
      return event
    end
  end
  state.event = nil
  return nil
end

local function sampleChannel(state, sampleIndex)
  local event = currentEvent(state, sampleIndex)
  if not event or sampleIndex < event.startSample then return 0 end
  local localSample = sampleIndex - event.startSample
  local elapsed = localSample / SAMPLE_RATE
  local volume = envelopeVolume(event.volume, event.fade, elapsed)
  if event.noise then
    return sampleNoise(state, event.parameter) * volume / 15
  end
  local register = sweptRegister(event.register, event.sweep, elapsed)
  if not register then return 0 end
  local frequency = 131072 / (2048 - register)
  local phase = state.phase
  state.phase = (phase + frequency / SAMPLE_RATE) % 1
  local duty = event.duty
  if event.dutyPattern then
    local frame = math.floor(localSample / FRAME_SAMPLES)
    duty = event.dutyPattern[(event.dutyOffset + frame) % 4 + 1]
  end
  local pattern = DUTY[duty or 0]
  local step = math.floor(phase * 8) % 8
  return (pattern[step + 1] == 0 and -1 or 1) * volume / 15
end

function Cry.render(raw, definition)
  assert(type(raw) == "string", "Crystal ROM bytes are required")
  assert(type(definition) == "table" and definition.header,
    "Crystal cry definition is required")
  local channels = parse(raw, definition)
  local samples = 0
  local states = {}
  for _, channel in ipairs(channels) do
    samples = math.max(samples, channel.totalFrames * FRAME_SAMPLES)
    states[#states + 1] = renderer(channel)
  end
  assert(samples > 0 and samples <= SAMPLE_RATE * 5,
    "invalid Crystal cry duration")
  local sound = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 2)
  for index = 0, samples - 1 do
    local value = 0
    for _, state in ipairs(states) do
      value = value + sampleChannel(state, index)
    end
    value = math.max(-1, math.min(1, value / 4))
    sound:setSample(index, 1, value)
    sound:setSample(index, 2, value)
  end
  return sound
end

function Cry.trace(raw, definition)
  local out = {}
  for _, channel in ipairs(parse(raw, definition)) do
    local events = {}
    for _, event in ipairs(channel.events) do
      events[#events + 1] = {
        frames = event.frames,
        register = event.register,
        volume = event.volume,
        fade = event.fade,
        parameter = event.parameter,
        duty = event.duty,
        dutyPattern = event.dutyPattern,
        dutyOffset = event.dutyOffset,
        sweep = event.sweep,
      }
    end
    out[#out + 1] = {
      number = channel.number,
      totalFrames = channel.totalFrames,
      events = events,
    }
  end
  return out
end

-- Compile the parsed Crystal cry into the engine's self-contained authored
-- chip format. Crystal stores pitch and duration as 16-bit species values;
-- baking those values into each note avoids trying to place them in the
-- byte-sized modifiers used by Generation I cry records.
function Cry.chip(raw, definition)
  local channels = {}
  for _, channel in ipairs(Cry.trace(raw, definition)) do
    local program = {}
    for _, event in ipairs(channel.events) do
      local sweep = event.sweep or { pace=0, subtract=false, shift=0 }
      program[#program + 1] = { pitchSweep = {
        pace=sweep.pace, subtract=sweep.subtract, shift=sweep.shift,
      } }
      local consumed = 0
      while consumed < event.frames do
        local frames = math.min(16, event.frames - consumed)
        if event.dutyPattern then
          local pattern, offset = {}, (event.dutyOffset or 0) + consumed
          for index = 1, 4 do
            pattern[index] = event.dutyPattern[(offset + index - 1) % 4 + 1]
          end
          program[#program + 1] = { dutyPattern=pattern }
        elseif event.duty ~= nil then
          program[#program + 1] = { duty=event.duty }
        end
        if channel.number == 8 then
          program[#program + 1] = { noiseNote = {
            len=frames, volume=event.volume, fade=event.fade,
            parameter=event.parameter,
          } }
        else
          program[#program + 1] = { squareNote = {
            len=frames, volume=event.volume, fade=event.fade,
            frequency=event.register,
          } }
        end
        consumed = consumed + frames
      end
    end
    channels[#channels + 1] = {
      hw=(channel.number - 1) % 4 + 1,
      program=program,
    }
  end
  return require("src.audio.ChipAsm").sfx({ channels=channels }).chip
end

return Cry
