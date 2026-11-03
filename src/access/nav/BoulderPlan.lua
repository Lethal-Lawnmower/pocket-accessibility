-- Whole-floor Strength search for Red, Blue and Yellow (decision 41's auto-push,
-- in Gen 1).  Read-only: nothing here moves a boulder.  Any boulder may be pushed;
-- the rules are the game's own (OverworldState:checkBoulderPush): the landing is a
-- walkable cell, no tile-pair wall from the pushing cell, not tile 0x15, nothing
-- standing there.  The player stays on the pushing cell after a push.  No map is
-- named here: targets and cells to avoid come from the caller.
--
-- BoulderPlan.fill plans until a boulder lands on any target (a hole or a pressure
-- switch); BoulderPlan.opening plans until the player can reach one of some cells.
-- Both return the list of pushes, or nil with "budget" when the search ran out.

local Collision = require("src.world.Collision")
local Map = require("src.world.Map")

local BoulderPlan = {}

local DIRS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }
local NO_PUSH_TILE = 0x15

local function heapPush(heap, node)
  heap[#heap + 1] = node
  local i = #heap
  while i > 1 do
    local parent = math.floor(i / 2)
    if heap[parent].f <= node.f then break end
    heap[i], heap[parent] = heap[parent], node
    i = parent
  end
end

local function heapPop(heap)
  local top = heap[1]
  local last = table.remove(heap)
  if #heap > 0 then
    heap[1] = last
    local i = 1
    while true do
      local l, r, smallest = i * 2, i * 2 + 1, i
      if heap[l] and heap[l].f < heap[smallest].f then smallest = l end
      if heap[r] and heap[r].f < heap[smallest].f then smallest = r end
      if smallest == i then break end
      heap[i], heap[smallest] = heap[smallest], heap[i]
      i = smallest
    end
  end
  return top
end

-- The floor as the search sees it.  `avoid` holds cells no boulder may land on and
-- `noStand` cells the player may not step on ("x,y" keys: warps, holes; a house-style
-- exit mat fires only when pressed outward, so a player can stand on it to push, and
-- Victory Road 1F needs that); `ledge(x, y, dir)` answers where a ledge hop lands.
local function floorModel(world, avoid, noStand, ledge)
  local map = world.map
  local width, height = map.widthCells, map.heightCells
  local land, avoided, blockedStand, fixed, boulders = {}, {}, {}, {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local i = y * width + x
      land[i] = map:isWalkableCell(x, y) == true
      avoided[i] = avoid[x .. "," .. y] == true
      blockedStand[i] = noStand[x .. "," .. y] == true
    end
  end
  for _, entity in ipairs(world.entities or world.npcs or {}) do
    if entity ~= world.player and type(entity) == "table" then
      if type(entity.def) == "table" and Map.isPushable(entity.def) then
        boulders[#boulders + 1] = { entity = entity, start = entity.cellY * width + entity.cellX }
      elseif not entity.passable then
        fixed[entity.cellY * width + entity.cellX] = true
      end
    end
  end
  -- the player's steps, worked out once: walls and tile pairs do not change here
  local steps = {}
  local mover = { cellX = 0, cellY = 0, surfing = false }
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local i = y * width + x
      local list = {}
      for _, d in ipairs(DIRS) do
        local nx, ny = ledge and ledge(x, y, d[1])
        if nx then
          list[#list + 1] = ny * width + nx
        else
          local tx, ty = x + d[2], y + d[3]
          if tx >= 0 and ty >= 0 and tx < width and ty < height then
            mover.cellX, mover.cellY = x, y
            if Collision.canMove(map, {}, mover, d[1]) then
              list[#list + 1] = ty * width + tx
            end
          end
        end
      end
      steps[i] = list
    end
  end
  return { map = map, width = width, height = height, land = land, avoided = avoided, noStand = blockedStand,
    fixed = fixed, boulders = boulders, steps = steps }
end

local function playerRegion(model, start, occupied, extra)
  local seen, queue, head, rep = { [start] = true }, { start }, 1, start
  while queue[head] do
    local i = queue[head]
    head = head + 1
    for _, n in ipairs(model.steps[i]) do
      if not seen[n] and not occupied[n] and not model.fixed[n] and model.land[n]
         and (not model.noStand[n] or (extra and extra[n])) then
        seen[n] = true
        queue[#queue + 1] = n
        if n < rep then rep = n end
      end
    end
  end
  return seen, rep
end

local function canPush(model, bx, by, d, allowed)
  local map, width = model.map, model.width
  local sx, sy = bx - d[2], by - d[3]
  local lx, ly = bx + d[2], by + d[3]
  if lx < 0 or ly < 0 or lx >= width or ly >= model.height then return nil end
  if sx < 0 or sy < 0 or sx >= width or sy >= model.height then return nil end
  local li = ly * width + lx
  if not model.land[li] or model.fixed[li] then return nil end
  if model.avoided[li] and not (allowed and allowed[li]) then return nil end
  if map:cellTile(lx, ly) == NO_PUSH_TILE then return nil end
  if Collision.pairBlocked(map, {}, sx, sy, lx, ly) then return nil end
  return li, sy * width + sx
end

-- For each cell, how many pushes it takes to bring a boulder from there to `target`
-- on an otherwise empty floor (missing: it can never get there).
local function pushDistances(model, targetIndex, allowed)
  local width, height = model.width, model.height
  local dist = { [targetIndex] = 0 }
  local queue, head = { targetIndex }, 1
  while queue[head] do
    local n = queue[head]
    head = head + 1
    local nx, ny = n % width, math.floor(n / width)
    for _, d in ipairs(DIRS) do
      local cx, cy = nx - d[2], ny - d[3]
      if cx >= 0 and cy >= 0 and cx < width and cy < height then
        local c = cy * width + cx
        if not dist[c] and model.land[c] and not model.avoided[c] and not model.fixed[c] then
          local li, si = canPush(model, cx, cy, d, allowed)
          if li == n and si and model.land[si] and not model.noStand[si] then
            dist[c] = dist[n] + 1
            queue[#queue + 1] = c
          end
        end
      end
    end
  end
  return dist
end

local function stateKey(positions, rep)
  local sorted = {}
  for i, pos in ipairs(positions) do sorted[i] = pos end
  table.sort(sorted)
  return table.concat(sorted, ",") .. "|" .. rep
end

local function pathOf(node)
  local path = {}
  while node and node.push do
    table.insert(path, 1, node.push)
    node = node.parent
  end
  return path
end

-- The search shared by both goals.  `check(li, region)` says a push reached the goal.
local function search(model, world, opts)
  local width = model.width
  local player = world.player
  local positions, occupied = {}, {}
  for i, b in ipairs(model.boulders) do
    positions[i] = b.start
    occupied[b.start] = true
  end
  local start = player.cellY * width + player.cellX
  local region, rep = playerRegion(model, start, occupied, opts.standExtra)
  local h0 = opts.heuristic(positions)
  if h0 == nil then return nil end
  local heap = {}
  heapPush(heap, { positions = positions, region = region, g = 0, f = h0 })
  local visited = { [stateKey(positions, rep)] = true }
  local expanded, maxExpanded = 0, opts.maxExpanded or 60000
  local deadline = os.clock() + (opts.maxSeconds or 1.5)
  while #heap > 0 do
    local node = heapPop(heap)
    expanded = expanded + 1
    if expanded > maxExpanded or os.clock() > deadline then return nil, "budget" end
    local taken = {}
    for _, pos in ipairs(node.positions) do taken[pos] = true end
    for bi, b in ipairs(model.boulders) do
      local pos = node.positions[bi]
      local bx, by = pos % width, math.floor(pos / width)
      for _, d in ipairs(DIRS) do
        local li, si = canPush(model, bx, by, d, opts.allowedLanding)
        if li and node.region[si] and not taken[li] then
          local push = { boulder = b, fromX = bx, fromY = by, toX = bx + d[2], toY = by + d[3],
            standX = bx - d[2], standY = by - d[3], direction = d[1] }
          local nextPositions, nextTaken = {}, {}
          for i, p in ipairs(node.positions) do
            nextPositions[i] = i == bi and li or p
            nextTaken[nextPositions[i]] = true
          end
          local nextRegion, nextRep = playerRegion(model, si, nextTaken, opts.standExtra)
          local child = { parent = node, push = push }
          if opts.check(li, nextRegion) then return pathOf(child) end
          local key = stateKey(nextPositions, nextRep)
          if not visited[key] then
            visited[key] = true
            local h = opts.heuristic(nextPositions)
            if h ~= nil then
              child.positions, child.region, child.g = nextPositions, nextRegion, node.g + 1
              child.f = child.g + (opts.weight or 1) * h
              heapPush(heap, child)
            end
          end
        end
      end
    end
  end
  return nil
end

-- Until a boulder lands on any of `targets` ({ x, y }): the pushes, or nil.
function BoulderPlan.fill(world, targets, avoid, noStand, ledge, budget)
  local model = floorModel(world, avoid, noStand, ledge)
  local width = model.width
  local allowed, distances = {}, {}
  for _, target in ipairs(targets) do
    allowed[target.y * width + target.x] = true
  end
  for _, target in ipairs(targets) do
    distances[#distances + 1] = pushDistances(model, target.y * width + target.x, allowed)
  end
  local function liveCount(positions)
    local live = 0
    for _, pos in ipairs(positions) do
      for _, dist in ipairs(distances) do
        if dist[pos] then live = live + 1 break end
      end
    end
    return live
  end
  local startPositions = {}
  for i, b in ipairs(model.boulders) do startPositions[i] = b.start end
  -- never park so many boulders that a target this floor could fill loses its last hope
  local need = math.min(#targets, liveCount(startPositions))
  if need == 0 then return nil end
  budget = budget or {}
  return search(model, world, {
    allowedLanding = allowed,
    weight = 2,
    maxSeconds = budget.maxSeconds, maxExpanded = budget.maxExpanded,
    heuristic = function(positions)
      if liveCount(positions) < need then return nil end
      local best
      for _, pos in ipairs(positions) do
        for _, dist in ipairs(distances) do
          local value = dist[pos]
          if value and (not best or value < best) then best = value end
        end
      end
      return best
    end,
    check = function(li) return allowed[li] == true end,
  })
end

-- Until the player can reach one of `goals`: the pushes, or nil.  { } and "open" when
-- no push is needed.
function BoulderPlan.opening(world, goals, avoid, noStand, ledge, budget)
  local model = floorModel(world, avoid, noStand, ledge)
  local width = model.width
  local goalCell = {}
  for _, goal in ipairs(goals or {}) do goalCell[goal.y * width + goal.x] = true end
  local function reaches(region)
    for i in pairs(goalCell) do if region[i] then return true end end
    return false
  end
  local occupied = {}
  for _, b in ipairs(model.boulders) do occupied[b.start] = true end
  local start = world.player.cellY * width + world.player.cellX
  if reaches(playerRegion(model, start, occupied, goalCell)) then return {}, "open" end
  if #model.boulders == 0 then return nil end
  budget = budget or {}
  return search(model, world, {
    standExtra = goalCell,
    maxSeconds = budget.maxSeconds, maxExpanded = budget.maxExpanded,
    heuristic = function() return 0 end,
    check = function(_, region) return reaches(region) end,
  })
end

return BoulderPlan
