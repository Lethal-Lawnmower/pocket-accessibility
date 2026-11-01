-- Reused from the old Pocket Accessibility project
-- (src/accessibility/gen2/Accessibility.lua at commit 71cdd419e, upstream
-- v0.3.32) under decision 20, navigation half only; adapted for v0.3.98.
-- Its screen speech (describe), battle health and battle damage parts are
-- not carried over: those are the new presenters in src/access/screens.
-- Nothing here changes game state.

-- The navigation coordinator for Gold, Silver and Crystal: a subclass of the
-- Gen 1 coordinator (../Navigation.lua) that answers every world question
-- from Gen 2's own data -- COLL_* collision (src/world/gen2/Permissions.lua),
-- the live World and its NPCs, warps, bg events, connections, field moves,
-- badges and the stone-table command queue.  The commands, object list,
-- route narration, guided navigation, cross-map planner and sonar logic are
-- the shared ones.
--
-- Three upstream additions the old code relied on do not exist at v0.3.98
-- and are re-derived read-only: World:busyBesidesMovement (the fields of
-- World:busy, WorldAdapter.gen2.scriptHeld), Clock.meridiemLabel (AM/PM the
-- way the Pokegear's clock card prints it) and NPC.BIG_OBJECT (the live
-- `bigObject` field; the movement bytes for planned maps).

local Shared = require("src.access.nav.Navigation")
local Snapshot = require("src.access.nav.gen2.WorldSnapshot")
local Terrain = require("src.access.nav.gen2.TerrainSemantics")
local Puzzle = require("src.access.nav.gen2.PuzzleAssistance")
local WorldAdapter = require("src.access.nav.WorldAdapter")
local Pathfinder = require("src.access.nav.Pathfinder")
local Permissions = require("src.world.gen2.Permissions")
local Gen2Map = require("src.world.gen2.Map")
local FieldMoves = require("src.world.gen2.FieldMoves")

local Gen2 = WorldAdapter.gen2

local Navigation = {}
Navigation.__index = Navigation
setmetatable(Navigation, { __index = Shared })

local ORDER = { "up", "right", "down", "left" }
local DELTA = {
  up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
}
local function cellKey(x, y) return tostring(x) .. "," .. tostring(y) end

local function titleCase(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("\n", " ")
  text = text:gsub("(%a)(%a*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
  text = text:gsub("Pok\195\169Mon", "Pok\195\169mon")
  text = text:gsub("%.(%a%a)", ". %1")
  return text
end

function Navigation.new(game, opts)
  opts = opts or {}
  opts.worldSnapshot = opts.worldSnapshot or Snapshot
  opts.terrainSemantics = opts.terrainSemantics or Terrain
  opts.puzzleAssistance = opts.puzzleAssistance or Puzzle
  local self = Shared.new(game, opts)
  self.generation = 2
  return setmetatable(self, Navigation)
end

-- ------------------------------------------------------------ the world

-- One stable facade per live World, so routes that yield across frames and
-- auto-walk keep one identity.  Every read goes through to the live world
-- (its map, NPCs and player change on each load); only the player is wrapped,
-- to answer `surfing` and `onBike` from the world's player state the way Gen 1
-- players carry them, and `entities` puts that wrapper first.
function Navigation:worldState()
  local native = self.game and self.game.world
  if not (type(native) == "table" and native.map and native.player) then return nil end
  local facade = self.gen2WorldFacade
  if facade and facade.native == native then return facade end
  local player = setmetatable({}, { __index = function(_, key)
    if key == "surfing" then return FieldMoves.isSurfing(native.playerState) end
    if key == "onBike" then return FieldMoves.isBiking(native.playerState) end
    local live = native.player
    return live and live[key]
  end })
  facade = setmetatable({ native = native, player = player }, {
    __index = function(_, key)
      if key == "entities" then
        local list = { player }
        for _, npc in ipairs(native.npcs or {}) do list[#list + 1] = npc end
        return list
      elseif key == "surfing" then
        return FieldMoves.isSurfing(native.playerState)
      end
      return native[key]
    end,
  })
  self.gen2WorldFacade = facade
  return facade
end

-- The world may be spoken of: no screen, script, text, menu, field-move
-- animation, battle or door fade over it.  Movement (walking, ice, currents,
-- a whirlpool's bounce) does not stop narration.
function Navigation:isDescribableWorld()
  local game = self.game
  local native = game and game.world
  if not (game and game.phase == "play" and type(native) == "table"
          and native.map and native.player) then return false end
  if game.stack and game.stack:top() ~= nil then return false end
  if native.mapSetup ~= nil then return false end
  return not Gen2.scriptHeld(native)
end

-- The player can act and a route may be measured from where they stand: also
-- no scripted movement, and not on a cell whose next move is forced (ice
-- latch, current, waterfall, the step off an arrival door).  Mid-step is fine,
-- as it is in Gen 1: routes start from the cell being left.
function Navigation:isActionableWorld()
  if not self:isDescribableWorld() then return false end
  local native = self.game.world
  if native.moveState ~= nil then return false end
  return not Gen2.transitioning(native)
end

function Navigation:worldForCommand()
  if not self:isActionableWorld() then return nil, "Not on a map" end
  return self:worldState()
end

function Navigation:currentMapIdOf(world)
  local map = type(world) == "table" and world.map or nil
  return map and (map.id or (type(map.def) == "table" and map.def.id)) or nil
end

-- ------------------------------------------------------------ names

function Navigation:speakerNames()
  local save = self.game and self.game.save
  if type(save) ~= "table" then return nil end
  local names, found = {}, false
  for _, value in ipairs({
    save.player and save.player.name, save.rival and save.rival.name,
    save.mom and save.mom.name,
  }) do
    if type(value) == "string" and value ~= "" then
      names[value] = true
      found = true
    end
  end
  return found and names or nil
end

-- The names objects are labelled with.  A new game's rival is "???" until the
-- player names him to the officer (Save.lua seeds wRivalName that way, as the
-- cartridge does); a screen reader may say nothing at all for "???", so the
-- object is "Rival" until then.
local function saveNames(game)
  local save = game and game.save or {}
  local rival = save.rival and save.rival.name
  if type(rival) == "string" and not rival:find("%w") then rival = "Rival" end
  return save.player and save.player.name, rival, save.mom and save.mom.name
end

-- ------------------------------------------------------------ field moves

local function badgeLabel(badge)
  return titleCase(tostring(badge)) .. " Badge"
end

local MOVE_LABEL = {
  CUT = "Cut", SURF = "Surf", STRENGTH = "Strength", WHIRLPOOL = "Whirlpool",
  WATERFALL = "Waterfall", HEADBUTT = "Headbutt", ROCK_SMASH = "Rock Smash",
  FLASH = "Flash",
}

-- The checks the game makes before a field move works: a party member that
-- can use it (World:partyMoveUser, which honours fieldmove.eligibility) and,
-- for the HMs, the badge (FieldMoves.BADGE).  Returns usable, missing-move,
-- missing-badge.
function Navigation:fieldMoveStatus(moveId)
  local native = self.game and self.game.world
  local save = self.game and self.game.save
  local hasMon = false
  if native and type(native.partyMoveUser) == "function" then
    local ok, mon = pcall(native.partyMoveUser, native, moveId)
    hasMon = ok and mon ~= nil
  end
  local badge = FieldMoves.BADGE[moveId]
  local hasBadge = FieldMoves.hasBadge(save, badge)
  return hasMon and hasBadge, not hasMon, (not hasBadge) and badge or nil
end

-- "Needs Cut", "Needs Hive Badge", or nil when the player can use it.  The
-- old code's `allowed and nil or "Needs X"` always gave the phrase; this
-- spells the condition out.
function Navigation:fieldMoveRequirement(moveId)
  local usable, missingMon, missingBadge = self:fieldMoveStatus(moveId)
  if usable then return nil end
  local parts = {}
  if missingMon then parts[#parts + 1] = MOVE_LABEL[moveId] or titleCase(moveId) end
  if missingBadge then parts[#parts + 1] = badgeLabel(missingBadge) end
  return "Needs " .. table.concat(parts, " and ")
end

function Navigation:hmAllowed(_world, moveId, policy)
  -- Honour the base default: connectionGoals and interactionGoals call this
  -- with no policy.
  policy = policy or 2
  if policy == 3 then return true end
  if policy ~= 2 then return false end
  return (self:fieldMoveStatus(moveId)) == true
end

function Navigation:isCuttableCell(world, x, y)
  local map = world and world.map
  if not (map and map:inBounds(x, y)) then return false end
  return Permissions.isCutTree(map:cellCollision(x, y))
end

function Navigation:hasCardKey() return false end
function Navigation:isClosedCardKeyDoorCell() return false end

-- Auto-walk: the steps that need an A press facing them, the way the player
-- starts these field moves on the map (the game asks before using one).
local A_PRESS_KINDS = { cut = "Cut", whirlpool = "Whirlpool", surf = "Surf",
  waterfall = "Waterfall" }

function Navigation:stepInteraction(_world, step)
  local move = step and A_PRESS_KINDS[step.kind]
  if not move then return nil end
  return { move = move, failText = "Could not use " .. move .. ", auto walk stopped",
    hint = "Use " .. move .. " facing " .. step.direction }
end

-- Auto-walk's last cell of a walk to a carpet warp (a doormat or gate mat):
-- it fires only while its direction is held (Permissions.carpetDirection).
function Navigation:warpPressDirection(world, x, y)
  local map = world and world.map
  if not (map and map:inBounds(x, y)) then return nil end
  return Permissions.carpetDirection(map:cellCollision(x, y))
end

-- ------------------------------------------------------------ object list

local STD_TILES = Terrain.STD_TILES

local FIELD_TILES = {
  { test = Permissions.isCutTree, kind = "cut_tree", label = "Cuttable Tree", move = "CUT" },
  { test = Permissions.isHeadbuttTree, kind = "headbutt_tree", label = "Headbutt Tree", move = "HEADBUTT" },
  { test = Permissions.isWhirlpool, kind = "whirlpool", label = "Whirlpool", move = "WHIRLPOOL" },
  { test = Permissions.isWaterfall, kind = "waterfall", label = "Waterfall", move = "WATERFALL",
    requiredFacing = "up" },
}

local function tileKind(coll)
  for _, field in ipairs(FIELD_TILES) do
    if field.test(coll) then return field.kind, field end
  end
  local label = STD_TILES[coll]
  if label then return "std:" .. label, { kind = "standard_interaction", label = label } end
  return nil
end

-- Interactive tiles, one object per connected group of the same kind (a
-- two-cell bookshelf or a 2x2 tree block is one object; every cell can be
-- faced).  Waterfalls are climbed from below, so only each column's bottom
-- cells are interaction cells.  Mod-authored objects and the puzzle's own
-- objects are added as in Gen 1.
function Navigation:interactiveBrowseObjects(world, puzzle)
  local map = world and world.map
  if type(map) ~= "table" or type(map.widthCells) ~= "number" then return {} end
  local mapId = self:currentMapIdOf(world) or "unknown"
  local width, height = map.widthCells, map.heightCells
  local kinds, seen = {}, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      kinds[y * width + x] = tileKind(map:cellCollision(x, y))
    end
  end
  -- a standard tile with a sign on it is listed as that sign (its A press
  -- runs the sign's script), so its group is not listed twice
  local signCells = {}
  for _, sign in ipairs(Snapshot.projectSigns(type(map.def) == "table" and map.def or {},
                                              world.native or world, map)) do
    for _, cell in ipairs(sign.cells or { sign }) do signCells[cell.y * width + cell.x] = true end
  end
  local player = world.player
  local result, ids = {}, {}
  local function add(record)
    if type(record) ~= "table" or type(record.x) ~= "number"
       or type(record.y) ~= "number" then return end
    local id = record.id
    if type(id) ~= "string" or id == "" or ids[id] then return end
    ids[id] = true
    result[#result + 1] = record
  end
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x
      local kind = kinds[index]
      if kind and not seen[index] then
        local _, info = tileKind(map:cellCollision(x, y))
        -- flood the 4-connected group of this kind
        local cells, queue, head = {}, { { x, y } }, 1
        seen[index] = true
        while head <= #queue do
          local cx, cy = queue[head][1], queue[head][2]
          head = head + 1
          cells[#cells + 1] = { x = cx, y = cy }
          for _, d in pairs(DELTA) do
            local nx, ny = cx + d[1], cy + d[2]
            local ni = ny * width + nx
            if nx >= 0 and ny >= 0 and nx < width and ny < height
               and not seen[ni] and kinds[ni] == kind then
              seen[ni] = true
              queue[#queue + 1] = { nx, ny }
            end
          end
        end
        local signed = false
        if info.kind == "standard_interaction" then
          for _, cell in ipairs(cells) do
            if signCells[cell.y * width + cell.x] then signed = true break end
          end
        end
        local faced = signed and {} or cells
        if info.requiredFacing == "up" then
          faced = {}
          for _, cell in ipairs(cells) do
            if kinds[(cell.y + 1) * width + cell.x] ~= kind then faced[#faced + 1] = cell end
          end
        end
        local nearest, best = faced[1], math.huge
        for _, cell in ipairs(faced) do
          local distance = player and (math.abs(cell.x - player.cellX)
            + math.abs(cell.y - player.cellY)) or 0
          if distance < best then nearest, best = cell, distance end
        end
        if nearest then
          add({
            id = info.kind .. ":" .. mapId .. ":" .. cellKey(cells[1].x, cells[1].y),
            label = info.label, x = nearest.x, y = nearest.y,
            interaction = info.move and "field_move" or "interact",
            interactionCells = faced, requiredFacing = info.requiredFacing,
            semanticKind = info.kind,
            requirement = info.move and self:fieldMoveRequirement(info.move) or nil,
          })
        end
      end
    end
  end

  local def = type(map.def) == "table" and map.def or {}
  local authored = def.accessibilityObjects
  local a11y = type(def.accessibility) == "table" and def.accessibility or nil
  if type(authored) ~= "table" and a11y then authored = a11y.interactiveObjects end
  for i, object in ipairs(type(authored) == "table" and authored or {}) do
    local copy = {}
    for key, value in pairs(object) do copy[key] = value end
    copy.id = copy.id or ("interactive:" .. tostring(mapId) .. ":" .. i)
    add(copy)
  end
  puzzle = puzzle or self.puzzleAssistance.describe(self.game, world)
  for _, object in ipairs(puzzle.objects or {}) do add(object) end
  return result
end

local SMASHABLE_ROCK, STRENGTH_BOULDER = 0x18, 0x19

-- Labels and requirements for the object-backed field obstacles: smashable
-- rocks (Rock Smash) and Strength boulders off the puzzle floors.
function Navigation:fieldObjectOverrides(world)
  local overrides = {}
  for _, npc in ipairs(world.npcs or {}) do
    local def = type(npc) == "table" and npc.def or nil
    local movement = def and def.movement
    if npc.id and movement == SMASHABLE_ROCK then
      overrides[npc.id] = { label = "Smashable Rock", interaction = "field_move",
        requirement = self:fieldMoveRequirement("ROCK_SMASH") }
    elseif npc.id and movement == STRENGTH_BOULDER then
      overrides[npc.id] = { requirement = self:fieldMoveRequirement("STRENGTH") }
    end
  end
  return overrides
end

-- Stone-table holes: one object each, named by their table row, with the
-- puzzle's state, instead of one grouped "Drop to" entry.
local function holeTargets(puzzle)
  local holes = {}
  for _, target in ipairs(puzzle and puzzle.targetStates or {}) do
    if target.hole then holes[cellKey(target.x, target.y)] = target end
  end
  return holes
end

function Navigation:captureWorld(filter)
  local world, reason = self:worldForCommand()
  if not world then return nil, reason end
  local data, save = self.game.data, self.game.save
  local puzzle = self.puzzleAssistance.describe(self.game, world)
  local overrides = self:fieldObjectOverrides(world)
  for key, override in pairs(puzzle.objectOverrides or {}) do
    local merged = {}
    for k, v in pairs(overrides[key] or {}) do merged[k] = v end
    for k, v in pairs(override) do merged[k] = v end
    overrides[key] = merged
  end
  local playerName, rivalName, momName = saveNames(self.game)
  local snapshot, snapshotError = self.worldSnapshot.capture(world, {
    maps = data and data.gen2Maps,
    filter = filter or self.browseFilter,
    customNames = self:customNames(),
    playerName = playerName, rivalName = rivalName, momName = momName,
    edition = save and save.version,
    -- species display names, for Pokemon objects named by their cry
    pokemon = data and data.pokemon,
    interactiveObjects = self:interactiveBrowseObjects(world, puzzle),
    objectOverrides = overrides,
    holeTargets = holeTargets(puzzle),
  })
  if snapshot and (filter or self.browseFilter) == "area" then
    snapshot.browse = self:areaBrowse(world)
  end
  return snapshot, snapshotError
end

function Navigation:readCollisionTiles()
  local world, reason = self:worldForCommand()
  if not world then return self:announceManual({ reason }) end
  local map, player = world.map, world.player
  local x, y = player.cellX, player.cellY
  local function value(cx, cy)
    local ok, coll = pcall(map.cellCollision, map, cx, cy)
    return ok and coll ~= nil and tostring(coll) or "unknown"
  end
  return self:announceManual({
    ("Now on %s, Up %s, Down %s, Left %s, Right %s"):format(
      value(x, y), value(x, y - 1), value(x, y + 1), value(x - 1, y), value(x + 1, y)),
  })
end

-- ------------------------------------------------------------ world events

-- Gold encodes a ledge hop on the cell the player stands on, and the terrain
-- footstep below already cues `ledge` there; Gen 1's adjacent-ledge cue would
-- cue it twice (the old project measured "ledge, ledge").
function Navigation:hasAdjacentLedge() return false end

local FOOTSTEP = { grass = true, water = true, ice = true, current = true,
  waterfall = true, whirlpool = true, ledge = true }

function Navigation:usesTerrainFootstep(record)
  return type(record) == "table" and FOOTSTEP[record.kind] == true
end

-- Crystal shows the landmark's name on a sign when the player enters a new
-- one (src/world/gen2/MapNameSign.lua; Gold and Silver show none).  Speak the
-- name the sign shows, once per sign, unless it repeats the map name.
function Navigation:announceLandmarkSign(world)
  local native = world and world.native
  local sign = native and native.mapSign
  if type(sign) ~= "table" or sign == self.lastLandmarkSign then return end
  self.lastLandmarkSign = sign
  local name = titleCase(sign.name)
  if type(name) ~= "string" or name == "" then return end
  local mapId = self:currentMapIdOf(world)
  local names = self:customNames()
  local location = self.worldSnapshot.locationName(world.map, mapId,
    type(names.maps) == "table" and names.maps[mapId] or nil, (saveNames(self.game)))
  local function plain(text) return tostring(text or ""):lower():gsub("[^%w]", "") end
  if plain(location):find(plain(name), 1, true) then return end
  self:announce(name, { interrupt = false })
end

function Navigation:processWorldEvents(_state)
  if not self:isDescribableWorld() then
    return Shared.processWorldEvents(self, nil)
  end
  -- `transient`: cue this cell, but do not re-announce a route from it.
  local result = Shared.processWorldEvents(self, {
    isOverworld = true,
    transient = not self:isActionableWorld(),
  })
  if not self.pendingMapEvent then self:announceLandmarkSign(self:worldState()) end
  return result
end

function Navigation:updateNavigationInterruption(state)
  local navigation = self.activeNavigation
  if not navigation then
    self.navigationInterruptedByBattle = false
    return false
  end
  if type(state) == "table"
     and (state.isBattle == true or state.accessibilityRole == "battle") then
    self.navigationInterruptedByBattle = true
    return false
  end
  if self.navigationInterruptedByBattle and self:isActionableWorld() then
    self.navigationInterruptedByBattle = false
    navigation.lastDirectiveKey = nil
    return self:refreshActiveNavigation()
  end
  return false
end

-- ------------------------------------------------------------ time (Q)

function Navigation:readGameTime()
  local native = self.game and self.game.world
  if not (native and type(native.hour) == "function") then
    return self:announceManual({ "Time unavailable" })
  end
  local Clock = require("src.core.gen2.Clock")
  local okHour, hour = pcall(native.hour, native)
  local okMinute, minute = pcall(native.minute, native)
  local okDay, weekday = pcall(native.weekday, native)
  if not (okHour and okMinute and type(hour) == "number" and type(minute) == "number") then
    return self:announceManual({ "Time unavailable" })
  end
  local display = hour % 12
  if display == 0 then display = 12 end
  -- the Pokegear's clock card: AM below 12, PM from 12 (src/ui/gen2/Pokegear.lua)
  local meridiem = hour < 12 and "AM" or "PM"
  local day = okDay and type(weekday) == "number" and Clock.weekdayName(weekday + 1) or nil
  local daytime = ({ MORN = "morning", DAY = "day", NITE = "night" })[Clock.daytimeLabel(hour)]
  local parts = {}
  if day then parts[#parts + 1] = titleCase(day) end
  parts[#parts + 1] = ("%d:%02d %s"):format(display, minute, meridiem)
  if daytime then parts[#parts + 1] = daytime end
  return self:announceManual({ table.concat(parts, ", ") })
end

-- ------------------------------------------------------------ routing

-- Movement collision answers for an NPC the way the engine's does: one that
-- stands on the cell (World:npcAt covers a big object's whole 2x2), or one
-- walking into it, unless it is passable or authored as ignorable.
local function actorBlocks(npc)
  if npc == nil then return false end
  if npc.passable then return false end
  return not (type(npc.def) == "table" and npc.def.ignorable == true)
end

local function npcBlocks(native, x, y)
  if type(native) ~= "table" then return false end
  if type(native.npcAt) == "function" then
    local ok, npc = pcall(native.npcAt, native, x, y)
    if ok and actorBlocks(npc) then return true end
  end
  for _, actor in ipairs(type(native.npcs) == "table" and native.npcs or {}) do
    if type(actor) == "table" and actor.moving
       and actor.targetX == x and actor.targetY == y and actorBlocks(actor) then
      return true
    end
  end
  return false
end

-- The collision byte for side-wall checks: across a map seam on the live
-- world (World:cellCollisionAcross, as movement reads it), inside the map
-- for a planned one.
local function collisionReader(world)
  local map, native = world.map, world.native
  if type(native) == "table" and type(native.cellCollisionAcross) == "function"
     and native.map == map then
    return function(x, y)
      local ok, coll = pcall(native.cellCollisionAcross, native, map, x, y)
      if ok then return coll end
      return map:cellCollision(x, y)
    end
  end
  return function(x, y) return map:cellCollision(x, y) end
end

-- One movement graph for the live world and for planned maps, so a planned
-- leg obeys the physics of the walked one: side walls on the standing and
-- neighbouring cells, two-cell ledge hops off the ledge cell, ice slides and
-- currents as single edges, Surf entry, Cut and Whirlpool ("use, then
-- move"), Waterfall climbs, big objects, and warps blocked unless they are
-- the goal.
function Navigation:routeOptionsFor(world, goals, policy)
  if not world then return nil, "Not on a map" end
  if type(goals) ~= "table" or #goals == 0 then return nil, "No path" end
  policy = policy or 1
  local map, native, player = world.map, world.native, world.player
  local goalSet = {}
  for _, goal in ipairs(goals) do goalSet[cellKey(goal.x, goal.y)] = true end
  local canSurf = player.surfing == true or self:hmAllowed(world, "SURF", policy)
  local canCut = self:hmAllowed(world, "CUT", policy)
  local canWhirlpool = self:hmAllowed(world, "WHIRLPOOL", policy)
  local canWaterfall = self:hmAllowed(world, "WATERFALL", policy)
  local collOf = collisionReader(world)

  local function passable(x, y, allowWarp)
    if not map:inBounds(x, y) or npcBlocks(native, x, y) then return false end
    local coll = map:cellCollision(x, y)
    if map:warpAt(x, y) and Permissions.isWarpCollision(coll) and not allowWarp then
      return false
    end
    if Permissions.isCutTree(coll) then return canCut end
    if Permissions.isWhirlpool(coll) then return canWhirlpool end
    -- a waterfall is water; only a climber may enter it (descending is the
    -- current's own carry, below)
    if Permissions.isWaterfall(coll) then return canWaterfall end
    if Permissions.isWalkable(coll) then return true end
    if Permissions.isWater(coll) then return canSurf end
    return false
  end

  local function permitted(x, y, direction)
    return Permissions.stepPermitted(collOf, x, y, direction)
  end

  local function landing(fromX, fromY, direction)
    local d = DELTA[direction]
    local x, y = fromX + d[1], fromY + d[2]
    if not permitted(fromX, fromY, direction) then return nil end
    if not passable(x, y, goalSet[cellKey(x, y)] == true) then
      local facings = Permissions.ledgeFacings(map:cellCollision(fromX, fromY))
      if not (facings and facings[direction]) then return nil end
      x, y = fromX + d[1] * 2, fromY + d[2] * 2
      if not passable(x, y, goalSet[cellKey(x, y)] == true) then return nil end
      return x, y, "ledge", "Jump ledge " .. direction
    end

    local fromColl, enteredColl = map:cellCollision(fromX, fromY), map:cellCollision(x, y)
    local fromWater = Permissions.isWater(fromColl) and not Permissions.isWaterfall(fromColl)
    local entryKind, entryInstruction
    if Permissions.isCutTree(enteredColl) then
      entryKind, entryInstruction = "cut",
        "Use Cut facing " .. direction .. ", then move " .. direction
    elseif Permissions.isWhirlpool(enteredColl) then
      -- World:runWhirlpool, like Cut, clears the obstacle and leaves the
      -- player where they stand; the edge lands on the cleared cell
      entryKind, entryInstruction = "whirlpool",
        "Use Whirlpool facing " .. direction .. ", then move " .. direction
    elseif Permissions.isWater(enteredColl) and not Permissions.isWaterfall(enteredColl)
        and not fromWater then
      -- from land onto water always takes Surf, even mid-plan after surfing
      -- to an island
      entryKind, entryInstruction = "surf", "Use Surf facing " .. direction
    end

    -- Climbing: the whole column in one scripted move, landing on the first
    -- cell above it (World:runWaterfall).  Without this a step up onto the
    -- waterfall entered the forced-movement loop and was carried back to its
    -- own start, a self-loop.
    if Permissions.isWaterfall(enteredColl) and direction == "up" then
      local climbX, climbY, climbed = x, y, 0
      while Permissions.isWaterfall(map:cellCollision(climbX, climbY)) do
        climbY = climbY - 1
        climbed = climbed + 1
        if not map:inBounds(climbX, climbY) or climbed > map.heightCells then return nil end
      end
      if not passable(climbX, climbY, goalSet[cellKey(climbX, climbY)] == true) then
        return nil
      end
      return climbX, climbY, "waterfall",
        "Use Waterfall facing up, then climb " .. climbed
          .. (climbed == 1 and " cell" or " cells")
    end

    -- Forced movement: a goal cannot stop it, only a warp or the end of the
    -- chain (a bump or a cell that does not carry on).
    local travelled, kind, initialDirection = 1, nil, direction
    while not map:warpAt(x, y) do
      local coll = map:cellCollision(x, y)
      local nextDirection = Permissions.currentDirection(coll)
      if nextDirection then
        kind = kind or "current"
      elseif Permissions.isIce(coll) then
        nextDirection = direction
        kind = kind or "ice"
      else
        break
      end
      if not permitted(x, y, nextDirection) then break end
      local nd = DELTA[nextDirection]
      local nx, ny = x + nd[1], y + nd[2]
      -- A warp does not stop a slide or a current: the game carries the
      -- player onto it and the warp fires (Ice Path B2F's slide up from the
      -- bottom row ran onto the B1F ladder).  The move ends there, which is
      -- only a move when that warp is the goal.
      if map:inBounds(nx, ny) and map:warpAt(nx, ny)
         and Permissions.isWarpCollision(map:cellCollision(nx, ny))
         and not npcBlocks(native, nx, ny) then
        if not goalSet[cellKey(nx, ny)] then return nil end
        x, y, direction, travelled = nx, ny, nextDirection, travelled + 1
        break
      end
      if not passable(nx, ny, goalSet[cellKey(nx, ny)] == true) then break end
      x, y, direction, travelled = nx, ny, nextDirection, travelled + 1
      if travelled > map.widthCells * map.heightCells then return nil end
    end
    local instruction
    if kind == "ice" then
      instruction = "Move " .. initialDirection .. " onto ice; slide "
        .. travelled .. " cells"
    elseif kind == "current" then
      instruction = "Move " .. initialDirection .. " into current; carried to x "
        .. x .. ", y " .. y
    end
    if x == fromX and y == fromY then return nil end
    if entryInstruction and instruction then
      instruction = entryInstruction .. ", then " .. instruction:sub(1, 1):lower()
        .. instruction:sub(2)
    elseif entryInstruction then
      instruction = entryInstruction
    end
    return x, y, entryKind or kind, instruction
  end

  local function neighbors(x, y)
    local result = {}
    for _, direction in ipairs(ORDER) do
      local tx, ty, kind, instruction = landing(x, y, direction)
      if tx ~= nil then
        result[#result + 1] = {
          x = tx, y = ty, direction = direction,
          kind = kind, instruction = instruction,
        }
      end
    end
    return result
  end

  return {
    start = { x = player.cellX, y = player.cellY }, goals = goals,
    bounds = { width = map.widthCells, height = map.heightCells },
    allowBlockedGoal = false, policy = policy, neighbors = neighbors,
    canTraverse = function() return true end, maxSeconds = 0.25,
  }, world
end

function Navigation:worldRouteRequest(goals, policy)
  local world, reason = self:worldForCommand()
  if not world then return nil, reason end
  return self:routeOptionsFor(world, goals, policy)
end

function Navigation:routeNarration(_world, result)
  if result.cost == 0 then return { "Already there" } end
  local tokens = {}
  local function add(text, countable)
    local prior = tokens[#tokens]
    if countable and prior and prior.countable and prior.text == text then
      prior.count = prior.count + 1
    else
      tokens[#tokens + 1] = { text = text, count = 1, countable = countable }
    end
  end
  for _, step in ipairs(result.steps or {}) do
    if step.kind then add(step.instruction or step.direction, false)
    else add(step.direction, true) end
  end
  local parts = {}
  for _, token in ipairs(tokens) do
    parts[#parts + 1] = token.countable
      and (token.count .. " " .. token.text) or token.text
  end
  return parts
end

local REQUIREMENT_KEY = { CUT = "CUT", SURF = "SURF", WHIRLPOOL = "WHIRLPOOL",
  WATERFALL = "WATERFALL" }

-- The capabilities the route needs that the player cannot use yet, as the
-- base requirement keys (a missing badge is named as the badge).
function Navigation:routeRequirements(world, result)
  local needed = {}
  local function need(moveId)
    local usable, missingMon, missingBadge = self:fieldMoveStatus(moveId)
    if usable then return end
    if missingMon then needed[REQUIREMENT_KEY[moveId]] = true end
    if missingBadge then needed[missingBadge .. "_BADGE"] = true end
  end
  for _, step in ipairs(result.steps or {}) do
    local coll = world.map:cellCollision(step.x, step.y)
    if step.kind == "cut" or Permissions.isCutTree(coll) then need("CUT") end
    if step.kind == "surf" then need("SURF") end
    if step.kind == "whirlpool" then need("WHIRLPOOL") end
    if step.kind == "waterfall" then need("WATERFALL") end
  end
  return needed
end

-- ------------------------------------------------------------ sonar

function Navigation:isPushableEntity(entity)
  return Terrain.isBoulder(entity) == true
end

-- Ordinary walking only ("can I step there"), with the router's side-wall
-- rule; Surf only while already surfing, as Gen 1's probe does.
function Navigation:sonarCanMove(world, probe, direction)
  local map = world and world.map
  if not (map and type(map.cellCollision) == "function") then return false end
  local delta = DELTA[direction]
  if not (delta and probe) then return false end
  local fromX, fromY = probe.cellX, probe.cellY
  local x, y = fromX + delta[1], fromY + delta[2]
  if not map:inBounds(x, y) then return false end
  local okStep, permitted = pcall(Permissions.stepPermitted, collisionReader(world),
    fromX, fromY, direction)
  if not okStep or not permitted then return false end
  if npcBlocks(world.native, x, y) then return false end
  local coll = map:cellCollision(x, y)
  if Permissions.isWalkable(coll) then return true end
  if Permissions.isWater(coll) then return probe.surfing == true end
  return false
end

-- A door the player could enter except that a live actor stands on every
-- approach: leaving the map will not help, so say so (base behaviour, with
-- Gen 2's movement rules).
function Navigation:blockedWarpEntrance(navigation)
  if not navigation or navigation.targetType ~= "warp" then return false end
  local world = self:worldForCommand()
  if not world or navigation.targetMapId ~= self:currentMapIdOf(world) then return false end
  local map = world.map
  local collOf = collisionReader(world)
  local viable = false
  for _, goal in ipairs(navigation.targetGoals or {}) do
    for _, direction in ipairs(ORDER) do
      local d = DELTA[direction]
      local fromX, fromY = goal.x - d[1], goal.y - d[2]
      if map:inBounds(fromX, fromY) and Permissions.isWalkable(map:cellCollision(fromX, fromY))
         and Permissions.stepPermitted(collOf, fromX, fromY, direction) then
        viable = true
        if not npcBlocks(world.native, fromX, fromY) then return false end
      end
    end
  end
  return viable
end

-- ------------------------------------------------------------ cross-map

function Navigation:regionalMapDef(mapId)
  local data = self.game and self.game.data
  local maps = data and data.gen2Maps
  return maps and maps[mapId] or nil
end

function Navigation:regionalTilesetFor(def)
  local data = self.game and self.game.data
  local tilesets = data and data.gen2Tilesets
  return (def and tilesets) and tilesets[def.tileset] or nil
end

function Navigation:regionalMap(def)
  if not def then return nil end
  self.regionalMapCache = self.regionalMapCache or setmetatable({}, { __mode = "k" })
  local cached = self.regionalMapCache[def]
  if cached ~= nil then return cached or nil end
  local tileset = self:regionalTilesetFor(def)
  local ok, map = false, nil
  if tileset then ok, map = pcall(Gen2Map.new, def, tileset) end
  self.regionalMapCache[def] = ok and map or false
  return ok and map or nil
end

-- An object on a map the player is not on, only if the game would show it:
-- its time of day (World:objectTimeVisible) and its event flag
-- (Events:objectVisible), read through the live world.
function Navigation:regionalObjectVisible(object)
  if type(object) ~= "table" then return false end
  local native = self.game and self.game.world
  if native and type(native.objectTimeVisible) == "function" then
    local okTime, timeVisible = pcall(native.objectTimeVisible, native, object)
    if okTime and timeVisible == false then return false end
  end
  local flag = object.eventFlag
  if flag == nil or flag == 0xFFFF then return true end
  local events = native and native.events
  if not (events and type(events.objectVisible) == "function") then return true end
  local ok, visible = pcall(events.objectVisible, events, flag)
  if not ok then return true end
  return visible and true or false
end

-- data/sprites/map_objects.asm rows whose flags carry BIG_OBJECT (the live
-- NPC's `bigObject`, src/world/gen2/Npc.lua; not exported upstream).
local BIG_OBJECT_MOVEMENT = { [0x15] = true, [0x20] = true, [0x21] = true }

-- A headless world for a map the player is not on: a Gen 2 Map and the
-- objects the game would show, big objects filling their 2x2.  Surfing
-- carries into the plan.
function Navigation:regionalStaticWorld(mapId, start)
  local def = self:regionalMapDef(mapId)
  local map = self:regionalMap(def)
  if not map then return nil end
  local live = self:worldState()
  local surfing = live and live.player and live.player.surfing == true or false
  local player = { cellX = start.x, cellY = start.y, facing = "down", surfing = surfing }
  local occupied, npcs = {}, {}
  for _, object in ipairs(def.objects or {}) do
    if object.x and object.y and self:regionalObjectVisible(object) then
      local actor = { cellX = object.x, cellY = object.y, def = object,
        bigObject = BIG_OBJECT_MOVEMENT[object.movement] == true }
      npcs[#npcs + 1] = actor
      occupied[cellKey(object.x, object.y)] = actor
      if actor.bigObject then
        for dy = 0, 1 do
          for dx = 0, 1 do occupied[cellKey(object.x + dx, object.y + dy)] = actor end
        end
      end
    end
  end
  local native = { npcAt = function(_, x, y) return occupied[cellKey(x, y)] end }
  local entities = { player }
  for _, actor in ipairs(npcs) do entities[#entities + 1] = actor end
  return { isOverworld = true, map = map, native = native, player = player,
           npcs = npcs, entities = entities }
end

function Navigation:regionalDryRoute(mapId, start, goals, useLive, maxSeconds)
  if useLive then
    local live = self:worldForCommand()
    if live and self:currentMapIdOf(live) == mapId
       and live.player.cellX == start.x and live.player.cellY == start.y then
      local options = self:routeOptionsFor(live, goals, 1)
      if not options then return nil end
      options.maxSeconds = maxSeconds or options.maxSeconds
      return Pathfinder.find(options)
    end
  end
  local world = self:regionalStaticWorld(mapId, start)
  if not world then return nil end
  local options = self:routeOptionsFor(world, goals, 1)
  if not options then return nil end
  options.maxSeconds = maxSeconds or options.maxSeconds
  return Pathfinder.find(options)
end

-- Where a warp leads.  Destination warp 0xFF is "back where you came from"
-- and names the map itself (every Pokemon Center 2F, elevator floor); the
-- world resolves it through the backup warp it recorded (World:resolveWarp).
-- Unresolved, the warp gives no edge: before the game has recorded one there
-- is genuinely nothing to go back to.
function Navigation:regionalResolveWarp(warp)
  if type(warp) ~= "table" then return nil, nil end
  if warp.destWarp ~= 0xff then return warp.destMap, warp.destWarp end
  local destMap, destWarp = Snapshot.returnWarpDestination(self.game and self.game.world, warp)
  if destMap and destWarp and destWarp ~= 0xff then return destMap, destWarp end
  return nil, nil
end

local CONNECTION_STEP = { north = "up", south = "down", west = "left", east = "right" }

function Navigation:regionalTransitions(mapId)
  local def = self:regionalMapDef(mapId)
  if not def then return {} end
  local sourceMap = self:regionalMap(def)
  local result = {}
  for index, warp in ipairs(def.warps or {}) do
    -- Gen 2 takes a warp only on warp collision (Permissions.isWarpCollision)
    local active = true
    if sourceMap then
      local ok, coll = pcall(sourceMap.cellCollision, sourceMap, warp.x, warp.y)
      active = ok and Permissions.isWarpCollision(coll)
    end
    local destMap, destWarp = self:regionalResolveWarp(warp)
    local destination = destMap and self:regionalMapDef(destMap)
    local arrival = destination and destination.warps and destWarp
      and destination.warps[destWarp]
    if active and destination and arrival then
      result[#result + 1] = {
        kind = "warp", index = index, x = warp.x, y = warp.y,
        destMap = destMap, destX = arrival.x, destY = arrival.y,
      }
    end
  end
  if not sourceMap then return result end
  -- Connections: the name is `mapId` (Gen 2 writes the numeric map byte into
  -- `map`), landing by Map.connectionLanding, refused where the strip ends or
  -- where the landing cell's side wall refuses entry (World:tryConnection).
  for _, direction in ipairs({ "north", "east", "south", "west" }) do
    local conn = (def.connections or {})[direction]
    local destId = type(conn) == "table" and conn.mapId or nil
    local destination = type(destId) == "string" and self:regionalMapDef(destId)
    local destMap = destination and self:regionalMap(destination)
    if destMap then
      local step = CONNECTION_STEP[direction]
      local vertical = step == "up" or step == "down"
      local width, height = sourceMap.widthCells, sourceMap.heightCells
      local count = vertical and width or height
      local offset = (tonumber(conn.offset) or 0) * 2
      for coordinate = 0, count - 1 do
        local x = (direction == "west") and 0
               or (direction == "east") and (width - 1) or coordinate
        local y = (direction == "north") and 0
               or (direction == "south") and (height - 1) or coordinate
        local destX, destY = Gen2Map.connectionLanding(destination, conn, step, x, y)
        local inStrip = destX and ((vertical and destX or destY) == coordinate - offset)
        if inStrip then
          local here = sourceMap:cellCollision(x, y)
          local there = destMap:cellCollision(destX, destY)
          if Permissions.surfable(here) ~= nil and Permissions.surfable(there) ~= nil
             and Permissions.neighborBlocks(step, there) ~= step then
            result[#result + 1] = {
              kind = "connection", direction = direction, x = x, y = y,
              destMap = destId, destX = destX, destY = destY,
            }
          end
        end
      end
    end
  end
  return result
end

function Navigation:regionalDestinationName(mapId)
  local def = self:regionalMapDef(mapId)
  local ok, name = pcall(self.worldSnapshot.locationName, def or { id = mapId }, mapId,
    nil, (saveNames(self.game)))
  if ok and type(name) == "string" and name ~= "" then return name end
  return tostring(mapId)
end

-- The Area category (decision 25) on Gen 2 maps: item balls the game would
-- still show on the other maps of the current building or zone (maps sharing
-- the first two words of their id), named by item and map.
function Navigation:areaBrowse(world)
  local data = self.game and self.game.data
  local maps = data and data.gen2Maps or {}
  local here = self:currentMapIdOf(world)
  local key = type(here) == "string" and here:match("^([A-Z0-9]+_[A-Z0-9]+)") or nil
  local items = {}
  if not key then return items end
  local members = {}
  for mapId in pairs(maps) do
    if type(mapId) == "string" and mapId:match("^([A-Z0-9]+_[A-Z0-9]+)") == key then
      members[#members + 1] = mapId
    end
  end
  if #members < 2 then return items end
  table.sort(members)
  local native = self.game.world
  for _, mapId in ipairs(members) do
    if mapId ~= here then
      local mapName = self:regionalDestinationName(mapId)
      for _, object in ipairs(maps[mapId].objects or {}) do
        local ball = type(object.itemball) == "table" and object.itemball or nil
        if ball and self:regionalObjectVisible(object) then
          local itemId = type(ball.item) == "string" and ball.item or nil
          if not itemId and native and type(native.itemIdByIndex) == "function" then
            local ok, id = pcall(native.itemIdByIndex, native, ball.item)
            itemId = ok and id or nil
          end
          if itemId then
            local label = tostring(self.worldSnapshot.humanize(itemId) or itemId)
              .. ", " .. tostring(mapName)
            items[#items + 1] = {
              id = "area:" .. mapId .. ":" .. tostring(object.index),
              type = "area", category = "area", label = label, description = label,
              mapId = mapId, x = object.x, y = object.y,
            }
          end
        end
      end
    end
  end
  return items
end

-- ------------------------------------------------------------ renaming

-- Shift+K and Shift+M with Gen 2's own naming screen (src/ui/gen2/NamingScreen,
-- which takes an initial text and leaves popping to the caller).
function Navigation:beginRename(kind)
  local item, snapshot
  if kind == "object" then
    local reason
    item, reason, snapshot = self:selectedBrowseItem(0)
    if not item then return self:announceManual({ reason }) end
  else
    local reason
    snapshot, reason = self:captureWorld("all")
    if not snapshot then return self:announceManual({ reason }) end
  end
  local names = self:writableCustomNames()
  if not names then return self:announceManual({ "Names could not be saved" }) end
  local mapId = snapshot.mapId
  local current
  if kind == "map" then
    current = names.maps[mapId] or snapshot.locationName
  else
    names.objects[mapId] = names.objects[mapId] or {}
    current = names.objects[mapId][item.id] or item.label
  end
  local NamingScreen = require("src.ui.gen2.NamingScreen")
  local game = self.game
  local screen
  local function close()
    if game.stack and game.stack:top() == screen then game.stack:pop() end
  end
  screen = NamingScreen.new(game, {
    type = "nickname",
    prompt = kind == "map" and "MAP NAME?" or "OBJECT NAME?",
    maxLength = 10,
    initial = tostring(current or ""):sub(1, 10),
    onDone = function(value)
      close()
      if kind == "map" then
        names.maps[mapId] = value ~= "" and value or nil
      else
        names.objects[mapId][item.id] = value ~= "" and value or nil
      end
      if game.writeOptions then game:writeOptions() end
      self:announceManual({ "Names saved" })
    end,
    onCancel = close,
  })
  screen.accessibilityTitle = kind == "map" and "Rename map" or "Rename selected item"
  game.stack:push(screen)
  return true
end

-- ------------------------------------------------------------ Unown puzzle

-- Pokemon Access's Gen 2 Shift+E on the Unown puzzle reads the held piece;
-- elsewhere it stays the terrain query.  The screen is recognised by its
-- class and read from its own fields (src/ui/gen2/UnownPuzzle.lua).
function Navigation:unownPuzzleState()
  local Unown = package.loaded["src.ui.gen2.UnownPuzzle"]
  local stack = self.game and self.game.stack
  local state = stack and stack:top() or nil
  if Unown and type(state) == "table" and getmetatable(state) == Unown then return state end
  return nil
end

function Navigation:commandAllowed(actionId)
  if self:worldForCommand() then return true end
  return actionId == "read_terrain" and self:unownPuzzleState() ~= nil
end

function Navigation:handleCommand(actionId)
  local puzzle = actionId == "read_terrain" and self:unownPuzzleState() or nil
  if puzzle then
    if puzzle.waiting then return self:readScreenText() end
    if puzzle.holding ~= true then
      return self:announceManual({ "You have to pick a piece first" })
    end
    local held = puzzle.held
    if type(held) ~= "number" or held <= 0 or held % 1 ~= 0 then
      return self:announceManual({ "Held piece unavailable" })
    end
    return self:announceManual({ "Holding piece " .. tostring(held) })
  end
  return Shared.handleCommand(self, actionId)
end

return Navigation
