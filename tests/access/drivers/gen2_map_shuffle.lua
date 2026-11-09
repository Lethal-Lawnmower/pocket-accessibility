-- Gen 2 navigation under a map (door) randomizer, in Crystal on the real data.
-- The driver swaps two New Bark Town house doors by hand, the way the randomizer's
-- `maps` module writes them (launcher/mods/crystal_randomizer/MAPS.md): in place, the
-- town's two door warps exchange destMap and destWarp, and each house's explicit way
-- out returns to the door now used.  Then it checks that the object list names each
-- door by where it leads now, that auto-walk through a door arrives where the list
-- said, and that a journey from one house to the other plans and walks over the
-- shuffled doors.  The driver's teleports and its rewrite of the warps are the
-- harness; the list, plans and walks are the layer.  Vanilla values are put back.
--
--   POKEPORT_IDENTITY=pocket-access-maps-nav POKEPORT_ACCESS_SILENT=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/gen2_map_shuffle.lua lovec .
-- Read the RESULT, PASS and FAIL lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local failures = 0
  local function expect(ok, what)
    if ok then U.log("PASS", what) else failures = failures + 1 U.log("FAIL", what) end
  end

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") return end
  U.wait(30)
  local nav = L.nav()
  if not nav then U.log("FAIL", "no navigation coordinator on", L.where()) return end
  local maps = game.data.gen2Maps
  local town = maps.NEW_BARK_TOWN
  -- the two dead-end houses: warp 3 (3,11) and warp 4 (11,13)
  local neighbors, elms = town.warps[3], town.warps[4]
  if not (neighbors and elms and neighbors.destMap == "PLAYERS_NEIGHBORS_HOUSE"
          and elms.destMap == "ELMS_HOUSE") then
    U.log("FAIL", "New Bark Town's warps are not the vanilla ones this driver expects")
    return
  end
  local neighborsName = nav:regionalDestinationName("PLAYERS_NEIGHBORS_HOUSE")
  local elmsName = nav:regionalDestinationName("ELMS_HOUSE")
  U.log("RESULT", "names", neighborsName, "/", elmsName)

  local function doorAt(x, y)
    return L.find(function(i) return i.type == "warp" and i.x == x and i.y == y end)
  end

  -- what `maps` does for this pair; `swap` twice restores the vanilla values
  local function swap()
    neighbors.destMap, elms.destMap = elms.destMap, neighbors.destMap
    neighbors.destWarp, elms.destWarp = elms.destWarp, neighbors.destWarp
    for _, id in ipairs({ "PLAYERS_NEIGHBORS_HOUSE", "ELMS_HOUSE" }) do
      for _, inside in ipairs(maps[id].warps) do
        if inside.destMap == "NEW_BARK_TOWN" then inside.destWarp = inside.destWarp == 3 and 4 or 3 end
      end
    end
  end

  -- harness: stand in town below the player's house door, past the teacher's scene
  game.world.mapScenes = game.world.mapScenes or {}
  game.world.mapScenes.NEW_BARK_TOWN = 1
  L.teleport("NEW_BARK_TOWN", 13, 6, "down")
  U.log("RESULT", "start", L.where())
  local before = doorAt(3, 11)
  expect(before and before.label == neighborsName,
    "vanilla: the door at 3,11 is " .. tostring(before and before.description))

  -- while the player stands on the map: no reload, as the randomizer writes on load
  swap()
  L.logBrowse("all")
  local door = doorAt(3, 11)
  local other = doorAt(11, 13)
  expect(door and door.label == elmsName, "shuffled: the door at 3,11 is " .. tostring(door and door.description))
  expect(other and other.label == neighborsName,
    "shuffled: the door at 11,13 is " .. tostring(other and other.description))

  -- auto-walk through the shuffled door
  U.log("RESULT", "walk to the door at 3,11 =>", L.walkTo(door, { trace = true, answer = "a" }))
  L.settle(600, true)
  U.log("RESULT", "after the door =>", L.heard(), "now", L.where())
  expect(L.pos() == "ELMS_HOUSE", "auto-walk: through the door at 3,11 into " .. L.where())

  -- the way out, named and walked
  local exit = L.find(function(i) return i.type == "warp" end)
  expect(exit and exit.label == nav:regionalDestinationName("NEW_BARK_TOWN"),
    "inside: the way out is " .. tostring(exit and exit.description))

  -- a journey from this house to the other one.  Gen 2 offers journeys to the Area
  -- category (maps of one building or zone, by map id); no other map shares these
  -- houses' ids, so the harness adds the one Area entry the list would build for
  -- the other house.  The plan and the walk are the layer's.
  local target = maps.PLAYERS_NEIGHBORS_HOUSE
  local entryWarp = target.warps[1]
  local areaBrowse = nav.areaBrowse
  nav.areaBrowse = function()
    return { {
      id = "area:PLAYERS_NEIGHBORS_HOUSE", type = "area", category = "area",
      label = neighborsName, description = neighborsName, mapId = "PLAYERS_NEIGHBORS_HOUSE",
      x = entryWarp.x, y = entryWarp.y - 2, wholeMap = true,
    } }
  end
  local area = L.find(function(i) return i.type == "area" end, "area")
  nav.browseFilter, nav.browseSelectionId = "area", area and area.id
  nav.navigation = nil
  local leg, why = nav:regionalNextLeg({ targetMapId = "PLAYERS_NEIGHBORS_HOUSE",
    targetGoals = { { x = entryWarp.x, y = entryWarp.y - 2 } } })
  U.log("RESULT", "first leg", leg and leg.nextMapId or tostring(why))
  local seen = {}
  local text = L.walkTo(area, { filter = "area", trace = true, answer = "a", limit = 6000,
    onFrame = function()
      local id, x, y = L.pos()
      seen[#seen + 1] = id .. ":" .. x .. "," .. y
    end })
  nav.areaBrowse = areaBrowse
  L.settle(600, true)
  U.log("RESULT", "journey =>", text, "now", L.where())
  local trail = table.concat(seen, " ")
  expect(L.pos() == "PLAYERS_NEIGHBORS_HOUSE", "journey: reached the neighbours' house, now " .. L.where())
  expect(trail:find("NEW_BARK_TOWN:3,1[12]") ~= nil, "journey: came out of the door at 3,11, the one Elm's house now opens onto")
  expect(trail:find("NEW_BARK_TOWN:11,1[34]") ~= nil, "journey: went in by the door at 11,13, the one that leads there now")

  -- restored for a vanilla save
  swap()
  L.teleport("NEW_BARK_TOWN", 13, 6, "down")
  local restored = doorAt(3, 11)
  expect(restored and restored.label == neighborsName,
    "restored: the door at 3,11 is " .. tostring(restored and restored.description))
  U.log("RESULT", "failures", failures)
  U.log("DONE")
end
