local T = require("tests.harness")
local S = T.suite("accessibility pathfinder")
local Pathfinder = require("src.access.nav.Pathfinder")

local function open()
  return true
end

local function find(start, goal, extra)
  local options = {
    start = start,
    goal = goal,
    bounds = { width = 7, height = 7 },
    canTraverse = open,
  }
  for key, value in pairs(extra or {}) do options[key] = value end
  return Pathfinder.find(options)
end

-- Start-at-goal is a valid zero-step route and does not query collision.
local callbackCalls = 0
local result, err = Pathfinder.find({
  start = { x = 2, y = 3 },
  goal = { x = 2, y = 3 },
  bounds = { minX = 0, minY = 0, maxX = 5, maxY = 5 },
  canTraverse = function() callbackCalls = callbackCalls + 1; return true end,
})
S.check(result ~= nil and err == nil, "start-at-goal succeeds")
S.eq(result.cost, 0, "start-at-goal has zero cost")
S.same(result.directions, {}, "start-at-goal has no directions")
S.same(result.cells, { { x = 2, y = 3 } },
  "start-at-goal retains the one path cell")
S.eq(callbackCalls, 0, "start-at-goal does not consult traversal")

-- A solid column forces the shortest route around its lower end.
local walls = { ["1,0"] = true, ["1,1"] = true }
result = assert(find({ x = 0, y = 0 }, { x = 2, y = 0 }, {
  blockedCells = walls,
}))
S.eq(result.cost, 6, "obstacle detour has shortest cardinal cost")
S.same(result.directions,
  { "down", "down", "right", "right", "up", "up" },
  "obstacle detour is deterministic")
S.same(result.cells[1], { x = 0, y = 0 }, "path cells include the start")
S.same(result.cells[#result.cells], { x = 2, y = 0 },
  "path cells include the chosen goal")
S.eq(#result.steps, result.cost, "one step record is returned per direction")
S.same(result.steps[1], {
  direction = "down", fromX = 0, fromY = 0, x = 0, y = 1,
}, "step records carry direction and both cell endpoints")

-- Blocking a full row yields a controlled no-path result.
result, err = find({ x = 0, y = 0 }, { x = 0, y = 2 }, {
  bounds = { width = 3, height = 3 },
  blockedCells = { ["0,1"] = true, ["1,1"] = true, ["2,1"] = true },
})
S.eq(result, nil, "unreachable goal returns nil")
S.eq(err, "no path", "unreachable goal has a stable error")

-- Multiple goals choose the cheapest reachable target.
result = assert(Pathfinder.find({
  start = { x = 3, y = 3 },
  goals = { { x = 6, y = 3 }, { x = 3, y = 2 } },
  bounds = { width = 7, height = 7 },
  canTraverse = open,
}))
S.same(result.goal, { x = 3, y = 2 }, "multiple goals select the shortest target")
S.same(result.directions, { "up" }, "multiple-goal route reaches that target")

-- Equal-cost alternatives follow the documented neighbor order every time.
local deterministicOptions = {
  start = { x = 1, y = 1 },
  goal = { x = 2, y = 0 },
  bounds = { width = 4, height = 4 },
  canTraverse = open,
}
local first = assert(Pathfinder.find(deterministicOptions))
for _ = 1, 5 do
  local again = assert(Pathfinder.find(deterministicOptions))
  S.same(again.directions, first.directions,
    "equal-cost route output is repeatably deterministic")
end
S.same(first.directions, { "up", "right" },
  "fixed up/right/down/left tie-break order is observable")

-- Directional traversal can model a ledge or any other one-way edge.
result = assert(find({ x = 0, y = 0 }, { x = 2, y = 0 }, {
  bounds = { width = 3, height = 2 },
  canTraverse = function(fromX, fromY, toX, toY, direction)
    if fromX == 0 and fromY == 0 and toX == 1 and toY == 0
       and direction == "right" then return false end
    return true
  end,
}))
S.same(result.directions, { "down", "right", "up", "right" },
  "a forbidden forward edge detours around a one-way boundary")
local reverse = assert(find({ x = 1, y = 0 }, { x = 0, y = 0 }, {
  bounds = { width = 3, height = 2 },
  canTraverse = function(_, _, _, _, direction)
    return direction ~= "right"
  end,
}))
S.same(reverse.directions, { "left" },
  "the reverse side of a directional edge remains traversable")

-- Native one-input movement may span multiple cells. Custom neighbors retain
-- that action as one edge and preserve semantic narration metadata.
result = assert(Pathfinder.find({
  start = { x = 0, y = 0 }, goal = { x = 1, y = 2 },
  bounds = { width = 2, height = 3 },
  neighbors = function(x, y)
    if x == 0 and y == 0 then
      return { { x = 0, y = 2, direction = "down", kind = "ledge",
                 instruction = "Jump ledge down" } }
    elseif x == 0 and y == 2 then
      return { { x = 1, y = 2, direction = "right" } }
    end
    return {}
  end,
  canTraverse = function() return true end,
}))
S.same(result.cells,
  { { x = 0, y = 0 }, { x = 0, y = 2 }, { x = 1, y = 2 } },
  "a multi-cell native action retains only its actual landing cell")
S.same(result.directions, { "down", "right" },
  "a one-input ledge remains one route action")
S.eq(result.steps[1].kind, "ledge",
  "custom edge kind survives path reconstruction")
S.eq(result.steps[1].instruction, "Jump ledge down",
  "custom edge narration survives path reconstruction")

result, err = Pathfinder.find({
  start = { x = 0, y = 0 }, goal = { x = 1, y = 0 },
  bounds = { width = 2, height = 1 },
  neighbors = function() return { { x = 1, y = 0, direction = "warp" } } end,
  canTraverse = open,
})
S.eq(result, nil, "invalid custom movement edges fail closed")
S.check(err:find("invalid direction", 1, true) ~= nil,
  "invalid custom movement edges return a controlled diagnostic")

-- Dynamic blockers stop routes, ignorable records do not, and a selected
-- destination is exempt by default so an NPC/object can be the route target.
result = assert(find({ x = 0, y = 0 }, { x = 2, y = 0 }, {
  bounds = { width = 3, height = 2 },
  blockedCells = { { cellX = 1, cellY = 0 } },
}))
S.same(result.directions, { "down", "right", "right", "up" },
  "a dynamic entity blocks its occupied cell")
result = assert(find({ x = 0, y = 0 }, { x = 2, y = 0 }, {
  bounds = { width = 3, height = 2 },
  blockedCells = { { x = 1, y = 0, ignorable = true } },
}))
S.same(result.directions, { "right", "right" },
  "an ignorable dynamic object does not block a route")
result = assert(find({ x = 0, y = 0 }, { x = 1, y = 0 }, {
  bounds = { width = 2, height = 1 },
  blockedCells = { { x = 1, y = 0 } },
}))
S.same(result.directions, { "right" },
  "the selected blocked target receives the default target exception")
result, err = find({ x = 0, y = 0 }, { x = 1, y = 0 }, {
  bounds = { width = 2, height = 1 },
  blockedCells = { { x = 1, y = 0 } },
  allowBlockedGoal = false,
})
S.eq(result, nil, "target exception can be disabled")
S.eq(err, "no path", "disabled target exception yields no path")

-- A caller's policy is forwarded by identity on every traversal query.
local policy = { hmMode = "available", badges = { 2, 5 } }
local policySeen, policyMismatch = 0, false
result = assert(find({ x = 0, y = 0 }, { x = 2, y = 0 }, {
  bounds = { width = 3, height = 1 },
  policy = policy,
  canTraverse = function(fromX, fromY, toX, toY, direction, received)
    policySeen = policySeen + 1
    if received ~= policy then policyMismatch = true end
    return math.abs(toX - fromX) + math.abs(toY - fromY) == 1
       and direction == "right"
  end,
}))
S.check(policySeen > 0 and not policyMismatch,
  "the exact traversal policy is forwarded to callbacks")
S.same(policy, { hmMode = "available", badges = { 2, 5 } },
  "pathfinding never mutates the caller's policy")

-- A broken mod collision hook cannot unwind the game loop.
result, err = find({ x = 0, y = 0 }, { x = 1, y = 0 }, {
  bounds = { width = 2, height = 1 },
  canTraverse = function() error("mod traversal exploded") end,
})
S.eq(result, nil, "callback exception is contained")
S.check(type(err) == "string" and err:find("canTraverse callback failed", 1, true),
  "callback exception returns a controlled diagnostic")
S.check(err:find("mod traversal exploded", 1, true) ~= nil,
  "callback diagnostic retains the useful cause")

-- Hard bounds prevent any query from escaping the map rectangle.
local escaped = false
result, err = find({ x = 0, y = 0 }, { x = 1, y = 1 }, {
  bounds = { width = 2, height = 2 },
  blockedCells = { { x = 1, y = 0 }, { x = 0, y = 1 } },
  canTraverse = function(_, _, toX, toY)
    if toX < 0 or toY < 0 or toX > 1 or toY > 1 then escaped = true end
    return true
  end,
})
S.eq(result, nil, "hard bounds can make a boxed-in route unreachable")
S.eq(err, "no path", "boxed-in route reports no path")
S.check(not escaped, "traversal callback is never queried outside hard bounds")

result, err = find({ x = 0, y = 0 }, { x = 6, y = 6 }, { maxNodes = 1 })
S.eq(result, nil, "node guard stops an oversized search")
S.eq(err, "node limit exceeded", "node guard has a controlled diagnostic")

local task = assert(Pathfinder.start({
  start = { x = 0, y = 0 }, goal = { x = 6, y = 6 },
  bounds = { width = 7, height = 7 }, canTraverse = open,
}, { yieldEvery = 1 }))
local taskDone, _, _, progress = task:step()
S.check(not taskDone and progress.expanded == 1,
  "cooperative route task yields deterministic progress")
task:cancel()
local cancelledDone, cancelledResult, cancelledError = task:step()
S.check(cancelledDone and cancelledResult == nil,
  "cancelled cooperative route task completes without a result")
S.eq(cancelledError, "cancelled",
  "cancelled cooperative route task has a stable accessible reason")

local clockTicks = 0
result, err = Pathfinder.find({
  start = { x = 0, y = 0 }, goal = { x = 6, y = 6 },
  bounds = { width = 7, height = 7 }, canTraverse = open,
  maxSeconds = 0.5,
  clock = function() clockTicks = clockTicks + 1; return clockTicks end,
})
S.eq(result, nil, "route time budget fails closed")
S.eq(err, "time limit exceeded", "route time budget has a stable diagnostic")

result, err = Pathfinder.find({
  start = { x = 0, y = 0 }, goal = { x = 1, y = 0 },
  bounds = { width = 2, height = 1 }, canTraverse = open,
  isCancelled = function() error("cancel probe broke") end,
})
S.eq(result, nil, "broken cancellation callback cannot unwind the caller")
S.check(err:find("isCancelled callback failed", 1, true) ~= nil,
  "broken cancellation callback returns a controlled diagnostic")

result, err = Pathfinder.find({
  start = { x = 0.5, y = 0 }, goal = { x = 1, y = 0 },
  bounds = { width = 2, height = 1 }, canTraverse = open,
})
S.eq(result, nil, "fractional coordinates are rejected")
S.check(err:find("finite integers", 1, true) ~= nil,
  "bad coordinate input returns a readable reason")

-- Route grouping preserves traversal order; repeated ordinary moves become
-- one speech segment exactly as in Pokemon Access.
local groups = assert(Pathfinder.groupDirections({
  "right", "right", "down", "left", "left", "left", "up",
}))
S.same(groups, {
  { direction = "right", count = 2, text = "2 right" },
  { direction = "down", count = 1, text = "1 down" },
  { direction = "left", count = 3, text = "3 left" },
  { direction = "up", count = 1, text = "1 up" },
}, "consecutive directions group in route narration order")
local narration = assert(Pathfinder.narrateDirections(result or {
  directions = { "up", "up", "right" },
}, { labels = { up = "  north\n", right = "east" } }))
S.same(narration, { "2 north", "1 east" },
  "narration returns safe readable localized utterances")
local badGroups, badGroupErr = Pathfinder.groupDirections({ "up", "teleport" })
S.eq(badGroups, nil, "invalid narration direction is rejected")
S.eq(badGroupErr, "invalid direction at index 2",
  "invalid narration direction has a controlled error")

-- Searches and narration do not alter any of the caller-owned structures.
local immutableStart = { x = 0, y = 0, note = "keep" }
local immutableGoals = { { x = 2, y = 0, note = "goal" } }
local immutableBlocked = { { x = 1, y = 1, ignorable = true } }
assert(Pathfinder.find({
  start = immutableStart,
  goals = immutableGoals,
  bounds = { width = 3, height = 2 },
  blockedCells = immutableBlocked,
  canTraverse = open,
}))
S.same(immutableStart, { x = 0, y = 0, note = "keep" },
  "start cell is not mutated")
S.same(immutableGoals, { { x = 2, y = 0, note = "goal" } },
  "goal cells are not mutated")
S.same(immutableBlocked, { { x = 1, y = 1, ignorable = true } },
  "blocked cells are not mutated")

S.finish()
