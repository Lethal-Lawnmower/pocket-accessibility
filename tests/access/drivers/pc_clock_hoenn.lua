-- The PC Clock mod (launcher/mods/pc_clock) on Ruby, Sapphire or Emerald, on a
-- disposable profile where the package has copied the mod in (it starts on).
-- Starts a new game directly, opens the wall clock the way StartWallClock does,
-- then compares the game's time with the device's, gives the save a wrong
-- clock offset and an imported cartridge's skew, and reads again.
-- Silent and isolated; read the RESULT, PASS and FAIL lines.
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/pc_clock_hoenn.lua
--   POKEPORT_VERSION=emerald POKEPORT_GAME=emerald POKEPORT_IDENTITY=<disposable>
return function(game)
  local L = dofile("tests/access/drivers/rse_menus_lib.lua")(game)
  local U = L.U
  local Rtc = require("src.core.game3.rtc")

  local spoken = {}
  local Speech = require("src.access.Speech")
  local say = Speech.say
  Speech.say = function(text, opts)
    spoken[#spoken + 1] = tostring(text)
    return say(text, opts)
  end

  L.waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  L.wait(60)
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 }) end)
  if not ok then U.log("FAIL", "new game: " .. tostring(err)) return end
  L.wait(120)
  L.talk(40)
  L.wait(60)
  local session = L.session()

  local function device()
    local t = os.date("*t")
    return t.hour * 60 + t.min
  end
  local function close(a, b)
    return math.abs(a - b) <= 1 or math.abs(a - b) >= 24 * 60 - 1
  end
  local function check(label, wantDays)
    local lt = Rtc.calcLocalTime(session)
    local got, want = lt.hours * 60 + lt.minutes, device()
    U.log(close(got, want) and "PASS" or "FAIL", label .. " time", lt.hours .. ":" .. lt.minutes, "device", want)
    if wantDays then
      U.log(lt.days == wantDays and "PASS" or "FAIL", label .. " day count", lt.days, "expected", wantDays)
    end
    return lt
  end

  -- The wall clock, as StartWallClock opens it at the start of the game.
  local WallClock = require("src.ui.game3.rse.wall_clock")
  local result
  WallClock.open({ mode = "set", session = session, onDone = function(r)
    result = r
    require("src.core.game3.time_events").init(session)
  end })
  local frames = 0
  while not result and frames < 600 do L.wait(1); frames = frames + 1 end
  local right = result and result.confirmed and close(result.hours * 60 + result.minutes, device())
  U.log(right and "PASS" or "FAIL", "wall clock answered itself",
    tostring(result and result.hours) .. ":" .. tostring(result and result.minutes), "after", frames, "frames")
  local heard = table.concat(spoken, " | ")
  U.log(heard:find("Clock set from your device", 1, true) and "PASS" or "FAIL", "said", heard:sub(1, 300))

  local first = check("after the wall clock", 0)

  -- A clock set 6 hours 30 minutes wrong, and a cartridge whose clock was 3 days
  -- and 5000 seconds off the device's: the time stays the device's, the day count
  -- moves by the whole days only, and the save keeps both as they were.
  local offset = session.localTimeOffset
  session.localTimeOffset = Rtc.newTime(offset.days, 6, 30, 0)
  session.rtcSkew = 3 * 86400 + 5000
  check("wrong offset and skew", first.days + 3)
  local kept = session.localTimeOffset.hours == 6 and session.localTimeOffset.minutes == 30
    and session.rtcSkew == 3 * 86400 + 5000
  U.log(kept and "PASS" or "FAIL", "the save keeps its own offset and skew",
    session.localTimeOffset.hours, session.localTimeOffset.minutes, session.rtcSkew)
  session.rtcSkew = -(2 * 86400 + 4000)
  check("a skew behind the device", first.days - 2)

  -- What the player's own wall clock in the house shows
  session.localTimeOffset, session.rtcSkew = offset, 0
  local viewed
  local clock = WallClock.open({ mode = "view", session = session, onDone = function() viewed = true end })
  L.wait(60)
  U.log(close(clock.t.hours * 60 + clock.t.minutes, device()) and "PASS" or "FAIL", "the wall clock shows",
    clock.t.hours .. ":" .. clock.t.minutes)
  L.closeAll()
  U.log("DONE", tostring(viewed))
end
