-- Crystal randomizer: where doors lead (MAPS.md is the design this follows).
--
-- This module owns the `maps` question and applies a placement; it does not
-- decide one.  Three libraries other modules offer in `ctx.lib` do that:
--   mapGraph.build(data)        the doors and complexes of the vanilla maps
--   mapRules.model(data, graph) what is fixed and what keeps the game winnable
--   mapPlacer.place(graph, rules, level, rng, hmPlacement)
--                               placement[doorId] = doorId' (door A now leads
--                               where door A' led), and a report
--
-- How a door is changed.  A door is an outdoor warp `{ x, y, destMap,
-- destWarp }` in data.gen2Maps[map].warps (warp numbers are 1-based list
-- indexes, as World:takeWarp reads them).  When door A takes door A'
-- destination, A's outdoor warp gets the vanilla destMap and destWarp of A'
-- outdoor warp, so the player arrives where A' used to lead.
--
-- How leaving comes back to the door used.  The complex warps that lead back
-- out (graph.doors[A'].inside) come in two kinds:
--   * destWarp 0xff: World:recordWarpBackup notes the warp stepped on and the
--     map left whenever the warp arrived on says 0xff, and World:resolveWarp
--     sends the 0xff warp back there.  Those already return to door A and are
--     left alone.
--   * an explicit destMap and destWarp naming A' outdoor side: those are
--     pointed at door A instead.
-- A placement that would point one explicit warp at two different doors (two
-- doors sharing a destination) is refused as a whole, because one of those
-- doors would let its player out somewhere else.
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

-- The writes that make `placement` true on `data` (still vanilla), as a list
-- of { target = warp, field = "destMap" | "destWarp", value = ... } in a fixed
-- order, plus how many doors moved.  Or nil and the reason, changing nothing.
function M.plan(data, graph, placement)
  if type(graph) ~= "table" or type(graph.doors) ~= "table" then
    return nil, "the graph has no doors"
  end
  if type(placement) ~= "table" then return nil, "the placement is not a table" end
  local writes, wanted, moved = {}, {}, 0
  -- wanted[warp][field] = { value, by }: one value per field, or a conflict
  local function want(warp, field, value, by)
    wanted[warp] = wanted[warp] or {}
    local had = wanted[warp][field]
    if had then
      if had.value ~= value then
        return ("a warp would lead to two doors (%s and %s)"):format(had.by, by)
      end
      return nil
    end
    wanted[warp][field] = { value = value, by = by }
    if warp[field] ~= value then
      writes[#writes + 1] = { target = warp, field = field, value = value }
    end
    return nil
  end
  for _, doorId in ipairs(sortedKeys(placement)) do
    if type(graph.doors[doorId]) ~= "table" then return nil, "no door " .. tostring(doorId) end
  end
  -- every door, so one that stays claims its own way out and a door moved
  -- onto its complex is caught as a conflict instead of stealing that exit
  for _, doorId in ipairs(sortedKeys(graph.doors)) do
    local targetId = placement[doorId]
    if targetId == nil or targetId == doorId then
      for _, spot in ipairs(graph.doors[doorId].inside or {}) do
        local inside = type(spot) == "table" and warpOf(data, spot.map, spot.warp) or nil
        if inside and inside.destWarp ~= M.RETURN_WARP then
          local why = want(inside, "destMap", inside.destMap, doorId)
            or want(inside, "destWarp", inside.destWarp, doorId)
          if why then return nil, why end
        end
      end
    else
      local door, target = graph.doors[doorId], graph.doors[targetId]
      if type(door) ~= "table" then return nil, "no door " .. tostring(doorId) end
      if type(target) ~= "table" then return nil, "no door " .. tostring(targetId) end
      local outside = warpOf(data, door.map, door.warp)
      local targetOutside = warpOf(data, target.map, target.warp)
      if not outside then return nil, "door " .. tostring(doorId) .. " has no warp in the map data" end
      if not targetOutside then return nil, "door " .. tostring(targetId) .. " has no warp in the map data" end
      if not warpOf(data, targetOutside.destMap, targetOutside.destWarp) then
        return nil, "door " .. tostring(targetId) .. " leads to a warp that does not exist"
      end
      local why = want(outside, "destMap", targetOutside.destMap, doorId)
        or want(outside, "destWarp", targetOutside.destWarp, doorId)
      if why then return nil, why end
      for _, spot in ipairs(target.inside or {}) do
        local inside = type(spot) == "table" and warpOf(data, spot.map, spot.warp) or nil
        if not inside then
          return nil, "door " .. tostring(targetId) .. " names an inside warp that does not exist"
        end
        if inside.destWarp ~= M.RETURN_WARP then
          why = want(inside, "destMap", door.map, doorId) or want(inside, "destWarp", door.warp, doorId)
          if why then return nil, why end
        end
      end
      moved = moved + 1
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
    local writes, movedOrWhy = M.plan(data, graph, placement)
    if not writes then
      return ctx.log("maps: placement not applied, %s; doors stay where they are", movedOrWhy)
    end
    for _, w in ipairs(writes) do set(w.target, w.field, w.value) end
    ctx.shared.maps = { placement = placement, report = report }
    ctx.log("maps: level %s, %d doors lead elsewhere, %d warp fields changed",
      level, movedOrWhy, #writes)
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
