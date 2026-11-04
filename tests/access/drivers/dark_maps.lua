-- Dark maps need Flash (decision 37), on the real dark maps of each
-- generation: the list, auto-walk, guided navigation and the camera before
-- Flash, then again once the harness has lit the map the way Flash does.
-- Silent and isolated, with POKEPORT_VERSION naming the game:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/dark_maps.lua
return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local isGen3 = version == "firered" or version == "leafgreen"
  local L = dofile(isGen3 and "tests/access/drivers/gen3_nav_lib.lua"
    or "tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local AutoWalk = require("src.access.nav.AutoWalk")
  local isGen1 = version == "red" or version == "blue" or version == "yellow"
  local started
  if isGen3 then started = L.boot()
  elseif isGen1 then started = U.newGame(game)
  else started = L.settle(2000, true) end
  if not started then U.log("FAIL", "never reached the free world") return end
  U.wait(30)

  local rooms = {
    firered = "FR_ROCK_TUNNEL_1F", leafgreen = "FR_ROCK_TUNNEL_1F",
    red = "ROCK_TUNNEL_1F", blue = "ROCK_TUNNEL_1F", yellow = "ROCK_TUNNEL_1F",
    crystal = "DARK_CAVE_VIOLET_ENTRANCE", gold = "DARK_CAVE_VIOLET_ENTRANCE",
    silver = "DARK_CAVE_VIOLET_ENTRANCE",
  }
  local mapId = rooms[version]
  -- Gen 2 keeps its maps apart from the Gen 1 table
  local maps = game.data.gen2Maps or game.data.maps
  local record = maps[mapId]
  local warp = (record.def or record).warps[1]
  if isGen1 then U.teleport(game, mapId, warp.x, warp.y, "down")
  else L.teleport(mapId, warp.x, warp.y) end
  U.wait(60)

  local function worldAndNav()
    local nav = L.nav()
    return nav:worldForCommand(), nav
  end

  local function report(stage)
    local world, nav = worldAndNav()
    U.log("RESULT", stage, "dark", tostring(nav:isDark(world)), "at",
      world.player.cellX .. "," .. world.player.cellY)
    local unfiltered = nav:captureWorld("all").browse or {}
    nav.browseFilter, nav.browseSelectionId, nav.browseIndex = "all", nil, 1
    local item, reason, snapshot = nav:selectedBrowseItem(0)
    local names = {}
    for _, entry in ipairs(item and snapshot.browse or {}) do names[#names + 1] = tostring(entry.description) end
    U.log("RESULT", stage, "listed", #names, "of", #unfiltered, reason or "", table.concat(names, " | "))
    return unfiltered
  end

  local function tryNavigation(stage, target)
    local _, nav = worldAndNav()
    nav.browseFilter, nav.browseSelectionId = "all", target.id
    L.heard()
    nav:describeRouteToSelected()
    U.wait(10)
    U.log("RESULT", stage, "guided =>", L.heard())
    if nav.activeNavigation then nav:stopNavigation(false) end
    nav:cancelPendingRoute(false)
    L.heard()
    AutoWalk.start(nav, game, L.adapter and L.adapter() or nil)
    local walking = AutoWalk.active()
    if walking then
      for _ = 1, 4000 do
        if not AutoWalk.active() then break end
        U.wait(1)
      end
      if AutoWalk.active() then AutoWalk.stop() end
    end
    U.wait(10)
    U.log("RESULT", stage, "auto-walk to", tostring(target.label), "walked", tostring(walking), "=>", L.heard())
  end

  local function tryCamera(stage)
    local _, nav = worldAndNav()
    nav:resetSonar()
    L.heard()
    for _, direction in ipairs({ "left", "left", "left", "left", "left", "left" }) do
      nav:moveSonar(direction, true)
    end
    U.wait(5)
    U.log("RESULT", stage, "camera x", tostring(nav.sonarX), "=>", L.heard())
    nav:resetSonar()
  end

  local all = report("before Flash")
  local far
  local world = worldAndNav()
  for _, item in ipairs(all) do
    if type(item.x) == "number" and math.abs(item.x - world.player.cellX) + math.abs(item.y - world.player.cellY) > 12 then
      far = item
      break
    end
  end
  far = far or all[#all]
  tryNavigation("before Flash", far)
  tryCamera("before Flash")

  -- The state Flash leaves, set directly (each game's own field, as its Flash
  -- code does); the field-move menu itself is not driven here.
  if isGen1 then
    game.save.flashLit = true
    game.overworld:setDark(false)
  elseif isGen3 then
    package.loaded["src.core.game3.field_view"].setFlashLevel(0)
  else
    game.world.flashUsed = true
  end
  U.wait(10)

  report("after Flash")
  tryCamera("after Flash")
  tryNavigation("after Flash", far)
  U.log("RESULT", "dark_maps done")
end
