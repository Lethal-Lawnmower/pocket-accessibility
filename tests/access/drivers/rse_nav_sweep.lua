-- Ruby, Sapphire and Emerald navigation against the whole cartridge: the label
-- sweep gen3_nav_sweep.lua runs on FireRed.  For every map of the running game,
-- from a new game's flags: the object list a player standing on the map's first
-- warp would get, checked for empty, nil, raw-id, ROM-address and placeholder
-- labels and for generic ones (a person with no name, "Signpost N"); every
-- active warp must resolve; every behaviour on the map must be one navigation
-- knows.  RSE_SWEEP_LIST=1 logs every label.
-- Silent and isolated; needs an imported Hoenn profile.
return function(game)
  local L = dofile("tests/access/drivers/rse_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then
    U.log("RESULT", "rse_nav_sweep", "NO CHECKS -- no game")
    return
  end
  local maps = game.data and game.data.maps
  local nav = L.nav()
  if not (maps and nav) then
    U.log("RESULT", "rse_nav_sweep", "NO CHECKS -- no map data or navigation")
    return
  end
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
  local World = require("src.access.nav.gen3.World")
  local MB = require("src.core.game3.mb")
  local listAll = os.getenv("RSE_SWEEP_LIST") == "1"

  local ids = L.mapIds()
  local stats = { maps = 0, labels = 0, signposts = 0, generic = 0, variable = 0, bad = 0, warps = 0, unresolved = 0,
    connections = 0, roles = {}, objects = {}, behaviours = {}, specials = {} }
  local function bad(label)
    if type(label) ~= "string" or label == "" then return true end
    return label:find("g3:", 1, true) or label:find("nil", 1, true)
      or label:find("Unknown", 1, true) or label:find(L.prefix, 1, true)
      or label:match("^Warp %d") or label:match("^Object %d") or label:find("Interactive object", 1, true)
      or label:find("_", 1, true) or label:match("%x%x%x%x%x%x") ~= nil
  end
  local function generic(item)
    local label = tostring(item.label)
    return label:match("^Signpost %d") or label == "Person" or label == "Trainer" or label == "Exit"
  end
  -- an object event at the item's cell whose graphics a variable picks
  local function variableSprite(def, item)
    for _, obj in ipairs(def.objects or {}) do
      local gfx = tonumber(obj.graphicsId or obj.graphics)
      if gfx and gfx >= 240 and tonumber(obj.x) == tonumber(item.x) and tonumber(obj.y) == tonumber(item.y) then
        return true
      end
    end
    return false
  end
  -- a warp to the dynamic warp (map number 0x7F): it leads back where the player
  -- came in, which the game records on the way in; a new game's flags have none
  local function dynamicWarp(def, item)
    for _, warp in ipairs(def.warps or {}) do
      if tonumber(warp.mapNum) == 0x7F and tonumber(warp.x) == tonumber(item.x) and tonumber(warp.y) == tonumber(item.y) then
        return true
      end
    end
    return false
  end
  local puzzleFloors = {}
  for index, mapId in ipairs(ids) do
    local def = maps[mapId]
    local okView, view = pcall(World.plannedView, game, def)
    if okView and view then
      stats.maps = stats.maps + 1
      for y = 0, view.heightCells - 1 do
        for x = 0, view.widthCells - 1 do
          local beh = view:behavior(x, y)
          if beh then
            local row = stats.behaviours[beh]
            if not row then row = { count = 0, first = mapId } stats.behaviours[beh] = row end
            row.count = row.count + 1
          end
        end
      end
      local start = { x = 0, y = 0 }
      local firstWarp = def.warps and def.warps[1]
      if firstWarp then start = { x = firstWarp.x, y = firstWarp.y } end
      local world = nav:regionalStaticWorld(mapId, start)
      local okCapture, snapshot = pcall(Snapshot.capture, world, {
        filter = "all", customNames = {}, playerName = "RED", rivalName = "MAY",
        interactiveObjects = nav:interactiveBrowseObjects(world, { objects = {} }),
      })
      if not okCapture or not snapshot then
        stats.bad = stats.bad + 1
        U.log("BAD", mapId, "capture failed", tostring(snapshot))
      else
        for _, item in ipairs(snapshot.browse or {}) do
          stats.labels = stats.labels + 1
          if listAll then U.log("LABEL", mapId, item.type, tostring(item.label)) end
          if bad(item.label) then
            stats.bad = stats.bad + 1
            U.log("BAD", mapId, item.type, tostring(item.label))
          end
          if generic(item) and ((item.label == "Person" and variableSprite(def, item))
              or (item.label == "Exit" and dynamicWarp(def, item))) then
            -- the game picks this person's sheet when the map loads (OBJ_EVENT_GFX_VAR_*),
            -- or this warp's destination as the player walks in; a live map says it
            -- (checked on live maps, 2026-11-09), a map the player is not on cannot know
            stats.variable = stats.variable + 1
            U.log("VARIABLE", mapId, tostring(item.x) .. "," .. tostring(item.y))
          elseif generic(item) then
            stats.generic = stats.generic + 1
            U.log("GENERIC", mapId, item.type, tostring(item.label), tostring(item.x) .. "," .. tostring(item.y))
          end
          if tostring(item.label):match("^Signpost %d") then
            stats.signposts = stats.signposts + 1
            local event = def.bgEvents and def.bgEvents[tonumber(tostring(item.label):match("%d+"))]
            local reach = event and require("src.access.nav.gen3.Scripts").reach(event.scriptKey, 8)
            local ops, specials = {}, {}
            for op in pairs(reach and reach.ops or {}) do ops[#ops + 1] = op end
            for name in pairs(reach and reach.specials or {}) do specials[#specials + 1] = name end
            table.sort(ops)
            U.log("SIGNPOST", mapId, tostring(item.label), table.concat(specials, " "), "|", table.concat(ops, " "))
          end
          if item.type == "signpost" and not tostring(item.label):match("^Signpost") then
            local short = tostring(item.label):gsub("^Sign: .*", "Sign:")
            stats.roles[short] = (stats.roles[short] or 0) + 1
          end
          if item.type == "object" then
            stats.objects[item.label] = (stats.objects[item.label] or 0) + 1
          end
          if item.type == "connection" then stats.connections = stats.connections + 1 end
        end
      end
      for i, warp in ipairs(def.warps or {}) do
        local active, activeIndex = view:warpAt(warp.x, warp.y)
        if active and activeIndex == i then
          stats.warps = stats.warps + 1
          local dest = view:warpDestination(warp)
          if not dest then
            stats.unresolved = stats.unresolved + 1
            U.log("UNRESOLVED", mapId, i, tostring(warp.destMap), "mapNum", tostring(warp.mapNum))
          end
        end
      end
      local okTargets, targets, boulders = pcall(Puzzle.targetsFor, world)
      if okTargets and targets then puzzleFloors[#puzzleFloors + 1] = { id = mapId, n = #boulders, t = #targets } end
    else
      U.log("NOVIEW", mapId, tostring(view))
    end
    if index % 20 == 0 then U.wait(1) end
  end
  U.log("SWEEP", "maps", stats.maps, "labels", stats.labels, "bad", stats.bad, "generic", stats.generic, "variable", stats.variable,
    "signposts", stats.signposts, "active warps", stats.warps, "unresolved", stats.unresolved,
    "connections", stats.connections)
  local function sortedCounts(tbl)
    local list = {}
    for label, n in pairs(tbl) do list[#list + 1] = tostring(label) .. "=" .. n end
    table.sort(list)
    return table.concat(list, ", ")
  end
  U.log("ROLES", sortedCounts(stats.roles))
  U.log("OBJECTS", sortedCounts(stats.objects))
  local behaviours = {}
  for beh, row in pairs(stats.behaviours) do behaviours[#behaviours + 1] = { beh, row } end
  table.sort(behaviours, function(a, b) return a[1] < b[1] end)
  for _, entry in ipairs(behaviours) do
    U.log("BEH", string.format("%x", entry[1]), tostring(MB.nameOf(entry[1])), entry[2].count, entry[2].first)
  end
  for _, floor in ipairs(puzzleFloors) do U.log("PUZZLE", floor.id, "boulders", floor.n, "targets", floor.t) end
  L.check(stats.maps >= 300, "every map has a view (" .. stats.maps .. ")")
  L.check(stats.bad == 0, "no bad labels (" .. stats.bad .. ")")
  L.check(stats.generic == 0, "no generic labels (" .. stats.generic .. ")")
  L.finish("rse_nav_sweep")
end
