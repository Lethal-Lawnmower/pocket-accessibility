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
-- pressing the nearest switch first can block the rest); otherwise, or when
-- that search runs out of budget, the plan drops one boulder into a hole or
-- onto one switch.  The answer is the plan's first push.  Elevation is read
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
  local function canStep(x, y, direction, toX, toY)
    if map:dirBlocked(x, y, toX, toY, direction) then return false end
    return not elevationsMismatch(elevation[y * width + x], elevation[toY * width + toX])
  end
  local model = { map = map, width = width, height = height, land = land, pressDir = pressDir,
    standable = standable, fixed = fixed, warpCell = warpCell, hole = hole,
    boulders = list, elevation = elevation, canStep = canStep }
  -- Dead squares: cells from which a boulder can still reach some target,
  -- searched backwards from every target (pulls), walls and directional
  -- walls counted, other boulders not.
  local live = {}
  local queue, head = {}, 1
  for _, target in ipairs(targets) do
    if not target.solved then
      local t = target.y * width + target.x
      if not live[t] then live[t] = true queue[#queue + 1] = t end
    end
  end
  while head <= #queue do
    local n = queue[head]
    head = head + 1
    local nx, ny = n % width, math.floor(n / width)
    for _, d in ipairs(DIRS) do
      local cx, cy = nx - d[2], ny - d[3]  -- the boulder before the push
      local sx, sy = cx - d[2], cy - d[3]  -- the player pushing it
      local c, s = cy * width + cx, sy * width + sx
      if cx >= 0 and cy >= 0 and cx < width and cy < height
         and sx >= 0 and sy >= 0 and sx < width and sy < height
         and not live[c] and land[c] and not hole[c] and standable[s] and pressDir[s] ~= d[1]
         and canStep(cx, cy, d[1], nx, ny) and canStep(sx, sy, d[1], cx, cy) then
        live[c] = true
        queue[#queue + 1] = c
      end
    end
  end
  model.live = live
  return model
end
Puzzle.floorModel = floorModel

local function playerRegion(model, px, py, occupied)
  local width, height = model.width, model.height
  local start = py * width + px
  local seen, queue, head, rep = { [start] = true }, { start }, 1, start
  while head <= #queue do
    local i = queue[head]
    head = head + 1
    local x, y = i % width, math.floor(i / width)
    for _, d in ipairs(DIRS) do
      local nx, ny = x + d[2], y + d[3]
      local ni = ny * width + nx
      if nx >= 0 and ny >= 0 and nx < width and ny < height and not seen[ni]
         and model.standable[ni] and not model.fixed[ni] and not occupied[ni]
         and model.pressDir[i] ~= d[1] and model.canStep(x, y, d[1], nx, ny) then
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
--     (Seafoam's holes, and the fallback when the whole-floor search runs
--     out of budget)
-- Returns the first push: { boulder, standX, standY, direction, target,
-- pushes } (target: where that boulder ends in the plan), or nil, reason.
local function search(world, targets, boulders, budget, mode)
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

  local function distance(pos, target)
    return math.abs(pos % width - target.x) + math.abs(math.floor(pos / width) - target.y)
  end
  -- "one": the nearest boulder to any goal; "switches": for every open
  -- switch, the nearest free boulder (not admissible, but it keeps the
  -- whole-floor search short)
  local function heuristic(positions, covered)
    if mode == "one" then
      local best = math.huge
      for _, pos in ipairs(positions) do
        if pos then
          for _, target in ipairs(goals) do
            local dist = distance(pos, target)
            if dist < best then best = dist end
          end
        end
      end
      return best
    end
    local total = 0
    for index, target in ipairs(goals) do
      if not covered[index] then
        local best = math.huge
        for _, pos in ipairs(positions) do
          if pos then
            local dist = distance(pos, target)
            if dist < best then best = dist end
          end
        end
        if best == math.huge then return math.huge end
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
  if heuristic(startPositions, startCovered) == math.huge then return nil, "unreachable" end
  local region, rep = playerRegion(model, player.cellX, player.cellY, occupied)
  local function key(positions, covered, r)
    local parts = {}
    for i, pos in ipairs(positions) do parts[i] = pos or "x" end
    local c = {}
    for index in pairs(covered) do c[#c + 1] = index end
    table.sort(c)
    return table.concat(parts, ",") .. "|" .. table.concat(c, ",") .. "|" .. r
  end
  local function coveredCount(covered)
    local n = 0
    for _ in pairs(covered) do n = n + 1 end
    return n
  end
  -- The whole-floor search leans on its estimate (weighted A*): a plan for
  -- seven switches is found in time, at the cost of a few extra pushes; a
  -- single target keeps the plain shortest search.
  local weight = mode == "switches" and (budget.weight or 3) or 1
  local heap = {}
  heapPush(heap, { positions = startPositions, covered = startCovered, assign = assign,
    region = region, g = 0, f = weight * heuristic(startPositions, startCovered) })
  local visited = { [key(startPositions, startCovered, rep)] = true }
  local expanded, maxExpanded = 0, budget.maxExpanded or 20000
  local deadline = os.clock() + (budget.maxSeconds or 0.4)
  while #heap > 0 do
    local node = heapPop(heap)
    expanded = expanded + 1
    if budget.stats then budget.stats.expanded = (budget.stats.expanded or 0) + 1 end
    if budget.onExpand then budget.onExpand(node.positions, node.g, mode) end
    if expanded > maxExpanded or os.clock() > deadline then return nil, "budget" end
    local positions = node.positions
    -- every boulder's cell: free ones where they are, locked ones on their
    -- switch (or where they started, already on one)
    local taken = {}
    for i, pos in ipairs(positions) do
      taken[pos or (node.assign.cells and node.assign.cells[i]) or model.boulders[i].start] = true
    end
    for bi, b in ipairs(model.boulders) do
      local pos = positions[bi]
      if pos then
        local bx, by = pos % width, math.floor(pos / width)
        for _, d in ipairs(DIRS) do
          local sx, sy = bx - d[2], by - d[3]
          local lx, ly = bx + d[2], by + d[3]
          local si, li = sy * width + sx, ly * width + lx
          if node.region[si] and lx >= 0 and ly >= 0 and lx < width and ly < height
             and model.land[li] and not model.fixed[li] and not taken[li]
             and model.pressDir[si] ~= d[1] and model.canStep(sx, sy, d[1], bx, by)
             and model.canStep(bx, by, d[1], lx, ly) then
            local push = node.first or { boulder = b, standX = sx, standY = sy, direction = d[1] }
            local goal = goalAt[li]
            local g = node.g + 1
            if goal and mode == "one" then
              push.target = goals[goal]
              push.pushes = g
              return push
            end
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
                  push.target = nextAssign.target[push.boulder.number] or goals[goal]
                  push.pushes = g
                  return push
                end
              else
                nextPositions[bi] = li
              end
              local nextTaken = {}
              for i, p in ipairs(nextPositions) do
                nextTaken[p or (nextAssign.cells and nextAssign.cells[i]) or model.boulders[i].start] = true
              end
              local nextRegion, nextRep = playerRegion(model, sx, sy, nextTaken)
              local k = key(nextPositions, nextCovered, nextRep)
              if not visited[k] then
                visited[k] = true
                local h = heuristic(nextPositions, nextCovered)
                if h < math.huge then
                  heapPush(heap, { positions = nextPositions, covered = nextCovered, assign = nextAssign,
                    region = nextRegion, g = g, f = g + weight * h, first = push })
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

-- The first push of the plan for this floor: every open switch covered when
-- the floor has switches (falling back to the nearest single switch when
-- that search runs out of budget), else one boulder into a hole.
function Puzzle.planFloor(world, targets, boulders, budget)
  budget = budget or {}
  local hasSwitch = false
  for _, target in ipairs(targets) do
    if target.kind == "switch" and not target.solved then hasSwitch = true end
  end
  if hasSwitch then
    local plan, why = search(world, targets, boulders, budget, "switches")
    if plan then return plan end
    -- out of budget: no hint rather than a nearest-first push that can
    -- block the rest (the Tanoby Key room); only a floor with no full
    -- solution (fewer boulders than switches) falls back to one target
    if why ~= "no plan" and why ~= "unreachable" then return nil, why end
  end
  return search(world, targets, boulders, budget, "one")
end

local CACHE = setmetatable({}, { __mode = "k" })

local function signature(world, boulders, prefix)
  local map = world.map
  local parts = { tostring(map), prefix, tostring(world.player.cellX), tostring(world.player.cellY) }
  for _, entity in ipairs(world.npcs or {}) do
    if type(entity) == "table" then
      parts[#parts + 1] = tostring(entity.localId) .. "@" .. tostring(entity.cellX) .. ","
        .. tostring(entity.cellY)
    end
  end
  -- scripts open barriers with setmetatile: the COLL grid is part of the key
  local cells = {}
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do cells[#cells + 1] = tostring(map:coll(x, y)) end
  end
  parts[#parts + 1] = table.concat(cells, "")
  parts[#parts + 1] = tostring(#boulders)
  return table.concat(parts, "|")
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

  local okPlan, plan, why = pcall(Puzzle.planFloor, world, targets, boulders)
  if not okPlan then plan, why = nil, nil end
  local served = plan and plan.target
  local noPlan = why == "budget" and "no boulder plan found in time from here"
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
      override.stateText = plan and "not the next push" or "no safe push known"
      override.routeInstruction = prefix .. "push only when a route is known"
    end
    result.objectOverrides[objectId(mapId, entity)] = override
  end
  if okSig then CACHE[map] = { key = key, result = result } end
  return result
end

Puzzle.isBoulder = isBoulder

return Puzzle
