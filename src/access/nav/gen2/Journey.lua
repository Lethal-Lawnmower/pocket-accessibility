-- One-pass journey search for Gold, Silver and Crystal.  The shared planner
-- (RegionalPathfinder.lua) runs a full route for every transition of every map it
-- expands, which used up its time on floors with many warps (every Ice Path floor,
-- Dark Cave, Whirl Islands): "Could not plan a route".  This walks the movement graph
-- of each map once, cell by cell, across warps and connections, so its cost is the
-- cells of the maps it touches.  Read-only.  FireRed has the same idea in
-- gen3/Navigation.lua, with its elevators and thin ice on top.

local Permissions = require("src.world.gen2.Permissions")

local Journey = {}

local function push(heap, node)
  heap[#heap + 1] = node
  local i = #heap
  while i > 1 do
    local parent = math.floor(i / 2)
    local a, b = heap[parent], heap[i]
    if a.cost < b.cost or (a.cost == b.cost and a.seq <= b.seq) then break end
    heap[parent], heap[i] = b, a
    i = parent
  end
end

local function pop(heap)
  local top = heap[1]
  local last = table.remove(heap)
  local size = #heap
  if size > 0 then
    heap[1] = last
    local i = 1
    while true do
      local left, right, smallest = i * 2, i * 2 + 1, i
      local function smaller(a, b)
        return a.cost < b.cost or (a.cost == b.cost and a.seq < b.seq)
      end
      if left <= size and smaller(heap[left], heap[smallest]) then smallest = left end
      if right <= size and smaller(heap[right], heap[smallest]) then smallest = right end
      if smallest == i then break end
      heap[i], heap[smallest] = heap[smallest], heap[i]
      i = smallest
    end
  end
  return top
end

local function cellKey(x, y) return x .. "," .. y end

-- One map as the search sees it: the live world for the map the player is on, a
-- planned one otherwise; its movement graph with every transition and target cell
-- allowed as an end (warps are walls to the graph otherwise); its transitions by cell.
local function journeyMap(nav, mapId, policy, target, live)
  local world = live
  if not (live and nav:currentMapIdOf(live) == mapId) then
    world = nav:regionalStaticWorld(mapId, { x = 0, y = 0 })
  end
  if not world then return nil end
  local byCell, goals = {}, {}
  for _, transition in ipairs(nav:regionalTransitions(mapId)) do
    local key = cellKey(transition.x, transition.y)
    if not byCell[key] then
      byCell[key] = {}
      goals[#goals + 1] = { x = transition.x, y = transition.y }
    end
    table.insert(byCell[key], transition)
  end
  local targetSet = {}
  if mapId == target.mapId then
    for _, goal in ipairs(target.goals) do
      targetSet[cellKey(goal.x, goal.y)] = true
      goals[#goals + 1] = { x = goal.x, y = goal.y }
    end
  end
  if #goals == 0 then goals[1] = { x = 0, y = 0 } end
  local options = nav:routeOptionsFor(world, goals, policy)
  if not options then return nil end
  return { world = world, map = world.map, neighbors = options.neighbors,
    byCell = byCell, targetSet = targetSet }
end

-- The cheapest way from start ({ mapId, x, y }) to any cell of target ({ mapId, goals })
-- at one route policy, over the maps `allowed` admits (nil: any), until `deadline`
-- (os.clock).  Returns { firstTransition, final, cost, legs, maps }, or nil and
-- "no regional path" or "regional search timed out".
function Journey.search(nav, start, target, policy, allowed, deadline)
  local live = nav:worldForCommand()
  local maps = {}
  local function mapOf(mapId)
    local entry = maps[mapId]
    if entry == nil then
      entry = journeyMap(nav, mapId, policy, target, live) or false
      maps[mapId] = entry
    end
    return entry or nil
  end
  -- A node is a cell reached by walking (a warp under it fires) or by arriving through
  -- a transition (the player stands on the warp they came out of and may walk off it).
  local function nodeKey(mapId, x, y, arrived)
    return mapId .. ":" .. x .. "," .. y .. (arrived and "a" or "w")
  end
  local seq = 1
  local heap = { { mapId = start.mapId, x = start.x, y = start.y, arrived = true, cost = 0, hops = 0, seq = seq } }
  local best = { [nodeKey(start.mapId, start.x, start.y, true)] = 0 }
  local function reach(node)
    local key = nodeKey(node.mapId, node.x, node.y, node.arrived)
    if best[key] ~= nil and best[key] <= node.cost then return end
    best[key] = node.cost
    seq = seq + 1
    node.seq = seq
    push(heap, node)
  end
  local function finish(node)
    local legs, cursor = {}, node
    while cursor.parent do
      if cursor.step then
        local leg = legs[1]
        if not (leg and leg.mapId == cursor.mapId) then
          leg = { mapId = cursor.mapId, steps = {} }
          table.insert(legs, 1, leg)
        end
        table.insert(leg.steps, 1, cursor.step)
      end
      cursor = cursor.parent
    end
    return { firstTransition = node.firstTransition, final = node.hops == 0,
      cost = node.cost, legs = legs, maps = maps }
  end
  local expanded = 0
  while #heap > 0 do
    local node = pop(heap)
    if best[nodeKey(node.mapId, node.x, node.y, node.arrived)] == node.cost then
      expanded = expanded + 1
      if expanded % 64 == 0 and os.clock() > deadline then return nil, "regional search timed out" end
      local entry = mapOf(node.mapId)
      if entry then
        local cell = cellKey(node.x, node.y)
        if entry.targetSet[cell] then return finish(node) end
        local map = entry.map
        local fires = not node.arrived and map:warpAt(node.x, node.y) ~= nil
          and Permissions.isWarpCollision(map:cellCollision(node.x, node.y))
        for _, transition in ipairs(entry.byCell[cell] or {}) do
          if (transition.kind == "connection" or fires)
             and (not allowed or allowed[transition.destMap]) then
            reach({ mapId = transition.destMap, x = transition.destX, y = transition.destY,
              arrived = true, cost = node.cost + 1, hops = node.hops + 1, parent = node,
              firstTransition = node.firstTransition or transition })
          end
        end
        if not fires then
          for _, edge in ipairs(entry.neighbors(node.x, node.y)) do
            reach({ mapId = node.mapId, x = edge.x, y = edge.y, arrived = false,
              cost = node.cost + 1, hops = node.hops, parent = node,
              firstTransition = node.firstTransition,
              step = { fromX = node.x, fromY = node.y, x = edge.x, y = edge.y,
                direction = edge.direction, kind = edge.kind, instruction = edge.instruction } })
          end
        end
      end
    end
  end
  return nil, "no regional path"
end

return Journey
