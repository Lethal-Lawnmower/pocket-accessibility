-- The device clock for Gold, Silver and Crystal (src/access/PcClock.lua), on a
-- disposable profile.  With POKEPORT_ACCESS=0 the same run shows upstream's own
-- behaviour, where the screens wait and the clock opens on 10 AM.  Starts a new game
-- through the real intro, so Oak's clock screen runs, then compares the game's
-- clock with the device's, sets a wrong offset the way a wrong answer would, and
-- reads again.  Silent; read the RESULT, PASS and FAIL lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local Clock = require("src.core.gen2.Clock")
  local loaded = package.loaded["src.ui.gen2.InitClock"]
  U.log("RESULT", "screen patched", tostring(loaded and loaded.new ~= nil))
  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end

  local function device()
    local t = os.date("*t")
    return t.hour * 60 + t.min, (t.wday - 1) % 7
  end
  local function check(label)
    local want, day = device()
    local got = Clock.minutes(game.save)
    -- a minute may turn over between the two reads
    local close = math.abs(got - want) <= 1 or math.abs(got - want) >= 24 * 60 - 1
    U.log(close and "PASS" or "FAIL", label .. " time", got, "device", want)
    local gotDay = Clock.weekday(game.save)
    U.log(gotDay == day and "PASS" or "FAIL", label .. " weekday", gotDay, "device", day)
  end

  check("after the intro")

  -- Oak's and Mom's screens themselves: each must close on its own with the
  -- device's answer, the way the game opens them.
  local Screens = require("src.ui.Screens")
  for _, mode in ipairs({ "clock", "day" }) do
    local answer
    local pushed = Screens.push(game, "Gen2InitClock", {
      mode = mode, save = game.save,
      onDone = function(a, b) answer = { a, b }; game.stack:pop() end,
    })
    local frames = 0
    while pushed and not answer and frames < 600 do U.wait(1); frames = frames + 1 end
    local hour, day = os.date("*t").hour, (os.date("*t").wday - 1) % 7
    local right = answer and (mode == "day" and answer[1] == day or mode == "clock" and answer[1] == hour)
    U.log(right and "PASS" or "FAIL", mode .. " screen answered itself", tostring(answer and answer[1]),
      "after", frames, "frames")
  end
  check("after both screens")
  game.save.rtc = game.save.rtc or {}
  game.save.rtc.startMinute = 6 * 60
  game.save.rtc.startDay = 3
  check("after a wrong offset")
  local kept = game.save.rtc.startMinute == 6 * 60 and game.save.rtc.startDay == 3
  U.log(kept and "PASS" or "FAIL", "the save keeps its own offset", game.save.rtc.startMinute, game.save.rtc.startDay)
  U.log("DONE")
end
