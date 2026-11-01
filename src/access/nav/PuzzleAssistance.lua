-- Reused from the old Pocket Accessibility project (src/accessibility/PuzzleAssistance.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Read-only guidance for puzzles whose native state is difficult to infer
-- without sight. Nothing here moves an actor, changes a flag, or opens a gate.

local Collision = require("src.world.Collision")
local Map = require("src.world.Map")

local PuzzleAssistance = {}

local DIRECTIONS = {
  { 0, -1, "up" }, { 0, 1, "down" },
  { -1, 0, "left" }, { 1, 0, "right" },
}

local VICTORY_ROAD = {
  VICTORY_ROAD_1F = {
    { x = 17, y = 13, flag = "EVENT_VICTORY_ROAD_1_BOULDER_ON_SWITCH",
      label = "Pressure Switch 1", boulder = 1 },
  },
  VICTORY_ROAD_2F = {
    { x = 1, y = 16, flag = "EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1",
      label = "Pressure Switch 1", boulder = 1 },
    { x = 9, y = 16, flag = "EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2",
      label = "Pressure Switch 2", boulder = 3 },
  },
  VICTORY_ROAD_3F = {
    { x = 3, y = 5, flag = "EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1",
      label = "Pressure Switch 1", boulder = 1 },
    { x = 23, y = 15, flag = "EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2",
      label = "Boulder Drop Hole", hole = true, boulder = 4 },
  },
}

function PuzzleAssistance.enabled(game)
  return not (game and game.save and game.save.options
              and game.save.options.puzzleAssistance == false)
end

local function isBoulder(entity)
  return type(entity) == "table" and type(entity.def) == "table"
         and Map.isPushable(entity.def)
end

local function boulderNumber(entity, fallback)
  local name = entity.def and entity.def.name or ""
  return tonumber(name:match("BOULDER(%d+)$")) or fallback
end

local function cellKey(x, y) return tostring(x) .. "," .. tostring(y) end

-- Sokoban search over boulder position plus the player's reachable region.
-- The hard bounds keep malformed mod maps from monopolizing a frame.
local function planShoves(overworld, boulder, targetX, targetY, canMove,
                          canPush, canStand)
  canMove = canMove or Collision.canMove
  local map, player = overworld.map, overworld.player
  if type(map.widthCells) ~= "number" or type(map.heightCells) ~= "number"
     or type(player) ~= "table" then return nil end
  local width, height = map.widthCells, map.heightCells
  local fixed = {}
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    if entity ~= player and entity ~= boulder then fixed[#fixed + 1] = entity end
  end
  local function openForBoulder(x, y, bx, by)
    if x < 0 or y < 0 or x >= width or y >= height then return false end
    if x == bx and y == by then return false end
    local ok, walkable = pcall(map.isWalkableCell, map, x, y)
    return ok and walkable and not Collision.occupied(fixed, x, y)
  end
  local function playerRegion(px, py, bx, by)
    if not openForBoulder(px, py, bx, by)
        or (canStand and not canStand(map, px, py)) then return nil, {} end
    local seen, queue, head = { [cellKey(px, py)] = true }, { { px, py } }, 1
    local representative = py * width + px
    while head <= #queue do
      local cell = queue[head]; head = head + 1
      for _, direction in ipairs(DIRECTIONS) do
        local nx, ny = cell[1] + direction[1], cell[2] + direction[2]
        local key = cellKey(nx, ny)
        if not seen[key] and openForBoulder(nx, ny, bx, by)
            and (not canStand or canStand(map, nx, ny)) then
          local mover = { cellX = cell[1], cellY = cell[2], surfing = false }
          local allowed = canMove(map, fixed, mover, direction[3])
          if allowed then
            seen[key] = true
            queue[#queue + 1] = { nx, ny }
            representative = math.min(representative, ny * width + nx)
          end
        end
      end
    end
    return representative, seen
  end

  local representative, reachable = playerRegion(
    player.cellX, player.cellY, boulder.cellX, boulder.cellY)
  if not representative then return nil end
  local start = { bx = boulder.cellX, by = boulder.cellY,
                  representative = representative, reachable = reachable,
                  path = {} }
  local queue, head, expanded = { start }, 1, 0
  local visited = {
    [cellKey(start.bx, start.by) .. ":" .. tostring(representative)] = true,
  }
  while head <= #queue and expanded < 4096 do
    local node = queue[head]; head = head + 1; expanded = expanded + 1
    if node.bx == targetX and node.by == targetY then return node.path end
    if #node.path < 60 then
      for _, direction in ipairs(DIRECTIONS) do
        local standX, standY = node.bx - direction[1], node.by - direction[2]
        local landX, landY = node.bx + direction[1], node.by + direction[2]
        if node.reachable[cellKey(standX, standY)]
           and openForBoulder(landX, landY, node.bx, node.by)
           and (not canPush or canPush(map, node.bx, node.by,
             direction[3], targetX, targetY)) then
          local rep, region = playerRegion(
            node.bx, node.by, landX, landY)
          local key = rep and (cellKey(landX, landY) .. ":" .. tostring(rep))
          if key and not visited[key] then
            visited[key] = true
            local path = {}
            for i, step in ipairs(node.path) do path[i] = step end
            path[#path + 1] = {
              standX = standX, standY = standY, direction = direction[3],
              boulderX = node.bx, boulderY = node.by,
            }
            queue[#queue + 1] = { bx = landX, by = landY,
              representative = rep, reachable = region, path = path }
          end
        end
      end
    end
  end
  return nil
end

local function strengthPrefix(game, overworld)
  local inventory = game and game.save and game.save.inventory or {}
  local knows = false
  if type(overworld.partyKnows) == "function" then
    local ok, mon = pcall(overworld.partyKnows, overworld, "STRENGTH")
    knows = ok and mon ~= nil
  else
    for _, mon in ipairs(game and game.save and game.save.party or {}) do
      for _, move in ipairs(mon.moves or {}) do
        if move == "STRENGTH" then knows = true break end
      end
      if knows then break end
    end
  end
  if not knows then return "Teach Strength to a party Pokémon; " end
  if not inventory.RAINBOWBADGE then return "Needs Rainbow Badge; " end
  if not overworld.strengthActive then return "Use Strength from the party menu; " end
  return ""
end

local CACHE = setmetatable({}, { __mode = "k" })

local function liveSignature(game, overworld, mapId, targets, rules)
  local prefix = rules.strengthPrefix or strengthPrefix
  local parts = { tostring(overworld.map), mapId,
                  overworld.strengthActive and "strength:on" or "strength:off",
                  prefix(game, overworld) }
  if rules.cacheSignature then
    parts[#parts + 1] = tostring(rules.cacheSignature(overworld))
  end
  local flags = game and game.save and game.save.flags or {}
  for _, target in ipairs(targets or {}) do
    parts[#parts + 1] = table.concat({ tostring(target.x), tostring(target.y),
      tostring(target.boulder), tostring(target.label),
      tostring(target.hole), tostring(target.flag),
      tostring(target.flag ~= nil and flags[target.flag] == true) }, ":")
  end
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    if entity ~= overworld.player then
      local def = type(entity.def) == "table" and entity.def or nil
      parts[#parts + 1] = table.concat({
        tostring(entity.id or (entity.def and entity.def.name)),
        tostring(entity.cellX), tostring(entity.cellY),
        tostring(entity.visible), tostring(entity.passable),
        tostring(def and def.index), tostring(def and def.movement),
      }, ":")
    end
  end
  return table.concat(parts, "|")
end

-- What a generation has to answer for its own puzzles.
--
-- Gen I's three answers were hard-wired: a hand-written coordinate table, a
-- boulder test that reads the sprite name, and Gen I's tile-pair collision.
-- None of the three is right for Gold, and none of them is the interesting part
-- of this module -- the Sokoban search over boulder position plus the player's
-- reachable region is generation-neutral and stays shared.
PuzzleAssistance.RULES = {
  targets = function(mapId) return VICTORY_ROAD[mapId] end,
  isBoulder = isBoulder,
  boulderNumber = boulderNumber,
  canMove = Collision.canMove,
}

function PuzzleAssistance.describe(game, overworld, rules)
  rules = rules or PuzzleAssistance.RULES
  local result = { objects = {}, objectOverrides = {} }
  if not PuzzleAssistance.enabled(game) or type(overworld) ~= "table"
     or type(overworld.map) ~= "table" then return result end
  local mapId = overworld.map.id or (overworld.map.def and overworld.map.def.id)
  local targets = rules.targets(mapId, overworld, game)
  if not targets then return result end
  local signature = liveSignature(game, overworld, mapId, targets, rules)
  local cached = CACHE[overworld]
  if cached and cached.signature == signature then return cached.result end

  local boulders = {}
  for _, entity in ipairs(overworld.entities or overworld.npcs or {}) do
    if rules.isBoulder(entity) then
      boulders[#boulders + 1] = {
        entity = entity,
        number = rules.boulderNumber(entity, #boulders + 1),
      }
    end
  end
  local flags = game and game.save and game.save.flags or {}
  local bestForBoulder = {}
  local prefix = (rules.strengthPrefix or strengthPrefix)(game, overworld)
  for index, target in ipairs(targets) do
    local occupied
    for _, candidate in ipairs(boulders) do
      if candidate.entity.cellX == target.x and candidate.entity.cellY == target.y
          and (not target.requiresBoulder
            or candidate.number == target.boulder) then
        occupied = candidate
        break
      end
    end
    local solved = flags[target.flag] == true or occupied ~= nil
    local best, bestPlan
    if not solved then
      for _, candidate in ipairs(boulders) do
        if candidate.number == target.boulder then
          local plan = planShoves(overworld, candidate.entity,
            target.x, target.y, rules.canMove, rules.canPush,
            rules.canStand)
          if plan then best, bestPlan = candidate, plan end
          break
        end
      end
    end
    local state
    if solved then
      state = occupied and ("pressed by Boulder " .. occupied.number) or "pressed"
    elseif bestPlan then
      state = "not pressed; Boulder " .. best.number .. " can reach it"
        .. "; next push " .. bestPlan[1].direction
      local current = bestForBoulder[best.entity]
      if not current or #bestPlan < #current.plan then
        bestForBoulder[best.entity] = {
          target = target, plan = bestPlan, targetIndex = index,
        }
      end
      if not result.nextAction then
        local first = bestPlan[1]
        result.nextAction = {
          boulderId = best.entity.id or (best.entity.def and best.entity.def.name),
          boulderLabel = "Boulder " .. tostring(best.number),
          targetLabel = target.label,
          standX = first.standX, standY = first.standY,
          direction = first.direction,
          instruction = prefix .. "push " .. first.direction
            .. " toward " .. target.label,
        }
      end
    else
      state = "not pressed; no safe boulder route from current positions"
    end
    if not target.hole then
      result.objects[#result.objects + 1] = {
        id = "victory_road_switch:" .. mapId .. ":" .. tostring(index),
        label = target.label, x = target.x, y = target.y,
        interaction = "pressure_switch", semanticKind = "pressure_switch",
        stateText = state,
        routeInstruction = "Push a boulder onto this pressure switch",
      }
    end
  end

  for _, candidate in ipairs(boulders) do
    local entity, assignment = candidate.entity, bestForBoulder[candidate.entity]
    local override = {
      label = "Boulder " .. tostring(candidate.number),
      interaction = "strength_push", semanticKind = "strength_boulder",
    }
    if assignment then
      local first = assignment.plan[1]
      override.requiredFacing = first.direction
      override.stateText = "target " .. assignment.target.label
        .. "; next push " .. first.direction
      override.routeInstruction = prefix .. "push " .. first.direction
        .. " toward " .. assignment.target.label
    else
      override.stateText = "no currently planned unpressed target"
      override.routeInstruction = prefix .. "push only when a route is known"
    end
    result.objectOverrides[entity.id or (entity.def and entity.def.name)] = override
  end
  CACHE[overworld] = { signature = signature, result = result }
  return result
end

return PuzzleAssistance
