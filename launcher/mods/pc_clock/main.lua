-- PC Clock: Gold, Silver and Crystal keep the device's time and weekday.
--
-- The port already reads the device clock, through an offset taken when the
-- player answers Oak's "What time is it?" and Mom's "What day is it?"
-- (src/core/gen2/Clock.lua).  This mod makes both answers the device's own and
-- keeps that offset at zero, so the game can never drift from the device, an
-- old save included.  Daylight saving needs nothing extra: the device's local
-- time already includes it.  Mom's daylight saving question still appears; in
-- this port its answer is stored but never moves the clock.
--
-- Nothing is written that outlives the mod: switch it off and a save reads the
-- offset it had before.

local SPOKEN_DAYS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }

local function now()
  local t = os.date("*t")
  -- os.date's wday is 1 for Sunday; the game's SUNDAY is 0
  return t.hour, t.min, (t.wday - 1) % 7
end

local function spokenTime(hour, minute)
  local suffix = hour < 12 and "AM" or "PM"
  local shown = hour % 12
  if shown == 0 then shown = 12 end
  return ("%d:%02d %s"):format(shown, minute, suffix)
end

-- Through the screen reader layer when it is there; silent otherwise.
local function say(text)
  local ok, Speech = pcall(require, "src.access.Speech")
  if ok and type(Speech) == "table" and Speech.say then Speech.say(text) end
end

return function(mod)
  local Clock = require("src.core.gen2.Clock")
  local InitClock = require("src.ui.gen2.InitClock")

  -- Every read of the clock goes through these two, so a zero offset here is
  -- the device's time everywhere the game looks.
  -- The offset is set to zero only for the read and put back after it, so the save
  -- keeps the player's own setting for when the mod is off.
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
  Clock.minutes = withoutOffset(Clock.minutes, "startMinute")
  Clock.weekday = withoutOffset(Clock.weekday, "startDay")

  -- Both questions use this screen.  autoConfirm is the screen's own way of
  -- walking itself to the end on the values it opens with, so it opens on the
  -- device's time and day and takes them.
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
        say("Day set from your device: " .. SPOKEN_DAYS[day + 1] .. ".")
      else
        say("Clock set from your device: " .. spokenTime(hour, minute) .. ".")
      end
      if onDone then return onDone(...) end
    end
    return newScreen(game, answered)
  end

  mod.log:info("Gold, Silver and Crystal follow the device clock")
end
