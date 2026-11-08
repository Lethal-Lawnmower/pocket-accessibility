-- Gold, Silver and Crystal keep the device's time and weekday (decision 56).
--
-- Upstream already reads the device clock, through an offset taken when the
-- player answers Oak's "What time is it?" and Mom's "What day is it?"
-- (src/core/gen2/Clock.lua).  Here both answers are the device's own and the
-- offset is read as zero, so the game cannot drift from the device, an old save
-- included.  Daylight saving needs nothing extra: the device's local time
-- already includes it.  Mom's daylight saving question still appears; upstream
-- stores that answer and never moves the clock with it.
--
-- Nothing is replaced on disk and no upstream file is edited: the two Clock
-- reads and InitClock.new are wrapped at runtime (docs/access/architecture.md),
-- and the offset in the save is put back after every read, so POKEPORT_ACCESS=0
-- still plays the clock the save holds.

local Speech = require("src.access.Speech")

local PcClock = {}

local SPOKEN_DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local installed = false

local function now()
  local t = os.date("*t")
  -- os.date's wday is 1 for Sunday; the game's SUNDAY is 0
  return t.hour, t.min, (t.wday - 1) % 7
end

function PcClock.spokenTime(hour, minute)
  local shown = hour % 12
  if shown == 0 then shown = 12 end
  return ("%d:%02d %s"):format(shown, minute, hour < 12 and "AM" or "PM")
end

-- A Clock read with the save's offset at zero, which is put back afterwards.
local function withoutOffset(read, field)
  return function(save)
    local rtc = type(save) == "table" and type(save.rtc) == "table" and save.rtc or nil
    if not rtc then return read(save) end
    local kept = rtc[field]
    rtc[field] = 0
    local ok, value = pcall(read, save)
    rtc[field] = kept
    if not ok then error(value, 0) end
    return value
  end
end

function PcClock.install()
  if installed then return false end
  installed = true
  local Clock = require("src.core.gen2.Clock")
  local InitClock = require("src.ui.gen2.InitClock")

  -- Every read of the game clock goes through these two.
  Clock.minutes = withoutOffset(Clock.minutes, "startMinute")
  Clock.weekday = withoutOffset(Clock.weekday, "startDay")

  -- Oak's and Mom's questions are both this screen.  autoConfirm is its own way
  -- of walking to the end on the values it opens with: the device's.
  local newScreen = InitClock.new
  InitClock.new = function(game, opts)
    opts = opts or {}
    local hour, minute, day = now()
    local answered = {}
    for key, value in pairs(opts) do answered[key] = value end
    answered.hour, answered.minute, answered.day = hour, minute, day
    answered.autoConfirm = true
    local onDone = opts.onDone
    answered.onDone = function(...)
      if answered.mode == "day" then
        Speech.say("Day set from your device: " .. SPOKEN_DAYS[day + 1] .. ".")
      else
        Speech.say("Clock set from your device: " .. PcClock.spokenTime(hour, minute) .. ".")
      end
      if onDone then return onDone(...) end
    end
    return newScreen(game, answered)
  end
  return true
end

return PcClock
