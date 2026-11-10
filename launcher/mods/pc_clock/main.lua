-- PC Clock: the game's clock is the device's clock.
--
-- Gold, Silver and Crystal keep the device's time and weekday.
-- The port already reads the device clock, through an offset taken when the
-- player answers Oak's "What time is it?" and Mom's "What day is it?"
-- (src/core/gen2/Clock.lua).  This mod makes both answers the device's own and
-- keeps that offset at zero, so the game can never drift from the device, an
-- old save included.  Daylight saving needs nothing extra: the device's local
-- time already includes it.  Mom's daylight saving question is answered from the
-- device too, and so is her "is that OK?" after it; in this port that answer is
-- stored (rtc.dst) but never moves the clock.
--
-- Ruby, Sapphire and Emerald (since 1.1.0): see hoenn() below.
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

local function johto(mod)
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

  -- Mom's daylight saving question (maps/PlayersHouse1F.asm): a `yesorno` whose
  -- script goes on to `special InitialSetDSTFlag`, then a second `yesorno` after
  -- that special (or InitialClearDSTFlag) that confirms it.  Each is replaced by
  -- `setval` with the device's answer, so the script takes the same branch a
  -- player answering truthfully would, and nothing waits for a button.
  -- A special's operand is the cart's number; the VM names it (Vm:specialName).
  local function specialName(vm, row)
    if type(row) ~= "table" or row.op ~= "special" then return nil end
    if type(vm.specialName) == "function" then
      local ok, name = pcall(vm.specialName, vm, row.id)
      if ok and name then return tostring(name) end
    end
    return tostring(row.id)
  end
  local function dstQuestion(vm, list, index)
    for i = index + 1, math.min(#list, index + 3) do
      if specialName(vm, list[i]) == "InitialSetDSTFlag" then return true end
    end
    return false
  end
  local function dstConfirm(vm, list, index)
    local name = specialName(vm, list[index - 1])
    return name == "InitialSetDSTFlag" or name == "InitialClearDSTFlag"
  end
  mod.hooks:wrap("script.command", function(nextFn, sctx, name, args, cmd)
    local vm = type(sctx) == "table" and sctx.vm or nil
    local list, index = vm and vm.cmdList, vm and vm.cmdIndex
    if name ~= "yesorno" or type(list) ~= "table" or type(index) ~= "number" then
      return nextFn(sctx, name, args, cmd)
    end
    if dstQuestion(vm, list, index) then
      local dst = os.date("*t").isdst == true
      say(dst and "Daylight saving time: yes, from your device." or "Daylight saving time: no, from your device.")
      return nextFn(sctx, "setval", {}, { op = "setval", value = dst and 1 or 0 })
    elseif dstConfirm(vm, list, index) then
      return nextFn(sctx, "setval", {}, { op = "setval", value = 1 })
    end
    return nextFn(sctx, name, args, cmd)
  end)

  mod.log:info("Gold, Silver and Crystal follow the device clock")
end

-- Ruby, Sapphire and Emerald.  The game's time is the cartridge clock minus an
-- offset (src/core/game3/rtc.lua, after pokeemerald's rtc.c): the player's wall
-- clock answer sets the offset's hours and minutes, and its days make the game's
-- day count start at 0 on that first day (berries, the lottery, daily events).
-- Here the device stands in for the cartridge clock, plus `rtcSkew`, which an
-- imported save gets when its cartridge's clock was far from the device's
-- (Rtc.anchorToLastUpdate).
--
-- So every read of the game's time (Rtc.calcLocalTime) is made with the
-- offset's hours, minutes and seconds at zero and the skew rounded to whole
-- days: the time of day is the device's, daylight saving included, and the day
-- count keeps counting from where the save had it.  Both are put back after the
-- read, so the save keeps the player's own setting for when the mod is off.
-- On a save whose clock was set wrong, the first read can move the day count
-- one day on (a day's events happen once) or the time of day back some hours
-- (berries wait until the device catches up); no day is lost or repeated.
--
-- The wall clock the player sets at the start opens on the device's time and
-- confirms itself.  The title screen's clock reset (Up, Select and B) is left
-- alone: with the mod on, what it sets has no effect on the time of day.
local function hoenn(mod)
  local Rtc = require("src.core.game3.rtc")
  local WallClock = require("src.ui.game3.rse.wall_clock")
  local DAY = 86400

  local calcLocalTime = Rtc.calcLocalTime
  Rtc.calcLocalTime = function(session, ...)
    if type(session) ~= "table" then return calcLocalTime(session, ...) end
    local offset, skew = session.localTimeOffset, session.rtcSkew
    local days = type(offset) == "table" and tonumber(offset.days) or 0
    local wholeDays = math.floor((tonumber(skew) or 0) / DAY + 0.5) * DAY
    session.localTimeOffset = Rtc.newTime(days, 0, 0, 0)
    session.rtcSkew = wholeDays
    local ok, value = pcall(calcLocalTime, session, ...)
    session.localTimeOffset, session.rtcSkew = offset, skew
    if not ok then error(value, 0) end
    return value
  end

  -- Setting the clock: open on the device's time and go straight to the
  -- screen's own "confirmed" step, which stores it (Rtc.initLocalTimeOffset)
  -- and closes the screen the way a YES would.
  local newClock = WallClock.new
  WallClock.new = function(opts)
    local clock = newClock(opts)
    if clock.mode == WallClock.MODE.SET then
      local now = Rtc.hostInfo(nil)
      local t = clock.t
      t.hours, t.minutes = now.hour, now.minute
      t.minuteAngle = t.minutes * 6
      t.hourAngle = (t.hours % 12) * 30 + math.floor(t.minutes / 10) * 5
      t.period = t.hours < 12 and WallClock.PERIOD.AM or WallClock.PERIOD.PM
      clock.pcClockAnswer = true
    end
    return clock
  end
  local frame = WallClock.frame
  WallClock.frame = function(self, inp)
    if self.pcClockAnswer and self.state == "set_input" then
      self.pcClockAnswer = nil
      self.state = "confirmed"
      say("Clock set from your device: " .. spokenTime(self.t.hours, self.t.minutes) .. ".")
    end
    return frame(self, inp)
  end

  mod.log:info("Ruby, Sapphire and Emerald follow the device clock")
end

return function(mod)
  local GameVersion = require("src.core.GameVersion")
  if GameVersion.generation(GameVersion.get()) == 3 then
    hoenn(mod)
  else
    johto(mod)
  end
end
