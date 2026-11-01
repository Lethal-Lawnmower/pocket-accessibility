-- Reused from the old Pocket Accessibility project (src/accessibility/Pathfinder.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Deterministic, read-only cardinal pathfinding for accessibility routes.
--
-- This module deliberately does not know about Map, Collision, Player, HMs,
-- ledges, or mods.  The caller supplies the authoritative directional
-- traversal predicate:
--
--   canTraverse(fromX, fromY, toX, toY, direction, policy) -> allowed
--
-- Callers with native multi-cell movement (for example a one-input ledge hop)
-- may additionally provide:
--
--   neighbors(x, y, policy) -> { { x, y, direction, cost?, kind?, instruction? } }
--
-- Keeping that rule at the integration seam prevents this helper from growing
-- a second, subtly different copy of the game's movement logic.

local Pathfinder = {}

-- Fixed order is part of the deterministic contract.  It is intentionally
-- private: callers cannot change an in-flight search by mutating an exported
-- table.
local DIRECTIONS = {
  { name = "up",    dx =  0, dy = -1 },
  { name = "right", dx =  1, dy =  0 },
  { name = "down",  dx =  0, dy =  1 },
  { name = "left",  dx = -1, dy =  0 },
}

Pathfinder.DIRECTION_ORDER = { "up", "right", "down", "left" }

local VALID_DIRECTION = {
  up = true,
  right = true,
  down = true,
  left = true,
}

local function safeString(value)
  local ok, rendered = pcall(tostring, value)
  if ok then return rendered end
  return "unknown error"
end

local function isInteger(value)
  return type(value) == "number"
     and value == value
     and value ~= math.huge
     and value ~= -math.huge
     and value % 1 == 0
end

local function cellKey(x, y)
  return tostring(x) .. ":" .. tostring(y)
end

local function coordinates(cell, label)
  if type(cell) ~= "table" then
    return nil, nil, label .. " must be a cell table"
  end
  local x = cell.x
  if x == nil then x = cell.cellX end
  if x == nil then x = cell[1] end
  local y = cell.y
  if y == nil then y = cell.cellY end
  if y == nil then y = cell[2] end
  if not isInteger(x) or not isInteger(y) then
    return nil, nil, label .. " coordinates must be finite integers"
  end
  return x, y
end

local function normalizeBounds(value)
  if type(value) ~= "table" then
    return nil, "bounds must be a table"
  end

  local minX = value.minX
  if minX == nil then minX = value.x end
  if minX == nil then minX = 0 end
  local minY = value.minY
  if minY == nil then minY = value.y end
  if minY == nil then minY = 0 end

  local maxX = value.maxX
  local maxY = value.maxY
  if maxX == nil and isInteger(value.width) then
    maxX = minX + value.width - 1
  end
  if maxY == nil and isInteger(value.height) then
    maxY = minY + value.height - 1
  end

  if not isInteger(minX) or not isInteger(minY)
     or not isInteger(maxX) or not isInteger(maxY) then
    return nil, "bounds require finite integer min/max coordinates or width/height"
  end
  if maxX < minX or maxY < minY then
    return nil, "bounds must describe a non-empty rectangle"
  end

  return { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
end

local function inBounds(bounds, x, y)
  return x >= bounds.minX and x <= bounds.maxX
     and y >= bounds.minY and y <= bounds.maxY
end

local function addGoal(goals, goalSet, value, label, bounds)
  local x, y, err = coordinates(value, label)
  if err then return nil, err end
  if not inBounds(bounds, x, y) then
    return nil, label .. " is outside bounds"
  end
  local key = cellKey(x, y)
  if not goalSet[key] then
    goals[#goals + 1] = { x = x, y = y, key = key }
    goalSet[key] = true
  end
  return true
end

local function normalizeGoals(options, bounds)
  local goals, goalSet = {}, {}

  if options.goal ~= nil then
    local ok, err = addGoal(goals, goalSet, options.goal, "goal", bounds)
    if not ok then return nil, nil, err end
  end

  if options.goals ~= nil then
    if type(options.goals) ~= "table" then
      return nil, nil, "goals must be an array of cells"
    end
    -- Accept a cell directly as a convenience, but otherwise require a
    -- dense array so silently skipped holes cannot change a selected target.
    local directX = options.goals.x
    if directX == nil then directX = options.goals.cellX end
    if directX ~= nil then
      local ok, err = addGoal(goals, goalSet, options.goals, "goals", bounds)
      if not ok then return nil, nil, err end
    else
      local count = #options.goals
      for index = 1, count do
        if options.goals[index] == nil then
          return nil, nil, "goals must be a dense array"
        end
        local ok, err = addGoal(goals, goalSet, options.goals[index],
          "goal " .. tostring(index), bounds)
        if not ok then return nil, nil, err end
      end
    end
  end

  if #goals == 0 then
    return nil, nil, "at least one goal is required"
  end
  return goals, goalSet
end

local function addBlocked(blocked, x, y)
  if isInteger(x) and isInteger(y) then
    blocked[cellKey(x, y)] = true
  end
end

local function addBlockedRecord(blocked, value, label, blockIgnorable)
  if type(value) ~= "table" then
    return nil, label .. " must be a cell table"
  end
  if value.ignorable == true and not blockIgnorable then return true end

  local x, y, err = coordinates(value, label)
  if err then return nil, err end
  addBlocked(blocked, x, y)

  -- Runtime entities may reserve the cell they are stepping into.  Supporting
  -- these optional fields keeps the core useful without depending on Entity.
  if value.targetX ~= nil or value.targetY ~= nil then
    if not isInteger(value.targetX) or not isInteger(value.targetY) then
      return nil, label .. " target coordinates must be finite integers"
    end
    addBlocked(blocked, value.targetX, value.targetY)
  end
  return true
end

local function normalizeBlocked(options)
  if options.ignoreBlocked ~= nil and type(options.ignoreBlocked) ~= "boolean" then
    return nil, "ignoreBlocked must be boolean"
  end
  if options.blockIgnorable ~= nil and type(options.blockIgnorable) ~= "boolean" then
    return nil, "blockIgnorable must be boolean"
  end
  if options.ignoreBlocked == true or options.blockedCells == nil then return {} end
  if type(options.blockedCells) ~= "table" then
    return nil, "blockedCells must be an array or coordinate-keyed set"
  end

  local blocked = {}
  local seenNumeric = {}
  for index, value in ipairs(options.blockedCells) do
    seenNumeric[index] = true
    local ok, err = addBlockedRecord(blocked, value,
      "blocked cell " .. tostring(index), options.blockIgnorable == true)
    if not ok then return nil, err end
  end

  -- A keyed set is convenient for callers that already index occupancy.
  -- Keys use "x,y" (not the private internal key) to remain readable.
  for key, value in pairs(options.blockedCells) do
    if not (type(key) == "number" and seenNumeric[key]) then
      if type(key) == "string" and value then
        local sx, sy = key:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
        if not sx then
          return nil, "blocked cell set keys must use x,y coordinates"
        end
        local ignorable = type(value) == "table" and value.ignorable == true
        if not ignorable or options.blockIgnorable == true then
          addBlocked(blocked, tonumber(sx), tonumber(sy))
        end
      else
        return nil, "blockedCells must be a dense array or x,y keyed set"
      end
    end
  end
  return blocked
end

local function heuristic(x, y, goals, customNeighbors)
  -- A custom edge may travel multiple cells for one action. Manhattan distance
  -- could then overestimate, so custom graphs use Dijkstra's admissible zero
  -- heuristic. Vanilla cardinal searches retain A* behavior.
  if customNeighbors then return 0 end
  local best
  for index = 1, #goals do
    local goal = goals[index]
    local distance = math.abs(goal.x - x) + math.abs(goal.y - y)
    if best == nil or distance < best then best = distance end
  end
  return best
end

local function nodeBefore(a, b)
  if a.f ~= b.f then return a.f < b.f end
  if a.h ~= b.h then return a.h < b.h end
  return a.sequence < b.sequence
end

local function heapPush(heap, node)
  local index = #heap + 1
  heap[index] = node
  while index > 1 do
    local parent = math.floor(index / 2)
    if not nodeBefore(node, heap[parent]) then break end
    heap[index] = heap[parent]
    index = parent
  end
  heap[index] = node
end

local function heapPop(heap)
  local root = heap[1]
  local last = heap[#heap]
  heap[#heap] = nil
  if #heap == 0 then return root end

  local index = 1
  while true do
    local left = index * 2
    if left > #heap then break end
    local right = left + 1
    local child = left
    if right <= #heap and nodeBefore(heap[right], heap[left]) then child = right end
    if not nodeBefore(heap[child], last) then break end
    heap[index] = heap[child]
    index = child
  end
  heap[index] = last
  return root
end

local function copyCell(x, y)
  return { x = x, y = y }
end

local function buildResult(goalNode, startKey, cameFrom, expanded)
  local reverseCells = { copyCell(goalNode.x, goalNode.y) }
  local reverseEdges = {}
  local currentKey = goalNode.key

  while currentKey ~= startKey do
    local edge = cameFrom[currentKey]
    -- All reached non-start nodes have an edge.  Keep this check controlled
    -- in case a future change corrupts reconstruction rather than looping.
    if not edge then return nil, "path reconstruction failed" end
    reverseEdges[#reverseEdges + 1] = edge
    reverseCells[#reverseCells + 1] = copyCell(edge.fromX, edge.fromY)
    currentKey = edge.fromKey
  end

  local directions, edges, cells = {}, {}, {}
  for index = #reverseEdges, 1, -1 do
    local edge = reverseEdges[index]
    directions[#directions + 1] = edge.direction
    edges[#edges + 1] = edge
  end
  for index = #reverseCells, 1, -1 do
    cells[#cells + 1] = reverseCells[index]
  end

  local steps = {}
  for index = 1, #directions do
    local edge = edges[index]
    steps[index] = {
      direction = directions[index],
      fromX = cells[index].x,
      fromY = cells[index].y,
      x = cells[index + 1].x,
      y = cells[index + 1].y,
      kind = edge.kind,
      instruction = edge.instruction,
    }
  end

  return {
    directions = directions,
    cells = cells,
    steps = steps,
    cost = goalNode.g,
    actionCount = #directions,
    goal = copyCell(goalNode.x, goalNode.y),
    expanded = expanded,
  }
end

local function neighborEdges(options, node, bounds)
  if type(options.neighbors) ~= "function" then
    local edges = {}
    for index = 1, #DIRECTIONS do
      local direction = DIRECTIONS[index]
      local x, y = node.x + direction.dx, node.y + direction.dy
      if inBounds(bounds, x, y) then
        edges[#edges + 1] = {
          x = x, y = y, direction = direction.name, cost = 1,
        }
      end
    end
    return edges
  end

  local ok, supplied = pcall(options.neighbors, node.x, node.y, options.policy)
  if not ok then return nil, "neighbors callback failed: " .. safeString(supplied) end
  if type(supplied) ~= "table" then
    return nil, "neighbors callback must return an array"
  end
  local edges = {}
  for index = 1, #supplied do
    local value = supplied[index]
    if type(value) ~= "table" then
      return nil, "neighbor " .. tostring(index) .. " must be a table"
    end
    local x = value.x
    if x == nil then x = value.toX end
    local y = value.y
    if y == nil then y = value.toY end
    if not isInteger(x) or not isInteger(y) then
      return nil, "neighbor " .. tostring(index)
        .. " coordinates must be finite integers"
    end
    if not VALID_DIRECTION[value.direction] then
      return nil, "neighbor " .. tostring(index) .. " has invalid direction"
    end
    local cost = value.cost == nil and 1 or value.cost
    if type(cost) ~= "number" or cost ~= cost or cost <= 0
       or cost == math.huge then
      return nil, "neighbor " .. tostring(index) .. " cost must be positive"
    end
    if inBounds(bounds, x, y) then
      edges[#edges + 1] = {
        x = x, y = y, direction = value.direction, cost = cost,
        kind = type(value.kind) == "string" and value.kind or nil,
        instruction = type(value.instruction) == "string"
                      and value.instruction or nil,
      }
    end
  end
  return edges
end

local function findImpl(options)
  if type(options) ~= "table" then return nil, "options must be a table" end
  if type(options.canTraverse) ~= "function" then
    return nil, "canTraverse callback is required"
  end

  local bounds, boundsErr = normalizeBounds(options.bounds)
  if not bounds then return nil, boundsErr end

  local startX, startY, startErr = coordinates(options.start, "start")
  if startErr then return nil, startErr end
  if not inBounds(bounds, startX, startY) then
    return nil, "start is outside bounds"
  end

  local goals, goalSet, goalsErr = normalizeGoals(options, bounds)
  if not goals then return nil, goalsErr end

  local blocked, blockedErr = normalizeBlocked(options)
  if not blocked then return nil, blockedErr end

  if options.allowBlockedGoal ~= nil
     and type(options.allowBlockedGoal) ~= "boolean" then
    return nil, "allowBlockedGoal must be boolean"
  end
  local allowBlockedGoal = options.allowBlockedGoal ~= false

  local width = bounds.maxX - bounds.minX + 1
  local height = bounds.maxY - bounds.minY + 1
  local area = width * height
  if area ~= area or area == math.huge then return nil, "bounds are too large" end

  local maxNodes = options.maxNodes
  if maxNodes == nil then maxNodes = math.min(area, 100000) end
  if not isInteger(maxNodes) or maxNodes < 1 then
    return nil, "maxNodes must be a positive integer"
  end
  if options.isCancelled ~= nil and type(options.isCancelled) ~= "function" then
    return nil, "isCancelled must be a function"
  end
  if options.maxSeconds ~= nil
     and (type(options.maxSeconds) ~= "number"
          or options.maxSeconds ~= options.maxSeconds
          or options.maxSeconds <= 0 or options.maxSeconds == math.huge) then
    return nil, "maxSeconds must be a positive finite number"
  end
  if options.clock ~= nil and type(options.clock) ~= "function" then
    return nil, "clock must be a function"
  end
  local yieldEvery = options._yieldEvery
  if yieldEvery ~= nil and (not isInteger(yieldEvery) or yieldEvery < 1) then
    return nil, "yield interval must be a positive integer"
  end
  local clock = options.clock or os.clock
  local started
  if options.maxSeconds then
    local clockOK, value = pcall(clock)
    if not clockOK or type(value) ~= "number" then
      return nil, "clock callback failed"
    end
    started = value
  end

  local function interruption(expanded)
    if options.isCancelled then
      local ok, cancelled = pcall(options.isCancelled, expanded)
      if not ok then
        return "isCancelled callback failed: " .. safeString(cancelled)
      end
      if cancelled then return "cancelled" end
    end
    if started then
      local ok, now = pcall(clock)
      if not ok or type(now) ~= "number" then return "clock callback failed" end
      if now - started >= options.maxSeconds then return "time limit exceeded" end
    end
    return nil
  end

  local startKey = cellKey(startX, startY)
  if goalSet[startKey] then
    return {
      directions = {},
      cells = { copyCell(startX, startY) },
      steps = {},
      cost = 0,
      goal = copyCell(startX, startY),
      expanded = 0,
    }
  end

  local sequence = 1
  local customNeighbors = type(options.neighbors) == "function"
  local startH = heuristic(startX, startY, goals, customNeighbors)
  local open = {}
  heapPush(open, {
    x = startX, y = startY, key = startKey,
    g = 0, h = startH, f = startH, sequence = sequence,
  })

  local scores = { [startKey] = 0 }
  local cameFrom = {}
  local closed = {}
  local expanded = 0

  while #open > 0 do
    local node = heapPop(open)
    if not closed[node.key] and scores[node.key] == node.g then
      if goalSet[node.key] then
        return buildResult(node, startKey, cameFrom, expanded)
      end

      expanded = expanded + 1
      if expanded > maxNodes then return nil, "node limit exceeded" end
      local interrupted = interruption(expanded)
      if interrupted then return nil, interrupted end
      if yieldEvery and expanded % yieldEvery == 0 then
        coroutine.yield({ expanded = expanded, maxNodes = maxNodes })
      end
      closed[node.key] = true

      local candidates, neighborError = neighborEdges(options, node, bounds)
      if not candidates then return nil, neighborError end
      for index = 1, #candidates do
        local edge = candidates[index]
        local toX, toY = edge.x, edge.y
        local nextKey = cellKey(toX, toY)
        local goalException = goalSet[nextKey] and allowBlockedGoal
        if (not blocked[nextKey] or goalException) and not closed[nextKey] then
          local ok, allowed = pcall(options.canTraverse,
            node.x, node.y, toX, toY, edge.direction, options.policy, edge)
          if not ok then
            return nil, "canTraverse callback failed: " .. safeString(allowed)
          end
          if allowed then
            local tentative = node.g + edge.cost
            if scores[nextKey] == nil or tentative < scores[nextKey] then
              scores[nextKey] = tentative
              cameFrom[nextKey] = {
                fromKey = node.key,
                fromX = node.x,
                fromY = node.y,
                direction = edge.direction,
                cost = edge.cost,
                kind = edge.kind,
                instruction = edge.instruction,
              }
              local h = heuristic(toX, toY, goals, customNeighbors)
              sequence = sequence + 1
              heapPush(open, {
                x = toX, y = toY, key = nextKey,
                g = tentative, h = h, f = tentative + h,
                sequence = sequence,
              })
            end
          end
        end
      end
    end
  end

  return nil, "no path"
end

-- Returns a shortest cardinal route or nil,error.  The pcall boundary also
-- contains hostile/broken mod metamethods, while callback failures receive a
-- more specific error from findImpl.
function Pathfinder.find(options)
  local ok, result, err = pcall(findImpl, options)
  if not ok then return nil, "pathfinder failed: " .. safeString(result) end
  return result, err
end

-- Cooperative search task for frame-driven callers. Each step resumes at most
-- `yieldEvery` expanded nodes; cancel() is observed at the next safe boundary.
-- The synchronous find() API remains unchanged for deterministic unit callers.
function Pathfinder.start(options, taskOptions)
  if type(options) ~= "table" then return nil, "options must be a table" end
  taskOptions = taskOptions or {}
  if type(taskOptions) ~= "table" then return nil, "task options must be a table" end
  local yieldEvery = taskOptions.yieldEvery or 128
  if not isInteger(yieldEvery) or yieldEvery < 1 then
    return nil, "yieldEvery must be a positive integer"
  end

  local copied = {}
  for key, value in pairs(options) do copied[key] = value end
  local cancelled = false
  local callerCancellation = copied.isCancelled
  copied._yieldEvery = yieldEvery
  copied.isCancelled = function(expanded)
    if cancelled then return true end
    if callerCancellation then return callerCancellation(expanded) end
    return false
  end

  local task = { done = false, result = nil, error = nil, progress = nil }
  local thread = coroutine.create(function() return findImpl(copied) end)
  function task:cancel() cancelled = true end
  function task:step()
    if self.done then return true, self.result, self.error, self.progress end
    local ok, first, second = coroutine.resume(thread)
    if not ok then
      self.done = true
      self.error = "pathfinder failed: " .. safeString(first)
    elseif coroutine.status(thread) == "dead" then
      self.done = true
      self.result, self.error = first, second
    else
      self.progress = first
    end
    return self.done, self.result, self.error, self.progress
  end
  return task
end

local function readableLabel(labels, direction)
  local label = labels and labels[direction]
  if type(label) ~= "string" then label = direction end
  label = label:gsub("[%c%s]+", " "):match("^%s*(.-)%s*$")
  if label == "" then label = direction end
  return label
end

local function groupImpl(route, options)
  if type(route) ~= "table" then return nil, "route must be a direction array" end
  local directions = route.directions or route
  if type(directions) ~= "table" then
    return nil, "route directions must be an array"
  end
  options = options or {}
  if type(options) ~= "table" then return nil, "narration options must be a table" end
  if options.labels ~= nil and type(options.labels) ~= "table" then
    return nil, "narration labels must be a table"
  end

  local groups = {}
  for index = 1, #directions do
    local direction = directions[index]
    if not VALID_DIRECTION[direction] then
      return nil, "invalid direction at index " .. tostring(index)
    end
    local group = groups[#groups]
    if group and group.direction == direction then
      group.count = group.count + 1
      group.text = tostring(group.count) .. " "
        .. readableLabel(options.labels, direction)
    else
      groups[#groups + 1] = {
        direction = direction,
        count = 1,
        text = "1 " .. readableLabel(options.labels, direction),
      }
    end
  end
  return groups
end

-- Groups only consecutive moves and preserves path order, matching Pokemon
-- Access's route narration (one queued utterance per returned segment).
function Pathfinder.groupDirections(route, options)
  local ok, result, err = pcall(groupImpl, route, options)
  if not ok then return nil, "narration failed: " .. safeString(result) end
  return result, err
end

function Pathfinder.narrateDirections(route, options)
  local groups, err = Pathfinder.groupDirections(route, options)
  if not groups then return nil, err end
  local output = {}
  for index = 1, #groups do output[index] = groups[index].text end
  return output
end

return Pathfinder
