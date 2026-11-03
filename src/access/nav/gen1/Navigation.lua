-- The navigation coordinator for Red, Blue and Yellow: the shared coordinator
-- (../Navigation.lua) plus what Crystal and FireRed got in play (decision 41, the
-- owner's parity request of 2026-11-03).  Everything is read from live game data and
-- done through the game's own actions; nothing here changes a rule.
--
-- - Signs named by their own text, connections only where the game really crosses,
--   and floor holes never walked onto by accident.
-- - Auto-walk pushes boulders (BoulderPlan), flips the Mansion's switches and searches
--   Vermilion Gym's trash cans (SwitchWalk).  Gen 1 has no A press for field moves, only
--   the party menu, so auto-walk calls the same field-move functions that menu calls,
--   after the same checks.
-- - Journeys use field moves when walking gets nowhere.

local Shared = require("src.access.nav.Navigation")
local Pathfinder = require("src.access.nav.Pathfinder")
local Puzzle = require("src.access.nav.PuzzleAssistance")
local BoulderPlan = require("src.access.nav.BoulderPlan")
local TraversalSemantics = require("src.access.nav.TraversalSemantics")
local Map = require("src.world.Map")

local Navigation = {}
Navigation.__index = Navigation
setmetatable(Navigation, { __index = Shared })

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local SIGN_NAME_LENGTH = 48

function Navigation.new(game, opts)
  return setmetatable(Shared.new(game, opts), Navigation)
end

Navigation.autoWalkJourneys = true
-- A door or stair fires when stepped onto, not while standing on it after coming through.
Navigation.stepBackOntoWarps = true

function Navigation:currentMapIdOf(world)
  local map = type(world) == "table" and world.map or nil
  return type(map) == "table" and (map.id or (type(map.def) == "table" and map.def.id)) or nil
end

-- ---------------------------------------------------------------- holes

-- Cells that drop the player (MANSION_HOLES, HOLE_FALLS and VICTORY_ROAD_3F.onStep in
-- data/scripts): walkable tiles with no warp, so a route would cross them unaware.
function Navigation:holeCells(mapId)
  self.holeCache = self.holeCache or {}
  local cached = self.holeCache[mapId]
  if cached then return cached end
  local cells, seen = {}, {}
  local function add(x, y)
    local key = x .. "," .. y
    if not seen[key] then
      seen[key] = true
      cells[#cells + 1] = { x = x, y = y }
    end
  end
  local def = self.game.data.maps[mapId]
  local traversal = TraversalSemantics.forMap(mapId, def)
  for _, warp in ipairs(traversal and traversal.specialWarps or {}) do
    if warp.kind == "hole" then add(warp.x, warp.y) end
  end
  for _, hole in ipairs(Puzzle.seafoamHoles(self.game, mapId)) do add(hole.x, hole.y) end
  self.holeCache[mapId] = cells
  return cells
end

-- The cells no boulder should land on (warps, holes) and those that move a player who
-- steps there (warp tiles, holes; an exit mat waits for a press outward).
function Navigation:avoidedCells(world)
  local avoid, noStand = {}, {}
  local map = world.map
  for _, warp in ipairs(map.def and map.def.warps or {}) do
    avoid[warp.x .. "," .. warp.y] = true
    if map:isWarpTileCell(warp.x, warp.y) then noStand[warp.x .. "," .. warp.y] = true end
  end
  for _, hole in ipairs(self:holeCells(self:currentMapIdOf(world))) do
    avoid[hole.x .. "," .. hole.y] = true
    noStand[hole.x .. "," .. hole.y] = true
  end
  return avoid, noStand
end

function Navigation:worldForCommand()
  if self.plannedWorld then return self.plannedWorld end
  return Shared.worldForCommand(self)
end

-- Only the tree's own tile can be faced for Cut: a tree block also holds fence and path
-- cells, where the game says "nothing to cut" (OverworldState:useCutFieldMove).  Routes
-- through those cells stopped on Pewter's, Viridian's and Route 2's walls.
function Navigation:isCuttableCell(world, x, y)
  if not Shared.isCuttableCell(self, world, x, y) then return false end
  local tileset = world.map.def and world.map.def.tileset
  local tile = world.map:cellTile(x, y)
  return (tileset == "OVERWORLD" and tile == 0x3d) or (tileset == "GYM" and tile == 0x50)
end

-- The doors on field.cardKeyDoors' own map list open with the Card Key.  The same table
-- holds Rocket Hideout's lift gates, which open when their guards are beaten: with the
-- key in the bag, a route went through one and pressed A at it three times.
function Navigation:isCardKeyMap(mapId)
  local card = self.game.data.field.cardKeyDoors
  for _, candidate in ipairs(card and card.maps or {}) do
    if candidate == mapId then return true end
  end
  return false
end

function Navigation:isClosedCardKeyDoorCell(world, x, y)
  return self:isCardKeyMap(self:currentMapIdOf(world)) and Shared.isClosedCardKeyDoorCell(self, world, x, y)
end

function Navigation:tilesetHasWater(map)
  local tileset = map.def and map.def.tileset
  for _, candidate in ipairs(self.game.data.field.waterTilesets or {}) do
    if candidate == tileset then return true end
  end
  return false
end

function Navigation:worldRouteRequest(goals, policy)
  local options, world = Shared.worldRouteRequest(self, goals, policy)
  if not options then return options, world end
  -- A tile number that means water on a coast is a counter or a wall indoors, and Surf is
  -- refused there (IsNextTileShoreOrWater); a route took the Museum's wall as a lake.
  if not self:tilesetHasWater(world.map) then
    local canTraverse, map = options.canTraverse, world.map
    options.canTraverse = function(fromX, fromY, toX, toY, direction, cost, edge)
      if map:isWaterCell(toX, toY) and not map:isWalkableCell(toX, toY) then return false end
      return canTraverse(fromX, fromY, toX, toY, direction, cost, edge)
    end
  end
  local goalSet = {}
  for _, goal in ipairs(goals) do goalSet[goal.x .. "," .. goal.y] = true end
  for index, hole in ipairs(self:holeCells(self:currentMapIdOf(world))) do
    if not goalSet[hole.x .. "," .. hole.y] then
      options.blockedCells[#options.blockedCells + 1] = { x = hole.x, y = hole.y, id = "hole:" .. index }
    end
  end
  return options, world
end

-- Interaction cells skip holes as they do warps: standing there means falling.
function Navigation:interactionGoals(world, item)
  local goals, instructions = Shared.interactionGoals(self, world, item)
  local holes = {}
  for _, hole in ipairs(self:holeCells(self:currentMapIdOf(world))) do holes[hole.x .. "," .. hole.y] = true end
  if next(holes) then
    local kept = {}
    for _, goal in ipairs(goals) do
      if not holes[goal.x .. "," .. goal.y] then kept[#kept + 1] = goal end
    end
    goals = kept
  end
  return goals, instructions
end

-- ---------------------------------------------------------------- the list

-- A sign's words, from the table or the script it opens (never run).
function Navigation:signWords(mapId, def, textId)
  local data = self.game.data
  local ok, text = pcall(data.resolveText, data, def.label, textId)
  if ok and type(text) == "string" then return text end
  local MapScripts = package.loaded["src.script.MapScripts"]
  local script = MapScripts and MapScripts.talkScript(mapId, textId)
  if type(script) ~= "table" then return nil end
  local function scan(rows, depth)
    for _, row in ipairs(rows) do
      if type(row) == "table" then
        for _, value in ipairs(row) do
          if type(value) == "string" and type(data.text[value]) == "string" then return data.text[value] end
          if type(value) == "table" and depth < 3 then
            local found = scan(value, depth + 1)
            if found then return found end
          end
        end
      end
    end
    return nil
  end
  return scan(script, 0)
end

-- The sign's first page on one line, cut at a word.  A short first page ("TRAINER TIPS!",
-- on 22 signs) takes the next one too, or those signs would all read the same.
function Navigation.signNameFrom(text, names)
  if type(text) ~= "string" then return nil end
  names = names or {}
  text = text:gsub("{PLAYER}", names.player or "Player"):gsub("{RIVAL}", names.rival or "Rival")
  local page, rest = text:match("^([^\f]*)\f?(.*)$")
  local function clean(words)
    return (words:gsub("{[^}]*}", " "):gsub("%c", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
  end
  page = clean(page or text)
  if #page < 20 and rest and rest ~= "" then
    page = clean(page .. " " .. (rest:match("^([^\f]*)") or ""))
  end
  if page == "" then return nil end
  if #page > SIGN_NAME_LENGTH then
    local cut = page:sub(1, SIGN_NAME_LENGTH)
    page = cut:match("^(.*)%s%S*$") or cut
  end
  return "Sign: " .. page
end

-- Cells on an edge with a connection where a step really lands on the next map, and
-- whether any exist with Surf.  The game bumps at the others (Pewter's south edge has 2
-- such cells in 28), and the walk "arrived" at a wall.
function Navigation:connectionLandingOpen(world, direction, x, y, surfing)
  local map = world.map
  local connection = ((map.def or map).connections or {})[direction]
  local data = self.game.data
  local dest = connection and data.maps[connection.map]
  local tileset = dest and data.tilesets[dest.tileset]
  if not tileset then return nil end
  local destW, destH = dest.width * 2, dest.height * 2
  local lx, ly
  if direction == "north" then lx, ly = x - connection.offset * 2, destH - 1
  elseif direction == "south" then lx, ly = x - connection.offset * 2, 0
  elseif direction == "west" then lx, ly = destW - 1, y - connection.offset * 2
  else lx, ly = 0, y - connection.offset * 2 end
  lx, ly = math.max(0, math.min(destW - 1, lx)), math.max(0, math.min(destH - 1, ly))
  return Map.defPassable(dest, tileset, lx, ly, surfing)
end

function Navigation:connectionGoals(world, item)
  local goals = Shared.connectionGoals(self, world, item)
  local kept = {}
  for _, goal in ipairs(goals) do
    local water = world.map:isWaterCell(goal.x, goal.y)
    if self:connectionLandingOpen(world, item.direction, goal.x, goal.y, water) then
      kept[#kept + 1] = goal
    end
  end
  return #kept > 0 and kept or goals
end

-- A connection with no cell at all to cross on, even by water (Route 22's north edge is
-- all trees; the way is through the gate).
function Navigation:connectionCrossable(world, item)
  local map = world.map
  local width, height = map.widthCells, map.heightCells
  local function try(x, y)
    local water = map:isWaterCell(x, y)
    return (water or map:isWalkableCell(x, y)) and self:connectionLandingOpen(world, item.direction, x, y, water)
  end
  if item.direction == "north" or item.direction == "south" then
    local y = item.direction == "north" and 0 or height - 1
    for x = 0, width - 1 do if try(x, y) then return true end end
  else
    local x = item.direction == "west" and 0 or width - 1
    for y = 0, height - 1 do if try(x, y) then return true end end
  end
  return false
end

function Navigation:captureWorld(filter)
  local snapshot, reason = Shared.captureWorld(self, filter)
  if not snapshot then return snapshot, reason end
  local world = Shared.worldForCommand(self)
  local mapId = world and self:currentMapIdOf(world)
  local def = mapId and self.game.data.maps[mapId]
  if not def then return snapshot, reason end
  local kept, pads = {}, 0
  for _, item in ipairs(snapshot.browse or {}) do
    local keep = true
    if item.type == "warp" and item.destinationMapId == mapId then
      -- pads on one floor (Saffron Gym's maze): a number, and where each one lands
      pads = pads + 1
      local label = "Teleport pad " .. pads
      local dest = def.warps and item.destinationWarp and def.warps[item.destinationWarp]
      local landing = dest and self.worldSnapshot.formatRelative(item.x, item.y, dest.x, dest.y)
      item.description = label .. tostring(item.description or ""):sub(#item.label + 1)
        .. (landing and ("; lands " .. landing .. " from it") or "")
      item.label = label
    elseif item.type == "signpost" and tostring(item.label):match("^Signpost %d") then
      local who = self.game.save and self.game.save.player or {}
      local name = Navigation.signNameFrom(self:signWords(mapId, def, item.textId),
        { player = who.name, rival = who.rival })
      -- what runs a screen says nothing to read: the map's own name for it (TV, Vending
      -- Machine 1, Prize Vendor 2)
      if not name and type(item.textId) == "string" then
        name = self.worldSnapshot.humanize((item.textId:gsub("^TEXT_%w+_", "")))
      end
      if name then
        item.description = name .. tostring(item.description or ""):sub(#item.label + 1)
        item.label = name
      end
    elseif item.type == "connection" then
      local ok, crossable = pcall(self.connectionCrossable, self, world, item)
      keep = not ok or crossable
    elseif item.semanticKind == "card_key_door" and not self:isCardKeyMap(mapId) then
      item.label, item.requirement, item.interaction = "Lift gate", nil, "inspect"
      item.stateText = "closed until this floor's guards are beaten"
      item.routeInstruction = "Closed passage; beat this floor's guards"
      item.description = "Lift gate"
        .. (item.relativeText and (": " .. item.relativeText) or "") .. "; " .. item.stateText
    end
    if keep then kept[#kept + 1] = item end
  end
  snapshot.browse = kept
  return snapshot, reason
end

-- ---------------------------------------------------------------- field moves

-- Gen 1 starts Cut and Surf only from the party menu (no A press on the map, see
-- OverworldState:interact), so a step needing one calls what that menu calls.  The game
-- shows its own text; the walk pauses for it and carries on.
function Navigation:stepInteraction(world, step)
  if not step then return nil end
  local map, player = world.map, world.player
  if player.surfing then return nil end
  -- the tile number of water is a plain floor tile in some indoor tilesets
  if map:isWaterCell(step.x, step.y) and not map:isWalkableCell(step.x, step.y)
     and not map:isWaterCell(step.fromX, step.fromY) then
    local action = { move = "Surf", failText = "Could not use Surf, auto walk stopped",
      hint = "Use Surf facing " .. step.direction }
    action.use = function()
      local why = world.useSurfFieldMove and world:useSurfFieldMove()
      if why == "ok" then
        local fx, fy = player:facingCell()
        world:trySurf(fx, fy)
        return true
      end
      -- Seafoam Islands B4F, before the boulders above have stopped its current
      if why == "current" then
        action.failText = "The current is too fast to Surf here, auto walk stopped"
        action.hint = "Boulders dropped from the floor above calm it"
      end
      return false
    end
    return action
  end
  if self:isCuttableCell(world, step.x, step.y) then
    return { move = "Cut", failText = "Could not use Cut, auto walk stopped",
      hint = "Use Cut facing " .. step.direction,
      use = function()
        if world.useCutFieldMove and world:useCutFieldMove() == "ok" then
          local fx, fy = player:facingCell()
          return world:tryCut(fx, fy) == true
        end
        return false
      end }
  end
  return nil
end

-- What stands in the way, for auto-walk's refusal: a field move ("Needs Surf"), the
-- Cinnabar quiz doors, or a person in the only way through (the Game Corner's Rocket on
-- his poster, a guard): the list names them, so the player knows who to deal with.
function Navigation:routeNeeds(goals)
  local phrase = self:routeRequirement(goals)
  if phrase and phrase ~= "Cannot reach yet" then return phrase end
  local world = Shared.worldForCommand(self)
  if not world then return nil end
  local passable = {}
  for key, value in pairs(world) do passable[key] = value end
  local people = {}
  for _, entity in ipairs(world.entities or {}) do
    if entity == world.player or (type(entity.def) == "table" and Map.isPushable(entity.def)) then
      people[#people + 1] = entity
    end
  end
  passable.entities, passable.npcs = people, nil
  self.plannedWorld = passable
  local ok, options = pcall(self.worldRouteRequest, self, goals, 2)
  self.plannedWorld = nil
  if ok and options then
    local found, result = pcall(Pathfinder.find, options)
    if found and result then
      for _, step in ipairs(result.steps or {}) do
        for _, entity in ipairs(world.entities or {}) do
          if entity ~= world.player and entity.cellX == step.x and entity.cellY == step.y and not entity.passable then
            local described = self.worldSnapshot.describeEntity(entity, { mapId = self:currentMapIdOf(world) })
            return "Blocked by " .. tostring(described and described.label or "someone")
          end
        end
      end
    end
  end
  local traversal = TraversalSemantics.forMap(self:currentMapIdOf(world), world.map)
  for _, switch in ipairs(traversal and traversal.switches or {}) do
    if switch.gate and not self.game.save.flags[switch.stateFlag] then
      return "Behind doors the quiz machines open"
    end
  end
  return nil
end

-- Exit mats and stair tiles at a map's edge fire only while pressed outward; a walk that
-- reached one sideways said "Arrived" and stayed in the room.  The direction is the
-- game's own check (Warp.extraCheck).
function Navigation:warpPressDirection(world, x, y)
  local map = world.map
  if not map:warpAtCell(x, y) or map:isWarpTileCell(x, y) then return nil end
  local Warp = require("src.world.Warp")
  local carpets = self.game.data.field.warpCarpets
  for _, dir in ipairs({ "down", "up", "left", "right" }) do
    if Warp.extraCheck(map, carpets, x, y, dir) then return dir end
  end
  return nil
end

-- ---------------------------------------------------------------- boulders

function Navigation:startStrength(world)
  local mon = world.partyKnows and world:partyKnows("STRENGTH")
  if mon and world.useStrengthFieldMove then world:useStrengthFieldMove(mon) end
end

local function ledgeFor(self, world)
  return function(x, y, dir) return self:ledgeDestination(world, x, y, dir) end
end

-- The kept plan's next push while the boulders stand where it has them.
local function goalsKey(goals)
  local parts = {}
  for _, goal in ipairs(goals or {}) do parts[#parts + 1] = goal.x .. "," .. goal.y end
  return table.concat(parts, " ")
end

local function nextKeptPush(self, world, goals)
  local kept = self.boulderPlan
  if not (kept and kept.map == world.map) then return nil end
  if kept.mode == "open" and kept.goals ~= goalsKey(goals) then
    self.boulderPlan = nil
    return nil
  end
  while kept.steps[kept.index] do
    local push = kept.steps[kept.index]
    local b = push.boulder.entity
    if b.cellX == push.fromX and b.cellY == push.fromY then return push end
    if b.cellX == push.toX and b.cellY == push.toY then
      kept.index = kept.index + 1
    else
      break
    end
  end
  self.boulderPlan = nil
  return nil
end

-- BoulderWalk's question.  On a floor with holes or pressure switches still open, the
-- next push of filling them, with stone = true; a floor with none, or when none can be
-- filled from here, the first push that opens a way to `goals`.
function Navigation:boulderOpening(world, goals)
  local map = world and world.map
  local mapId = self:currentMapIdOf(world)
  local needs = Puzzle.strengthPrefix(self.game, world)
  local kept = nextKeptPush(self, world, goals)
  if kept then return kept, nil, needs, self.boulderPlan.mode == "fill" end
  local avoid, noStand = self:avoidedCells(world)
  local targets = Puzzle.RULES.targets(mapId, world, self.game)
  local flags = self.game.save and self.game.save.flags or {}
  local unsolved, boulderOn = {}, {}
  for _, entity in ipairs(world.entities or {}) do
    if type(entity.def) == "table" and Map.isPushable(entity.def) then
      boulderOn[entity.cellX .. "," .. entity.cellY] = true
    end
  end
  for _, target in ipairs(targets or {}) do
    if not flags[target.flag] and not boulderOn[target.x .. "," .. target.y] then
      unsolved[#unsolved + 1] = target
    end
  end
  local function keep(steps, mode)
    self.boulderPlan = { map = map, steps = steps, index = 1, mode = mode, goals = goalsKey(goals) }
    return steps[1]
  end
  if #unsolved > 0 then
    local ok, steps, why = pcall(BoulderPlan.fill, world, unsolved, avoid, noStand, ledgeFor(self, world), { maxSeconds = 2 })
    if ok and steps and #steps > 0 then return keep(steps, "fill"), nil, needs, true end
    if ok and why == "budget" then return nil, nil, needs, true end
  end
  -- every goal on a filled floor, or a floor with no holes or switches: only opening
  -- a way remains
  if goals and #goals > 0 then
    local ok, steps, why = pcall(BoulderPlan.opening, world, goals, avoid, noStand, ledgeFor(self, world), { maxSeconds = 1.5 })
    if ok and steps and #steps > 0 then return keep(steps, "open"), nil, needs, false end
    if ok and why == "open" then return nil, "open", needs, targets ~= nil, #unsolved end
    return nil, nil, needs, targets ~= nil
  end
  if targets then
    return nil, "finished", needs, true, #unsolved
  end
  return nil, nil, needs, false
end

-- ---------------------------------------------------------------- switches

-- The Mansion's Secret Switches (the quiz machines carry gates and are answered, not flipped).
function Navigation:switchSigns(world)
  local signs = {}
  local mapId = self:currentMapIdOf(world)
  local traversal = TraversalSemantics.forMap(mapId, world.map)
  if not (traversal and traversal.stateFlag) then return signs end
  for _, switch in ipairs(traversal.switches or {}) do
    if not switch.gate then
      local goals = self:interactionGoals(world, { type = "object", x = switch.x, y = switch.y,
        requiredFacing = switch.requiredFacing })
      if #goals > 0 then
        signs[#signs + 1] = { label = "Secret switch " .. switch.x .. "," .. switch.y,
          x = switch.x, y = switch.y, goals = goals }
      end
    end
  end
  return signs
end

-- The cans the second switch can be under once the first is found under `first`: the
-- game's own table of neighbours (vermilion_gym_trash.asm GymTrashCans, Yellow's table),
-- plus can 0 for the bug that table is known for.  Candidates only; which one holds the
-- switch is found by pressing.
local function secondCandidates(trash, first)
  local set = { [0] = true }
  if trash.yellowTable then
    local yt = trash.yellowTable
    local row = first * 9 + 1
    for i = 1, 2 * (yt[row] or 0) do
      if yt[row + i] then set[yt[row + i]] = true end
    end
  else
    for _, can in ipairs((trash.adjacent or {})[first] or {}) do set[can] = true end
  end
  return set
end

-- Vermilion Gym's trash cans, for the same walk's hidden switches.  It learns by pressing:
-- the first switch is under an even can (Random & $e), the second near the first, and a
-- wrong second can sends the game back to the start with a new first.  The flags and the
-- first can are what the game has just told the player on screen.
function Navigation:hiddenSwitchSigns(world)
  local signs = {}
  local mapId = self:currentMapIdOf(world)
  local trash = self.game.data.field.hiddenExtras and self.game.data.field.hiddenExtras.trashCans
  if not (trash and mapId == "VERMILION_GYM") then return signs end
  local save = self.game.save
  local puzzle = save.trashPuzzle or {}
  local candidates = save.flags.EVENT_1ST_LOCK_OPENED and puzzle.first
    and secondCandidates(trash, puzzle.first) or nil
  for _, can in ipairs(trash.cans or {}) do
    local goals = self:interactionGoals(world, { type = "object", x = can.x, y = can.y })
    local plausible = candidates and candidates[can.can] or (not candidates and can.can % 2 == 0)
    if #goals > 0 and plausible then
      signs[#signs + 1] = { label = "Trash can " .. tostring(can.can), x = can.x, y = can.y, goals = goals }
    end
  end
  return signs
end

function Navigation:floorMarks()
  local flags = self.game.save.flags
  return (flags.EVENT_1ST_LOCK_OPENED and "1" or "0") .. (flags.EVENT_2ND_LOCK_OPENED and "1" or "0")
end

-- ---------------------------------------------------------------- journeys

-- The Area category: the shared list of item balls, plus each other floor of the area
-- itself, aimed at through a warp whose four sides are all on that floor (a journey's goals
-- are the cells around its target).
function Navigation:areaBrowse(world)
  local items = Shared.areaBrowse(self, world)
  local maps = self.game.data.maps
  local here = self:currentMapIdOf(world)
  local key = type(here) == "string" and here:match("^([A-Z0-9]+_[A-Z0-9]+)") or nil
  if not key then return items end
  local members = {}
  for mapId, def in pairs(maps) do
    if type(mapId) == "string" and mapId ~= here and type(def) == "table" and type(def.warps) == "table"
       and mapId:match("^([A-Z0-9]+_[A-Z0-9]+)") == key then
      members[#members + 1] = mapId
    end
  end
  table.sort(members)
  local floors = {}
  for _, mapId in ipairs(members) do
    local def = maps[mapId]
    local width, height = (def.width or 0) * 2, (def.height or 0) * 2
    for _, warp in ipairs(def.warps) do
      -- stairs or a door, not a pad that throws the walk around
      if warp.destMap ~= mapId and warp.x > 0 and warp.y > 0 and warp.x < width - 1 and warp.y < height - 1 then
        local name = tostring(self:regionalDestinationName(mapId))
        floors[#floors + 1] = { id = "area:" .. mapId, type = "area", category = "area", label = name,
          description = name, mapId = mapId, x = warp.x, y = warp.y }
        break
      end
    end
  end
  for _, item in ipairs(items) do floors[#floors + 1] = item end
  return floors
end

-- One plan asks for the same floors over and over: built once per plan (Map.new parses
-- the whole floor, and the budget ran out on Pokemon Tower and the Mansion).
function Navigation:regionalStaticWorld(mapId, start)
  local cache = self.regionalWorlds
  local world = cache and cache[mapId]
  if not world then
    world = Shared.regionalStaticWorld(self, mapId, start)
    if not world then return nil end
    local live = Shared.worldForCommand(self)
    if live and live.partyKnows then
      world.partyKnows = function(_, moveId) return live:partyKnows(moveId) end
    end
    if cache then cache[mapId] = world end
  end
  world.player.cellX, world.player.cellY = start.x, start.y
  return world
end

-- Every cell a player can walk to from `start` on a floor, by the rules of a walked route
-- (floor holes and warps stop the walk: they can be walked onto, not across).  One flood
-- answers all of a floor's transitions: a route per transition ran out of time on
-- Pokemon Tower, the Mansion and Victory Road.
function Navigation:regionalFlood(mapId, start, useLive)
  local policy = self.regionalPolicy or 1
  local key = table.concat({ mapId, start.x, start.y, policy, useLive and "live" or "plan" }, ":")
  local floods = self.regionalFloods
  if floods and floods[key] then return floods[key] end
  local live = Shared.worldForCommand(self)
  local world
  if useLive and live and self:currentMapIdOf(live) == mapId
     and live.player.cellX == start.x and live.player.cellY == start.y then
    world = live
  else
    world = self:regionalStaticWorld(mapId, start)
  end
  if not world then return nil end
  self.plannedWorld = world ~= live and world or nil
  local ok, options = pcall(self.worldRouteRequest, self, { { x = -1, y = -1 } }, policy)
  self.plannedWorld = nil
  if not ok or not options then return nil end
  local width, height = options.bounds.width, options.bounds.height
  local stops = {}
  for _, cell in ipairs(options.blockedCells or {}) do
    if cell.x and cell.y then stops[cell.y * width + cell.x] = true end
  end
  local first = start.y * width + start.x
  local cost, queue, head = { [first] = 0 }, { first }, 1
  while queue[head] do
    local at = queue[head]
    head = head + 1
    local x, y = at % width, math.floor(at / width)
    for _, edge in ipairs(options.neighbors(x, y)) do
      if edge.x >= 0 and edge.y >= 0 and edge.x < width and edge.y < height then
        local to = edge.y * width + edge.x
        if not cost[to] and options.canTraverse(x, y, edge.x, edge.y, edge.direction, nil, edge) then
          cost[to] = cost[at] + 1
          if not stops[to] then queue[#queue + 1] = to end
        end
      end
    end
  end
  local flood = { cost = cost, width = width }
  if floods then floods[key] = flood end
  return flood
end

-- The journey planner only wants to know whether, and how far.
function Navigation:regionalDryRoute(mapId, start, goals, useLive)
  local flood = self:regionalFlood(mapId, start, useLive)
  if not flood then return nil end
  local best
  for _, goal in ipairs(goals or {}) do
    local cost = goal.x >= 0 and goal.y >= 0 and goal.x < flood.width and flood.cost[goal.y * flood.width + goal.x]
    if cost and (not best or cost < best) then best = cost end
  end
  return best and { cost = best } or nil
end

-- Holes are ways down too: on the Mansion's 3F they are the only way into the sealed part of
-- 1F.  Walked to only when the search finds no way without them is not promised: the
-- search takes the shortest.
function Navigation:regionalTransitions(mapId)
  local cached = self.regionalLinks and self.regionalLinks[mapId]
  if cached then return cached end
  local result = Shared.regionalTransitions(self, mapId)
  if self.regionalLinks then self.regionalLinks[mapId] = result end
  local def = self.game.data.maps[mapId]
  local traversal = def and TraversalSemantics.forMap(mapId, def)
  for _, warp in ipairs(traversal and traversal.specialWarps or {}) do
    if warp.kind == "hole" and self.game.data.maps[warp.destinationMap] then
      result[#result + 1] = { kind = "warp", x = warp.x, y = warp.y, destMap = warp.destinationMap,
        destX = warp.destinationX, destY = warp.destinationY }
    end
  end
  return result
end

-- Walking first; then what the party can do, as a walked route does.
function Navigation:regionalNextLeg(navigation)
  self.regionalWorlds, self.regionalLinks, self.regionalFloods = {}, {}, {}
  self.regionalPolicy = 1
  local ok, leg, reason = pcall(Shared.regionalNextLeg, self, navigation)
  if ok and not leg and reason ~= "regional search timed out" then
    self.regionalPolicy = 2
    local okSecond, second, why = pcall(Shared.regionalNextLeg, self, navigation)
    if okSecond and second then leg, reason = second, nil
    elseif okSecond then reason = why or reason end
  end
  self.regionalPolicy, self.regionalWorlds, self.regionalLinks, self.regionalFloods = nil, nil, nil, nil
  if not ok then return nil, "no regional path" end
  -- an Area target is aimed at through the cells around it: never one that moves the player
  -- (Silph Co. 8F's pads threw a walk back and forth for ever)
  if leg and leg.final then
    local world = Shared.worldForCommand(self)
    local _, noStand = self:avoidedCells(world)
    local kept = {}
    for _, goal in ipairs(leg.goals or {}) do
      if not noStand[goal.x .. "," .. goal.y] then kept[#kept + 1] = goal end
    end
    if #kept > 0 then leg.goals = kept end
  end
  return leg, reason
end

return Navigation
