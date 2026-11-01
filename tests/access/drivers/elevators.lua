-- Scripted ride in each Gen 1 elevator, as a navigation user would take it:
-- auto-walk to the elevator door, auto-walk to the floor panel, press A, pick
-- the second floor in the menu, then check what the car's exit is called and
-- auto-walk out.  Logs the speech at each step.  Run silently
-- (POKEPORT_ACCESS_SILENT=1) with a disposable Red identity.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  game.speedOverride = 4
  game.save.inventory.LIFT_KEY = 1

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local function heard() local s = table.concat(said, " | ") said = {} return s end
  local function nav() return package.loaded["src.access.nav"].coordinator() end
  local function mapId() return game.overworld.map.def and game.overworld.map.def.id end
  local function waitTransition()
    for _ = 1, 240 do if not game.overworld.transitioning then break end U.wait(1) end
  end

  -- Selects the first browse entry of `filter` whose label contains `text`.
  local function select(filter, text)
    local coordinator = nav()
    coordinator.browseFilter = filter
    local snap = coordinator:captureWorld(filter)
    local labels = {}
    for _, item in ipairs(snap and snap.browse or {}) do
      labels[#labels + 1] = tostring(item.label)
      if text and tostring(item.label):find(text, 1, true) then
        coordinator.browseSelectionId = item.id
        return item.label
      end
    end
    return nil, table.concat(labels, "; ")
  end

  local function walk()
    AutoWalk.start(nav(), game)
    for _ = 1, 3000 do
      if not AutoWalk.active() then break end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() return "timed out" end
    waitTransition()
    U.wait(30)
    return heard()
  end

  local rides = {
    { from = "CELADON_MART_1F", car = "CELADON_MART_ELEVATOR" },
    { from = "SILPH_CO_1F", car = "SILPH_CO_ELEVATOR" },
    { from = "ROCKET_HIDEOUT_B2F", car = "ROCKET_HIDEOUT_ELEVATOR" },
  }
  for _, ride in ipairs(rides) do
    if os.getenv("ELEV_ONLY") and not ride.car:find(os.getenv("ELEV_ONLY"), 1, true) then goto nextRide end
    waitTransition()
    local w = game.data.maps[ride.from].warps[1]
    U.teleport(game, ride.from, w.x, w.y, "down")
    waitTransition()
    U.wait(30)
    heard()
    local door, all = select("warps", "Elevator")
    U.log("DOOR", ride.from, door or ("no elevator warp; warps: " .. tostring(all)))
    if door then
      U.log("WALK", "to door =>", walk(), "now on", mapId())
      do
        local p = game.overworld.player
        U.log("AT", p.cellX .. "," .. p.cellY, tostring(p.facing), "inputLocked", tostring(p.inputLocked), "top is map", tostring(game.stack:top() == game.overworld))
      end
      local panel, signs = select("signposts", "")
      if not panel then panel = select("signposts", nil) end
      local _, signList = select("signposts", nil)
      U.log("SIGNS", mapId(), signList)
      local coordinator = nav()
      local snap = coordinator:captureWorld("signposts")
      local first = snap and snap.browse and snap.browse[1]
      if first then
        coordinator.browseFilter, coordinator.browseSelectionId = "signposts", first.id
        local p = game.overworld.player
        U.log("CAR", "entered at", p.cellX .. "," .. p.cellY)
        local walked = walk()
        U.log("WALK", "to panel =>", walked, "at", p.cellX .. "," .. p.cellY, "on", mapId())
        -- face the panel as the arrival line says, then press A
        local face = walked:match("Face (%a+) and interact")
        if face then U.tap(game, face) U.wait(12) end
        U.tap(game, "a") U.wait(40)
        for _ = 1, 6 do
          if game.stack:top() ~= game.overworld then break end
          U.wait(10)
        end
        U.log("MENU", heard())
        -- press A through any text until the floor menu, then pick the 2nd floor
        U.tap(game, "down") U.wait(20)
        U.log("MENU", "after down =>", heard())
        U.tap(game, "a") U.wait(60)
        for _ = 1, 40 do
          if game.stack:top() == game.overworld then break end
          U.tap(game, "a") U.wait(8)
        end
        U.log("RIDE", heard())
        local exit, warps = select("warps", nil)
        U.log("EXIT", "warps in car =>", tostring(warps))
        local wsnap = nav():captureWorld("warps")
        if wsnap and wsnap.browse and wsnap.browse[1] then
          nav().browseFilter, nav().browseSelectionId = "warps", wsnap.browse[1].id
          local out = walk()
          -- a car exit is left by stepping down off the exit mat
          if mapId():find("ELEVATOR") then U.tap(game, "down") U.wait(8) U.hold = nil for _ = 1, 30 do U.tap(game, "down") U.wait(2) end waitTransition() U.wait(30) end
          U.log("WALK", "out =>", out, "then down; now on", mapId(), "heard", heard())
        end
      end
    end
    ::nextRide::
  end
  Speech.say = say
  U.log("DONE")
end
