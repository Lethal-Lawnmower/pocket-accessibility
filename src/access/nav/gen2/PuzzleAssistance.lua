-- Reused from the old Pocket Accessibility project
-- (src/accessibility/gen2/PuzzleAssistance.lua at commit 71cdd419e, upstream
-- v0.3.32) under decision 20; adapted for v0.3.98.  Read-only: nothing here
-- moves a boulder, writes the command queue or changes a flag.

-- Strength puzzle help for Gold, Silver and Crystal: the two stone-table
-- floors, Ice Path B1F and Blackthorn Gym 2F (the owner's first puzzle-help
-- targets; Pokemon Access handles both badly).  The Sokoban search in
-- ../PuzzleAssistance.lua is generation-neutral; this module answers its
-- generation questions from the game's own data:
--
--   targets      the rows of the stone table the world is actually polling
--                (World.cmdQueue, written by the map's MAPCALLBACK_CMDQUEUE),
--                each a pit warp plus the boulder object that falls through
--                it; no hand-written fallback, so guidance never promises a
--                drop the game would not make
--   isBoulder    SPRITEMOVEDATA_STRENGTH_BOULDER and an object index, the
--                gates CmdQueue.stoneFall itself applies
--   canMove      the player's step under Gold's side-wall rules
--   canPush      Map:objectStepPermitted, the boulder's own rule, and never
--                across a different pit first (the game drops it there)
--   canStand     never on a warp or pit (stepping there leaves the floor)

local Shared = require("src.access.nav.PuzzleAssistance")
local Permissions = require("src.world.gen2.Permissions")
local CmdQueue = require("src.world.gen2.CmdQueue")
local FieldMoves = require("src.world.gen2.FieldMoves")

local PIT = { [0x60] = true, [0x68] = true }
local DELTA = { up = { 0, -1 }, down = { 0, 1 },
  left = { -1, 0 }, right = { 1, 0 } }

local Puzzle = {}
for key, value in pairs(Shared) do Puzzle[key] = value end

local function isBoulder(entity)
  local def = type(entity) == "table" and entity.def or nil
  return type(def) == "table" and def.movement == CmdQueue.BOULDER_MOVEDATA
    and type(def.index) == "number" and def.index >= 1
    and entity.visible ~= false and entity.passable ~= true
end

-- Stone tables name boulders by the cart's object id (object_const_def
-- starts at 2), which is the extractor's 1-based index plus one; boulders are
-- numbered by that index.
local function boulderNumber(entity)
  local def = type(entity) == "table" and entity.def or nil
  return def and def.index or nil
end

local function collisionOf(map)
  return function(cx, cy) return map:cellCollision(cx, cy) end
end

local function canMove(map, entities, mover, direction)
  if type(map) ~= "table" or type(map.cellCollision) ~= "function" then return false end
  local delta = DELTA[direction]
  if not delta then return false end
  local fromX, fromY = mover.cellX, mover.cellY
  local x, y = fromX + delta[1], fromY + delta[2]
  local okBounds, inBounds = pcall(map.inBounds, map, x, y)
  if not okBounds or not inBounds then return false end
  local okStep, permitted = pcall(Permissions.stepPermitted, collisionOf(map),
    fromX, fromY, direction)
  if not okStep or not permitted then return false end
  if not Permissions.isWalkable(map:cellCollision(x, y)) then return false end
  for _, entity in ipairs(entities or {}) do
    if entity ~= mover and not entity.passable then
      local covers = entity.cellX == x and entity.cellY == y
      if entity.bigObject then
        local dx, dy = x - entity.cellX, y - entity.cellY
        covers = dx >= 0 and dx < 2 and dy >= 0 and dy < 2
      end
      if covers then return false end
    end
  end
  return true
end

-- The script a stone row runs must really make that boulder disappear; an
-- extracted row names its script by key into the world's scripts.
local function scriptDrops(row, overworld)
  local script = row and row.script
  if type(script) == "string" then
    local scripts = overworld and overworld.scripts
    script = type(scripts) == "table" and scripts[script] or nil
  end
  if type(script) ~= "table" then return false end
  for _, command in ipairs(script) do
    if type(command) == "table" and command.op == "disappear"
        and command.object == row.object then return true end
  end
  return false
end

function Puzzle.targetsFor(mapId, overworld)
  local queue = overworld and overworld.cmdQueue
  if type(queue) ~= "table" then return nil end
  local rows
  for i = 1, CmdQueue.CAPACITY do
    local entry = queue[i]
    if type(entry) == "table" and entry.kind == CmdQueue.STONETABLE
        and (entry.mapId == nil or entry.mapId == mapId) then
      rows = entry.rows
      break
    end
  end
  if type(rows) ~= "table" then return nil end
  local map = overworld and overworld.map
  local def = map and (map.def or map)
  local warps = def and def.warps
  if type(warps) ~= "table" or type(map.cellCollision) ~= "function"
      or type(map.inBounds) ~= "function" then return nil end
  -- A row whose boulder is no longer on the floor is done: the game removes
  -- it when it falls through (Ice Path also sets its event flag, so it stays
  -- gone; Blackthorn's come back when the floor is loaded again).
  local present = {}
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    if isBoulder(entity) then present[entity.def.index + 1] = true end
  end
  local targets = {}
  for index, row in ipairs(rows) do
    local warp = type(row) == "table" and warps[row.warp] or nil
    if type(row) == "table" and type(row.warp) == "number"
        and row.warp >= 1 and row.warp % 1 == 0
        and type(row.object) == "number" and row.object >= 2
        and row.object % 1 == 0 and scriptDrops(row, overworld)
        and type(warp) == "table" and type(warp.x) == "number"
        and type(warp.y) == "number" and map:inBounds(warp.x, warp.y)
        and PIT[map:cellCollision(warp.x, warp.y)] then
      targets[#targets + 1] = {
        x = warp.x, y = warp.y, hole = true, requiresBoulder = true,
        label = "Hole " .. index, boulder = row.object - 1,
        solved = not present[row.object],
      }
    end
  end
  return #targets > 0 and targets or nil
end

-- What still stands between the player and a push, from the same checks the
-- game makes: a party member with Strength, the Plain Badge, and Strength
-- switched on for this floor (World.strengthActive, cleared on every load).
local function strengthPrefix(game, overworld)
  local native = overworld and (overworld.native or overworld)
  if not (native and type(native.partyMoveUser) == "function") then
    return "Strength availability unknown; "
  end
  local ok, mon = pcall(native.partyMoveUser, native, "STRENGTH")
  if not ok then return "Strength availability unknown; " end
  if not mon then return "Needs a party Pokémon with Strength; " end
  if not FieldMoves.hasBadge(game and game.save, FieldMoves.BADGE.STRENGTH) then
    return "Needs the Plain Badge; "
  end
  if not native.strengthActive then
    return "Use Strength from the party menu; "
  end
  return ""
end

local function canPush(map, x, y, direction, targetX, targetY)
  local delta = DELTA[direction]
  if not delta or type(map.objectStepPermitted) ~= "function"
      or type(map.warpAt) ~= "function" then return false end
  local landX, landY = x + delta[1], y + delta[2]
  if map:warpAt(landX, landY) and (landX ~= targetX or landY ~= targetY) then
    return false
  end
  return map:objectStepPermitted(x, y, direction) == true
end

local function canStand(map, x, y)
  return type(map.warpAt) == "function" and not map:warpAt(x, y)
    and not PIT[map:cellCollision(x, y)]
end

-- A block swap or a mod overlay can change safe pushing without moving a
-- boulder; the two floors are small, so the collision grid is part of the key.
local function cacheSignature(overworld)
  local map = overworld.map
  local parts = {}
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      parts[#parts + 1] = tostring(map:cellCollision(x, y))
    end
  end
  return table.concat(parts, ",")
end

Puzzle.RULES = {
  targets = Puzzle.targetsFor, isBoulder = isBoulder,
  boulderNumber = boulderNumber, canMove = canMove,
  canPush = canPush, canStand = canStand, strengthPrefix = strengthPrefix,
  cacheSignature = cacheSignature,
}

-- ------------------------------------------------------------ floor search
--
-- v0.3.98 addition.  The shared search moves only a target's own boulder and
-- treats every other boulder as a wall.  Blackthorn Gym 2F cannot be solved
-- that way: a boulder that is in no stone row (Boulder 6) closes the only way
-- to Boulder 4's pushing position and has to be pushed aside first.  So the
-- Gen 2 floors are searched as a whole: any Strength boulder may be pushed,
-- the goal is any stone-table boulder dropping into its own hole, and the
-- answer is the first push of the shortest plan found (A* over pushes; the
-- distance of the nearest boulder to its hole never overestimates).  The
-- player stays on the pushing cell after a push, as on the cart (.CheckNPC's
-- bump).  A boulder never lands on a warp other than its own hole: the game
-- would leave it standing on the pit (CmdQueue.stoneFall needs its row).

local DIRS = { { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }

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

-- The floor as the search sees it: which cells a boulder or the player may
-- use, the live boulders (in object order) and which hole each one fits.
local function floorModel(world, targets)
  local map = world.map
  local width, height = map.widthCells, map.heightCells
  local collOf = collisionOf(map)
  local land, standable, fixed = {}, {}, {}
  local def = map.def or map
  local warpCell = {}
  for _, warp in ipairs(def.warps or {}) do warpCell[warp.y * width + warp.x] = true end
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local i = y * width + x
      local coll = map:cellCollision(x, y)
      land[i] = Permissions.isWalkable(coll)
      standable[i] = land[i] and not warpCell[i] and not PIT[coll]
    end
  end
  local boulders = {}
  local holeOf = {}
  for _, target in ipairs(targets) do
    holeOf[target.boulder] = target
  end
  for _, entity in ipairs(world.entities or world.npcs or {}) do
    if entity ~= world.player and type(entity) == "table" then
      if isBoulder(entity) then
        boulders[#boulders + 1] = { entity = entity, number = entity.def.index,
          target = holeOf[entity.def.index], start = entity.cellY * width + entity.cellX }
      elseif not entity.passable then
        local size = entity.bigObject and 1 or 0
        for dy = 0, size do
          for dx = 0, size do fixed[(entity.cellY + dy) * width + entity.cellX + dx] = true end
        end
      end
    end
  end
  -- Dead squares (standard Sokoban pruning): the cells from which a
  -- boulder could still be pushed into its own hole, walls and side walls
  -- counted, other boulders not.  A stone-table boulder is never pushed
  -- anywhere else; without this the shortest first drop on Ice Path B1F
  -- parked Boulder 1 where it can never move again.
  local live = {}
  for _, target in ipairs(targets) do
    local hole = target.y * width + target.x
    local set, queue, head = { [hole] = true }, { hole }, 1
    while head <= #queue do
      local n = queue[head]
      head = head + 1
      local nx, ny = n % width, math.floor(n / width)
      for _, d in ipairs({ { "up", 0, -1 }, { "down", 0, 1 }, { "left", -1, 0 }, { "right", 1, 0 } }) do
        local cx, cy = nx - d[2], ny - d[3]      -- the boulder before the push
        local sx, sy = cx - d[2], cy - d[3]      -- the player pushing it
        local c, s = cy * width + cx, sy * width + sx
        if cx >= 0 and cy >= 0 and cx < width and cy < height
           and sx >= 0 and sy >= 0 and sx < width and sy < height
           and not set[c] and land[c] and not warpCell[c] and standable[s]
           and map:objectStepPermitted(cx, cy, d[1]) then
          set[c] = true
          queue[#queue + 1] = c
        end
      end
    end
    live[target] = set
  end
  return { map = map, width = width, height = height, collOf = collOf, land = land,
    standable = standable, fixed = fixed, warpCell = warpCell, boulders = boulders, live = live }
end

-- The cells the player can reach from (px, py) with boulders on `occupied`.
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
         and Permissions.stepPermitted(model.collOf, x, y, d[1]) then
        seen[ni] = true
        queue[#queue + 1] = ni
        if ni < rep then rep = ni end
      end
    end
  end
  return seen, rep
end

local function stateKey(positions, rep)
  local parts = {}
  for i, pos in ipairs(positions) do parts[i] = pos or "x" end
  return table.concat(parts, ",") .. "|" .. rep
end

-- The first push of the shortest plan that drops a stone-table boulder into
-- its own hole: { boulder, standX, standY, direction, target, pushes }, or nil.
function Puzzle.planFloor(world, targets, budget)
  budget = budget or {}
  local model = floorModel(world, targets)
  local map, width = model.map, model.width
  local player = world.player
  if not (player and #model.boulders > 0) then return nil end
  local function heuristic(positions)
    local best = math.huge
    for i, b in ipairs(model.boulders) do
      local pos = positions[i]
      if pos and b.target then
        local distance = math.abs(pos % width - b.target.x)
          + math.abs(math.floor(pos / width) - b.target.y)
        if distance < best then best = distance end
      end
    end
    return best
  end
  local startPositions = {}
  local occupied = {}
  for i, b in ipairs(model.boulders) do
    startPositions[i] = b.start
    occupied[b.start] = true
  end
  local region, rep = playerRegion(model, player.cellX, player.cellY, occupied)
  if heuristic(startPositions) == math.huge then return nil end
  local heap = {}
  heapPush(heap, { positions = startPositions, region = region, g = 0,
    f = heuristic(startPositions), first = nil })
  local visited = { [stateKey(startPositions, rep)] = true }
  local expanded, maxExpanded = 0, budget.maxExpanded or 20000
  local deadline = os.clock() + (budget.maxSeconds or 0.4)
  while #heap > 0 do
    local node = heapPop(heap)
    expanded = expanded + 1
    if expanded > maxExpanded or os.clock() > deadline then return nil, "budget" end
    local positions = node.positions
    local taken = {}
    for _, pos in ipairs(positions) do if pos then taken[pos] = true end end
    for bi, b in ipairs(model.boulders) do
      local pos = positions[bi]
      if pos then
        local bx, by = pos % width, math.floor(pos / width)
        for _, d in ipairs(DIRS) do
          local sx, sy = bx - d[2], by - d[3]
          local lx, ly = bx + d[2], by + d[3]
          local si, li = sy * width + sx, ly * width + lx
          if node.region[si] and lx >= 0 and ly >= 0 and lx < width and ly < model.height
             and model.land[li] and not model.fixed[li] and not taken[li]
             and map:objectStepPermitted(bx, by, d[1]) then
            local push = node.first or { boulder = b, standX = sx, standY = sy, direction = d[1] }
            local fits = b.target and b.target.x == lx and b.target.y == ly
            if fits then
              push.target = b.target
              push.pushes = node.g + 1
              return push
            end
            local deadSquare = b.target and not model.live[b.target][li]
            if not model.warpCell[li] and not deadSquare then
              local nextPositions = {}
              for i, p in ipairs(positions) do nextPositions[i] = p end
              nextPositions[bi] = li
              local nextTaken = {}
              for _, p in ipairs(nextPositions) do if p then nextTaken[p] = true end end
              local nextRegion, nextRep = playerRegion(model, sx, sy, nextTaken)
              local key = stateKey(nextPositions, nextRep)
              if not visited[key] then
                visited[key] = true
                local g = node.g + 1
                heapPush(heap, { positions = nextPositions, region = nextRegion, g = g,
                  f = g + heuristic(nextPositions), first = push })
              end
            end
          end
        end
      end
    end
  end
  return nil
end

local CACHE = setmetatable({}, { __mode = "k" })

local function signature(game, world, targets, prefix)
  local map = world.map
  local parts = { tostring(map), prefix, cacheSignature(world) }
  local occupied = {}
  for _, entity in ipairs(world.entities or world.npcs or {}) do
    if entity ~= world.player and type(entity) == "table" then
      parts[#parts + 1] = tostring(entity.id) .. "@" .. tostring(entity.cellX) .. ","
        .. tostring(entity.cellY)
      occupied[entity.cellY * map.widthCells + entity.cellX] = true
    end
  end
  for _, target in ipairs(targets) do parts[#parts + 1] = tostring(target.solved) end
  -- the player's region decides which pushes are open, not the cell
  local model = { width = map.widthCells, height = map.heightCells, collOf = collisionOf(map),
    standable = setmetatable({}, { __index = function(_, i)
      local x, y = i % map.widthCells, math.floor(i / map.widthCells)
      return canStand(map, x, y) and Permissions.isWalkable(map:cellCollision(x, y))
    end }), fixed = {} }
  local _, rep = playerRegion(model, world.player.cellX, world.player.cellY, occupied)
  parts[#parts + 1] = "region:" .. tostring(rep)
  return table.concat(parts, "|")
end

function Puzzle.describe(game, world)
  local result = { objects = {}, objectOverrides = {}, targetStates = {} }
  local map = world and world.map
  if not (Shared.enabled(game) and type(map) == "table" and type(map.widthCells) == "number"
      and type(map.heightCells) == "number" and map.widthCells > 0 and map.heightCells > 0
      and map.widthCells * map.heightCells <= 4096 and type(world.player) == "table") then
    return result
  end
  local mapId = map.id or (type(map.def) == "table" and map.def.id)
  local okTargets, targets = pcall(Puzzle.targetsFor, mapId, world)
  if not okTargets or not targets then return result end
  local prefix = strengthPrefix(game, world)
  local okSig, key = pcall(signature, game, world, targets, prefix)
  local cached = okSig and CACHE[world]
  if cached and cached.key == key then return cached.result end

  local okPlan, plan = pcall(Puzzle.planFloor, world, targets)
  if not okPlan then plan = nil end
  local served = plan and plan.target
  local helper = plan and served and plan.boulder.number ~= served.boulder
  for _, target in ipairs(targets) do
    local state
    if target.solved then
      state = "filled"
    elseif served == target then
      state = "empty; Boulder " .. tostring(target.boulder) .. " can reach it; "
        .. (helper and ("first push Boulder " .. tostring(plan.boulder.number) .. " "
          .. plan.direction) or ("next push " .. plan.direction))
    elseif plan then
      state = "empty"
    else
      state = "empty; no safe boulder route from current positions"
    end
    result.targetStates[#result.targetStates + 1] = {
      x = target.x, y = target.y, label = target.label, state = state, hole = true,
    }
  end
  for _, entity in ipairs(world.entities or world.npcs or {}) do
    if entity ~= world.player and isBoulder(entity) then
      local number = entity.def.index
      local own
      for _, target in ipairs(targets) do
        if target.boulder == number and not target.solved then own = target end
      end
      local override = { label = "Boulder " .. tostring(number),
        interaction = "strength_push", semanticKind = "strength_boulder" }
      if plan and plan.boulder.entity == entity then
        override.requiredFacing = plan.direction
        if helper then
          override.stateText = "next push " .. plan.direction .. ", to clear the way for Boulder "
            .. tostring(served.boulder)
          override.routeInstruction = prefix .. "push " .. plan.direction
            .. " to clear the way for Boulder " .. tostring(served.boulder)
        else
          override.stateText = "target " .. served.label .. "; next push " .. plan.direction
          override.routeInstruction = prefix .. "push " .. plan.direction .. " toward " .. served.label
        end
        result.nextAction = {
          boulderId = entity.id, boulderLabel = override.label,
          targetLabel = helper and ("clear the way for Boulder " .. tostring(served.boulder))
            or served.label,
          standX = plan.standX, standY = plan.standY, direction = plan.direction,
          instruction = override.routeInstruction,
        }
      else
        override.stateText = own and ("goes in " .. own.label) or "goes in no hole"
        override.routeInstruction = prefix .. "push only when a route is known"
      end
      result.objectOverrides[entity.id or tostring(number)] = override
    end
  end
  if okSig then CACHE[world] = { key = key, result = result } end
  return result
end

Puzzle.isBoulder = isBoulder
Puzzle.boulderNumber = boulderNumber
Puzzle.canMove = canMove
Puzzle.canPush = canPush
Puzzle.canStand = canStand
Puzzle.strengthPrefix = strengthPrefix

return Puzzle
