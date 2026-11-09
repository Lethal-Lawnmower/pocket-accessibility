-- The PC Clock mod (launcher/mods/pc_clock), on a disposable Gold, Silver or
-- Crystal profile with the mod in its mods folder.  Without the mod the same run
-- shows upstream's own behaviour: the screens wait and the clock opens on 10 AM.
-- Starts a new game
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

  -- Mom's Pokegear scene on 1F: the day wheel and the daylight saving question.
  -- Arrive down the stairs the way the player does, then press A through her
  -- lines; with the mod, both DST yes/no prompts answer themselves.
  if game.world and game.world.warpToMapId then
    game.save.rtc = game.save.rtc or {}
    game.save.rtc.dst = nil
    local said = {}
    pcall(game.world.warpToMapId, game.world, "PLAYERS_HOUSE_1F", 9, 0, "down")
    U.wait(30)
    local def = game.data.gen2Maps and game.data.gen2Maps.PLAYERS_HOUSE_1F
    for _, event in ipairs(def and (def.coordEvents or def.coords) or {}) do
      U.log("RESULT", "coord event", event.x, event.y, tostring(event.scene), tostring(event.script))
    end
    -- the scene starts as the player steps off the stairs
    for _ = 1, 6 do L.tap("down", 16) end
    for _ = 1, 300 do
      L.tap("a", 6)
      for _, line in ipairs(L.said) do said[#said + 1] = line end
      L.said = {}
      if L.free() then break end
    end
    local text = table.concat(said, " | ")
    local wantDst = os.date("*t").isdst == true
    U.log("RESULT", "Mom's scene said", text:sub(1, 600))
    U.log(text:find("Daylight saving time", 1, true) and "PASS" or "FAIL", "the DST question answered itself")
    U.log((game.save.rtc.dst == wantDst) and "PASS" or "FAIL", "saved DST matches the device",
      tostring(game.save.rtc.dst), "device", tostring(wantDst))
  else
    U.log("FAIL", "no world to reach Mom")
  end
  game.save.rtc = game.save.rtc or {}
  game.save.rtc.startMinute = 6 * 60
  game.save.rtc.startDay = 3
  check("after a wrong offset")
  local kept = game.save.rtc.startMinute == 6 * 60 and game.save.rtc.startDay == 3
  U.log(kept and "PASS" or "FAIL", "the save keeps its own offset", game.save.rtc.startMinute, game.save.rtc.startDay)
  U.log("DONE")
end
