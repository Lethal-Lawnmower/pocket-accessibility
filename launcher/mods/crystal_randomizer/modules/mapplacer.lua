-- Crystal randomizer: where each door leads (the placer of MAPS.md).
--
-- Offers ctx.lib.mapPlacer.place(graph, rules, level, rng, hmPlacement) and
-- asks no question; the `maps` module owns the question and applies the result.
--
-- placement[doorId] = doorId' means door A now leads where door A' led.  The
-- placement lists every door of the graph; a door that does not move maps to
-- itself.  Within each pool the targets are a permutation of the pool, so the
-- swap is one-to-one: every destination is still used by exactly one door.
--
-- Pools per level (MAPS.md "Levels").  A door never moves when its complex is
-- missing from the graph, is in rules.fixed, or has story = true.
--   houses  "houses": doors of dead-end INDOOR complexes.
--   caves   "houses" as above, plus "caves": doors of CAVE and DUNGEON
--           complexes (dead end or not).  The two pools never mix.
--   full    "all": every door that may move, any kind to any kind.
--
-- The search, bounded by M.LIMITS and deterministic for the rng given:
--   1. The vanilla doors (every door to itself) must pass rules.canWin, or
--      nothing is placed: no shuffle can be trusted under a model that
--      rejects the vanilla game.
--   2. Shuffle: up to LIMITS.shuffles times, every pool is shuffled whole
--      (Fisher-Yates from the rng) and the result is checked.  The first one
--      canWin accepts is used.  Where the logic is loose (always for houses
--      under a model whose houses hold nothing the story needs) this is the
--      first try.
--   3. Grow: if no whole shuffle passed, start again from the vanilla doors
--      and propose random swaps of two doors' targets within a pool
--      (LIMITS.passes proposals per door).  Proposals are tried in chunks
--      (LIMITS.chunk at a time): a chunk canWin accepts is kept whole, a chunk
--      it rejects is undone and split in halves, down to single swaps, which
--      are kept or dropped.  Every kept state passed canWin, so the result
--      does.  This stops when the proposals or LIMITS.calls run out.
--   4. If the result moves no door at all, nothing is placed (nil, report).
--
-- Determinism: every list is built from door ids sorted as strings, pools are
-- visited in a fixed order, and the only randomness is the rng's own draws,
-- so the same rng state and graph give the same placement in any table order.
-- rules.canWin is assumed deterministic; it is handed a copy of the placement
-- each time, so it cannot disturb the search by changing the table.
-- os.clock is read only to report the time taken, never to decide anything.

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

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
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

-- The pool a door belongs to at `level`, or nil and why it stays.
function M.poolFor(graph, rules, door, level)
  local complex = door and graph.complexes and graph.complexes[door.complex]
  local reason = fixedReason(complex, rules)
  if reason then return nil, reason end
  if level == "full" then return "all" end
  if complex.environment == "INDOOR" and complex.deadEnd == true then return "houses" end
  if level == "caves" and CAVE_ENVIRONMENTS[complex.environment] then return "caves" end
  return nil, "not in this level"
end

-- { [poolName] = { doorId, ... } } with each list sorted, and the pool names
-- in a fixed order.
function M.pools(graph, rules, level)
  local pools, names = {}, {}
  for _, id in ipairs(sortedKeys(graph.doors)) do
    local pool = M.poolFor(graph, rules, graph.doors[id], level)
    if pool then
      if not pools[pool] then pools[pool] = {}; names[#names + 1] = pool end
      local list = pools[pool]
      list[#list + 1] = id
    end
  end
  table.sort(names)
  return pools, names
end

local function countMoved(placement)
  local n = 0
  for door, target in pairs(placement) do if door ~= target then n = n + 1 end end
  return n
end

-- graph, rules: MAPS.md shapes.  level: "houses" | "caves" | "full".
-- rng: a stream (rng.lua) with :next, :int and :shuffled.
-- hmPlacement: passed through to rules.canWin.
-- Returns placement, report; or nil, report (report.reason says why).
function M.place(graph, rules, level, rng, hmPlacement)
  local started = os.clock()
  local limits = M.LIMITS
  local report = { level = level, pools = {}, movable = 0, moved = 0, calls = 0,
    shuffles = 0, grown = 0, phase = nil, reason = nil }
  local function finish(placement, reason)
    report.reason = reason
    report.seconds = os.clock() - started
    if placement then report.moved = countMoved(placement) end
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

  local pools, names = M.pools(graph, rules, level)
  for _, name in ipairs(names) do
    report.pools[name] = #pools[name]
    report.movable = report.movable + #pools[name]
  end

  local current = {}
  for id in pairs(graph.doors) do current[id] = id end

  local function wins()
    if report.calls >= limits.calls then return false, "out of calls" end
    report.calls = report.calls + 1
    local ok, why = rules.canWin(copy(current), hmPlacement)
    return ok == true, why
  end

  local okVanilla, whyVanilla = wins()
  if not okVanilla then
    return finish(nil, "the vanilla doors fail canWin: " .. tostring(whyVanilla))
  end
  if report.movable < 2 then return finish(nil, "fewer than two doors may move") end

  -- 2. whole shuffles
  local lastWhy
  for attempt = 1, limits.shuffles do
    if report.calls >= limits.calls then break end
    for _, name in ipairs(names) do
      local pool = pools[name]
      local targets = rng:shuffled(pool)
      for i, door in ipairs(pool) do current[door] = targets[i] end
    end
    report.shuffles = attempt
    local ok, why = wins()
    if ok and countMoved(current) > 0 then
      report.phase = "shuffle"
      return finish(current)
    end
    lastWhy = why
  end
  report.lastRejection = lastWhy

  -- 3. grow from the vanilla doors by kept swaps
  for id in pairs(current) do current[id] = id end
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
  return finish(current)
end

function M.install(mod, ctx)
  ctx.lib.mapPlacer = { place = M.place, pools = M.pools, poolFor = M.poolFor, limits = M.LIMITS }
end

return M
