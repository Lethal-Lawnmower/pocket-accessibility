-- Crystal randomizer: where each doorway leads (the placer of MAPS.md).
--
-- Offers ctx.lib.mapPlacer.place(graph, rules, level, rng, hmPlacement) and
-- asks no question; the `maps` module owns the question and applies the result.
--
-- What moves is an ENTRANCE, never a single warp tile.  mapgraph groups the
-- tiles of one doorway (AZALEA_TOWN:7 and :8, ROUTE_23:1 and :2) into
-- graph.entrances[entranceId] = { id, map, complex, doors = { doorId, ... },
-- inside }, and sets door.entrance on each tile.  A graph without entrances
-- (or a door no entrance lists) is read as one entrance per door, id = door id.
--
-- The result, one table:
--   placement.entrances[E] = E'   entrance E now leads where entrance E' led;
--                                 every entrance is listed, unmoved ones to
--                                 themselves; a permutation within each pool.
--   placement[doorId] = doorId'   for every tile of every entrance: the
--                                 representative door (the first in its
--                                 doors list) of the entrance it now leads to.
-- So every tile of one doorway goes to the same place, and the entrances map
-- one-to-one.  rules.canWin is given this same shape.
--
-- Pools per level (MAPS.md "Levels").  An entrance never moves when its
-- complex is missing from the graph, is in rules.fixed, or has story = true.
-- A dead end is a complex with one entrance (complex.deadEnd, which mapgraph
-- counts in entrances; worked out here from the entrances when it is absent).
--   houses  "houses": entrances of dead-end INDOOR complexes.
--   caves   "houses" as above, plus "caves": entrances of CAVE and DUNGEON
--           complexes (dead end or not).  The two pools never mix.
--   full    "all": every entrance that may move, any kind to any kind.
--
-- The search, bounded by M.LIMITS and deterministic for the rng given:
--   1. The vanilla doors (every entrance to itself) must pass rules.canWin,
--      or nothing is placed: no shuffle can be trusted under a model that
--      rejects the vanilla game.
--   2. Shuffle: up to LIMITS.shuffles times, every pool is shuffled whole
--      (Fisher-Yates from the rng) and the result is checked.  The first one
--      canWin accepts is used.
--   3. Grow: if no whole shuffle passed, start again from the vanilla doors
--      and propose random swaps of two entrances' targets within a pool
--      (LIMITS.passes proposals per entrance).  Proposals are tried in chunks
--      (LIMITS.chunk at a time): a chunk canWin accepts is kept whole, a chunk
--      it rejects is undone and split in halves, down to single swaps, which
--      are kept or dropped.  Every kept state passed canWin, so the result
--      does.  This stops when the proposals or LIMITS.calls run out.
--   4. If the result moves no entrance at all, nothing is placed (nil, report).
--
-- Determinism: every list is built from ids sorted as strings, pools are
-- visited in a fixed order, and the only randomness is the rng's own draws,
-- so the same rng state and graph give the same placement in any table order.
-- rules.canWin is assumed deterministic; it is handed a fresh copy each time,
-- so it cannot disturb the search by changing the table.  os.clock is read
-- only to report the time taken, never to decide anything.

local M = {
  id = "mapplacer",
  questions = {},
}

M.LEVELS = { houses = true, caves = true, full = true }

-- Search bounds.  `calls` caps rules.canWin calls in all; the vanilla check
-- and each whole shuffle count towards it.
M.LIMITS = { shuffles = 8, passes = 2, chunk = 64, calls = 2000 }

local CAVE_ENVIRONMENTS = { CAVE = true, DUNGEON = true }

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- { [entranceId] = { id, complex, doors = { doorId, ... } } } for the whole
-- graph: graph.entrances where given, else one entrance per door.  Tiles are
-- kept in the order the graph lists them (the first is the representative).
function M.entrances(graph)
  local out, covered = {}, {}
  for _, eid in ipairs(sortedKeys(graph.entrances)) do
    local e = graph.entrances[eid]
    if type(e) == "table" and type(e.doors) == "table" and #e.doors > 0 then
      local doors = {}
      for i, did in ipairs(e.doors) do
        if graph.doors[did] then doors[#doors + 1] = did; covered[did] = true end
      end
      if #doors > 0 then
        local complex = e.complex
        if complex == nil then complex = graph.doors[doors[1]].complex end
        out[eid] = { id = eid, complex = complex, doors = doors }
      end
    end
  end
  for _, did in ipairs(sortedKeys(graph.doors)) do
    if not covered[did] then
      out[did] = { id = did, complex = graph.doors[did].complex, doors = { did } }
    end
  end
  return out
end

-- Why the complex is immovable, or nil when it may move.
local function fixedReason(complex, rules)
  if type(complex) ~= "table" then return "no complex" end
  local fixed = type(rules) == "table" and type(rules.fixed) == "table" and rules.fixed[complex.id]
  if fixed then return "fixed: " .. tostring(fixed) end
  if complex.story then return "story" end
  return nil
end

-- Entrances per complex, for dead ends where complex.deadEnd is absent.
local function entranceCounts(entrances)
  local counts = {}
  for _, e in pairs(entrances) do
    if e.complex ~= nil then counts[e.complex] = (counts[e.complex] or 0) + 1 end
  end
  return counts
end

-- The pool an entrance belongs to at `level`, or nil and why it stays.
-- `counts` (optional) is entrances per complex.
function M.poolFor(graph, rules, entrance, level, counts)
  local complex = entrance and graph.complexes and graph.complexes[entrance.complex]
  local reason = fixedReason(complex, rules)
  if reason then return nil, reason end
  if level == "full" then return "all" end
  local deadEnd = complex.deadEnd
  if deadEnd == nil and counts then deadEnd = counts[complex.id] == 1 end
  if complex.environment == "INDOOR" and deadEnd == true then return "houses" end
  if level == "caves" and CAVE_ENVIRONMENTS[complex.environment] then return "caves" end
  return nil, "not in this level"
end

-- { [poolName] = { entranceId, ... } } with each list sorted, the pool names
-- in a fixed order, and the entrances table used.
function M.pools(graph, rules, level, entrances)
  entrances = entrances or M.entrances(graph)
  local counts = entranceCounts(entrances)
  local pools, names = {}, {}
  for _, eid in ipairs(sortedKeys(entrances)) do
    local pool = M.poolFor(graph, rules, entrances[eid], level, counts)
    if pool then
      if not pools[pool] then pools[pool] = {}; names[#names + 1] = pool end
      local list = pools[pool]
      list[#list + 1] = eid
    end
  end
  table.sort(names)
  return pools, names, entrances
end

local function countMoved(map)
  local n = 0
  for from, to in pairs(map) do if from ~= to then n = n + 1 end end
  return n
end

-- The placement table for an entrance map (see the top of the file).
local function expand(entrances, current)
  local placement = { entrances = {} }
  for eid, target in pairs(current) do
    placement.entrances[eid] = target
    local rep = entrances[target].doors[1]
    for _, did in ipairs(entrances[eid].doors) do placement[did] = rep end
  end
  return placement
end
M.expand = expand

-- graph, rules: MAPS.md shapes.  level: "houses" | "caves" | "full".
-- rng: a stream (rng.lua) with :int and :shuffled.
-- hmPlacement: passed through to rules.canWin.
-- Returns placement, report; or nil, report (report.reason says why).
function M.place(graph, rules, level, rng, hmPlacement)
  local started = os.clock()
  local limits = M.LIMITS
  local report = { level = level, pools = {}, movable = 0, moved = 0, movedDoors = 0, calls = 0,
    shuffles = 0, grown = 0, phase = nil, reason = nil }
  local function finish(placement, reason)
    report.reason = reason
    report.seconds = os.clock() - started
    if placement then
      report.moved = countMoved(placement.entrances)
      local n = 0
      for did, target in pairs(placement) do
        if did ~= "entrances" and did ~= target then n = n + 1 end
      end
      report.movedDoors = n
    end
    return placement, report
  end

  if not M.LEVELS[level] then return finish(nil, "level " .. tostring(level) .. " places nothing") end
  if type(graph) ~= "table" or type(graph.doors) ~= "table" or type(graph.complexes) ~= "table" then
    return finish(nil, "no door graph")
  end
  if type(rules) ~= "table" or type(rules.canWin) ~= "function" then
    return finish(nil, "no rules.canWin")
  end
  if type(rng) ~= "table" or type(rng.int) ~= "function" or type(rng.shuffled) ~= "function" then
    return finish(nil, "no rng")
  end

  local pools, names, entrances = M.pools(graph, rules, level)
  for _, name in ipairs(names) do
    report.pools[name] = #pools[name]
    report.movable = report.movable + #pools[name]
  end

  local current = {}
  for eid in pairs(entrances) do current[eid] = eid end

  local function wins()
    if report.calls >= limits.calls then return false, "out of calls" end
    report.calls = report.calls + 1
    local ok, why = rules.canWin(expand(entrances, current), hmPlacement)
    return ok == true, why
  end

  local okVanilla, whyVanilla = wins()
  if not okVanilla then
    return finish(nil, "the vanilla doors fail canWin: " .. tostring(whyVanilla))
  end
  if report.movable < 2 then return finish(nil, "fewer than two entrances may move") end

  -- 2. whole shuffles
  local lastWhy
  for attempt = 1, limits.shuffles do
    if report.calls >= limits.calls then break end
    for _, name in ipairs(names) do
      local pool = pools[name]
      local targets = rng:shuffled(pool)
      for i, eid in ipairs(pool) do current[eid] = targets[i] end
    end
    report.shuffles = attempt
    local ok, why = wins()
    if ok and countMoved(current) > 0 then
      report.phase = "shuffle"
      return finish(expand(entrances, current))
    end
    lastWhy = why
  end
  report.lastRejection = lastWhy

  -- 3. grow from the vanilla doors by kept swaps
  for eid in pairs(current) do current[eid] = eid end
  local proposals = {}
  for _ = 1, limits.passes do
    for _, name in ipairs(names) do
      local pool = pools[name]
      for _, a in ipairs(rng:shuffled(pool)) do
        local b = pool[rng:int(1, #pool)]
        if a ~= b then proposals[#proposals + 1] = { a, b } end
      end
    end
  end

  local function apply(lo, hi)
    for i = lo, hi do
      local a, b = proposals[i][1], proposals[i][2]
      current[a], current[b] = current[b], current[a]
    end
  end
  local function undo(lo, hi)
    for i = hi, lo, -1 do
      local a, b = proposals[i][1], proposals[i][2]
      current[a], current[b] = current[b], current[a]
    end
  end
  local function try(lo, hi)
    if report.calls >= limits.calls then return end
    apply(lo, hi)
    if wins() then report.grown = report.grown + (hi - lo + 1); return end
    undo(lo, hi)
    if lo == hi then return end
    local mid = math.floor((lo + hi) / 2)
    try(lo, mid)
    try(mid + 1, hi)
  end
  for lo = 1, #proposals, limits.chunk do
    if report.calls >= limits.calls then break end
    try(lo, math.min(lo + limits.chunk - 1, #proposals))
  end

  if countMoved(current) == 0 then
    return finish(nil, ("no shuffled placement passed canWin within %d calls (last: %s)")
      :format(report.calls, tostring(lastWhy)))
  end
  report.phase = "grow"
  return finish(expand(entrances, current))
end

function M.install(mod, ctx)
  ctx.lib.mapPlacer = { place = M.place, pools = M.pools, poolFor = M.poolFor,
    entrances = M.entrances, limits = M.LIMITS }
end

return M
