-- Generation II real-time clock, adapted to the Gen I save shape.
-- Crystal stores an offset from the host clock rather than a frozen hour.

local Clock = {}

Clock.MINUTES_PER_DAY = 1440
Clock.DAYS = 7
Clock.DEFAULT_HOUR = 10
Clock.DEFAULT_MINUTE = 0

local function hostMinutes()
  local hour = tonumber(os.date("%H")) or 0
  local minute = tonumber(os.date("%M")) or 0
  return (hour * 60 + minute) % Clock.MINUTES_PER_DAY
end

local function hostWeekday()
  return (tonumber(os.date("%w")) or 0) % Clock.DAYS
end

local function rtc(save)
  return type(save) == "table" and save.rtc or nil
end

function Clock.setTime(save, hour, minute)
  if type(save) ~= "table" then return false end
  save.rtc = save.rtc or {}
  local wanted = (math.floor(hour or 0) % 24) * 60
    + (math.floor(minute or 0) % 60)
  save.rtc.startMinute = (wanted - hostMinutes()) % Clock.MINUTES_PER_DAY
  return true
end

function Clock.setWeekday(save, day)
  if type(save) ~= "table" then return false end
  save.rtc = save.rtc or {}
  save.rtc.startDay = (math.floor(day or 0) - hostWeekday()) % Clock.DAYS
  save.rtc.dayOfWeek = math.floor(day or 0) % Clock.DAYS
  return true
end

function Clock.minutes(save)
  local r = rtc(save)
  return (hostMinutes() + (r and tonumber(r.startMinute) or 0))
    % Clock.MINUTES_PER_DAY
end

function Clock.hour(save)
  return math.floor(Clock.minutes(save) / 60)
end

function Clock.minute(save)
  return Clock.minutes(save) % 60
end

function Clock.weekday(save)
  local r = rtc(save)
  return (hostWeekday() + (r and tonumber(r.startDay) or 0)) % Clock.DAYS
end

function Clock.daytime(hour)
  hour = math.floor(hour or 12) % 24
  if hour < 4 then return "NIGHT" end
  if hour < 10 then return "MORNING" end
  if hour < 18 then return "DAY" end
  return "NIGHT"
end

function Clock.forSave(save)
  return Clock.daytime(Clock.hour(save))
end

-- The Kanto runtime owns an overworld, not the native Gen II world object.
function Clock.normalizePeriod(value)
  if type(value) ~= "string" then return nil end
  return ({ MORNING="MORNING", MORN="MORNING", MORN_F="MORNING",
    DAY="DAY", DAY_F="DAY", NIGHT="NIGHT", NITE="NIGHT", NITE_F="NIGHT",
    EVENING="NIGHT" })[value:upper()]
end

function Clock.forGame(game)
  local world = game and (game.overworld or game.world)
  if world and type(world.timeOfDay) == "function" then
    local ok, value = pcall(world.timeOfDay, world)
    local period = ok and Clock.normalizePeriod(value)
    if period then return period end
  end
  return Clock.forSave(game and game.save)
end

return Clock
