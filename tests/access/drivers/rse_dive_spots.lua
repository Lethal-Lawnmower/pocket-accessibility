-- Dive spots in the object list (Navigation:diveSpots), on Ruby, Sapphire and Emerald:
-- every map with deep water or a way up lists them, each says where it leads, and one
-- is used end to end: auto-walk to Route 126's spot over Sootopolis's seabed, the
-- game's own Dive question, then the "Way Up" entries below.
-- Silent and isolated; needs an imported Hoenn profile.
--   RSE_DIVE_ONLY=list  only the labels
return function(game)
  local L = dofile("tests/access/drivers/rse_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then U.log("RESULT", "rse_dive_spots", "NO CHECKS -- no game") return end
  L.giveParty()
  L.repel()
  local AutoWalk = require("src.access.nav.AutoWalk")
  local failures = 0
  local function check(ok, label, detail)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label, detail or "")
  end
  local function spots()
    local list = {}
    for _, item in ipairs(L.nav():captureWorld("all").browse or {}) do
      if item.semanticKind == "dive_spot" then list[#list + 1] = item end
    end
    return list
  end

  -- every map that has them, from a new game's flags, standing on its first spot
  local nav = L.nav()
  local total, maps = 0, 0
  for _, mapId in ipairs(L.mapIds()) do
    local world = nav:regionalStaticWorld(mapId, { x = 0, y = 0 })
    local ok, list = pcall(nav.diveSpots, nav, world)
    if ok and world and #list > 0 then
      maps = maps + 1
      for _, spot in ipairs(list) do
        total = total + 1
        U.log("SPOT", mapId, spot.label, "cells", #spot.cells, "rim", #spot.rim)
        if not (spot.label:match("^Dive Spot") or spot.label:match("^Way Up to ")) or spot.label:find("_", 1, true)
           or spot.label:find("nil", 1, true) or #spot.rim == 0 then
          check(false, "a dive spot's label and cells", mapId .. " " .. spot.label)
        end
      end
    end
  end
  check(maps >= 10 and total >= 30, "maps with dive spots", maps .. " maps, " .. total .. " spots")
  if os.getenv("RSE_DIVE_ONLY") == "list" then
    U.log("RESULT", "rse_dive_spots", failures == 0 and "PASS" or "FAIL")
    return
  end

  -- Route 126, surfing beside the deep water over Sootopolis's seabed (on it, where the
  -- route has no shallow water beside it)
  do
    local World = require("src.access.nav.gen3.World")
    local Player = require("src.core.game3.player")
    local def = game.data.maps[L.id("ROUTE126")]
    local view = World.plannedView(game, def)
    local world = nav:regionalStaticWorld(L.id("ROUTE126"), { x = 0, y = 0 })
    local deep, big = {}, nil
    for _, spot in ipairs(nav:diveSpots(world)) do
      for _, cell in ipairs(spot.cells) do deep[cell.y * view.widthCells + cell.x] = true end
      if spot.label:find("Sootopolis", 1, true) and (not big or #spot.cells > #big.cells) then big = spot end
    end
    local sx, sy
    for _, cell in ipairs(big and big.rim or {}) do
      for _, d in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
        local x, y = cell.x + d[1], cell.y + d[2]
        if not sx and view:inBounds(x, y) and view:isWater(x, y) and not deep[y * view.widthCells + x] then sx, sy = x, y end
      end
    end
    if not sx and big then sx, sy = big.rim[1].x, big.rim[1].y end
    U.log("NOTE", "start", tostring(sx) .. "," .. tostring(sy))
    L.teleport(L.id("ROUTE126"), sx or 32, sy or 9, "down")
    L.settle(120, true)
    Player.surfing = true
    U.wait(10)
  end
  local here = spots()
  -- the list, opened first, leaves the cell what it is (it was cached as "not water":
  -- WorldSnapshot.mapProxy)
  do
    local w = L.nav():worldForCommand()
    check(w.map:isWater(w.player.cellX, w.player.cellY) == true, "the player's cell is still water after the list was opened")
  end
  local toSootopolis
  for _, item in ipairs(here) do
    U.log("ITEM", tostring(item.description))
    if tostring(item.label):find("Sootopolis City", 1, true) and not toSootopolis then toSootopolis = item end
  end
  check(#here >= 4, "Route 126 lists its dive spots", tostring(#here))
  check(toSootopolis ~= nil, "one of them leads to Sootopolis City")
  if toSootopolis then
    nav = L.nav()
    nav.browseFilter, nav.browseSelectionId = "all", toSootopolis.id
    L.heard()
    nav:describeRouteToSelected()
    U.wait(30)
    local guided = L.heard()
    check(guided ~= "" and not guided:find("Cannot", 1, true), "guided navigation speaks a way to it", guided)
    if nav.activeNavigation then nav:stopNavigation(false) end
    nav:cancelPendingRoute(false)
    L.heard()
    nav.browseFilter, nav.browseSelectionId = "all", toSootopolis.id
    AutoWalk.start(nav, game, L.adapter and L.adapter() or nil)
    for _ = 1, 6000 do
      if not AutoWalk.active() then break end
      U.wait(1)
    end
    if AutoWalk.active() then AutoWalk.stop() end
    U.wait(10)
    local said = L.heard()
    check(said:find("Press A and answer yes to dive", 1, true) ~= nil, "auto-walk arrives and says how to dive", said:sub(-160))
    -- the game's own question, as a player answers it
    L.tap("a", 20)
    L.settle(1500, "a")
    check(L.pos() == L.id("UNDERWATER_ROUTE126"), "the A press dived there", L.where())
    local below = spots()
    for _, item in ipairs(below) do U.log("ITEM", tostring(item.description)) end
    local up
    for _, item in ipairs(below) do
      if tostring(item.label):match("^Way Up to Route 126") then up = item end
    end
    check(up ~= nil, "below, a Way Up to Route 126 is listed", tostring(#below))
    if up then
      nav = L.nav()
      nav.browseFilter, nav.browseSelectionId = "all", up.id
      L.heard()
      AutoWalk.start(nav, game, L.adapter and L.adapter() or nil)
      for _ = 1, 6000 do
        if not AutoWalk.active() then break end
        U.wait(1)
      end
      if AutoWalk.active() then AutoWalk.stop() end
      U.wait(10)
      said = L.heard()
      check(said:find("Press B and answer yes to surface", 1, true) ~= nil, "auto-walk says how to surface", said:sub(-160))
      L.tap("b", 20)
      L.settle(1500, "a")
      check(L.pos() == L.id("ROUTE126"), "the B press surfaced", L.where())
    end
  end
  U.log("RESULT", "rse_dive_spots", failures == 0 and "PASS" or "FAIL", "failures=" .. failures)
end
