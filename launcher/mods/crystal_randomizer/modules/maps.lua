-- Crystal randomizer: where doors lead (MAPS.md is the design this follows).
--
-- This module owns the `maps` question and applies a placement; it does not
-- decide one.  Three libraries other modules offer in `ctx.lib` do that:
--   mapGraph.build(data)        the doors, entrances and complexes of the vanilla maps
--   mapRules.model(data, graph) what is fixed and what keeps the game winnable
--   mapPlacer.place(graph, rules, level, rng, hmPlacement)
--                               placement[doorId] = doorId' and
--                               placement.entrances[entranceId] = entranceId',
--                               and a report
--
-- Doors and entrances.  A door is one outdoor warp `{ x, y, destMap,
-- destWarp }` in data.gen2Maps[map].warps (warp numbers are 1-based list
-- indexes, as World:takeWarp reads them).  Many doorways are two warp tiles
-- wide, so the graph groups the tiles of one doorway into an ENTRANCE
-- (graph.entrances[id] = { id, map, complex, doors, inside }, door.entrance;
-- the id and the first of `doors` is the doorway's first tile).  The placer
-- moves whole entrances; this module applies them per entrance:
--   * every tile of entrance A gets the vanilla destMap and destWarp of the
--     target entrance T's first tile, so both tiles of a wide doorway arrive
--     at the same place;
--   * every explicit exit in T.inside (a complex warp that led back to any
--     tile of T) is pointed at A's first tile;
--   * exits with destWarp 0xff are left alone: World:recordWarpBackup notes
--     the warp stepped on whenever the warp arrived on says 0xff, and
--     World:resolveWarp sends the 0xff warp back there, so they already
--     return to the tile used.
-- Which entrance A goes to comes from placement.entrances when the placer
-- gives it, else from placement[tile] of A's tiles; every tile of A must
-- agree, or the placement is refused.  A graph without `entrances` is read
-- as one entrance per door.
--
-- An exit that would have to lead to two different entrances (two entrances
-- sent to one target, or one sent onto an entrance that stays) refuses the
-- whole placement, because one of those doorways would let its player out
-- somewhere else.  Entrances that stay claim their own exits for this check.
--
-- Every switch of save puts every changed field back to its vanilla value
-- first (in reverse order of change), whatever the new save asks for.  The
-- graph is built once, from the data as it is right after that restore, so it
-- always describes the vanilla maps.  Warp tables are changed in place and
-- never replaced: the world's Map objects index the same tables by cell.
--
-- If a library is missing, fails, or the placer returns no placement, nothing
-- is changed for that save and the log says why; the save plays with vanilla
-- doors.  The plan is fully worked out and checked before the first field is
-- written, so a bad placement never leaves half the doors moved.

local M = {
  id = "maps",
  questions = {
    { key = "maps", kind = "choice", text = "Shuffle where\ndoors lead?",
      options = {
        { label = "OFF", value = "off" },
        { label = "HOUSES", value = "houses" },
        { label = "CAVES", value = "caves" },
        { label = "EVERYTHING", value = "full" },
      },
      recommended = "off", everything = "off" },
  },
}

M.RETURN_WARP = 0xff
M.LEVELS = { houses = true, caves = true, full = true }

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- The warp table numbered `index` on map `mapId`, or nil.
local function warpOf(data, mapId, index)
  local map = type(data.gen2Maps) == "table" and data.gen2Maps[mapId] or nil
  local warps = type(map) == "table" and map.warps or nil
  local warp = type(warps) == "table" and warps[index] or nil
  return type(warp) == "table" and warp or nil
end
M.warpOf = warpOf

-- The graph's entrances, and which entrance each door belongs to.  A graph
-- without `entrances` gets one entrance per door, named after it.
function M.entrancesOf(graph)
  local entrances, of = {}, {}
  if type(graph.entrances) == "table" and next(graph.entrances) ~= nil then
    for id, e in pairs(graph.entrances) do
      if type(e) ~= "table" or type(e.doors) ~= "table" or #e.doors == 0 then
        return nil, nil, "entrance " .. tostring(id) .. " has no doors"
      end
      entrances[id] = e
      for _, did in ipairs(e.doors) do
        if type(graph.doors[did]) ~= "table" then
          return nil, nil, "entrance " .. tostring(id) .. " names a door the graph lacks: " .. tostring(did)
        end
        if of[did] and of[did] ~= id then
          return nil, nil, "door " .. tostring(did) .. " is in two entrances"
        end
        of[did] = id
      end
    end
    for did in pairs(graph.doors) do
      if not of[did] then return nil, nil, "door " .. tostring(did) .. " is in no entrance" end
    end
  else
    for did, door in pairs(graph.doors) do
      entrances[did] = { id = did, map = door.map, complex = door.complex, doors = { did },
        inside = door.inside or {} }
      of[did] = did
    end
  end
  return entrances, of
end

-- Where each entrance goes under `placement`: target[entranceId] =
-- entranceId' (itself when it stays).  Or nil and the reason.
function M.entranceTargets(graph, placement, entrances, of)
  for _, key in ipairs(sortedKeys(placement)) do
    if key ~= "entrances" then
      if type(graph.doors[key]) ~= "table" then return nil, "no door " .. tostring(key) end
      local to = placement[key]
      if to ~= nil and type(graph.doors[to]) ~= "table" then return nil, "no door " .. tostring(to) end
    end
  end
  local byEntrance = type(placement.entrances) == "table" and placement.entrances or nil
  if byEntrance then
    for _, id in ipairs(sortedKeys(byEntrance)) do
      if not entrances[id] then return nil, "no entrance " .. tostring(id) end
      if not entrances[byEntrance[id]] then return nil, "no entrance " .. tostring(byEntrance[id]) end
    end
  end
  local target = {}
  for _, id in ipairs(sortedKeys(entrances)) do
    local e = entrances[id]
    local to = byEntrance and byEntrance[id] or nil
    -- every tile must agree with the entrance's target (or stay, if none is given)
    for _, did in ipairs(e.doors) do
      local tileTo = placement[did]
      local tileEntrance = (tileTo == nil or tileTo == did) and id or of[tileTo]
      if to == nil then to = tileEntrance end
      if tileEntrance ~= to and not (tileTo == nil and byEntrance) then
        return nil, ("the tiles of entrance %s lead to different entrances (%s and %s)")
          :format(tostring(id), tostring(to), tostring(tileEntrance))
      end
    end
    target[id] = to or id
  end
  return target
end

-- The writes that make `placement` true on `data` (still vanilla), as a list
-- of { target = warp, field = "destMap" | "destWarp", value = ... } in a fixed
-- order, plus { entrances = n, doors = n } moved.  Or nil and the reason,
-- changing nothing.
function M.plan(data, graph, placement)
  if type(graph) ~= "table" or type(graph.doors) ~= "table" then
    return nil, "the graph has no doors"
  end
  if type(placement) ~= "table" then return nil, "the placement is not a table" end
  local entrances, of, err = M.entrancesOf(graph)
  if not entrances then return nil, err end
  local target, why = M.entranceTargets(graph, placement, entrances, of)
  if not target then return nil, why end

  local writes, wanted = {}, {}
  local moved = { entrances = 0, doors = 0 }
  -- wanted[warp][field] = { value, by }: one value per field, or a conflict
  local function want(warp, field, value, by)
    wanted[warp] = wanted[warp] or {}
    local had = wanted[warp][field]
    if had then
      if had.value ~= value then
        return ("an exit would have to lead to two entrances (%s and %s)"):format(had.by, by)
      end
      return nil
    end
    wanted[warp][field] = { value = value, by = by }
    if warp[field] ~= value then
      writes[#writes + 1] = { target = warp, field = field, value = value }
    end
    return nil
  end
  local function insideWarps(e)
    local list = {}
    for _, spot in ipairs(e.inside or {}) do
      local w = type(spot) == "table" and warpOf(data, spot.map, spot.warp) or nil
      if not w then return nil, "entrance " .. tostring(e.id) .. " names an inside warp that does not exist" end
      list[#list + 1] = w
    end
    return list
  end

  for _, id in ipairs(sortedKeys(entrances)) do
    local e, toId = entrances[id], target[id]
    if toId == id then
      -- staying: its explicit exits keep leading to it
      local list, bad = insideWarps(e)
      if not list then return nil, bad end
      for _, w in ipairs(list) do
        if w.destWarp ~= M.RETURN_WARP then
          why = want(w, "destMap", w.destMap, id) or want(w, "destWarp", w.destWarp, id)
          if why then return nil, why end
        end
      end
    else
      local to = entrances[toId]
      local rep = graph.doors[to.doors[1]]
      local repOutside = warpOf(data, rep.map, rep.warp)
      if not repOutside then return nil, "door " .. tostring(rep.id) .. " has no warp in the map data" end
      if not warpOf(data, repOutside.destMap, repOutside.destWarp) then
        return nil, "door " .. tostring(rep.id) .. " leads to a warp that does not exist"
      end
      for _, did in ipairs(e.doors) do
        local door = graph.doors[did]
        local outside = warpOf(data, door.map, door.warp)
        if not outside then return nil, "door " .. tostring(did) .. " has no warp in the map data" end
        why = want(outside, "destMap", repOutside.destMap, id) or want(outside, "destWarp", repOutside.destWarp, id)
        if why then return nil, why end
        moved.doors = moved.doors + 1
      end
      local first = graph.doors[e.doors[1]]
      local list, bad = insideWarps(to)
      if not list then return nil, bad end
      for _, w in ipairs(list) do
        if w.destWarp ~= M.RETURN_WARP then
          why = want(w, "destMap", first.map, id) or want(w, "destWarp", first.warp, id)
          if why then return nil, why end
        end
      end
      moved.entrances = moved.entrances + 1
    end
  end
  return writes, moved
end

function M.install(mod, ctx)
  local changed = {}
  local cache = { data = nil, graph = nil }

  local function restore()
    for i = #changed, 1, -1 do
      local row = changed[i]
      row.target[row.field] = row.vanilla
    end
    changed = {}
  end

  local function set(target, field, value)
    if target[field] == value then return end
    changed[#changed + 1] = { target = target, field = field, vanilla = target[field] }
    target[field] = value
  end

  local function gameData()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    return type(data) == "table" and data or nil
  end

  local function call(what, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil, nil, what .. " failed: " .. tostring(a) end
    return a, b
  end

  local function apply(level)
    local lib = ctx.lib or {}
    local graphLib, rulesLib, placerLib = lib.mapGraph, lib.mapRules, lib.mapPlacer
    if type(graphLib) ~= "table" or type(graphLib.build) ~= "function" then
      return ctx.log("maps: no mapGraph library; doors stay where they are")
    end
    if type(rulesLib) ~= "table" or type(rulesLib.model) ~= "function" then
      return ctx.log("maps: no mapRules library; doors stay where they are")
    end
    if type(placerLib) ~= "table" or type(placerLib.place) ~= "function" then
      return ctx.log("maps: no mapPlacer library; doors stay where they are")
    end
    local data = gameData()
    if not data or type(data.gen2Maps) ~= "table" then
      return ctx.log("maps: no map data yet; doors stay where they are")
    end
    -- once, from vanilla data: restore() has already run for this switch
    if cache.data ~= data or not cache.graph then
      local graph, _, err = call("mapGraph.build", graphLib.build, data)
      if type(graph) ~= "table" then
        return ctx.log("maps: %s; doors stay where they are", err or "mapGraph.build gave no graph")
      end
      cache.data, cache.graph = data, graph
    end
    local graph = cache.graph
    local rules, _, rulesErr = call("mapRules.model", rulesLib.model, data, graph)
    if type(rules) ~= "table" then
      return ctx.log("maps: %s; doors stay where they are", rulesErr or "mapRules.model gave no rules")
    end
    local placement, report, placeErr = call("mapPlacer.place", placerLib.place, graph, rules, level,
      ctx.rng("maps"), ctx.shared.keyitems)
    if type(placement) ~= "table" then
      return ctx.log("maps: %s; doors stay where they are",
        placeErr or "no placement passed the rules (mapPlacer.place gave none)")
    end
    local okPlan, writes, movedOrWhy = pcall(M.plan, data, graph, placement)
    if not okPlan then writes, movedOrWhy = nil, "the plan failed: " .. tostring(writes) end
    if not writes then
      return ctx.log("maps: placement not applied, %s; doors stay where they are", movedOrWhy)
    end
    for _, w in ipairs(writes) do set(w.target, w.field, w.value) end
    ctx.shared.maps = { placement = placement, report = report }
    ctx.log("maps: level %s, %d entrances (%d door tiles) lead elsewhere, %d warp fields changed",
      level, movedOrWhy.entrances, movedOrWhy.doors, #writes)
  end

  ctx.onSave(function(active)
    restore()
    if not active then return end
    local level = ctx.option("maps")
    if level == nil or level == false or level == "off" then return end
    if not M.LEVELS[level] then
      return ctx.log("maps: unknown level %s; doors stay where they are", tostring(level))
    end
    apply(level)
  end)
end

return M
