-- Strength puzzle help for FireRed (decision 29): Victory Road's floor
-- switches and Seafoam Islands' holes, and any other floor that has
-- Strength boulders and a switch or a hole.  Read-only: nothing here moves
-- a boulder or sets a flag.
--
-- Everything comes from the floor itself, not from hand-written tables:
--   boulders   objects drawn as OBJ_EVENT_GFX_PUSHABLE_BOULDER (97), the
--              graphics the game's own push test checks (player.lua tryMove)
--   switches   MB_STRENGTH_BUTTON (0x20) cells; pressed while a boulder
--              stands on one (Field.onBoulderMoved runs the switch's coord
--              event when a boulder arrives)
--   holes      MB_FALL_WARP (0x66) cells: a boulder pushed in falls to the
--              floor below (Field.onBoulderMoved's fall warp)
--   a push     the boulder's own move test: the cell beyond must be land
--              (not water, not a cave door, no directional wall, a matching
--              elevation) or a hole, and free of objects; the player stays
--              where they stood (the push walks in place)
--
-- The search follows the Gen 2 floor search (gen2/PuzzleAssistance.planFloor:
-- A* over pushes, dead squares pruned, any boulder may move) with Gen 3's
-- rules.  On a floor with switches the plan covers every open switch at
-- once (boulders stay on switches; the Tanoby Key room needs all seven, and
-- pressing the nearest switch first can block the rest); otherwise the plan
-- drops one boulder into a hole or onto one switch.  The whole plan is kept
-- and followed push by push while the boulders stand where it has them; a
-- search that needs more than one request's time carries on across frames
-- (until then the help says it is still working, never a guessed push).
-- The answer is the plan's next push.  Elevation is read
-- per cell for the boulder as for the player (objects take the elevation of
-- the cell they stand on; 0 and 15 match anything).  Gen 1's Victory Road
-- tables do not apply: FireRed's maps are redrawn on 16-pixel cells.
--
-- What the player still lacks is said first: a Pokemon with Strength, the
-- Rainbow Badge, or Strength switched on (FLAG_SYS_USE_STRENGTH, set by
-- answering yes at a boulder; cleared on every map change).

local Shared = require("src.access.nav.PuzzleAssistance")
local Terrain = require("src.access.nav.gen3.TerrainSemantics")

local Puzzle = {}
for key, value in pairs(Shared) do Puzzle[key] = value end

local MB_STRENGTH_BUTTON, MB_FALL_WARP, MB_CAVE_DOOR = 0x20, 0x66, 0x60
local DIRS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local isBoulder = Terrain.isBoulder

-- The object-list id the shared snapshot gives a map object.
local function objectId(mapId, entity)
  local def = type(entity) == "table" and entity.def or {}
  return entity.accessibilityId or def.accessibilityId
    or ("object:" .. tostring(mapId) .. ":" .. tostring(def.index or entity.localId))
end
Puzzle.objectId = objectId

-- Elevations that refuse a move (IsElevationMismatchAt): both set, the
-- destination not 0 or 15, and different.
local function elevationsMismatch(from, to)
  if from == nil or to == nil then return false end
  if from == 0 or from == 15 or to == 0 or to == 15 then return false end
  return from ~= to
end
Puzzle.elevationsMismatch = elevationsMismatch

-- The floor's boulders (in object order, numbered from 1), switches and
-- holes.  Returns nil when this is not a puzzle floor.
function Puzzle.targetsFor(world)
  local map = world and world.map
  if type(map) ~= "table" or type(map.behavior) ~= "function" then return nil end
  local boulders = {}
  for _, entity in ipairs(world.npcs or {}) do
    if isBoulder(entity) and not entity.invisible then boulders[#boulders + 1] = entity end
  end
  if #boulders == 0 then return nil end
  table.sort(boulders, function(a, b)
    local ia = tonumber(a.def and a.def.index) or tonumber(a.localId) or 0
    local ib = tonumber(b.def and b.def.index) or tonumber(b.localId) or 0
    return ia < ib
  end)
  local occupied = {}
  for number, boulder in ipairs(boulders) do
    occupied[boulder.cellY * 1024 + boulder.cellX] = number
  end
  local targets, switches, holes = {}, 0, 0
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local beh = map:behavior(x, y)
      if beh == MB_STRENGTH_BUTTON then
        switches = switches + 1
        local on = occupied[y * 1024 + x]
        targets[#targets + 1] = { x = x, y = y, kind = "switch",
          label = "Pressure Switch " .. switches, pressedBy = on, solved = on ~= nil }
      elseif beh == MB_FALL_WARP then
        holes = holes + 1
        targets[#targets + 1] = { x = x, y = y, kind = "hole", hole = true,
          label = "Boulder Drop Hole " .. holes, solved = false }
      end
    end
  end
  if #targets == 0 then return nil end
  return targets, boulders
end

-- What stands between the player and a push.
function Puzzle.strengthPrefix(nav)
  if not (nav and type(nav.fieldMoveStatus) == "function") then
    return "Strength availability unknown; "
  end
  local ok, usable, missingMon, missingBadge = pcall(nav.fieldMoveStatus, nav, "STRENGTH")
  if not ok then return "Strength availability unknown; " end
  if not usable then
    if missingMon then return "Needs a party Pok\195\169mon with Strength; " end
    if missingBadge then return "Needs the Rainbow Badge; " end
  end
  if type(nav.strengthActive) == "function" and not nav:strengthActive() then
    return "Use Strength on a boulder first; "
  end
  return ""
end

-- The floor as the search sees it.
local function floorModel(world, targets, boulders)
  local map = world.map
  local width, height = map.widthCells, map.heightCells
  local land, standable, fixed, warpCell, hole, pressDir = {}, {}, {}, {}, {}, {}
  local elevation = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local i = y * width + x
      local beh = map:behavior(x, y)
      elevation[i] = map:elevation(x, y)
      local walk = map:walkableColl(x, y) and not map:isWater(x, y) and not map:overrideBlocked(x, y)
      local warp = map:warpAt(x, y) ~= nil
      hole[i] = beh == MB_FALL_WARP
      warpCell[i] = warp or hole[i]
      land[i] = (walk and beh ~= MB_CAVE_DOOR and not warp) or hole[i]
      -- a mat or stair warp can be stood on, as long as its own direction
      -- is not pressed there (Victory Road 1F's entrance mat)
      pressDir[i] = warp and map.standingWarp and map:standingWarp(x, y) or nil
      standable[i] = walk and (not warpCell[i] or pressDir[i] ~= nil)
        and beh ~= Terrain.MB.CRACKED_ICE
    end
  end
  for _, entity in ipairs(world.npcs or {}) do
    if type(entity) == "table" and not isBoulder(entity) and not entity.passable then
      fixed[entity.cellY * width + entity.cellX] = true
      if entity.moving and entity.targetX then
        fixed[entity.targetY * width + entity.targetX] = true
      end
    end
  end
  local list = {}
  for number, boulder in ipairs(boulders) do
    list[number] = { entity = boulder, number = number,
      start = boulder.cellY * width + boulder.cellX,
      elevation = tonumber(boulder.currentElevation) or 0 }
  end
  -- the step rule per cell and direction, worked out once (the search asks
  -- it many thousands of times)
  local DIR_INDEX = { up = 0, down = 1, left = 2, right = 3 }
  local stepKnown = {}
  local function canStep(x, y, direction, toX, toY)
    local slot = (y * width + x) * 4 + DIR_INDEX[direction]
    local known = stepKnown[slot]
    if known == nil then
      known = not map:dirBlocked(x, y, toX, toY, direction)
        and not elevationsMismatch(elevation[y * width + x], elevation[toY * width + toX])
      stepKnown[slot] = known
    end
    return known
  end
  -- where the player can walk from each cell, other objects counted,
  -- boulders not (playerRegion adds those)
  local walkNext = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local i = y * width + x
      local nexts = {}
      for _, d in ipairs(DIRS) do
        local nx, ny = x + d[2], y + d[3]
        local ni = ny * width + nx
        if nx >= 0 and ny >= 0 and nx < width and ny < height and standable[ni] and not fixed[ni]
           and pressDir[i] ~= d[1] and canStep(x, y, d[1], nx, ny) then
          nexts[#nexts + 1] = ni
        end
      end
      walkNext[i] = nexts
    end
  end
  local model = { map = map, width = width, height = height, land = land, pressDir = pressDir,
    standable = standable, fixed = fixed, warpCell = warpCell, hole = hole,
    boulders = list, elevation = elevation, canStep = canStep, walkNext = walkNext }
  -- Push distances: for each target, the fewest pushes that bring a boulder
  -- from each cell onto it, searched backwards from the target (pulls),
  -- walls and directional walls counted, other boulders not.  A cell with
  -- no distance to any target is a dead square.  `dist[i]` follows the
  -- order of `targets`; unsolved ones only.
  local live, dist = {}, {}
  for index, target in ipairs(targets) do
    if not target.solved then
      local t = target.y * width + target.x
      local d = { [t] = 0 }
      dist[index] = d
      live[t] = true
      local queue, head = { t }, 1
      while head <= #queue do
        local n = queue[head]
        head = head + 1
        local nx, ny = n % width, math.floor(n / width)
        for _, step in ipairs(DIRS) do
          local cx, cy = nx - step[2], ny - step[3]  -- the boulder before the push
          local sx, sy = cx - step[2], cy - step[3]  -- the player pushing it
          local c, s = cy * width + cx, sy * width + sx
          if cx >= 0 and cy >= 0 and cx < width and cy < height
             and sx >= 0 and sy >= 0 and sx < width and sy < height
             and d[c] == nil and land[c] and not hole[c] and standable[s] and pressDir[s] ~= step[1]
             and canStep(cx, cy, step[1], nx, ny) and canStep(sx, sy, step[1], cx, cy) then
            d[c] = d[n] + 1
            live[c] = true
            queue[#queue + 1] = c
          end
        end
      end
    end
  end
  model.live, model.dist = live, dist
  return model
end
Puzzle.floorModel = floorModel

local function playerRegion(model, px, py, occupied)
  local start = py * model.width + px
  local seen, queue, head, rep = { [start] = true }, { start }, 1, start
  local walkNext = model.walkNext
  while head <= #queue do
    local nexts = walkNext[queue[head]]
    head = head + 1
    for k = 1, nexts and #nexts or 0 do
      local ni = nexts[k]
      if not seen[ni] and not occupied[ni] then
        seen[ni] = true
        queue[#queue + 1] = ni
        if ni < rep then rep = ni end
      end
    end
  end
  return seen, rep
end
Puzzle.playerRegion = playerRegion

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

-- One search over pushes (A*, dead squares pruned, any boulder may move).
--   mode "switches": the goal is every open switch with a boulder on it; a
--     boulder that reaches a switch stays there, and none is dropped into a
--     hole (Victory Road, the Tanoby Key room)
--   mode "one": the goal is one boulder on a free switch or in a hole
--     (Seafoam's holes, and floors with fewer boulders than switches)
-- The search is a task: `run(seconds)` searches for that long and returns
-- the plan, or nil and "budget" (call again to carry on from where it
-- stopped), or nil and why there is none.  A plan is its first push
-- { boulder, standX, standY, direction, target, pushes } with every push
-- in `steps` (each with the cell it moves its boulder to) and the floor's
-- boulder cells before each push in `states` (see stateKey).
local function newSearch(world, targets, boulders, budget, mode)
  local goals = {}
  for _, target in ipairs(targets) do
    if not target.solved and (mode == "one" or target.kind == "switch") then
      goals[#goals + 1] = target
    end
  end
  if #goals == 0 then return nil, "no target" end
  local model = floorModel(world, goals, boulders)
  local width, height = model.width, model.height
  local player = world.player
  if not (player and #model.boulders > 0) then return nil, "no boulder" end
  local goalAt = {}
  for index, target in ipairs(goals) do goalAt[target.y * width + target.x] = index end

  -- Estimates in pushes, from the push distances (walls count, other
  -- boulders do not): "one", the nearest boulder to any goal; "switches",
  -- the nearest free boulder for every open switch (not admissible, but it
  -- keeps the whole-floor search short).  A switch no boulder can reach
  -- makes the state hopeless.
  local INF = math.huge
  local function distance(pos, index)
    local d = model.dist[index]
    return d and d[pos] or INF
  end
  local function heuristic(positions, covered)
    if mode == "one" then
      local best = INF
      for _, pos in ipairs(positions) do
        if pos then
          for index = 1, #goals do
            local dist = distance(pos, index)
            if dist < best then best = dist end
          end
        end
      end
      return best
    end
    local total = 0
    for index = 1, #goals do
      if not covered[index] then
        local best = INF
        for _, pos in ipairs(positions) do
          if pos then
            local dist = distance(pos, index)
            if dist < best then best = dist end
          end
        end
        if best == INF then return INF end
        total = total + best
      end
    end
    return total
  end

  local startPositions, occupied, assign = {}, {}, {}
  for i, b in ipairs(model.boulders) do
    local onSwitch = false
    for _, target in ipairs(targets) do
      if target.solved and target.pressedBy == b.number then onSwitch = true end
    end
    startPositions[i] = not onSwitch and b.start or false
    occupied[b.start] = true
  end
  local startCovered = {}
  if heuristic(startPositions, startCovered) == INF then return nil, "unreachable" end
  -- a short key: two bytes per boulder (cells fit, floors are at most
  -- 6400 cells), the covered switches as a bit mask, the region's lowest cell
  local char, floor = string.char, math.floor
  local function key(positions, covered, r)
    local parts = {}
    for i, pos in ipairs(positions) do
      parts[i] = pos and char(pos % 256, floor(pos / 256) + 1) or "\0\0"
    end
    local mask = 0
    for index in pairs(covered) do mask = mask + 2 ^ (index - 1) end
    parts[#parts + 1] = char(r % 256, floor(r / 256) + 1)
    parts[#parts + 1] = tostring(mask)
    return table.concat(parts)
  end
  local function coveredCount(covered)
    local n = 0
    for _ in pairs(covered) do n = n + 1 end
    return n
  end

  -- The plan from the goal node back to the start: every push, the floor's
  -- boulder cells before each one, and where each pushed boulder ends.
  local function finish(node, lastPush, target)
    local pushes = { lastPush }
    while node.parent do
      table.insert(pushes, 1, node.push)
      node = node.parent
    end
    local cells = {}
    for i, b in ipairs(model.boulders) do cells[i] = b.start end
    local states, finalCell = {}, {}
    for k, push in ipairs(pushes) do
      local parts = {}
      for i, cell in ipairs(cells) do parts[i] = cell end
      states[k] = table.concat(parts, ",")
      cells[push.boulder.number] = push.to
      finalCell[push.boulder.number] = push.to
    end
    for _, push in ipairs(pushes) do
      local final = finalCell[push.boulder.number]
      local goal = final and goalAt[final]
      -- a boulder moved aside (single-target plans) is said to go toward
      -- the plan's goal
      push.target = goal and goals[goal] or target
    end
    local first = pushes[1]
    local plan = { boulder = first.boulder, standX = first.standX, standY = first.standY,
      direction = first.direction, target = first.target, pushes = #pushes,
      steps = pushes, states = states, mode = mode }
    return plan
  end

  -- The whole-floor search leans on its estimate (weighted A*): a plan for
  -- seven switches is found in about a second (weights 3 to 6 were tried on
  -- the Tanoby Key room; 5 expanded the fewest states), at the cost of a
  -- few extra pushes; a single target keeps the plain shortest search.
  local weight = mode == "switches" and (budget.weight or 5) or 1
  local heap = {}
  -- The player's region is flooded into stamped arrays rather than new
  -- tables (the flood is most of the search's time): `taken` marks the
  -- boulders of the node being expanded, `region` that node's own region,
  -- `scratch` a child's region while its key is worked out.
  local walkNext = model.walkNext
  local takenMark, takenGen = {}, 0
  local regionMark, regionGen = {}, 0
  local scratchMark, scratchGen = {}, 0
  local queue = {}
  local function flood(px, py, mark, gen)
    local start = py * width + px
    mark[start] = gen
    local n, head, rep = 1, 1, start
    queue[1] = start
    while head <= n do
      local nexts = walkNext[queue[head]]
      head = head + 1
      for k = 1, nexts and #nexts or 0 do
        local ni = nexts[k]
        if mark[ni] ~= gen and takenMark[ni] ~= takenGen then
          mark[ni] = gen
          n = n + 1
          queue[n] = ni
          if ni < rep then rep = ni end
        end
      end
    end
    return rep
  end
  local function markTaken(positions, assigned)
    takenGen = takenGen + 1
    for i, pos in ipairs(positions) do
      takenMark[pos or (assigned and assigned[i]) or model.boulders[i].start] = takenGen
    end
  end

  markTaken(startPositions, nil)
  scratchGen = scratchGen + 1
  local rep = flood(player.cellX, player.cellY, scratchMark, scratchGen)
  heapPush(heap, { positions = startPositions, covered = startCovered, assign = assign,
    px = player.cellX, py = player.cellY, g = 0, f = weight * heuristic(startPositions, startCovered) })
  local visited = { [key(startPositions, startCovered, rep)] = true }
  local expanded, maxExpanded = 0, budget.maxExpanded or 200000
  local control = { deadline = 0 }

  local function body()
    while #heap > 0 do
      local node = heapPop(heap)
      expanded = expanded + 1
      if budget.stats then budget.stats.expanded = (budget.stats.expanded or 0) + 1 end
      if budget.onExpand then budget.onExpand(node.positions, node.g, mode) end
      if expanded > maxExpanded then return nil, "budget" end
      if os.clock() > control.deadline then coroutine.yield() end
      local positions = node.positions
      -- every boulder's cell: free ones where they are, locked ones on their
      -- switch (or where they started, already on one)
      local assigned = node.assign.cells
      markTaken(positions, assigned)
      regionGen = regionGen + 1
      flood(node.px, node.py, regionMark, regionGen)
      for bi, b in ipairs(model.boulders) do
        local pos = positions[bi]
        if pos then
          local bx, by = pos % width, math.floor(pos / width)
          for _, d in ipairs(DIRS) do
            local sx, sy = bx - d[2], by - d[3]
            local lx, ly = bx + d[2], by + d[3]
            local si, li = sy * width + sx, ly * width + lx
            if regionMark[si] == regionGen and lx >= 0 and ly >= 0 and lx < width and ly < height
               and model.land[li] and not model.fixed[li] and takenMark[li] ~= takenGen
               and model.pressDir[si] ~= d[1] and model.canStep(sx, sy, d[1], bx, by)
               and model.canStep(bx, by, d[1], lx, ly) then
              local push = { boulder = b, standX = sx, standY = sy, direction = d[1], to = li }
              local goal = goalAt[li]
              local g = node.g + 1
              if goal and mode == "one" then return finish(node, push, goals[goal]) end
              local allowed = (goal ~= nil and not node.covered[goal])
                or (not model.hole[li] and model.live[li])
              if allowed then
                local nextPositions = {}
                for i, p in ipairs(positions) do nextPositions[i] = p end
                local nextCovered, nextAssign = node.covered, node.assign
                if goal then
                  -- the boulder stays on the switch
                  nextPositions[bi] = false
                  nextCovered = {}
                  for index in pairs(node.covered) do nextCovered[index] = true end
                  nextCovered[goal] = true
                  nextAssign = { target = {}, cells = {} }
                  for k, v in pairs(node.assign.target or {}) do nextAssign.target[k] = v end
                  for k, v in pairs(node.assign.cells or {}) do nextAssign.cells[k] = v end
                  nextAssign.target[bi] = goals[goal]
                  nextAssign.cells[bi] = li
                  if coveredCount(nextCovered) == #goals then
                    return finish(node, push, goals[goal])
                  end
                else
                  nextPositions[bi] = li
                end
                -- the child's boulders: this one moved from pos to li
                takenMark[pos] = 0
                takenMark[li] = takenGen
                scratchGen = scratchGen + 1
                local nextRep = flood(sx, sy, scratchMark, scratchGen)
                takenMark[li] = 0
                takenMark[pos] = takenGen
                local k = key(nextPositions, nextCovered, nextRep)
                if not visited[k] then
                  visited[k] = true
                  local h = heuristic(nextPositions, nextCovered)
                  if h < INF then
                    heapPush(heap, { positions = nextPositions, covered = nextCovered, assign = nextAssign,
                      px = sx, py = sy, g = g, f = g + weight * h, parent = node, push = push })
                  end
                end
              end
            end
          end
        end
      end
    end
    return nil, "no plan"
  end

  local thread = coroutine.create(body)
  local task = { done = false }
  function task.run(seconds)
    if task.done then return task.plan, task.why end
    control.deadline = os.clock() + (seconds or 0.4)
    local ok, plan, why = coroutine.resume(thread)
    if not ok then
      task.done, task.why = true, "error: " .. tostring(plan)
    elseif coroutine.status(thread) == "dead" then
      task.done, task.plan, task.why = true, plan, why
    else
      return nil, "budget"
    end
    return task.plan, task.why
  end
  return task
end

-- The cells of the floor's boulders in their numbering order, as a plan's
-- `states` records them.
local function stateKey(world, boulders)
  local width = world.map.widthCells
  local parts = {}
  for i, b in ipairs(boulders) do parts[i] = b.cellY * width + b.cellX end
  return table.concat(parts, ",")
end
Puzzle.stateKey = stateKey

local function hasOpenSwitch(targets)
  for _, target in ipairs(targets) do
    if target.kind == "switch" and not target.solved then return true end
  end
  return false
end

-- A planning task for this floor: every open switch covered when the floor
-- has switches, else one boulder into a hole.  When the whole-floor search
-- runs out of time there is no hint rather than a nearest-first push that
-- can block the rest (the Tanoby Key room); only a floor with no full
-- solution (fewer boulders than switches) falls back to one target.
-- `task.run(seconds)` as for newSearch.
function Puzzle.newPlanTask(world, targets, boulders, budget)
  budget = budget or {}
  local current, why
  local fellBack = false
  local function fallBack()
    fellBack = true
    current, why = newSearch(world, targets, boulders, budget, "one")
  end
  if hasOpenSwitch(targets) then
    current, why = newSearch(world, targets, boulders, budget, "switches")
    if not current and why == "unreachable" then fallBack() end
  else
    fallBack()
  end
  local task = { done = false }
  function task.run(seconds)
    if task.done then return task.plan, task.why end
    if not current then
      task.done, task.why = true, why
      return nil, why
    end
    local plan, reason = current.run(seconds)
    if reason == "budget" and not current.done then return nil, "budget" end
    if not plan and not fellBack and (reason == "no plan" or reason == "unreachable") then
      fallBack()
      return task.run(seconds)
    end
    task.done, task.plan, task.why = true, plan, reason
    return plan, reason
  end
  return task
end

-- The first push of this floor's plan, searched for at most the budget's
-- seconds (synchronous: the sweep and tests).
function Puzzle.planFloor(world, targets, boulders, budget)
  budget = budget or {}
  local task = Puzzle.newPlanTask(world, targets, boulders, budget)
  return task.run(budget.maxSeconds or 0.4)
end

-- The push a known plan asks for next on this floor, or nil: the floor's
-- boulders stand where the plan has them before one of its pushes.
function Puzzle.followPlan(plan, world, boulders)
  if type(plan) ~= "table" or type(plan.states) ~= "table" then return nil end
  local here = stateKey(world, boulders)
  for k, state in ipairs(plan.states) do
    if state == here then
      local step = plan.steps[k]
      local entity = boulders[step.boulder.number]
      if not entity then return nil end
      return { boulder = { entity = entity, number = step.boulder.number },
        standX = step.standX, standY = step.standY, direction = step.direction,
        target = step.target, pushes = #plan.steps - k + 1 }
    end
  end
  return nil
end

local CACHE = setmetatable({}, { __mode = "k" })
-- Per map view: the last whole plan found (followed push by push while the
-- boulders stand where it has them), and a search still running.
local PLANS = setmetatable({}, { __mode = "k" })
local PENDING = setmetatable({}, { __mode = "k" })

-- What a plan depends on besides the boulders: the floor (scripts open
-- barriers with setmetatile, so the COLL grid counts) and every other
-- object.  The player's cell is not part of it.
local function floorKey(world, boulders)
  local map = world.map
  local parts = { tostring(map), tostring(#boulders) }
  for _, entity in ipairs(world.npcs or {}) do
    if type(entity) == "table" and not isBoulder(entity) then
      parts[#parts + 1] = tostring(entity.localId) .. "@" .. tostring(entity.cellX) .. ","
        .. tostring(entity.cellY)
    end
  end
  local cells = {}
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do cells[#cells + 1] = tostring(map:coll(x, y)) end
  end
  parts[#parts + 1] = table.concat(cells, "")
  return table.concat(parts, "|")
end

local function signature(world, boulders, prefix)
  return table.concat({ floorKey(world, boulders), prefix, tostring(world.player.cellX),
    tostring(world.player.cellY), stateKey(world, boulders) }, "|")
end

local function now()
  local timer = love and love.timer
  if timer and timer.getTime then
    local ok, value = pcall(timer.getTime)
    if ok and type(value) == "number" then return value end
  end
  return os.clock()
end

-- Time one object-list request may spend on a running search, and the
-- share of a frame the search takes while the player is on that floor.
Puzzle.DESCRIBE_SECONDS = 0.3
Puzzle.FRAME_SECONDS = 0.006

-- The next push on this floor: from the kept plan when the boulders are
-- where it has them, else from a search that carries on across requests
-- and frames (the Tanoby Key room's seven switches take a few seconds).
-- Returns the push, or nil and why ("budget" while still searching).
local function nextPush(world, targets, boulders)
  local map = world.map
  local key = floorKey(world, boulders)
  local kept = PLANS[map]
  if kept and kept.key == key then
    local push = Puzzle.followPlan(kept.plan, world, boulders)
    if push then return push end
  end
  local state = stateKey(world, boulders)
  local pending = PENDING[map]
  if not (pending and pending.key == key and pending.state == state) then
    pending = { key = key, state = state, task = Puzzle.newPlanTask(world, targets, boulders) }
    PENDING[map] = pending
  end
  -- several requests in one command each read the floor: only the first
  -- in a short while searches for long
  local t = now()
  local seconds = (pending.lastAsked and t - pending.lastAsked < 0.25) and 0.02 or Puzzle.DESCRIBE_SECONDS
  pending.lastAsked = t
  local plan, why = pending.task.run(seconds)
  if why == "budget" and not pending.task.done then return nil, "budget" end
  PENDING[map] = nil
  if not plan then return nil, why end
  PLANS[map] = { key = key, plan = plan }
  return Puzzle.followPlan(plan, world, boulders) or plan
end

-- A search still running for the floor the player is on gets a slice of
-- this frame (Navigation:updateNavigation).  True while one is running.
function Puzzle.continueSearch(world, seconds)
  local map = world and world.map
  local pending = map and PENDING[map]
  if not pending then return false end
  local _, why = pending.task.run(seconds or Puzzle.FRAME_SECONDS)
  if pending.task.done then
    PENDING[map] = nil
    local plan = pending.task.plan
    if plan then PLANS[map] = { key = pending.key, plan = plan } end
    return false
  end
  return why == "budget"
end

function Puzzle._resetPlansForTests()
  for k in pairs(PLANS) do PLANS[k] = nil end
  for k in pairs(PENDING) do PENDING[k] = nil end
  for k in pairs(CACHE) do CACHE[k] = nil end
end

-- The puzzle's objects and states for the object list:
--   targetStates   one per switch and hole: { x, y, label, state, hole }
--   objects        the switches, as objects to walk to
--   objectOverrides  boulder labels ("Boulder 2") and the next push
--   nextAction     the push to make now, or nil
function Puzzle.describe(game, world, nav)
  local result = { objects = {}, objectOverrides = {}, targetStates = {} }
  local map = world and world.map
  if not (Shared.enabled(game) and type(map) == "table" and type(map.widthCells) == "number"
      and map.widthCells * map.heightCells <= 6400 and type(world.player) == "table") then
    return result
  end
  local okTargets, targets, boulders = pcall(Puzzle.targetsFor, world)
  if not okTargets or not targets then return result end
  local mapId = map.id
  local prefix = Puzzle.strengthPrefix(nav)
  local okSig, key = pcall(signature, world, boulders, prefix)
  local cached = okSig and CACHE[map]
  if cached and cached.key == key then return cached.result end

  local okPlan, plan, why = pcall(nextPush, world, targets, boulders)
  if not okPlan then plan, why = nil, nil end
  -- the plan's target, matched by cell (a kept plan holds the targets of
  -- the floor it was searched on)
  local served
  for _, target in ipairs(targets) do
    if plan and plan.target and target.x == plan.target.x and target.y == plan.target.y then
      served = target
    end
  end
  if plan and not served then plan = nil end
  local searching = why == "budget"
  local noPlan = searching and "still working out a boulder plan; ask again in a few seconds"
    or "no safe boulder route from current positions"
  for _, target in ipairs(targets) do
    local state
    if target.kind == "switch" and target.solved then
      state = "pressed by Boulder " .. tostring(target.pressedBy)
    elseif served == target then
      state = (target.kind == "switch" and "not pressed; " or "")
        .. "Boulder " .. tostring(plan.boulder.number) .. " can reach it; next push " .. plan.direction
    elseif plan then
      state = target.kind == "switch" and "not pressed" or nil
    else
      state = (target.kind == "switch" and "not pressed; " or "") .. noPlan
    end
    result.targetStates[#result.targetStates + 1] = {
      x = target.x, y = target.y, label = target.label, state = state, hole = target.hole,
      kind = target.kind,
    }
    if target.kind == "switch" then
      result.objects[#result.objects + 1] = {
        id = "strength_switch:" .. tostring(mapId) .. ":" .. target.x .. "," .. target.y,
        label = target.label, x = target.x, y = target.y, stateText = state,
        interactionCells = { { x = target.x, y = target.y } },
        semanticKind = "strength_switch",
        routeInstruction = "Push a boulder onto it",
      }
    end
  end
  for number, entity in ipairs(boulders) do
    local override = { label = "Boulder " .. tostring(number),
      interaction = "strength_push", semanticKind = "strength_boulder" }
    local onSwitch
    for _, target in ipairs(targets) do
      if target.pressedBy == number then onSwitch = target end
    end
    if plan and plan.boulder.entity == entity then
      override.requiredFacing = plan.direction
      override.stateText = "next push " .. plan.direction .. " toward " .. served.label
      override.routeInstruction = prefix .. "push " .. plan.direction .. " toward " .. served.label
      result.nextAction = {
        boulderId = objectId(mapId, entity), boulderLabel = override.label,
        targetLabel = served.label, standX = plan.standX, standY = plan.standY,
        direction = plan.direction, instruction = override.routeInstruction,
      }
    elseif onSwitch then
      override.stateText = "on " .. onSwitch.label
      override.routeInstruction = "Leave it on " .. onSwitch.label
    else
      override.stateText = plan and "not the next push"
        or (searching and "plan still being worked out" or "no safe push known")
      override.routeInstruction = prefix .. "push only when a route is known"
    end
    result.objectOverrides[objectId(mapId, entity)] = override
  end
  result.searching = searching
  -- a search still running is asked again next time, not cached
  if okSig and not searching then CACHE[map] = { key = key, result = result } end
  return result
end

Puzzle.isBoulder = isBoulder

return Puzzle
