-- What the data says, for reading the cartridge's maps while working on Hoenn navigation:
--   NAME      every map's id and spoken name
--   BALL      item balls whose item the script reader could not name, with their scripts
--   LOADSTATE load scripts navigation cannot read, by what stops them
--   RSE_DUMP_MAPS=A,B   for those maps (ids without the prefix): warps, objects, signs,
--                       coord events, map scripts with their commands
-- Harness reading only; a new game's flags.  Silent; prints log lines.
return function(game)
  local L = dofile("tests/access/drivers/rse_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  local maps = game.data.maps
  local Scripts = require("src.access.nav.gen3.Scripts")
  local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
  local Terrain = require("src.access.nav.gen3.TerrainSemantics")
  local World = require("src.access.nav.gen3.World")
  local Space = require("src.core.game3.scripting.space")

  local function show(value, depth)
    depth = depth or 0
    if type(value) ~= "table" then return tostring(value) end
    if depth > 2 then return "{...}" end
    local parts = {}
    for k, v in pairs(value) do parts[#parts + 1] = tostring(k) .. "=" .. show(v, depth + 1) end
    table.sort(parts)
    return "{" .. table.concat(parts, " ") .. "}"
  end
  local function script(key, limit)
    local list = Scripts.get(key)
    if not list then return "(no script " .. tostring(key) .. ")" end
    local parts = {}
    for i, cmd in ipairs(list) do
      if limit and i > limit then parts[#parts + 1] = "..." break end
      parts[#parts + 1] = show(cmd)
    end
    return table.concat(parts, " ; ")
  end

  local flag = function(id) return false end
  local Flags = require("src.core.game3.scripting.flags")
  flag = function(id) return Flags.getFlag(Space.store, nil, id) == true end
  local var = function(id) return tonumber(Flags.getVar(Space.store, nil, id)) or 0 end

  local stops = {}
  for _, id in ipairs(L.mapIds()) do
    local def = maps[id]
    U.log("NAME", id, Snapshot.locationName(def, id))
    for _, object in ipairs(def.objects or {}) do
      if tonumber(object.graphicsId) == Terrain.GFX.ITEM_BALL and not Scripts.itemBallItem(object.scriptKey) then
        U.log("BALL", id, object.x, object.y, script(object.scriptKey, 12))
      end
    end
    local state, why = Scripts.loadState(def, flag, var)
    if not state then stops[tostring(why)] = (stops[tostring(why)] or 0) + 1 end
  end
  local list = {}
  for why, n in pairs(stops) do list[#list + 1] = why .. "=" .. n end
  table.sort(list)
  U.log("LOADSTATE", table.concat(list, ", "))

  -- connections no cell can cross, with what stands at the middle of the edge
  local nav = L.nav()
  local Connections = require("src.core.game3.connections")
  local Collision = require("src.core.game3.collision")
  for _, id in ipairs(L.mapIds()) do
    local def = maps[id]
    local crossing = {}
    for _, t in ipairs(nav:regionalTransitions(id)) do
      if t.kind == "connection" then crossing[t.direction] = (crossing[t.direction] or 0) + 1 end
    end
    for _, conn in ipairs(Connections.each(def)) do
      if not crossing[conn.dir] and conn.dir then
        local view = World.plannedView(game, def)
        local dest = maps[conn.map] and World.plannedView(game, maps[conn.map])
        local step = ({ north = "up", south = "down", west = "left", east = "right" })[conn.dir]
        local sample = {}
        if view and dest and step then
          local vertical = step == "up" or step == "down"
          local count = vertical and view.widthCells or view.heightCells
          for c = 0, count - 1, math.max(1, math.floor(count / 6)) do
            local x = step == "left" and 0 or step == "right" and view.widthCells - 1 or c
            local y = step == "up" and 0 or step == "down" and view.heightCells - 1 or c
            local lx, ly = Collision.connectionLanding(maps[conn.map], conn, step, x, y)
            sample[#sample + 1] = string.format("(%d,%d c%x b%x e%s w%s -> %s,%s c%s b%s w%s)", x, y, view:coll(x, y) or 0, view:behavior(x, y) or 0,
              tostring(view:elevation(x, y)), tostring(view:isWater(x, y)), tostring(lx), tostring(ly),
              lx and string.format("%x", dest:coll(lx, ly) or 0) or "-", lx and string.format("%x", dest:behavior(lx, ly) or 0) or "-", lx and tostring(dest:isWater(lx, ly)) or "-")
          end
        end
        U.log("NOCROSS", id, conn.dir, conn.map, "offset", conn.offset, table.concat(sample, " "))
      end
    end
  end

  -- RSE_DUMP_CELLS=MAP:x0:y0:x1:y1;...  behaviour, collision, elevation, per cell
  for spec in tostring(os.getenv("RSE_DUMP_CELLS") or ""):gmatch("[^;]+") do
    local name, x0, y0, x1, y1 = spec:match("([^:]+):(%d+):(%d+):(%d+):(%d+)")
    local def = maps[L.prefix .. tostring(name)]
    local view = def and World.plannedView(game, def)
    for y = tonumber(y0 or 0), tonumber(y1 or -1) do
      local row = {}
      for x = tonumber(x0), tonumber(x1) do
        row[#row + 1] = string.format("%d:b%x/c%x/e%s", x, view:behavior(x, y) or 0, view:coll(x, y) or 0, tostring(view:elevation(x, y)))
      end
      U.log("CELLS", name, y, table.concat(row, " "))
    end
  end

  -- Dive links, and how many cells each offers
  for _, id in ipairs(L.mapIds()) do
    local def = maps[id]
    if def.dive or def.emerge then
      local world = nav:regionalStaticWorld(id, { x = 0, y = 0 })
      local n = world and #nav:diveTransitions(world, 3) or -1
      local keys = {}
      for key in pairs(def.mapScripts or {}) do keys[#keys + 1] = tostring(key) end
      table.sort(keys)
      U.log("DIVELINK", id, "dive", show(def.dive), "emerge", show(def.emerge), "cells", n, "scripts", table.concat(keys, " "))
    end
  end

  local wanted = os.getenv("RSE_DUMP_MAPS")
  for name in tostring(wanted or ""):gmatch("[^,]+") do
    local id = L.prefix .. name
    local def = maps[id]
    if not def then
      U.log("DUMP", id, "no such map")
    else
      U.log("DUMP", id, "type", tostring(def.mapType), "cave", tostring(def.cave), "size", def.midLayout and def.midLayout.width, def.midLayout and def.midLayout.height,
        "dive", show(def.dive), "emerge", show(def.emerge), "keys", (function()
          local keys = {} for k in pairs(def) do keys[#keys + 1] = tostring(k) end table.sort(keys) return table.concat(keys, " ")
        end)())
      for i, warp in ipairs(def.warps or {}) do U.log("WARP", i, show(warp)) end
      for i, object in ipairs(def.objects or {}) do
        U.log("OBJECT", i, object.x, object.y, "gfx", object.graphicsId, "move", object.movementType, "flag", tostring(object.flag), "script", script(object.scriptKey, 8))
      end
      for i, event in ipairs(def.bgEvents or {}) do
        U.log("BG", i, event.type, event.x, event.y, "kind", tostring(event.kind), "script", event.scriptKey and script(event.scriptKey, 10) or "")
      end
      for i, event in ipairs(def.coordEvents or {}) do
        U.log("COORD", i, show(event), "script", event.scriptKey and script(event.scriptKey, 14) or "")
      end
      local ms = def.mapScripts or {}
      for kind, value in pairs(ms) do
        if type(value) == "string" then
          U.log("MS", kind, script(value))
        elseif type(value) == "table" then
          for _, row in ipairs(value) do U.log("MS", kind, show(row), script(row.script, 20)) end
        end
      end
      if os.getenv("RSE_DUMP_GRID") == "1" then
        local view = World.plannedView(game, def)
        for y = 0, view.heightCells - 1 do
          local row = {}
          for x = 0, view.widthCells - 1 do row[#row + 1] = string.format("%x:%x", view:behavior(x, y) or 0, view:coll(x, y) or 0) end
          U.log("GRID", y, table.concat(row, " "))
        end
      end
    end
  end
  U.log("DONE")
end
