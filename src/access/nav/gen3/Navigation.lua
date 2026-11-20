-- The navigation coordinator for FireRed (decision 29): a subclass of the
-- Gen 1 coordinator (../Navigation.lua), as gen2/Navigation.lua is for Gold,
-- Silver and Crystal.  Every world question is answered from Gen 3's own
-- field (nav/gen3/World.lua): COLL bytes, metatile behaviours, elevation,
-- the active warps and how each one fires, connections, objects (Cut trees,
-- Rock Smash rocks and Strength boulders are objects in Gen 3), badges and
-- the party's field moves.  The commands, object list, route narration,
-- guided navigation and auto-walk are the shared ones; journeys use a
-- one-pass search over every map of the area (journeySearch below) in
-- place of the shared per-transition planner.  Nothing here changes game
-- state.
--
-- New for FireRed (there was no Gen 3 navigation in the old project, only a
-- field inventory and an input classifier, reused in World.lua and
-- WorldAdapter.lua under decision 20).  The routing rules follow the game's
-- own movement code (src/core/game3/player.lua tryMove, collision.lua
-- canEnter and ledgeLanding, forced_movement.lua); Pokemon Access's GBA
-- script was read for behaviour only (decision 7): its elevation rule, its
-- "enter water" and "exit water" route steps, and the warning beside a
-- ledge.

local Shared = require("src.access.nav.Navigation")
local Snapshot = require("src.access.nav.gen3.WorldSnapshot")
local Terrain = require("src.access.nav.gen3.TerrainSemantics")
local Puzzle = require("src.access.nav.gen3.PuzzleAssistance")
local Scripts = require("src.access.nav.gen3.Scripts")
local World = require("src.access.nav.gen3.World")
local GameData = require("src.access.nav.gen3.GameData")
local WorldAdapter = require("src.access.nav.WorldAdapter")
local Pathfinder = require("src.access.nav.Pathfinder")
local bit = require("bit")

local Gen3 = WorldAdapter.gen3

local Navigation = {}
Navigation.__index = Navigation
setmetatable(Navigation, { __index = Shared })

local ORDER = { "up", "right", "down", "left" }
local DELTA = World.DELTA
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
local function cellKey(x, y) return tostring(x) .. "," .. tostring(y) end

local function loaded(path) return package.loaded[path] end

local function lazyRtc()
  local ok, Rtc = pcall(require, "src.core.game3.rtc")
  return ok and Rtc or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

function Navigation.new(game, opts)
  opts = opts or {}
  opts.worldSnapshot = opts.worldSnapshot or Snapshot
  opts.terrainSemantics = opts.terrainSemantics or Terrain
  opts.puzzleAssistance = opts.puzzleAssistance or Puzzle
  -- the shared constructor reads Gen 1's game.save.options; FireRed's
  -- persisted options are game.options
  local options = Gen3.options(game) or {}
  if opts.sonarFollowsPlayer == nil then
    opts.sonarFollowsPlayer = options.accessibilitySonarFollow ~= false
  end
  if opts.cueVolumeLevel == nil then opts.cueVolumeLevel = options.accessibilityCueVol end
  if opts.earcons == nil and options.accessSoundPack ~= nil then
    opts.earcons = require("src.access.nav.Earcons").new({ soundPackPath = options.accessSoundPack })
  end
  local self = Shared.new(game, opts)
  self.generation = 3
  setmetatable(self, Navigation)
  -- the shared constructor subscribed with the shared methods (this
  -- metatable is set only now): add the popup check on top
  self:subscribePopupEvent()
  return self
end

function Navigation:setSonarFollow(enabled, opts)
  opts = opts or {}
  self.sonarFollowsPlayer = enabled ~= false
  local options = Gen3.options(self.game)
  if options then options.accessibilitySonarFollow = self.sonarFollowsPlayer end
  if opts.persist and self.game and type(self.game.writeOptions) == "function" then
    pcall(self.game.writeOptions, self.game)
  end
  return true
end

-- ------------------------------------------------------------ the world

function Navigation:worldState()
  return Gen3.world(self.game)
end

-- The world may be spoken of: the field runs, its map is bound, and no
-- battle, message, menu, script, lock, fade or warp holds it.  Walking
-- (and forced movement) does not stop narration.
function Navigation:isDescribableWorld()
  local world = self:worldState()
  if not (world and world.map) then return false end
  if Gen3.battleActive() then return false end
  local Warp = loaded("src.core.game3.warp")
  if Warp and call(Warp.isBusy) then return false end
  return not Gen3.held(self.game)
end

-- The player can act and a route may be measured from where they stand.
-- Mid-step is fine, as in Gen 1: routes start from the cell being left.
function Navigation:isActionableWorld()
  if not self:isDescribableWorld() then return false end
  return not Gen3.transitioning(self:worldState())
end

function Navigation:worldForCommand()
  if not self:isActionableWorld() then return nil, "Not on a map" end
  local world = self:worldState()
  if not (world and world.map and World.liveView(self.game)) then return nil, "Not on a map" end
  return world
end

-- Decision 37.  A cave map's flash level until Flash clears it, and the circle
-- of light it leaves (FieldView.flashRadius, in pixels from the player).
-- Ruby, Sapphire and Emerald keep level 1 after Flash, so the flash flag says
-- when it is on.  Flash works only in a map whose header says cave, and Dewford Gym
-- is dark some other way: its level falls as its trainers lose (setflashlevel in its
-- own scripts) and the Flash move is refused there, so "use Flash" could never be
-- obeyed and the gym is not dark for this rule.
local function fieldView() return package.loaded["src.core.game3.field_view"] end

function Navigation:isDark(world)
  local view = fieldView()
  if not (type(view) == "table" and (tonumber(view.flashLevel) or 0) > 0) then return false end
  if not GameData.isHoenn() then return true end
  world = world or self:worldState()
  local def = world and world.map and world.map.def
  local cave = def and (def.cave == 1 or def.cave == true)
  if not cave then return false end
  local FieldMoves = loaded("src.core.game3.field_moves")
  local flag = FieldMoves and FieldMoves.SYS_FLAGS and FieldMoves.SYS_FLAGS.FLASH_ACTIVE
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  if flag and Space and Space.store and Flags and call(Flags.getFlag, Space.store, nil, flag) then return false end
  return true
end

function Navigation:darkCellVisible(world, x, y)
  local view = fieldView()
  local radius = view and view.flashRadius and view.flashRadius() or 0
  local dx, dy = (x - world.player.cellX) * 16, (y - world.player.cellY) * 16
  return dx * dx + dy * dy <= radius * radius
end

function Navigation:currentMapIdOf(world)
  local map = type(world) == "table" and world.map or nil
  return map and (map.id or (type(map.def) == "table" and map.def.id)) or nil
end

function Navigation:session() return World.session(self.game) end

-- ------------------------------------------------------------ names

local function cleanName(value)
  if type(value) ~= "string" then return nil end
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  -- a screen reader may say nothing at all for an unnamed "???"
  if value == "" or not value:find("%w") then return nil end
  return value
end

function Navigation:names()
  local session = self:session() or {}
  local save = type(self.game) == "table" and type(self.game.save) == "table" and self.game.save or {}
  return cleanName(session.name or save.name), cleanName(session.rivalName or save.rivalName)
end

function Navigation:speakerNames()
  local player, rival = self:names()
  local names, found = {}, false
  for _, value in ipairs({ player, rival }) do
    if value then names[value] = true found = true end
  end
  return found and names or nil
end

-- ------------------------------------------------------------ field moves

local MOVE_LABEL = {
  CUT = "Cut", SURF = "Surf", STRENGTH = "Strength", ROCK_SMASH = "Rock Smash",
  WATERFALL = "Waterfall", FLASH = "Flash", DIVE = "Dive", SECRET_POWER = "Secret Power",
}
-- FireRed's field-move badges (FieldMoves.BADGE_FLAGS).
local BADGE_LABEL = {
  FLASH = "Boulder Badge", CUT = "Cascade Badge", STRENGTH = "Rainbow Badge",
  SURF = "Soul Badge", ROCK_SMASH = "Marsh Badge", WATERFALL = "Volcano Badge",
}
Navigation.BADGE_LABEL = BADGE_LABEL

-- The badge a field move needs on this cartridge: upstream's table (Flags.BADGES and
-- the profile's names) on Ruby, Sapphire and Emerald, whose gyms differ.
local function badgeLabel(moveId)
  if not GameData.isHoenn() then return BADGE_LABEL[moveId] end
  local Flags = loaded("src.core.game3.scripting.flags")
  local ok, table_ = pcall(function() return Flags.forVersion(GameData.id()).BADGES end)
  for _, row in ipairs(ok and table_ or {}) do
    if row.fieldMove == moveId and type(row.name) == "string" then
      return row.name:sub(1, 1) .. row.name:sub(2):lower() .. " Badge"
    end
  end
  return nil
end

-- The checks the game makes before a field move works: a party member that
-- knows it (FieldMoves.partyMoveUser, which honours fieldmove.eligibility)
-- and the badge (FieldMoves.hasBadge on the script flag store).  Returns
-- usable, missing-move, missing-badge-label.
function Navigation:fieldMoveStatus(moveId)
  local FieldMoves = loaded("src.core.game3.field_moves")
  local session = self:session()
  if not FieldMoves then return false, true, nil end
  local mon = call(FieldMoves.partyMoveUser, session and session.party, moveId,
    { game = self.game, party = session and session.party })
  local Space = loaded("src.core.game3.scripting.space")
  local hasBadge = true
  if FieldMoves.BADGE_FLAGS and FieldMoves.BADGE_FLAGS[moveId] then
    hasBadge = Space ~= nil and Space.store ~= nil
      and call(FieldMoves.hasBadge, { store = Space.store }, moveId) == true
  end
  local hasMon = mon ~= nil
  return hasMon and hasBadge, not hasMon, (not hasBadge) and badgeLabel(moveId) or nil
end

function Navigation:fieldMoveRequirement(moveId)
  local usable, missingMon, missingBadge = self:fieldMoveStatus(moveId)
  if usable then return nil end
  local parts = {}
  if missingMon then parts[#parts + 1] = MOVE_LABEL[moveId] or moveId end
  if missingBadge then parts[#parts + 1] = missingBadge end
  return "Needs " .. table.concat(parts, " and ")
end

function Navigation:hmAllowed(_world, moveId, policy)
  policy = policy or 2
  if policy == 3 then return true end
  if policy ~= 2 then return false end
  return (self:fieldMoveStatus(moveId)) == true
end

-- Strength is switched on for this map (FLAG_SYS_USE_STRENGTH).
function Navigation:strengthActive()
  local FieldMoves = loaded("src.core.game3.field_moves")
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  if not (FieldMoves and Space and Space.store and Flags and Flags.getFlag) then return false end
  local flag = FieldMoves.SYS_FLAGS and FieldMoves.SYS_FLAGS.USE_STRENGTH
  return flag ~= nil and call(Flags.getFlag, Space.store, nil, flag) == true
end

-- Auto-walk's boulder pushing (BoulderWalk.lua).  With `goals` (a target with no route):
-- the first push that opens a way to it, whatever the floor holds; when pushes alone
-- cannot (Victory Road's barriers open only from their switches), the floor's own plan,
-- then the walk goes on once a route exists.  Without goals (the player asked for a
-- boulder, a switch or a hole): the floor's plan, stone = true.
function Navigation:boulderOpening(world, goals, wholeFloor)
  local needs = Puzzle.strengthPrefix(self)
  local aiming = not wholeFloor and type(goals) == "table" and #goals > 0
  if aiming then
    local first = goals[1]
    local mark = tostring(world.map) .. ":" .. first.x .. "," .. first.y
    -- no pushes open this way: not searched again after every push of the floor's plan
    if self.openingRefused ~= mark then
      local options = self:routeOptionsFor(self:withoutBoulders(world), goals, 2)
      local ok, push, why = pcall(Puzzle.planOpening, world, goals, options and options.neighbors)
      if ok and push then return push, nil, needs, false end
      if ok and why == "open" then return nil, "open", needs, false end
      self.openingRefused = mark
    end
  end
  local ok, targets, boulders = pcall(Puzzle.targetsFor, world)
  local okPush, push, why = false, nil, nil
  if ok and targets then okPush, push, why = pcall(Puzzle.nextPushFor, world, targets, boulders) end
  if okPush and push then return push, nil, needs, not aiming end
  if okPush and why == "budget" then return nil, "searching", needs, not aiming end
  if not aiming then
    -- no targets left: the last boulder has dropped through its hole
    return nil, "finished", needs, true
  end
  self.openingRefused = nil
  local options = self:routeOptionsFor(world, goals, 2)
  if options and Pathfinder.find(options) then return nil, "open", needs, false end
  return nil, nil, needs, false
end

-- The same world with the boulders off the floor, for the route graph planOpening asks.
function Navigation:withoutBoulders(world)
  -- (the live world is a facade: its fields come through its metatable)
  local copy = setmetatable({ npcs = {} }, { __index = world })
  for _, actor in ipairs(world.npcs or {}) do
    if not Terrain.isBoulder(actor) then copy.npcs[#copy.npcs + 1] = actor end
  end
  return copy
end

-- A message or a yes/no is on screen, waiting for the player.
function Navigation:promptWaiting()
  local Message = loaded("src.ui.game3.message")
  local Choice = loaded("src.ui.game3.choice")
  return (Message ~= nil and Message.open == true) or (Choice ~= nil and Choice.active == true)
end

-- Auto-walk's switch trying (SwitchWalk.lua): the Secret Switches on this floor,
-- each with the cells to stand on (the role comes from their scripts, Scripts.signRole).
local function labelledSigns(self, world, label)
  local signs = {}
  local ok, snapshot = pcall(self.captureWorld, self, "signposts")
  if not (ok and type(snapshot) == "table") then return signs end
  for _, item in ipairs(snapshot.browse or {}) do
    if item.label == label then
      local goals = self:interactionGoals(world, item)
      if type(goals) == "table" and #goals > 0 then
        local cell = (item.interactionCells or {})[1] or item
        signs[#signs + 1] = { label = label .. " " .. tostring(cell.x) .. "," .. tostring(cell.y),
          x = cell.x, y = cell.y, goals = goals }
      end
    end
  end
  return signs
end

function Navigation:switchSigns(world)
  local signs = labelledSigns(self, world, "Secret Switch")
  -- Ruby and Sapphire's Mossdeep Gym: four hidden switches, each turning its arrows
  if GameData.isHoenn() then
    for _, sign in ipairs(labelledSigns(self, world, "Hidden Switch")) do signs[#signs + 1] = sign end
  end
  -- Hoenn's floor switches: a step onto one presses it (Mauville, Mossdeep)
  for _, cell in ipairs(self:floorSwitchCells(world)) do
    signs[#signs + 1] = { label = "Floor Switch " .. cell.x .. "," .. cell.y, x = cell.x, y = cell.y,
      goals = { { x = cell.x, y = cell.y } }, step = true }
  end
  return signs
end

-- Mossdeep Gym and Trick House 5: each floor switch moves every object on an arrow of its
-- colour one cell along that arrow (RotatingTilePuzzle.move), so the floor after any presses can
-- be worked out, and which presses open the way to a target searched for without walking
-- them.  A state is where the objects stand and where the player last pressed.  The answer is
-- the next switch to press; nil when this floor has no such switches or no answer turned up.
local TILE_ARROW = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }
local ROTATE_STATES, ROTATE_SECONDS = 12000, 2.5

function Navigation:rotatingSwitchPlan(world, goals)
  local map = world.map
  local def = map.def
  local cells, trickHouse = {}, false
  for _, event in ipairs(type(def) == "table" and def.coordEvents or {}) do
    local rotation = type(event.x) == "number" and Scripts.rotatingSwitch(event.scriptKey) or nil
    if rotation then
      cells[#cells + 1] = { x = event.x, y = event.y, number = rotation.number,
        label = "Floor Switch " .. event.x .. "," .. event.y }
      trickHouse = rotation.trickHouse
    end
  end
  if #cells == 0 then return self:leverPlan(world, goals) end
  local set = GameData.constants()
  local labels = set and set.metatile_labels and set.metatile_labels.byName
  local start = labels and labels[trickHouse and "METATILE_TrickHousePuzzle_Arrow_YellowOnWhite_Right"
    or "METATILE_MossdeepGym_YellowArrow_Right"]
  local bound = labels and labels.METATILE_MossdeepGym_YellowArrow_Right
  local layout = def.midLayout
  if not (start and bound and layout and layout.midAt) then return nil, "no arrows" end
  -- the floor's arrows do not change, only who stands on them
  local function arrowAt(x, y)
    local mid = layout:midAt(x, y) or 0
    if mid < bound then return nil end
    local row = math.floor((mid - start) / 8) % 256
    if row >= 5 then return nil end
    local tile = (mid - start) % 8
    return row, TILE_ARROW[tile]
  end
  local actors, keyParts = {}, {}
  for i, actor in ipairs(world.npcs or {}) do
    actors[i] = { x = actor.cellX, y = actor.cellY, actor = actor }
  end
  local function stateKey(positions, px, py)
    for i, pos in ipairs(positions) do keyParts[i] = pos.x .. "," .. pos.y end
    return table.concat(keyParts, ";", 1, #positions) .. "@" .. px .. "," .. py
  end
  local function press(positions, number)
    local moved = {}
    for i, pos in ipairs(positions) do
      local row, arrow = arrowAt(pos.x, pos.y)
      if row == number and arrow then
        moved[i] = { x = pos.x + arrow[1], y = pos.y + arrow[2], actor = pos.actor }
      else
        moved[i] = pos
      end
    end
    return moved
  end
  -- every cell the player can reach from (px, py) with the objects there, through this map's pads
  local mapId = self:currentMapIdOf(world)
  local transitions = {}
  for _, transition in ipairs(self:regionalTransitions(mapId)) do
    if transition.kind == "warp" and transition.destMap == mapId then
      local key = cellKey(transition.x, transition.y)
      transitions[key] = transitions[key] or {}
      table.insert(transitions[key], transition)
    end
  end
  local allGoals = {}
  for _, goal in ipairs(goals) do allGoals[#allGoals + 1] = goal end
  for _, cell in ipairs(cells) do allGoals[#allGoals + 1] = { x = cell.x, y = cell.y } end
  for key in pairs(transitions) do
    local x, y = key:match("^(-?%d+),(-?%d+)$")
    allGoals[#allGoals + 1] = { x = tonumber(x), y = tonumber(y) }
  end
  local function region(positions, px, py)
    local npcs = {}
    for i, pos in ipairs(positions) do
      -- a copy at the worked-out cell, as occupancy and the elevation rule read it
      npcs[i] = setmetatable({ cellX = pos.x, cellY = pos.y, moving = false }, { __index = pos.actor })
    end
    local simulated = { isOverworld = true, map = map, npcs = npcs,
      player = { cellX = px, cellY = py, surfing = false } }
    local options = self:routeOptionsFor(simulated, allGoals, 2)
    if not options then return {} end
    local seen, queue, head = {}, { { px, py, true } }, 1
    while queue[head] do
      local node = queue[head]
      head = head + 1
      local key = cellKey(node[1], node[2])
      local mark = key .. (node[3] and "a" or "w")
      if not seen[mark] then
        seen[mark], seen[key] = true, true
        local fires = not node[3] and map:warpAt(node[1], node[2]) ~= nil and not map:standingWarp(node[1], node[2])
        if fires then
          for _, transition in ipairs(transitions[key] or {}) do
            queue[#queue + 1] = { transition.destX, transition.destY, true }
          end
        else
          -- a floor switch is an end of the walk: stepping on it presses it
          local pressed = false
          if not node[3] then
            for _, cell in ipairs(cells) do
              if cell.x == node[1] and cell.y == node[2] then pressed = true end
            end
          end
          if not pressed then
            for _, edge in ipairs(options.neighbors(node[1], node[2])) do
              queue[#queue + 1] = { edge.x, edge.y, false }
            end
          end
        end
      end
    end
    return seen
  end
  local player = world.player
  local first = { positions = actors, x = player.cellX, y = player.cellY }
  local seenStates = { [stateKey(actors, first.x, first.y)] = true }
  local queue, head = { first }, 1
  local deadline = os.clock() + ROTATE_SECONDS
  while queue[head] do
    local node = queue[head]
    head = head + 1
    if head > ROTATE_STATES or os.clock() > deadline then return nil, "limit " .. head end
    local reached = region(node.positions, node.x, node.y)
    for _, goal in ipairs(goals) do
      if reached[cellKey(goal.x, goal.y)] then
        -- the first press of this line of presses; none means the way is open
        return node.firstLabel, "open"
      end
    end
    for _, cell in ipairs(cells) do
      -- pressing the one underfoot again takes a step off and back
      if reached[cellKey(cell.x, cell.y)] then
        local positions = press(node.positions, cell.number)
        local key = stateKey(positions, cell.x, cell.y)
        if not seenStates[key] then
          seenStates[key] = true
          queue[#queue + 1] = { positions = positions, x = cell.x, y = cell.y,
            firstLabel = node.firstLabel or cell.label }
        end
      end
    end
  end
  return nil, "searched " .. head
end

-- A cell next to the player to step to and come back from, or nil (a floor switch pressed
-- twice running).
function Navigation:stepOffCell(world)
  local player = world.player
  local goals = { { x = player.cellX, y = player.cellY } }
  local options = self:routeOptionsFor(world, goals, 1)
  for _, edge in ipairs(options and options.neighbors(player.cellX, player.cellY) or {}) do
    if not edge.kind and math.abs(edge.x - player.cellX) + math.abs(edge.y - player.cellY) == 1
       and not world.map:warpAt(edge.x, edge.y) then
      return { x = edge.x, y = edge.y }
    end
  end
  return nil
end

-- A switch's script has let go but what it moved is still on its way (Mossdeep's statues).
function Navigation:objectsMoving()
  for _, actor in ipairs(World.actors()) do
    if actor.moving then return true end
  end
  return false
end

function Navigation:floorSwitchCells(world)
  local def = world and world.map and world.map.def
  if type(def) ~= "table" or not GameData.isHoenn() then return {} end
  self.gen3FloorSwitches = self.gen3FloorSwitches or setmetatable({}, { __mode = "k" })
  local cells = self.gen3FloorSwitches[def]
  if not cells then
    cells = Scripts.floorSwitches(def)
    self.gen3FloorSwitches[def] = cells
  end
  return cells
end

-- What a Hoenn floor switch can change beyond collision: where objects stand, and the
-- arrows it turned.
-- Ruby and Sapphire's Trick House 7: five levers (signs), each turning its own flag on
-- or off and redrawing arrows to match, and the arrows carry the player.  Pressing one
-- can leave the player where no other lever can be reached, so trying them one by one
-- (SwitchWalk) gets stuck; here the presses are planned ahead.  What each lever draws
-- is read from its script both ways (Scripts.pressCells), a floor is the levers that
-- are on drawn over the layout, and a search over which levers are on and where the
-- player stands finds the presses that open the way to the target.  The answer is the
-- next lever to press, by the label SwitchWalk lists it under; nil when this floor has
-- no such levers, a script cannot be read, or no answer turned up in time.
local LEVER_LIMIT, LEVER_STATES, LEVER_SECONDS = 6, 4000, 2.0

function Navigation:leverPlan(world, goals)
  if not GameData.isHoenn() then return nil end
  local def = world.map and world.map.def
  if type(def) ~= "table" or not def.midLayout then return nil end
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  local function flagSet(id)
    if not (Space and Space.store and Flags and Flags.getFlag) then return false end
    return call(Flags.getFlag, Space.store, nil, id) == true
  end
  local levers = {}
  for _, event in ipairs(def.bgEvents or {}) do
    if event.type == "sign" and type(event.x) == "number"
       and select(2, Scripts.signRole(event.scriptKey)) == "hidden_switch" then
      local flag = Scripts.reach(event.scriptKey, 8).flagsChecked[1]
      if flag then
        local function answer(own)
          return function(id) if id == flag then return own end return flagSet(id) end
        end
        local on = Scripts.pressCells(event.scriptKey, answer(false))
        local off = Scripts.pressCells(event.scriptKey, answer(true))
        if not (on and off) or next(on.cells) == nil then return nil end
        levers[#levers + 1] = { event = event, flag = flag, on = on.cells, off = off.cells,
          label = "Hidden Switch " .. event.x .. "," .. event.y }
      end
    end
  end
  if #levers == 0 or #levers > LEVER_LIMIT then return nil end
  local views = {}
  local function viewFor(mask)
    if views[mask] then return views[mask] end
    local merged = {}
    for i, lever in ipairs(levers) do
      local drawn = bit.band(mask, bit.lshift(1, i - 1)) ~= 0 and lever.on or lever.off
      for key, cell in pairs(drawn) do merged[key] = cell end
    end
    views[mask] = World.viewWithCells(self.game, def, merged)
    return views[mask]
  end
  local npcs = world.npcs or {}
  local function worldAt(mask, x, y, live)
    if live then return world end
    local player = { cellX = x, cellY = y, facing = "down", surfing = false }
    local entities = { player }
    for _, actor in ipairs(npcs) do entities[#entities + 1] = actor end
    return { isOverworld = true, map = viewFor(mask), player = player, npcs = npcs, entities = entities }
  end
  local function routeEnd(w, cellGoals, x, y)
    local options = self:routeOptionsFor(w, cellGoals, 1)
    if not options then return nil end
    local ok, result = pcall(Pathfinder.find, options)
    if not (ok and result and type(result.steps) == "table") then return nil end
    local last = result.steps[#result.steps]
    if not last then return x, y end
    return last.x, last.y
  end
  local function leverCells(view, event)
    local cells = {}
    for kind, d in pairs({ { 0, -1 }, { 0, 1 }, { 1, 0 }, { -1, 0 } }) do
      local x, y = event.x - d[1], event.y - d[2]
      local side = tonumber(event.kind) or 0
      if (side == 0 or side == kind) and view:isWalkableCell(x, y) and not view:warpAt(x, y) then
        cells[#cells + 1] = { x = x, y = y }
      end
    end
    return cells
  end
  local startMask = 0
  for i, lever in ipairs(levers) do
    if flagSet(lever.flag) then startMask = bit.bor(startMask, bit.lshift(1, i - 1)) end
  end
  local player = world.player
  local queue = { { mask = startMask, x = player.cellX, y = player.cellY, live = true } }
  local seen = { [startMask .. "@" .. player.cellX .. "," .. player.cellY] = true }
  local deadline = os.clock() + LEVER_SECONDS
  local head = 1
  while head <= #queue and head <= LEVER_STATES and os.clock() < deadline do
    local node = queue[head]
    head = head + 1
    local w = worldAt(node.mask, node.x, node.y, node.live)
    if routeEnd(w, goals, node.x, node.y) then return node.first end
    for i, lever in ipairs(levers) do
      local ex, ey = routeEnd(w, leverCells(w.map, lever.event), node.x, node.y)
      if ex then
        local mask = bit.bxor(node.mask, bit.lshift(1, i - 1))
        local key = mask .. "@" .. ex .. "," .. ey
        if not seen[key] then
          seen[key] = true
          queue[#queue + 1] = { mask = mask, x = ex, y = ey, first = node.first or lever.label }
        end
      end
    end
  end
  return nil
end

function Navigation:switchFloorExtra(map)
  if not GameData.isHoenn() then return nil end
  local parts = {}
  for _, actor in ipairs(World.actors()) do
    parts[#parts + 1] = tostring(actor.localId) .. "@" .. tostring(actor.cellX) .. "," .. tostring(actor.cellY)
  end
  local world = self:worldState()
  parts[#parts + 1] = world and world.map == map and self:floorMarks(world) or ""
  return table.concat(parts, ";")
end

-- ------------------------------------------------------------ spinning gates

-- Fortree Gym and Trick House 6: whether a step goes through depends on which way each gate
-- stands, and the step turns it, so a route is a search over cells and gate positions together.
-- The rules are Player.tryMove's and RotatingGate.checkCollision's, read here against a copy of
-- the orientations.  A journey plans these floors as walkable, and auto-walk asks this for
-- the walk itself (AutoWalk: findRoute).
local GATE_LIMIT = 300000
local GATE_SECONDS = 1.5

local function gatePuzzle(world)
  local RG = loaded("src.core.game3.rotating_gate")
  if not (RG and RG.active and call(RG.active)) then return nil end
  local p = rawget(RG, "_p")
  if type(p) ~= "table" or type(p.gates) ~= "table" or #p.gates == 0 then return nil end
  if world and world.map and p.map ~= world.map.id then return nil end
  return RG, p
end

-- The player is riding the Mach Bike.
function Navigation:onMachBike()
  local Player = loaded("src.core.game3.player")
  return Player ~= nil and Player.biking == true and Player.bikeType == "mach"
end

-- This floor has what only speed crosses: kept per map.
function Navigation:hasSpeedTiles(map)
  self.gen3SpeedFloors = self.gen3SpeedFloors or setmetatable({}, { __mode = "k" })
  local known = self.gen3SpeedFloors[map.def]
  if known ~= nil then return known end
  known = false
  local mud = Terrain.HOENN_MB.MUDDY_SLOPE
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local beh = map:behavior(x, y)
      if beh == mud or Terrain.isCrackedFloor(beh) then known = true end
    end
  end
  self.gen3SpeedFloors[map.def] = known
  return known
end

-- A walk on the Mach Bike over cracked floors and up muddy slopes: a search over cell, heading
-- and speed.  Each straight step raises the speed one gear (Bike: machTrySpeedUp) and any turn
-- drops it to nothing; a cracked floor holds only at the top gear
-- (step_callbacks_rse.crackedFloor) and a muddy slope pushes back anything slower
-- (ForcedMovement.muddySlope).  So a run-up is part of the route.
function Navigation:machRoute(world, goals)
  self.machStrict = true
  local options = self:routeOptionsFor(world, goals, 2)
  self.machStrict = nil
  if not options then return nil, "No path" end
  local map, player = world.map, world.player
  local Bike = loaded("src.core.game3.bike")
  local rse = Bike and call(Bike.rse)
  local gear = rse and rse.state and tonumber(rse.state.frameCounter) or 0
  local goalSet = {}
  for _, goal in ipairs(goals) do goalSet[cellKey(goal.x, goal.y)] = goal end
  local mud, cracked = Terrain.HOENN_MB.MUDDY_SLOPE, Terrain.HOENN_MB.CRACKED_FLOOR
  local first = { x = player.cellX, y = player.cellY, heading = player.facing, gear = gear }
  local seen = { [first.x .. "," .. first.y .. first.heading .. gear] = true }
  local queue, head = { first }, 1
  local deadline = os.clock() + GATE_SECONDS
  local function arrive(node, tx, ty, direction, nextGear, edge)
    local key = tx .. "," .. ty .. direction .. nextGear
    if seen[key] then return end
    seen[key] = true
    queue[#queue + 1] = { x = tx, y = ty, heading = direction, gear = nextGear, parent = node,
      step = { fromX = node.x, fromY = node.y, x = tx, y = ty, direction = direction,
        kind = edge and edge.kind or nil, instruction = edge and edge.instruction or nil } }
  end
  while queue[head] do
    local node = queue[head]
    head = head + 1
    local goal = goalSet[cellKey(node.x, node.y)]
    if goal then
      local steps, cursor = {}, node
      while cursor.parent do
        table.insert(steps, 1, cursor.step)
        cursor = cursor.parent
      end
      steps.ordered = true
      return { steps = steps, goal = goal, cost = #steps, policy = 2 }
    end
    if head % 256 == 0 and os.clock() > deadline then return nil, "regional search timed out" end
    local byDirection = {}
    for _, edge in ipairs(options.neighbors(node.x, node.y)) do byDirection[edge.direction] = edge end
    for _, direction in ipairs(ORDER) do
      local d = DELTA[direction]
      local tx, ty = node.x + d[1], node.y + d[2]
      local straight = direction == node.heading
      -- the gear this step ends in: a turn starts from nothing
      local nextGear = straight and math.min(node.gear + 1, 2) or 1
      local beh = map:inBounds(tx, ty) and map:behavior(tx, ty) or nil
      local fast = straight and node.gear >= 1
      if (beh == cracked or (beh == mud and direction == "up")) then
        if fast and not map:dirBlocked(node.x, node.y, tx, ty, direction) then
          arrive(node, tx, ty, direction, 2, nil)
        end
      elseif byDirection[direction] then
        local edge = byDirection[direction]
        arrive(node, edge.x, edge.y, direction, nextGear, edge)
      end
    end
  end
  return nil, "No path"
end

function Navigation:plannedRoute(goals)
  if not GameData.isHoenn() then return false end
  local world = self:worldForCommand()
  if not world then return false end
  if self:onMachBike() and self:hasSpeedTiles(world.map) then
    return true, self:machRoute(world, goals)
  end
  local RG, puzzle = gatePuzzle(world)
  if not RG then return false end
  local options = self:routeOptionsFor(world, goals, 2)
  if not options then return true, nil, "No path" end
  local Collision = loaded("src.core.game3.collision")
  local function wall(x, y)
    if Collision.inBounds and not Collision.inBounds(x, y) then return true end
    return not Collision.isWalkable(x, y)
  end
  local gates = puzzle.gates
  local info, layouts = RG.ROTATION_INFO, RG.ARM_LAYOUT
  local function canRotate(gate, orientation, direction)
    local arms = direction == RG.ROTATE_ANTICLOCKWISE and RG.ARM_POS_ACW or RG.ARM_POS_CW
    local layout = layouts[gate.shape]
    for arm = 0, 3 do
      for j = 0, 1 do
        if layout[2 * arm + j + 1] == 1 then
          local off = arms[2 * ((orientation + arm) % 4) + j + 1]
          if wall(gate.x + off[1], gate.y + off[2]) then return false end
        end
      end
    end
    return true
  end
  -- the orientations after stepping onto (x, y) moving `direction`; nil when a gate blocks
  local function stepThrough(orient, direction, x, y)
    local rows = info[direction]
    for i, gate in ipairs(gates) do
      if gate.x - 2 <= x and x <= gate.x + 1 and gate.y - 2 <= y and y <= gate.y + 1 then
        local r = rows[(y - gate.y + 2) * 4 + (x - gate.x + 2) + 1]
        if r then
          local arm = (r.arm - orient[i] + 4) % 4
          if layouts[gate.shape][arm * 2 + r.long + 1] == 1 then
            if not canRotate(gate, orient[i], r.dir) then return nil end
            local copy = { unpack(orient) }
            if r.dir == RG.ROTATE_ANTICLOCKWISE then
              copy[i] = (orient[i] + 3) % 4
            else
              copy[i] = (orient[i] + 1) % 4
            end
            return copy
          end
        end
      end
    end
    return orient
  end
  local start = {}
  for i = 1, #gates do start[i] = RG.getOrientation(i - 1) end
  local goalSet = {}
  for _, goal in ipairs(goals) do goalSet[cellKey(goal.x, goal.y)] = goal end
  local player = world.player
  local first = { x = player.cellX, y = player.cellY, orient = start }
  local key0 = cellKey(first.x, first.y) .. ":" .. table.concat(start, "")
  local seen, queue, head = { [key0] = true }, { first }, 1
  local deadline = os.clock() + GATE_SECONDS
  while queue[head] do
    local node = queue[head]
    head = head + 1
    if goalSet[cellKey(node.x, node.y)] then
      local steps, cursor = {}, node
      while cursor.parent do
        table.insert(steps, 1, cursor.step)
        cursor = cursor.parent
      end
      steps.ordered = true
      return true, { steps = steps, goal = goalSet[cellKey(node.x, node.y)], cost = #steps, policy = 2 }
    end
    if head % 256 == 0 and (os.clock() > deadline or head > GATE_LIMIT) then
      return true, nil, "Could not plan a route through the gates in time"
    end
    for _, edge in ipairs(options.neighbors(node.x, node.y)) do
      local orient = stepThrough(node.orient, edge.direction, node.x + DELTA[edge.direction][1], node.y + DELTA[edge.direction][2])
      if orient then
        local key = cellKey(edge.x, edge.y) .. ":" .. table.concat(orient, "")
        if not seen[key] then
          seen[key] = true
          queue[#queue + 1] = { x = edge.x, y = edge.y, orient = orient, parent = node,
            step = { fromX = node.x, fromY = node.y, x = edge.x, y = edge.y, direction = edge.direction,
              kind = edge.kind, instruction = edge.instruction } }
        end
      end
    end
  end
  return true, nil, "No path"
end

-- Sootopolis Gym's thin ice (IceWalk.lua); Hoenn only, since FireRed's Icefall Cave has its
-- own answer (falling through, decision 33).
-- A trainer who walked up can stand in the only way (Mauville Gym): the floor's switches may
-- still open another.  Read by auto-walk when a walk's route is lost.
Navigation.puzzlesOnResume = nil
setmetatable(Navigation, { __index = function(_, key)
  if key == "puzzlesOnResume" then return GameData.isHoenn() end
  return Shared[key]
end })

function Navigation:thinIceBehavior()
  return GameData.isHoenn() and Terrain.MB.THIN_ICE or nil
end
Navigation.crackedIceBehavior = Terrain.MB.CRACKED_ICE

-- The trash cans, for the same walk's hidden switches.  Their script ends at once when
-- the player faces up, so the cell below a can is left out.
function Navigation:hiddenSwitchSigns(world)
  local signs = labelledSigns(self, world, "Trash Can")
  for _, sign in ipairs(signs) do
    local goals = {}
    for _, goal in ipairs(sign.goals) do
      if not (goal.x == sign.x and goal.y == sign.y + 1) then goals[#goals + 1] = goal end
    end
    sign.goals = goals
  end
  return signs
end

-- What scripts have drawn on this floor; a change means a press did something, even
-- when nothing about walking changed.
function Navigation:floorMarks(world)
  local Field = loaded("src.core.game3.field")
  local bucket = Field and Field.metatileOverrides and Field.metatileOverrides[world.map.id]
  local parts = {}
  for key, written in pairs(bucket or {}) do
    parts[#parts + 1] = tostring(key) .. "=" .. tostring(written.metatile)
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

-- Cut trees are objects in FireRed, handled by the route graph.
function Navigation:isCuttableCell() return false end

local CARD_KEY = 355 -- ITEM_CARD_KEY

-- Read the bag without its accessors (Bag.get tidies the bag as it reads).
local function bagHas(bag, itemId)
  if type(bag) ~= "table" then return false end
  local ItemsData = loaded("src.core.game3.items_data")
  local function numeric(id)
    if ItemsData and ItemsData.toNumericId then
      local ok, value = pcall(ItemsData.toNumericId, id)
      if ok and value then return tonumber(value) end
    end
    return tonumber(id)
  end
  for _, slots in pairs(type(bag.pockets) == "table" and bag.pockets or {}) do
    for _, slot in ipairs(type(slots) == "table" and slots or {}) do
      if type(slot) == "table" and numeric(slot.id or slot.item) == itemId
         and (tonumber(slot.qty or slot.count) or 1) > 0 then
        return true
      end
    end
  end
  for key, qty in pairs(type(bag.stacks) == "table" and bag.stacks or {}) do
    if numeric(key) == itemId and (tonumber(qty) or 0) > 0 then return true end
  end
  return false
end
Navigation.bagHas = bagHas

-- The door scripts on this map decide: they check a flag (the Card Key
-- ball's pickup flag in FireRed), read here from the script store; with no
-- door on the map, the bag answers.
function Navigation:hasCardKey()
  local world = self:worldState()
  local map = world and world.map
  local flag
  for _, event in ipairs(map and map.def and map.def.bgEvents or {}) do
    flag = event.type == "sign" and Scripts.cardKeyFlag(event.scriptKey) or nil
    if flag then break end
  end
  if flag then
    local Space = loaded("src.core.game3.scripting.space")
    local Flags = loaded("src.core.game3.scripting.flags")
    if Space and Space.store and Flags and Flags.getFlag then
      return call(Flags.getFlag, Space.store, nil, flag) == true
    end
  end
  local session = self:session()
  return bagHas(session and session.bag, CARD_KEY)
end

-- Silph Co.'s doors: the cells of every card-key door sign on the map,
-- each with the door's own flag (or true when the script names none).
-- Kept per map, since journeys plan many floors at once.
function Navigation:cardKeyDoorCells(world)
  local map = world and world.map
  if not map or not map.def then return {} end
  self.gen3DoorCaches = self.gen3DoorCaches or setmetatable({}, { __mode = "k" })
  local cells = self.gen3DoorCaches[map.def]
  if cells then return cells end
  cells = {}
  -- every sign cell of every door (a door is two to four of them), whether
  -- or not the object list would show it now
  for _, event in ipairs(map.def.bgEvents or {}) do
    if event.type == "sign" and type(event.x) == "number" then
      local _, kind = Scripts.signRole(event.scriptKey)
      if kind == "card_key_door" then
        cells[cellKey(event.x, event.y)] = Scripts.cardKeyDoorOpenFlag(event.scriptKey) or true
      end
    end
  end
  self.gen3DoorCaches[map.def] = cells
  return cells
end

local function flagSet(flag)
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  if not (Space and Space.store and Flags and Flags.getFlag) then return false end
  return call(Flags.getFlag, Space.store, nil, flag) == true
end

-- A closed Silph Co. door.  On the map the player is on, a door sign over
-- a cell that is not floor yet.  On a planned map the layout draws every
-- door open (the floor's load script closes those whose own flag is
-- unset), so the door's flag decides: journeys from 4F walked through
-- 5F's closed doors and then found no way on 5F.
function Navigation:isClosedCardKeyDoorCell(world, x, y)
  local map = world and world.map
  if not map then return false end
  local door = self:cardKeyDoorCells(world)[cellKey(x, y)]
  if not door then return false end
  if not map.live and type(door) == "number" then return not flagSet(door) end
  return not map:isWalkableCell(x, y)
end

-- Auto-walk: the steps that need an A press facing them, the way the
-- player starts these field moves on the map (the game asks first).
local A_PRESS_KINDS = { cut = "Cut", rock_smash = "Rock Smash", surf = "Surf",
  waterfall = "Waterfall" }

function Navigation:stepInteraction(_world, step)
  if step and step.kind == "item_ball" then
    -- the pickup message pauses the walk; it resumes past the cell the
    -- ball stood on.  Still there afterwards (a full bag): stop.
    return { move = "item", failText = "Could not pick up the item, auto walk stopped",
      hint = "Pick up the item facing " .. step.direction }
  end
  local move = step and A_PRESS_KINDS[step.kind]
  if not move then return nil end
  return { move = move, failText = "Could not use " .. move .. ", auto walk stopped",
    hint = "Use " .. move .. " facing " .. step.direction }
end

-- The edge cells a connection can be crossed from (Collision.tryConnection):
-- inside the neighbour's strip, no directional wall on either side, and
-- land onto land, or water onto water or onto land of elevation 3 while
-- surfing.  Pallet Town's south edge is land, but Route 21 below it is
-- water: walking there on foot stops at the shore.
local CONNECTION_STEP_OF = { north = "up", south = "down", west = "left", east = "right" }

function Navigation:connectionGoals(world, item, anyMove)
  local map = world and world.map
  local C = loaded("src.core.game3.collision")
  local Connections = loaded("src.core.game3.connections")
  if not (map and map.def and C and C.connectionLanding and Connections and item) then
    return Shared.connectionGoals(self, world, item)
  end
  local conn
  for _, row in ipairs(call(Connections.each, map.def) or {}) do
    if row.dir == item.direction then conn = row break end
  end
  local destDef = conn and self:regionalMapDef(conn.map)
  local destView = World.plannedView(self.game, destDef)
  local step = CONNECTION_STEP_OF[item.direction]
  if not (destView and step) then return Shared.connectionGoals(self, world, item) end
  local width, height = map.widthCells, map.heightCells
  local count = (step == "up" or step == "down") and width or height
  local function crossings(canSurf)
    local goals = {}
    for coordinate = 0, count - 1 do
      local x = (step == "left") and 0 or (step == "right") and (width - 1) or coordinate
      local y = (step == "up") and 0 or (step == "down") and (height - 1) or coordinate
      local ok, lx, ly = pcall(C.connectionLanding, destDef, conn, step, x, y)
      if ok and lx and not map:dirBlocked(x, y, nil, nil, step)
         and not destView:dirBlocked(nil, nil, lx, ly, step) then
        local hereWater, hereLand = map:isWater(x, y), map:isWalkableCell(x, y)
        local thereWater, thereLand = destView:isWater(lx, ly), destView:isWalkableCell(lx, ly)
        if (hereLand and thereLand)
           or (canSurf and hereWater and (thereWater or (thereLand and destView:elevation(lx, ly) == 3))) then
          goals[#goals + 1] = { x = x, y = y }
        end
      end
    end
    return goals
  end
  local canSurf = anyMove or (world.player and world.player.surfing == true) or self:hmAllowed(world, "SURF")
  local goals = crossings(canSurf)
  -- An edge crossed only by water still has its crossings for a player who cannot Surf:
  -- the route then names the move ("Needs Surf") where no goal at all said "No path".
  if #goals == 0 and not canSurf then goals = crossings(true) end
  return goals
end

-- Auto-walk's last cell of a walk to a warp that fires while a direction
-- is pressed: exit mats (down), arrow warps, stair warps (left or right).
function Navigation:warpPressDirection(world, x, y)
  local map = world and world.map
  if not (map and map.pressDirection) then return nil end
  return map:pressDirection(x, y)
end

-- ------------------------------------------------------------ object list

local function nearestCell(cells, player)
  local nearest, best = cells[1], math.huge
  for _, cell in ipairs(cells) do
    local distance = player and (math.abs(cell.x - (player.cellX or 0))
      + math.abs(cell.y - (player.cellY or 0))) or 0
    if distance < best then nearest, best = cell, distance end
  end
  return nearest
end

-- Furniture the A button reads (MB-keyed, InteractionScripts), one object
-- per connected group of one kind; a group with a sign event on it is that
-- sign instead.  Then the puzzle's objects and mod-authored ones.
function Navigation:interactiveBrowseObjects(world, puzzle)
  local map = world and world.map
  if type(map) ~= "table" or type(map.widthCells) ~= "number" then return {} end
  local mapId = self:currentMapIdOf(world) or "unknown"
  local width, height = map.widthCells, map.heightCells
  local kinds = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local beh = map:behavior(x, y)
      local info = beh and Terrain.FURNITURE[beh]
      if info then kinds[y * width + x] = beh end
    end
  end
  local signCells = {}
  for _, event in ipairs(type(map.def) == "table" and map.def.bgEvents or {}) do
    if event.type == "sign" and type(event.x) == "number" then
      signCells[event.y * width + event.x] = true
    end
  end
  local result, ids, seen = {}, {}, {}
  local function add(record)
    if type(record) ~= "table" or type(record.x) ~= "number" or type(record.y) ~= "number" then return end
    local id = record.id
    if type(id) ~= "string" or id == "" or ids[id] then return end
    ids[id] = true
    result[#result + 1] = record
  end
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      local index = y * width + x
      local beh = kinds[index]
      if beh and not seen[index] then
        local cells, queue, head = {}, { { x, y } }, 1
        seen[index] = true
        local signed = false
        while head <= #queue do
          local cx, cy = queue[head][1], queue[head][2]
          head = head + 1
          cells[#cells + 1] = { x = cx, y = cy }
          if signCells[cy * width + cx] then signed = true end
          for _, d in pairs(DELTA) do
            local nx, ny = cx + d[1], cy + d[2]
            local ni = ny * width + nx
            if nx >= 0 and ny >= 0 and nx < width and ny < height
               and not seen[ni] and kinds[ni] == beh then
              seen[ni] = true
              queue[#queue + 1] = { nx, ny }
            end
          end
        end
        if not signed then
          local info = Terrain.FURNITURE[beh]
          local nearest = nearestCell(cells, world.player)
          add({
            id = "furniture:" .. mapId .. ":" .. cellKey(cells[1].x, cells[1].y),
            label = info.label, x = nearest.x, y = nearest.y,
            interaction = "interact", interactionCells = cells,
            requiredFacing = info.faceUp and "up" or nil,
            semanticKind = "furniture",
            browseType = info.scenery and "misc" or nil,
            category = info.scenery and "misc" or nil,
          })
        end
      end
    end
  end
  for _, cell in ipairs(self:floorSwitchCells(world)) do
    add({ id = "floor_switch:" .. mapId .. ":" .. cellKey(cell.x, cell.y), label = "Floor Switch",
      x = cell.x, y = cell.y, interaction = "walk_onto", semanticKind = "puzzle_switch",
      routeInstruction = "Step on it" })
  end
  -- a place Secret Power opens: a thing to walk up to and use the move on
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if Terrain.isSecretBaseSpot(map:behavior(x, y)) then
        add({
          id = "secret_spot:" .. mapId .. ":" .. cellKey(x, y), label = "Secret Base Spot", x = x, y = y,
          interaction = "interact", interactionCells = { { x = x, y = y } }, semanticKind = "furniture",
        })
      end
    end
  end
  -- where the player can dive, or come up (Navigation:diveSpots)
  local okSpots, spots = pcall(self.diveSpots, self, world)
  for _, spot in ipairs(okSpots and spots or {}) do
    local nearest = nearestCell(spot.cells, world.player)
    add({ id = spot.id, label = spot.label, x = nearest.x, y = nearest.y, interaction = "walk_onto",
      semanticKind = "dive_spot",
      requirement = (not spot.emerge) and self:fieldMoveRequirement("DIVE") or nil })
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
  puzzle = puzzle or self.puzzleAssistance.describe(self.game, world, self)
  for _, object in ipairs(puzzle.objects or {}) do add(object) end
  return result
end

-- Field obstacles are objects in FireRed: what each still needs.
function Navigation:fieldObjectOverrides(world)
  local overrides = {}
  local mapId = self:currentMapIdOf(world)
  for _, eo in ipairs(world.npcs or {}) do
    local gfx = tonumber(eo.graphicsId or (eo.def and eo.def.graphicsId))
    local id = Puzzle.objectId(mapId, eo)
    if gfx == Terrain.GFX.CUT_TREE then
      overrides[id] = { interaction = "field_move", requirement = self:fieldMoveRequirement("CUT"),
        routeInstruction = "use Cut" }
    elseif gfx == Terrain.GFX.ROCK then
      overrides[id] = { interaction = "field_move", requirement = self:fieldMoveRequirement("ROCK_SMASH") }
    elseif gfx == Terrain.GFX.BOULDER then
      overrides[id] = { requirement = self:fieldMoveRequirement("STRENGTH") }
    end
  end
  return overrides
end

local function holeTargets(puzzle)
  local holes = {}
  for _, target in ipairs(puzzle and puzzle.targetStates or {}) do
    if target.hole then holes[cellKey(target.x, target.y)] = target end
  end
  return holes
end

-- Doors no one walks to: a cable club room's door stands in its own closed room behind
-- the counter (the attendant's script walks the player there), and every way out of the
-- room beyond it is dynamic.  The cells around the door reach no other warp and no edge.
-- Kept while the player is inside that closed room.
function Navigation:closedRoomWarps(world)
  local map = world.map
  self.gen3ClosedRooms = self.gen3ClosedRooms or setmetatable({}, { __mode = "k" })
  local rooms = self.gen3ClosedRooms[map.def]
  if rooms then return rooms end
  rooms = {}
  local warpCells = {}
  for index, warp in ipairs(map.def.warps or {}) do
    local _, activeIndex = map:warpAt(warp.x, warp.y)
    if activeIndex == index then warpCells[cellKey(warp.x, warp.y)] = true end
  end
  for index, warp in ipairs(map.def.warps or {}) do
    local _, activeIndex = map:warpAt(warp.x, warp.y)
    local destId = activeIndex == index and map:warpDestination(warp) or nil
    local destDef = destId and self:regionalMapDef(destId)
    local destView = destDef and World.plannedView(self.game, destDef)
    local dynamicOnly = destView ~= nil and #(destDef.warps or {}) > 0
      and #(self:regionalTransitions(destId)) == 0
    if dynamicOnly then
      local seen, queue, head, open = { [cellKey(warp.x, warp.y)] = true }, { { warp.x, warp.y } }, 1, false
      while queue[head] and not open do
        local x, y = queue[head][1], queue[head][2]
        head = head + 1
        for _, d in pairs(DELTA) do
          local nx, ny = x + d[1], y + d[2]
          local key = cellKey(nx, ny)
          if not map:inBounds(nx, ny) then
            open = true
          elseif not seen[key] then
            if warpCells[key] then open = true end
            if map:walkableColl(nx, ny) and not map:isWater(nx, ny) then
              seen[key] = true
              queue[#queue + 1] = { nx, ny }
            end
          end
        end
      end
      if not open then rooms[cellKey(warp.x, warp.y)] = seen end
    end
  end
  self.gen3ClosedRooms[map.def] = rooms
  return rooms
end

-- What the list should not offer because no route could ever serve it: a connection no
-- cell can cross, with any field move (Route 5's edge toward Saffron is scenery; the way
-- is through the gate), and the closed rooms above.
function Navigation:dropUnservable(world, snapshot)
  local rooms = self:closedRoomWarps(world)
  local kept = {}
  local player = world.player
  for _, item in ipairs(snapshot.browse or {}) do
    local drop = false
    if item.type == "connection" then
      local goals = self:connectionGoals(world, item, true)
      drop = type(goals) == "table" and #goals == 0
      -- a map with nothing on it, only drawn past the edge (Saffron's surroundings)
      local dest = self:regionalMapDef(item.destinationMapId)
      if dest and #(dest.warps or {}) == 0 and #(dest.objects or {}) == 0 and #(dest.bgEvents or {}) == 0 then
        drop = true
      end
    elseif item.type == "warp" then
      local room = rooms[cellKey(item.x, item.y)]
      drop = room ~= nil and not room[cellKey(player.cellX, player.cellY)]
    end
    if not drop then kept[#kept + 1] = item end
  end
  snapshot.browse = kept
end

-- Exit mats, arrow warps and stairs need one more press after the player
-- stands on them; say which way, as Gen 1 does for edge carpets.
local function addPressInstructions(snapshot, world)
  local map = world.map
  for _, item in ipairs(snapshot and snapshot.browse or {}) do
    -- a hole's warning names the landing as the list does (the shared
    -- snapshot builds it from the raw map id: "Drop to Fr Seafoam ...")
    if item.type == "warp" and item.routePreamble then
      item.routePreamble = (tostring(item.label):gsub(", entrance %d+ of %d+$", ""))
    end
    if item.type == "warp" and type(item.navigationCells) == "table" then
      for _, cell in ipairs(item.navigationCells) do
        local press = map:pressDirection(cell.x, cell.y)
        if press then
          cell.transitionInstruction = "Continue " .. press .. " to "
            .. tostring(item.label):gsub(", entrance %d+ of %d+$", "")
          item.transitionInstruction = item.transitionInstruction or cell.transitionInstruction
        end
      end
    end
  end
end

function Navigation:captureWorld(filter)
  local world, reason = self:worldForCommand()
  if not world then return nil, reason end
  local puzzle = self.puzzleAssistance.describe(self.game, world, self)
  local overrides = self:fieldObjectOverrides(world)
  for key, override in pairs(puzzle.objectOverrides or {}) do
    local merged = {}
    for k, v in pairs(overrides[key] or {}) do merged[k] = v end
    for k, v in pairs(override) do merged[k] = v end
    overrides[key] = merged
  end
  local playerName, rivalName = self:names()
  local holes = holeTargets(puzzle)
  local snapshot, snapshotError = self.worldSnapshot.capture(world, {
    maps = self.game and self.game.data and self.game.data.maps,
    filter = filter or self.browseFilter,
    playerName = playerName, rivalName = rivalName,
    interactiveObjects = self:interactiveBrowseObjects(world, puzzle),
    objectOverrides = overrides,
    holeTargets = holes,
  })
  if snapshot then
    self:dropUnservable(world, snapshot)
    addPressInstructions(snapshot, world)
    -- a hole the puzzle aims at says so in its state
    for _, item in ipairs(snapshot.browse or {}) do
      local hole = item.type == "warp" and holes[cellKey(item.x, item.y)] or nil
      if hole and hole.state then
        item.stateText = hole.state
        item.description = tostring(item.description) .. "; " .. hole.state
      end
    end
    if (filter or self.browseFilter) == "area" then
      snapshot.browse = self:areaBrowse(world)
    end
  end
  return snapshot, snapshotError
end

-- E: the behaviour bytes under and around the player (their identifiers,
-- as Gen 1 speaks tile numbers and Gen 2 collision bytes).
function Navigation:readCollisionTiles()
  local world, reason = self:worldForCommand()
  if not world then return self:announceManual({ reason }) end
  local map, player = world.map, world.player
  local x, y = player.cellX, player.cellY
  local function value(cx, cy)
    if not map:inBounds(cx, cy) then return "edge" end
    local beh = map:behavior(cx, cy)
    return beh ~= nil and tostring(beh) or "unknown"
  end
  return self:announceManual({
    ("Now on %s, Up %s, Down %s, Left %s, Right %s"):format(
      value(x, y), value(x, y - 1), value(x, y + 1), value(x - 1, y), value(x + 1, y)),
  })
end

-- ------------------------------------------------------------ world events

-- A ledge the player could jump next to them (Pokemon Access warns there).
function Navigation:hasAdjacentLedge(world)
  local map, player = world and world.map, world and world.player
  if not (map and player and map.ledgeFacings) then return false end
  for direction, d in pairs(DELTA) do
    local facings = map:ledgeFacings(player.cellX + d[1], player.cellY + d[2])
    if facings and facings[direction] then return true end
  end
  return false
end

local FOOTSTEP = { grass = true, water = true, ice = true, thin_ice = true, cracked_ice = true,
  current = true, waterfall = true, spinner = true, moving_floor = true }

function Navigation:usesTerrainFootstep(record)
  return type(record) == "table" and FOOTSTEP[record.kind] == true
end

-- The game shows its own name popup on entering most outdoor maps and
-- dungeons (map.lua: showMapName set, and a new map section or a warp);
-- screen speech reads that popup, so the entry announcement is left to it
-- there and made here only where the game shows nothing.  M still reads the
-- map name anywhere.
local FLAG_DONT_SHOW_MAP_NAME_POPUP = 0x4000

local function popupSuppressed()
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  if Space and Space.store and Flags and Flags.getFlag then
    if call(Flags.getFlag, Space.store, nil, FLAG_DONT_SHOW_MAP_NAME_POPUP) then return true end
  end
  return false
end

function Navigation:subscribePopupEvent()
  local events = self.events
  if type(events) ~= "table" or type(events.on) ~= "function" or not self.worldSubscriptions then
    return
  end
  -- Map.load decides the popup after emitting map.entered: the previous
  -- section is still Map._lastSectionId here.  Priority below the shared
  -- handler (-1000; higher runs first), so this runs after it set
  -- pendingMapEvent.
  self.worldSubscriptions[#self.worldSubscriptions + 1] = events:on("map.entered", function(event)
    if not self.enabled or type(event) ~= "table" or not self.pendingMapEvent then return end
    local def = type(event.map) == "table" and event.map or nil
    local Map = loaded("src.core.game3.map")
    local lastSection = Map and rawget(Map, "_lastSectionId")
    local section = def and def.regionMapSectionId
    local shows = def ~= nil and (def.showMapName == 1 or def.showMapName == true)
      and not popupSuppressed()
      and (event.via ~= "connection" or lastSection == nil or lastSection ~= section)
    self.pendingMapEvent.gamePopup = shows == true
  end, -1001, self.eventOwner)
end

function Navigation:processWorldEvents(_state)
  if not self:isDescribableWorld() then
    return Shared.processWorldEvents(self, nil)
  end
  local mapEvent = self.pendingMapEvent
  if mapEvent then
    -- the shared entry handling, with FireRed's names, and silent where the
    -- game shows its own popup; a journey still hands over to its next leg
    self.pendingMapEvent = nil
    self.pendingStepEvent = nil
    local world = self:worldState()
    if self:currentMapIdOf(world) ~= mapEvent.mapId then return end
    local navigation = self.activeNavigation
    if not mapEvent.gamePopup then
      local playerName, rivalName = self:names()
      local location = Snapshot.locationName(world.map, mapEvent.mapId, nil, playerName, rivalName)
      if navigation and navigation.awaitingMap then
        navigation.pendingLocation = location
      else
        self:announce(location, { interrupt = true })
      end
    end
    if navigation and navigation.awaitingMap then self:resumeRegionalNavigation() end
    return
  end
  return Shared.processWorldEvents(self, {
    isOverworld = true,
    transient = not self:isActionableWorld(),
  })
end

function Navigation:updateNavigationInterruption(state)
  local navigation = self.activeNavigation
  if not navigation then
    self.navigationInterruptedByBattle = false
    return false
  end
  if type(state) == "table" and (state.isBattle == true or state.accessibilityRole == "battle") then
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

-- Game3 has no StateStack: the top comes from the world adapter.
function Navigation:updateNavigation()
  if not self.enabled then return end
  local state = Gen3.top(self.game)
  self:updateNavigationInterruption(state)
  self:updatePendingRoute()
  self:processWorldEvents(state)
  -- a Strength plan still being searched for this floor carries on a
  -- little each frame, so the next request has it
  if self:isActionableWorld() then Puzzle.continueSearch(self:worldState()) end
end

function Navigation:update()
  return self:updateNavigation()
end

-- Q: FireRed has no real-time clock (pret's FRLG has none).  Ruby, Sapphire and
-- Emerald say the game's own local time (Rtc.calcLocalTime: the time the player set
-- at the wall clock).
function Navigation:readGameTime()
  local Rtc = GameData.isHoenn() and lazyRtc() or nil
  local session = self:session()
  if Rtc and call(Rtc.enabled, session) then
    local time = call(Rtc.calcLocalTime, session)
    if type(time) == "table" and tonumber(time.hours) then
      local hours, minutes = tonumber(time.hours), tonumber(time.minutes) or 0
      local suffix = hours >= 12 and "PM" or "AM"
      local twelve = hours % 12
      if twelve == 0 then twelve = 12 end
      return self:announceManual({ ("%d:%02d %s"):format(twelve, minutes, suffix) })
    end
    return self:announceManual({ "The clock has not been set" })
  end
  return self:announceManual({ "This game has no clock" })
end

-- ------------------------------------------------------------ battle (H)

function Navigation:battleForCommand()
  if not Gen3.battleActive() then return nil end
  local Battle = loaded("src.core.game3.battle") or loaded("src.core.game3.battle.init")
  return Battle and call(Battle.getState) or WorldAdapter.GEN3_BATTLE
end

local STATUS_WORDS = { SLP = "asleep", FRZ = "frozen", PSN = "poisoned", BRN = "burned",
  PAR = "paralyzed", TOX = "badly poisoned" }

-- H and Shift+H.  The Gen 3 battle presenter answers from what the
-- healthbox shows when it provides `health`; otherwise the battler's
-- current values are read, as Gen 1 does.
function Navigation:readBattleHealth(side)
  -- the Gen 3 battle presenter reads the live battle (nil) as its healthbox
  -- shows it, doubles and the Safari Zone included; nil means no battle
  local okModule, Presenter = pcall(require, "src.access.screens.gen3.Battle")
  if okModule and type(Presenter) == "table" and type(Presenter.health) == "function" then
    local ok, text = pcall(Presenter.health, nil, side)
    if ok then
      if type(text) == "string" and text ~= "" then return self:announceManual({ text }) end
      return self:announceManual({ "Not in battle" })
    end
  end
  -- without the presenter: the battler's current values, as Gen 1 reads them
  local battle = self:battleForCommand()
  if not battle then return self:announceManual({ "Not in battle" }) end
  local battler = type(battle) == "table" and (side == "enemy" and battle.enemy or battle.player) or nil
  local mon = type(battler) == "table" and battler.mon or nil
  local hp = mon and tonumber(mon.hp)
  local maxHP = mon and (tonumber(mon.maxHP) or tonumber(mon.maxHp)
    or (type(mon.stats) == "table" and tonumber(mon.stats.hp)))
  if not (hp and maxHP and maxHP > 0) then return self:announceManual({ "No bar found" }) end
  if side == "enemy" then
    return self:announceManual({ ("Enemy health: %d percent"):format(math.floor(hp * 100 / maxHP + 0.5)) })
  end
  local name = (type(mon.nickname) == "string" and mon.nickname ~= "" and mon.nickname)
    or battler.name or "Pok\195\169mon"
  local text = ("Player %s, %d of %d HP"):format(tostring(name), hp, maxHP)
  local status = mon.status
  if type(status) == "string" and STATUS_WORDS[status] then text = text .. ", " .. STATUS_WORDS[status] end
  return self:announceManual({ text })
end

-- ------------------------------------------------------------ routing

-- The live and planned movement graph, one set of rules for both.

local GFX = Terrain.GFX

local function actorAt(actors, x, y)
  for _, actor in ipairs(actors) do
    if actor.cellX == x and actor.cellY == y then return actor end
    if actor.moving and actor.targetX == x and actor.targetY == y then return actor end
  end
  return nil
end

-- Objects that block a cell (Objects.blocks: visible, not passable, a
-- compatible elevation), keyed by cell, with the field obstacle kind.
local function occupancy(world)
  local cells = {}
  local player = world.player
  for _, actor in ipairs(world.npcs or {}) do
    if type(actor) == "table" and actor ~= player and not actor.passable
       and not (type(actor.def) == "table" and actor.def.ignorable == true) then
      local gfx = tonumber(actor.graphicsId or (actor.def and actor.def.graphicsId))
      local kind = (gfx == GFX.CUT_TREE and "cut_tree") or (gfx == GFX.ROCK and "rock")
        or (gfx == GFX.BOULDER and "boulder") or "object"
      -- an item ball the A button picks up (its script gives an item; a
      -- gift Poke Ball does not count): it leaves the map once taken
      local item
      if gfx == GFX.ITEM_BALL then
        item = Scripts.itemBallItem((type(actor.def) == "table" and actor.def.scriptKey) or actor.scriptKey)
        if item then kind = "item_ball" end
      end
      local entry = { actor = actor, kind = kind, item = item,
        itemName = item and (Scripts.itemLabel(item) or "the item") or nil,
        elevation = tonumber(actor.currentElevation) or 0 }
      cells[cellKey(actor.cellX, actor.cellY)] = entry
      if actor.moving and actor.targetX and actor.targetY then
        cells[cellKey(actor.targetX, actor.targetY)] = entry
      end
    end
  end
  return cells
end

local function elevationsCompatible(a, b)
  a, b = tonumber(a) or 0, tonumber(b) or 0
  return a == 0 or b == 0 or a == b
end

-- The movement graph (src/core/game3/player.lua tryMove, collision.lua
-- canEnter and ledgeLanding, forced_movement.lua):
--   * walking: in bounds, no MB wall on the cell left or entered, land the
--     COLL byte allows (never a ledge cell), no object (elevation rule),
--     elevation match (Pokemon Access's rule: 0 and 15 match anything)
--   * ledges: the cell ahead is a ledge facing the move; land two cells on
--   * Surf: from land onto water with an A press facing it; on water,
--     water; back onto land of elevation 3
--   * Cut trees and Rock Smash rocks: objects, "use, then move"; an item
--     ball in the way is picked up the same way (policy 2 and up; gone
--     once taken, as Gen 1 and Gen 2 treat collected balls)
--   * closed card key doors: walls, or opened on the way with the key
--   * Waterfall: climbed from below while surfing, the whole column in one
--     move; going down, the current carries the player down the column
--   * forced movement (ice, spinners, currents, walk and slide tiles) as one
--     move to where it stops; a warp crossed on the way ends it there
--   * warps only as the goal, entered the way they fire (a door only moving
--     up into it); holes and cracked ice never except as the goal
function Navigation:routeOptionsFor(world, goals, policy)
  if not world then return nil, "Not on a map" end
  if type(goals) ~= "table" or #goals == 0 then return nil, "No path" end
  policy = policy or 1
  local map, player = world.map, world.player
  local goalSet = {}
  for _, goal in ipairs(goals) do goalSet[cellKey(goal.x, goal.y)] = true end
  local surfing = player.surfing == true
  local canSurf = surfing or self:hmAllowed(world, "SURF", policy)
  local canCut = self:hmAllowed(world, "CUT", policy)
  local canSmash = self:hmAllowed(world, "ROCK_SMASH", policy)
  local canWaterfall = self:hmAllowed(world, "WATERFALL", policy)
  local useCardKey = policy >= 2 and (self:hasCardKey() or policy >= 3)
  local occupied = occupancy(world)
  -- routeNeeds asks for the way with people set aside, to name who stands in it
  if self.routeIgnoringPeople then
    -- all but those essentialBlocker is testing: they stay where they stand
    local solid = self.routeSolidPeople
    for key, entry in pairs(occupied) do
      if entry.kind == "object" and not (solid and solid[entry.actor.def or entry.actor]) then occupied[key] = nil end
    end
  end
  -- on the Mach Bike a journey plans cracked floors and slopes as floor; the walk on the
  -- floor itself works out the speed (machRoute, which asks with machStrict set)
  local hoenn = GameData.isHoenn()
  local machFree = not self.machStrict and hoenn and self:onMachBike()
  local floorSwitches = {}
  for _, cell in ipairs(self:floorSwitchCells(world)) do floorSwitches[cellKey(cell.x, cell.y)] = true end
  local closedDoors = {}
  for key in pairs(self:cardKeyDoorCells(world)) do
    local x, y = key:match("^(-?%d+),(-?%d+)$")
    if self:isClosedCardKeyDoorCell(world, tonumber(x), tonumber(y)) then closedDoors[key] = true end
  end
  local startX, startY = player.cellX, player.cellY
  local startElevation = tonumber(player.currentElevation)
  local width, height = map.widthCells, map.heightCells

  local function elevationOf(x, y)
    if x == startX and y == startY and startElevation then return startElevation end
    return map:elevation(x, y)
  end
  local function mismatch(fromX, fromY, x, y)
    return Puzzle.elevationsMismatch(elevationOf(fromX, fromY), map:elevation(x, y))
  end

  -- What stands on a cell: nil, or the occupancy entry.
  local function blocker(x, y, fromElevation)
    local entry = occupied[cellKey(x, y)]
    if not entry then return nil end
    if not elevationsCompatible(fromElevation, entry.elevation) then return nil end
    return entry
  end

  local function landCell(x, y)
    return map:walkableColl(x, y) and not map:isWater(x, y) and not map:overrideBlocked(x, y)
  end

  -- May the player end a move on (x, y), coming from (fromX, fromY)?
  -- `onWater`: they are surfing.  Objects are checked by the caller.
  local function enterable(fromX, fromY, x, y, direction, onWater)
    if not map:inBounds(x, y) then return false end
    if map:dirBlocked(fromX, fromY, x, y, direction) then return false end
    local isGoal = goalSet[cellKey(x, y)] == true
    local kind = map:warpKind(x, y)
    if kind then
      if isGoal then
        -- a door fires only moving up into it from the cell below
        if kind == "door" and direction ~= "up" then return false end
        return true
      end
      -- exit mats, arrow and stair warps fire only while their own
      -- direction is pressed: they may be walked across like floor
      -- (Victory Road's entrance mat); any other warp is never entered
      if not map:standingWarp(x, y) then return false end
    end
    local beh = map:behavior(x, y)
    if Terrain.givesWay(beh) and not isGoal
       and not (machFree and beh == Terrain.HOENN_MB.CRACKED_FLOOR) then
      return false
    end
    if Terrain.needsAcroBike(beh) then return false end
    -- crossing a floor switch would change the floor under the route; pressing one is a
    -- step of its own (SwitchWalk)
    if floorSwitches[cellKey(x, y)] and not isGoal and policy < 3 then return false end
    -- a closed card key door: opened on the way with the key, else a wall
    if closedDoors[cellKey(x, y)] then return useCardKey end
    local water = map:isWater(x, y)
    local differs = mismatch(fromX, fromY, x, y)
    if onWater then
      if water then return not differs end
      -- leaving the water (CanStopSurfing): a different elevation needs 3
      if not landCell(x, y) then return false end
      return not differs or map:elevation(x, y) == 3
    end
    if water or differs then return false end
    return landCell(x, y)
  end

  -- Forced movement from (x, y), arrived at moving `direction`: where it
  -- stops, its kind and how far it went; nil when it is not a usable move
  -- (it crosses a warp that is not the goal).
  local function forcedChain(x, y, direction, onWater)
    local travelled, kind, spinning = 0, nil, nil
    local limit = width * height
    local moveDir = direction
    while true do
      local beh = map:behavior(x, y)
      local nextDir, nextKind
      if spinning then
        -- a spin carries on across ordinary floor until a stop tile or a
        -- wall (TryUpdatePlayerSpinDirection)
        if beh == Terrain.STOP_SPINNING then break end
        nextDir = Terrain.SPIN[beh] or spinning
        spinning = nextDir
        nextKind = "spinner"
      else
        nextDir, nextKind = Terrain.forced(beh)
        if nextKind == "ice" then nextDir = moveDir end
        if nextKind == "spinner" then spinning = nextDir end
        if nextKind == "waterfall" and not onWater then nextDir = nil end
      end
      if not nextDir then break end
      local d = DELTA[nextDir]
      local nx, ny = x + d[1], y + d[2]
      local facings = map:ledgeFacings(nx, ny)
      if facings and facings[nextDir] and not onWater then
        -- a forced step hops a ledge it meets
        local lx, ly = x + d[1] * 2, y + d[2] * 2
        if not (map:inBounds(lx, ly) and landCell(lx, ly)) then break end
        nx, ny = lx, ly
      elseif not map:inBounds(nx, ny) or map:dirBlocked(x, y, nx, ny, nextDir)
          or blocker(nx, ny, elevationOf(x, y)) then
        break
      else
        if map:warpKind(nx, ny) and not map:standingWarp(nx, ny) then
          -- the game carries the player onto it and it fires; the move ends
          -- there, usable only when that warp is the goal
          if not goalSet[cellKey(nx, ny)] then return nil end
          return nx, ny, kind or nextKind, travelled + 1
        end
        local water = map:isWater(nx, ny)
        if onWater then
          if not water and not landCell(nx, ny) then break end
          -- Carried onto land.  Upstream leaves the player surfing there as far as the
          -- game knows (seen on Route 134's east sandbar: surfing set, standing on sand),
          -- so it offers no Surf and auto-walk stopped with "Could not use Surf".  Not a
          -- move to plan: another lane is taken, or the walk says there is no route.
          if not water then return nil end
        elseif water or not landCell(nx, ny) or mismatch(x, y, nx, ny) then
          break
        end
      end
      -- the kind of forced move is known once it has carried the player a
      -- cell (ice against a wall is only a step: "slide 0 cells" was said)
      kind = kind or nextKind
      x, y, moveDir = nx, ny, nextDir
      travelled = travelled + 1
      if travelled > limit then return nil end
    end
    return x, y, kind, travelled
  end

  local FORCED_TEXT = {
    spinner = "onto the spinner", current = "into the current", waterfall = "into the current",
    moving_floor = "onto the moving floor",
  }

  -- One move from (fromX, fromY): the cell it ends on, the edge kind and
  -- the spoken instruction for special moves; nil when it is not possible.
  local function landing(fromX, fromY, direction)
    local d = DELTA[direction]
    local x, y = fromX + d[1], fromY + d[2]
    if not map:inBounds(x, y) then return nil end
    -- pressing a standing warp's own direction on it would take it
    if map:standingWarp(fromX, fromY) == direction then return nil end
    local underwater = map.underwater == true
    local onWater = underwater or map:isWater(fromX, fromY)
    local fromElevation = elevationOf(fromX, fromY)
    -- a ledge ahead facing the move: the hop lands two cells on
    local facings = map:ledgeFacings(x, y)
    if facings and facings[direction] then
      if onWater then return nil end
      local lx, ly = fromX + d[1] * 2, fromY + d[2] * 2
      if not map:inBounds(lx, ly) or blocker(lx, ly, fromElevation) then return nil end
      if not landCell(lx, ly) then return nil end
      return lx, ly, "ledge", "Jump ledge " .. direction
    end
    if map:dirBlocked(fromX, fromY, x, y, direction) then return nil end
    local beh = map:behavior(x, y)
    -- What only a bike crosses, for naming what is missing (policy 3): a Mach Bike at
    -- speed over cracked floors and up muddy slopes, an Acro Bike on rails.  The walk
    -- itself is refused: both take a run-up and timing no route here knows how to hold.
    if machFree and beh == Terrain.HOENN_MB.MUDDY_SLOPE and direction == "up" and not blocker(x, y, fromElevation) then
      local cy = y
      while map:behavior(x, cy) == Terrain.HOENN_MB.MUDDY_SLOPE and cy > 0 do cy = cy - 1 end
      return x, cy
    end
    if policy >= 3 and not blocker(x, y, fromElevation) then
      if Terrain.needsAcroBike(beh) then return x, y, "acro_bike", "Ride the Acro Bike " .. direction end
      if Terrain.isCrackedFloor(beh) then return x, y, "mach_bike", "Ride the Mach Bike " .. direction end
      if beh == Terrain.HOENN_MB.MUDDY_SLOPE and direction == "up" then
        local cy = y
        while map:behavior(x, cy) == Terrain.HOENN_MB.MUDDY_SLOPE and cy > 0 do cy = cy - 1 end
        return x, cy, "mach_bike", "Ride the Mach Bike up the slope"
      end
    end
    -- Waterfall: climbed from below while surfing, the whole column in one
    -- move to the first cell above it (FieldMoves.tryWaterfallOW, the ride)
    if beh == Terrain.MB.WATERFALL and direction == "up" then
      if not (onWater and canWaterfall) then return nil end
      local cx, cy, climbed = x, y, 0
      while map:behavior(cx, cy) == Terrain.MB.WATERFALL do
        cy = cy - 1
        climbed = climbed + 1
        if not map:inBounds(cx, cy) or climbed > height then return nil end
      end
      if not map:isWater(cx, cy) or blocker(cx, cy, fromElevation) then return nil end
      return cx, cy, "waterfall", "Use Waterfall facing up, then climb " .. climbed
        .. (climbed == 1 and " cell" or " cells")
    end
    local entry = blocker(x, y, fromElevation)
    local entryKind, entryInstruction
    local toWater = map:isWater(x, y)
    if entry then
      -- Cut trees and Rock Smash rocks are cleared from where the player
      -- stands, then the step is taken; an item ball is picked up the same
      -- way (policy 2 and up, and dearer than a detour of one cell, so a
      -- way round is preferred)
      if entry.kind == "cut_tree" and canCut then
        entryKind, entryInstruction = "cut", "Use Cut facing " .. direction .. ", then move " .. direction
      elseif entry.kind == "rock" and canSmash then
        entryKind, entryInstruction = "rock_smash",
          "Use Rock Smash facing " .. direction .. ", then move " .. direction
      elseif entry.kind == "item_ball" and policy >= 2 then
        entryKind, entryInstruction = "item_ball",
          "Pick up " .. entry.itemName .. " facing " .. direction
            .. ", then move " .. direction
      else
        return nil
      end
      if not enterable(fromX, fromY, x, y, direction, onWater) then return nil end
    elseif toWater and not onWater then
      -- from land onto water takes Surf (an A press facing it; the hop
      -- ignores elevation)
      if not canSurf or map:warpKind(x, y) then return nil end
      entryKind, entryInstruction = "surf", "Use Surf facing " .. direction
    else
      if not enterable(fromX, fromY, x, y, direction, onWater) then return nil end
      if onWater and not toWater and not underwater then
        entryKind, entryInstruction = "exit_water", "Exit water " .. direction
      end
    end
    if map:warpKind(x, y) and (goalSet[cellKey(x, y)] or not map:standingWarp(x, y)) then
      return x, y, entryKind, entryInstruction
    end
    -- A bridge (Hoenn's elevation 15 cells): they keep the elevation the player came on with
    -- (Player.updateElevation), so what waits on the far side depends on the near side.  One
    -- straight crossing is one move, to the first cell past it, refused when the far side's
    -- elevation does not match the near side's.
    if hoenn and not onWater and map:elevation(x, y) == 15 and not goalSet[cellKey(x, y)]
       and fromElevation ~= 15 and not entry then
      local bx, by, crossed = x, y, 0
      while map:elevation(bx, by) == 15 do
        local nx, ny = bx + d[1], by + d[2]
        if not map:inBounds(nx, ny) or map:dirBlocked(bx, by, nx, ny, direction)
           or blocker(nx, ny, fromElevation) then
          return nil
        end
        if goalSet[cellKey(nx, ny)] and map:elevation(nx, ny) == 15 then return nx, ny end
        bx, by, crossed = nx, ny, crossed + 1
        if crossed > width + height then return nil end
      end
      if Puzzle.elevationsMismatch(fromElevation, map:elevation(bx, by)) then return nil end
      if not landCell(bx, by) or map:warpKind(bx, by) and not goalSet[cellKey(bx, by)] then return nil end
      return bx, by, nil, nil
    end
    -- forced movement from the cell entered; a goal on a forced tile cannot
    -- be stopped on, only where the movement ends
    local fx, fy, kind, travelled = forcedChain(x, y, direction, onWater or toWater)
    if fx == nil then return nil end
    if fx == fromX and fy == fromY then return nil end
    local instruction
    if kind == "ice" then
      instruction = "Move " .. direction .. " onto ice; slide " .. travelled
        .. (travelled == 1 and " cell" or " cells")
    elseif kind then
      instruction = "Move " .. direction .. " " .. FORCED_TEXT[kind] .. "; carried to x "
        .. fx .. ", y " .. fy
    end
    if entryInstruction and instruction then
      instruction = entryInstruction .. ", then " .. instruction:sub(1, 1):lower() .. instruction:sub(2)
    elseif entryInstruction then
      instruction = entryInstruction
    end
    local edgeKind = entryKind or (kind == "waterfall" and "current") or kind
    return fx, fy, edgeKind, instruction
  end

  local function neighbors(x, y)
    local result = {}
    for _, direction in ipairs(ORDER) do
      local tx, ty, kind, instruction = landing(x, y, direction)
      if tx ~= nil then
        result[#result + 1] = { x = tx, y = ty, direction = direction,
          kind = kind, instruction = instruction,
          cost = (kind == "item_ball" and 2) or (floorSwitches[cellKey(tx, ty)] and 12) or nil }
      end
    end
    return result
  end

  return {
    start = { x = startX, y = startY }, goals = goals,
    bounds = { width = width, height = height },
    allowBlockedGoal = false, policy = policy, neighbors = neighbors,
    canTraverse = function() return true end, maxSeconds = 0.25,
  }, world
end

-- Auto-walk tries a journey through other maps when a target on this map
-- has no route here, as guided navigation does (advancePendingRoute).
Navigation.autoWalkJourneys = true
Navigation.stepOffWarpTargets = true
-- a warp that lands on the same map (Saffron Gym's pads) moves the player off the route
-- without a new map: the journey is planned again from there, not the old leg's cell
Navigation.replanJourneyOffRoute = true
-- a connection is crossed mid-step: the next leg is planned once the player's cell is on
-- the new map (AutoWalk.update)
Navigation.journeyWaitsForLanding = true

-- What stands in the way, for auto-walk's refusal when there is no route: a
-- person (or other object that is no cut tree, rock, boulder or item) in the
-- only way through, such as the grunts the story moves later.  The route is
-- planned again with them set aside; the first one on it is named, as FireRed's
-- and Red's "Blocked by".  Nil when even that finds no way.
function Navigation:routeNeeds(goals)
  local world = self:worldForCommand()
  if not world then return nil end
  self.routeIgnoringPeople = true
  local ok, options = pcall(self.routeOptionsFor, self, world, goals, 2)
  self.routeIgnoringPeople = nil
  if not (ok and options) then return nil end
  local found, result = pcall(Pathfinder.find, options)
  if not (found and result and type(result.steps) == "table") then return nil end
  local occupied = occupancy(world)
  for _, step in ipairs(result.steps) do
    local entry = occupied[cellKey(step.x, step.y)]
    if entry and entry.kind == "object" then
      -- Lavaridge Gym's buried trainers stand in four of its holes, unseen until they
      -- jump out: not in any list, so a name ("Man") would point at no one
      if entry.actor.invisible then
        local def = type(entry.actor.def) == "table" and entry.actor.def or {}
        return tonumber(def.trainerType) == 3 and "Blocked by a hidden trainer" or "Blocked by something hidden"
      end
      local okLabel, label = pcall(Snapshot.objectLabel, entry.actor, {})
      return "Blocked by " .. tostring(okLabel and label or "someone")
    end
  end
  return nil
end

function Navigation:worldRouteRequest(goals, policy)
  local world, reason = self:worldForCommand()
  if not world then return nil, reason end
  -- the route depends on how the gates stand: say so, not a route that ignores them
  if gatePuzzle(world) then return nil, "Spinning gates here: use auto walk" end
  return self:routeOptionsFor(world, goals, policy)
end

-- A bridge's crossing as the cell-by-cell steps auto-walk follows (AutoWalk: findRoute).
function Navigation:expandRoute(result)
  local steps = result and result.steps
  if type(steps) ~= "table" then return result end
  local expanded
  for index, step in ipairs(steps) do
    local dx, dy = step.x - step.fromX, step.y - step.fromY
    local cells = math.abs(dx) + math.abs(dy)
    if not step.kind and cells > 1 and (dx == 0 or dy == 0) then
      if not expanded then
        expanded = {}
        for i = 1, index - 1 do expanded[i] = steps[i] end
      end
      local ux, uy = dx / cells, dy / cells
      for i = 1, cells do
        expanded[#expanded + 1] = { fromX = step.fromX + ux * (i - 1), fromY = step.fromY + uy * (i - 1),
          x = step.fromX + ux * i, y = step.fromY + uy * i, direction = step.direction }
      end
    elseif expanded then
      expanded[#expanded + 1] = step
    end
  end
  if expanded then result.steps = expanded end
  return result
end

-- Directions counted ("3 up"), special moves spoken whole; a card key door
-- on the way is said once.
function Navigation:routeNarration(world, result, routePolicy)
  if result.cost == 0 then return { "Already there" } end
  routePolicy = routePolicy or result.policy or 1
  local tokens = {}
  local doors = {}
  local function add(text, countable)
    local prior = tokens[#tokens]
    if countable and prior and prior.countable and prior.text == text then
      prior.count = prior.count + 1
    else
      tokens[#tokens + 1] = { text = text, count = 1, countable = countable }
    end
  end
  for _, step in ipairs(result.steps or {}) do
    if routePolicy > 1 and self:isClosedCardKeyDoorCell(world, step.x, step.y) then
      if not doors[cellKey(step.x, step.y)] then
        add("Use Card Key facing " .. step.direction, false)
      end
      doors[cellKey(step.x, step.y)] = true
    end
    if step.kind then add(step.instruction or step.direction, false)
    else
      -- (a bridge's crossing is one move of several cells)
      local cells = math.abs(step.x - step.fromX) + math.abs(step.y - step.fromY)
      for _ = 1, math.max(cells, 1) do add(step.direction, true) end
    end
  end
  local parts = {}
  for _, token in ipairs(tokens) do
    parts[#parts + 1] = token.countable and (token.count .. " " .. token.text) or token.text
  end
  return parts
end

local REQUIREMENT_KEY = { CUT = "CUT", SURF = "SURF", ROCK_SMASH = "ROCK_SMASH",
  WATERFALL = "WATERFALL" }

function Navigation:routeRequirements(world, result)
  local needed = {}
  local function need(moveId)
    local usable, missingMon, missingBadge = self:fieldMoveStatus(moveId)
    if usable then return end
    if missingMon then needed[REQUIREMENT_KEY[moveId] or moveId] = true end
    if missingBadge then needed[(missingBadge:upper():gsub(" ", "_"))] = true end
  end
  for _, step in ipairs(result.steps or {}) do
    if step.kind == "cut" then need("CUT") end
    if step.kind == "surf" then need("SURF") end
    if step.kind == "rock_smash" then need("ROCK_SMASH") end
    if step.kind == "waterfall" then need("WATERFALL") end
    if step.kind == "mach_bike" then needed.MACH_BIKE = true end
    if step.kind == "acro_bike" then needed.ACRO_BIKE = true end
    if self:isClosedCardKeyDoorCell(world, step.x, step.y) and not self:hasCardKey() then
      needed.CARD_KEY = true
    end
  end
  return needed
end

-- ------------------------------------------------------------ sonar

function Navigation:isPushableEntity(entity)
  return Terrain.isBoulder(entity) == true
end

-- Ordinary walking only ("can I step there"); Surf only while surfing.
function Navigation:sonarCanMove(world, probe, direction)
  local map = world and world.map
  local delta = DELTA[direction]
  if not (map and delta and probe) then return false end
  local fromX, fromY = probe.cellX, probe.cellY
  local x, y = fromX + delta[1], fromY + delta[2]
  if not map:inBounds(x, y) or map:dirBlocked(fromX, fromY, x, y, direction) then return false end
  if actorAt(world.npcs or {}, x, y) then return false end
  if map:isWater(x, y) then return probe.surfing == true end
  return map:isWalkableCell(x, y) or map:warpAt(x, y) ~= nil
end

-- A door the player could enter except that a live object stands on every
-- approach: leaving the map will not help, so say so.
function Navigation:blockedWarpEntrance(navigation)
  if not navigation or navigation.targetType ~= "warp" then return false end
  local world = self:worldForCommand()
  if not world or navigation.targetMapId ~= self:currentMapIdOf(world) then return false end
  local map = world.map
  local viable = false
  for _, goal in ipairs(navigation.targetGoals or {}) do
    for _, direction in ipairs(ORDER) do
      local d = DELTA[direction]
      local fromX, fromY = goal.x - d[1], goal.y - d[2]
      if map:inBounds(fromX, fromY) and map:isWalkableCell(fromX, fromY)
         and not map:dirBlocked(fromX, fromY, goal.x, goal.y, direction) then
        viable = true
        if not actorAt(world.npcs or {}, fromX, fromY) then return false end
      end
    end
  end
  return viable
end

-- ------------------------------------------------------------ cross-map

function Navigation:regionalMapDef(mapId)
  local data = self.game and self.game.data
  local maps = data and data.maps
  return maps and maps[mapId] or nil
end

local function regionalObjectVisible(object)
  if type(object) ~= "table" then return false end
  if tonumber(object.movementType) == 0x4C then return true end -- invisible, still blocks
  local Space = loaded("src.core.game3.scripting.space")
  if not (Space and Space.objectVisible) then return true end
  local ok, visible = pcall(Space.objectVisible, object)
  if not ok then return true end
  return visible and true or false
end
Navigation.regionalObjectVisible = function(_, object) return regionalObjectVisible(object) end

-- A headless world for a map the player is not on: its view and the
-- objects the game would show.  Surfing carries into the plan.
function Navigation:regionalStaticWorld(mapId, start)
  local def = self:regionalMapDef(mapId)
  local view = World.loadedView(self.game, def)
  if not view then return nil end
  local live = self:worldState()
  local surfing = live and live.player and live.player.surfing == true or false
  local player = { cellX = start.x, cellY = start.y, facing = "down", surfing = surfing }
  local npcs = {}
  for _, object in ipairs(def.objects or {}) do
    if object.x and object.y and regionalObjectVisible(object) then
      npcs[#npcs + 1] = { cellX = object.x, cellY = object.y, def = object,
        graphicsId = object.graphicsId, currentElevation = object.elevation,
        localId = object.localId, invisible = tonumber(object.movementType) == 0x4C }
    end
  end
  local entities = { player }
  for _, actor in ipairs(npcs) do entities[#entities + 1] = actor end
  return { isOverworld = true, map = view, player = player, npcs = npcs, entities = entities }
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

local CONNECTION_STEP = { north = "up", south = "down", west = "left", east = "right" }

-- Warps (active ones, resolved as the game resolves them; dynamic warps
-- through the session's record, else no edge) and connections (landing by
-- Collision.connectionLanding, refused where the strip ends, on a wall, on
-- water without Surf, or across a directional wall).
function Navigation:regionalTransitions(mapId)
  local def = self:regionalMapDef(mapId)
  local live = not self.journeySupposing and World.liveView(self.game)
  -- (a plan that supposes a flag reads the floor as it would then load: a locked door
  -- that the flag opens is a warp there)
  local view = (live and live.id == mapId) and live
    or (self.journeySupposing and World.loadedView(self.game, def)) or World.plannedView(self.game, def)
  if not (def and view) then return {} end
  local result = {}
  for index, warp in ipairs(def.warps or {}) do
    local active, activeIndex = view:warpAt(tonumber(warp.x), tonumber(warp.y))
    if active and activeIndex == index then
      local destMap, destX, destY = view:warpDestination(warp)
      if destMap and self:regionalMapDef(destMap) then
        result[#result + 1] = {
          kind = "warp", index = index, x = warp.x, y = warp.y,
          destMap = destMap, destX = destX, destY = destY,
        }
      end
    end
  end
  local C = loaded("src.core.game3.collision")
  local Connections = loaded("src.core.game3.connections")
  local rows = Connections and call(Connections.each, def) or {}
  for _, conn in ipairs(rows or {}) do
    local direction = conn.dir
    local step = CONNECTION_STEP[direction]
    local destDef = type(conn.map) == "string" and self:regionalMapDef(conn.map) or nil
    local destView = World.plannedView(self.game, destDef)
    if step and destView and C and C.connectionLanding then
      local vertical = step == "up" or step == "down"
      local count = vertical and view.widthCells or view.heightCells
      for coordinate = 0, count - 1 do
        local x = (direction == "west") and 0 or (direction == "east") and (view.widthCells - 1) or coordinate
        local y = (direction == "north") and 0 or (direction == "south") and (view.heightCells - 1) or coordinate
        local ok, destX, destY = pcall(C.connectionLanding, destDef, conn, step, x, y)
        local crossable = false
        if ok and destX and not view:dirBlocked(x, y, nil, nil, step)
           and not destView:dirBlocked(nil, nil, destX, destY, step) then
          local thereLand = destView:isWalkableCell(destX, destY)
          crossable = (view:isWalkableCell(x, y) and thereLand)
            or (view:isWater(x, y) and (destView:isWater(destX, destY)
              or (thereLand and destView:elevation(destX, destY) == 3)))
        end
        if crossable then
          result[#result + 1] = {
            kind = "connection", direction = direction, x = x, y = y,
            destMap = conn.map, destX = destX, destY = destY,
          }
        end
      end
    end
  end
  return result
end

function Navigation:regionalDestinationName(mapId)
  local playerName, rivalName = self:names()
  return Snapshot.locationName({ id = mapId }, mapId, nil, playerName, rivalName)
end

-- ------------------------------------------------------------ journeys

-- The shared journey planner (RegionalPathfinder) runs one route search
-- per transition per map it reaches, each with its own time slice: on
-- FireRed's many-warp floors that ran out of time before the first floor
-- was done (Silph Co. 1F to the Card Key, Rocket Hideout B2F to B4F:
-- "regional search timed out" after half a second, though a long search
-- found the Hideout route in 0.7 seconds).  Here one search runs over the
-- cells of every map in the journey at once, with the same movement graph
-- as a walked route (routeOptionsFor) and warps and connections as edges
-- between maps, so each cell is visited once.

local function heapPush(heap, node)
  heap[#heap + 1] = node
  local i = #heap
  while i > 1 do
    local parent = math.floor(i / 2)
    local p = heap[parent]
    if p.cost < node.cost or (p.cost == node.cost and p.seq < node.seq) then break end
    heap[i], heap[parent] = p, node
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
      local l, r, best = i * 2, i * 2 + 1, i
      local function earlier(a, b) return a.cost < b.cost or (a.cost == b.cost and a.seq < b.seq) end
      if heap[l] and earlier(heap[l], heap[best]) then best = l end
      if heap[r] and earlier(heap[r], heap[best]) then best = r end
      if best == i then break end
      heap[i], heap[best] = heap[best], heap[i]
      i = best
    end
  end
  return top
end

-- An elevator car's floor panel as journey edges: from each cell the panel
-- is used from, to each floor its script serves.  The floor menu stays the
-- player's (as in Gen 1 and Gen 2): such a leg ends at the panel with the
-- instruction.  A panel that checks a flag first (the Rocket Hideout's Lift
-- Key) opens only with the flag set, or at policy 3 to name what it needs.
function Navigation:elevatorTransitions(world, policy)
  local map = world.map
  local result = {}
  local def = map.def
  local seen = {}
  for _, event in ipairs(type(def) == "table" and def.bgEvents or {}) do
    local key = event.type == "sign" and event.scriptKey or nil
    if key and not seen[key] and Scripts.signRole(key) == "Floor Panel" then
      seen[key] = true
      local panel = Scripts.elevatorPanel(key)
      local open = panel ~= nil and (panel.gateFlag == nil or policy >= 3 or flagSet(panel.gateFlag))
      if open then
        local needs
        if panel.gateFlag and not flagSet(panel.gateFlag) then
          local item = Scripts.itemSettingFlag(panel.gateFlag)
          needs = (item and Scripts.itemLabel(item)) or "Elevator Key"
        end
        -- every sign event of the panel, from the cell below or beside it
        for _, other in ipairs(def.bgEvents) do
          if other.type == "sign" and other.scriptKey == key then
            for _, direction in ipairs(ORDER) do
              local d = DELTA[direction]
              local sx, sy = other.x - d[1], other.y - d[2]
              if map:isWalkableCell(sx, sy) and not map:warpAt(sx, sy) then
                for _, floor in ipairs(panel.floors) do
                  result[#result + 1] = { kind = "elevator", x = sx, y = sy, facing = direction,
                    destMap = floor.mapId, destX = floor.x, destY = floor.y, needs = needs }
                end
              end
            end
          end
        end
      end
    end
  end
  return result
end

-- Where the floor gives way (Scripts.crackedIceDrop): thin ice cracks when
-- stepped on and drops the player, at the same place one floor down, when
-- stepped on again; cracked ice drops them at once.  Only cells with floor
-- below count.
function Navigation:fallTransitions(world)
  local map = world.map
  local result = {}
  local def = map.def
  local destId
  if type(def) == "table" then destId = Scripts.crackedIceDrop(def) end
  local destDef = destId and self:regionalMapDef(destId)
  local below = destDef and World.loadedView(self.game, destDef)
  if not below then return result end
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local beh = map:behavior(x, y)
      if Terrain.isCrackedFloor(beh) then
        -- a cracked floor gives way at the first step, on anything but a Mach Bike at
        -- full speed: an ordinary drop
        if below:isWalkableCell(x, y) then
          result[#result + 1] = { kind = "fall", x = x, y = y, cracked = true,
            destMap = destId, destX = x, destY = y }
        end
      elseif (beh == Terrain.MB.THIN_ICE or beh == Terrain.MB.CRACKED_ICE)
         and below:isWalkableCell(x, y) then
        result[#result + 1] = { kind = "fall", x = x, y = y, cracked = beh == Terrain.MB.CRACKED_ICE,
          destMap = destId, destX = x, destY = y }
      end
    end
  end
  return result
end

-- Dive: a map's `dive` or `emerge` header (Dive.setDiveWarp) lands at the same x and y
-- on the map below or above.  Deep water dives (Dive.isDiveable); anywhere below the
-- surface but under solid rock emerges (Dive.isUnableToEmerge).  Taken with an A press
-- and the game's own question, so the leg ends at the cell (as an elevator's does).
function Navigation:diveTransitions(world, policy)
  local result = {}
  local map = world.map
  local def = map and map.def
  local Dive = loaded("src.core.game3.dive")
  if not (Dive and type(def) == "table") then return result end
  local link = map.underwater and def.emerge or def.dive
  local scripted = not link and Scripts.diveWarpOf(def) or nil
  if not (link or scripted) then return result end
  if policy < 3 and not self:hmAllowed(world, "DIVE", policy) then return result end
  local needs = (not self:hmAllowed(world, "DIVE", 2)) and "Dive" or nil
  local destId = scripted and scripted.mapId or (type(link) == "table" and link.map or link)
  local destDef = type(destId) == "string" and self:regionalMapDef(destId) or nil
  local dest = destDef and World.plannedView(self.game, destDef)
  if not dest then return result end
  for y = 0, map.heightCells - 1 do
    for x = 0, map.widthCells - 1 do
      local beh = map:behavior(x, y)
      local here
      if map.underwater then here = not Dive.isUnableToEmerge(beh) and (map:isWater(x, y) or map:walkableColl(x, y))
      else here = Dive.isDiveable(beh) end
      if here then
        -- a script's landing is one cell (a warp number lands where that warp stands)
        local toX, toY = x, y
        if scripted then
          toX, toY = scripted.x, scripted.y
          local warpRow = scripted.warp ~= nil and scripted.warp ~= 255 and (destDef.warps or {})[scripted.warp + 1]
          if warpRow then toX, toY = warpRow.x, warpRow.y end
        end
        if dest:inBounds(toX, toY) and (dest:isWater(toX, toY) or dest:walkableColl(toX, toY)) then
          result[#result + 1] = { kind = "dive", x = x, y = y, emerge = map.underwater == true,
            destMap = destId, destX = toX, destY = toY, needs = needs }
        end
      end
    end
  end
  return result
end

-- Cells of a view numbered by the connected patch they belong to (four neighbours).
local function patches(view, inPatch)
  local width, height = view.widthCells, view.heightCells
  local patch, count, sizes = {}, 0, {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if patch[y * width + x] == nil and inPatch(x, y) then
        count = count + 1
        patch[y * width + x] = count
        local queue, head = { { x, y } }, 1
        while queue[head] do
          local cx, cy = queue[head][1], queue[head][2]
          head = head + 1
          for _, d in pairs(DELTA) do
            local nx, ny = cx + d[1], cy + d[2]
            if nx >= 0 and ny >= 0 and nx < width and ny < height
               and patch[ny * width + nx] == nil and inPatch(nx, ny) then
              patch[ny * width + nx] = count
              queue[#queue + 1] = { nx, ny }
            end
          end
        end
        sizes[count] = #queue
      end
    end
  end
  -- the largest patch: a route's open water
  local largest
  for number, size in ipairs(sizes) do
    if not largest or size > sizes[largest] then largest = number end
  end
  return patch, largest
end

-- Which item balls the game would show on a map and the one above or below it, as one
-- string: what a dive spot's label depends on besides the maps themselves.
local function itemBallsShown(def, otherDef)
  local shown = {}
  for _, mapDef in ipairs({ def, otherDef }) do
    for _, object in ipairs(type(mapDef) == "table" and mapDef.objects or {}) do
      if tonumber(object.graphicsId) == GFX.ITEM_BALL then
        shown[#shown + 1] = regionalObjectVisible(object) and "1" or "0"
      end
    end
    shown[#shown + 1] = "/"
  end
  return table.concat(shown)
end

local function joinNames(names, limit)
  local kept = {}
  for i = 1, math.min(#names, limit or 3) do kept[i] = names[i] end
  if #kept <= 1 then return kept[1] end
  return table.concat(kept, ", ", 1, #kept - 1) .. " and " .. kept[#kept]
end

-- Dive spots (Hoenn).  Route 124 has sixteen patches of deep water over ten separate
-- seabeds, and most lead only to a pool ringed by rocks; nothing told them apart (the
-- owner, 2026-11-19: the old scripts' dive points were "multiple and confusing").  Each
-- patch of deep water over one seabed is one list entry that says where it leads: the
-- seabed's own doors (Underwater Sootopolis City), then the other waters that seabed
-- comes up in.  Below the surface each stretch that can surface is a "Way Up" that names
-- the water above it.  Read from the two maps' cells; cached per map, until an item ball
-- on either map is taken or appears (a label names them: "a pool with Red Shard" was
-- still said after the shard was picked up, until the game was started again).
--   returns { { id, label, cells, rim, inGroup, emerge }, ... }
function Navigation:diveSpots(world)
  local map = world and world.map
  local def = map and map.def
  if type(def) ~= "table" then return {} end
  self.gen3DiveSpots = self.gen3DiveSpots or setmetatable({}, { __mode = "k" })
  local cached = self.gen3DiveSpots[def]
  if cached and cached.balls == itemBallsShown(def, cached.otherDef) then return cached.spots end
  local spots = {}
  local entry = { spots = spots, balls = itemBallsShown(def, nil) }
  self.gen3DiveSpots[def] = entry
  local ok, list = pcall(self.diveTransitions, self, world, 3)
  if not ok or type(list) ~= "table" or #list == 0 then return spots end
  local mapId = self:currentMapIdOf(world) or tostring(def.id)
  local otherId = list[1].destMap
  local otherDef = self:regionalMapDef(otherId)
  local other = otherDef and World.plannedView(self.game, otherDef)
  if not other then return spots end
  entry.otherDef, entry.balls = otherDef, itemBallsShown(def, otherDef)
  local width, otherWidth = map.widthCells, other.widthCells
  local function open(view) return function(x, y) return view:isWater(x, y) or view:walkableColl(x, y) end end
  local hereWater, hereOpen = patches(map, open(map))
  local otherWater, otherOpen = patches(other, open(other))
  local isDive = {}
  for _, t in ipairs(list) do isDive[t.y * width + t.x] = t end
  local divePatch = patches(map, function(x, y) return isDive[y * width + x] ~= nil end)

  -- a door down there that opens on another seabed is named by where that one comes up
  -- (Route 126's seabed door is "Sootopolis City", not "Underwater Sootopolis City"),
  -- unless it comes up on this same map (the Sealed Chamber, under Route 134)
  local function beyond(dest)
    local destDef = self:regionalMapDef(dest)
    local destView = destDef and World.plannedView(self.game, destDef)
    if destView and destView.underwater then
      -- its header's link, or the one its script sets (Underwater Sootopolis City)
      local up = type(destDef.emerge) == "table" and destDef.emerge.map or destDef.emerge
      if type(up) ~= "string" then
        local scripted = Scripts.diveWarpOf(destDef)
        up = scripted and scripted.mapId
      end
      if type(up) == "string" and up ~= mapId and up ~= otherId then return up end
    end
    return dest
  end

  -- what one stretch of water holds, for a label: whether it is the map's open water
  -- (its largest stretch), its doors, the edge of the map it reaches, or a pool, with
  -- the item balls in it
  local function describe(view, viewDef, water, number, viewMapId, largest)
    local w, h = view.widthCells, view.heightCells
    local doors, seen, items, edge = {}, {}, {}, nil
    for index, warp in ipairs(viewDef.warps or {}) do
      local _, active = view:warpAt(warp.x, warp.y)
      if active == index and water[warp.y * w + warp.x] == number then
        local dest = view:warpDestination(warp)
        local name = dest and self:regionalDestinationName(beyond(dest))
        if name and not seen[name] then seen[name] = true doors[#doors + 1] = name end
      end
    end
    for x = 0, w - 1 do
      if water[x] == number then edge = edge or "north" end
      if water[(h - 1) * w + x] == number then edge = edge or "south" end
    end
    for y = 0, h - 1 do
      if water[y * w] == number then edge = edge or "west" end
      if water[y * w + w - 1] == number then edge = edge or "east" end
    end
    for _, object in ipairs(viewDef.objects or {}) do
      if tonumber(object.graphicsId) == GFX.ITEM_BALL and regionalObjectVisible(object)
         and type(object.x) == "number" and water[object.y * w + object.x] == number then
        local item = Scripts.itemBallItem(object.scriptKey)
        local name = item and Scripts.itemLabel(item)
        if name then items[#items + 1] = name end
      end
    end
    local place = self:regionalDestinationName(viewMapId)
    local rest = (#doors > 0 and joinNames(doors, 2))
      or (edge and ("water at the " .. edge .. " edge of " .. place))
      or (#items > 0 and ("a pool with " .. joinNames(items, 2))) or "an enclosed pool"
    return { doors = #doors > 0 and joinNames(doors, 2) or nil, open = number == largest, place = place, rest = rest }
  end

  local groups, order = {}, {}
  for _, t in ipairs(list) do
    local below = otherWater[t.destY * otherWidth + t.destX]
    -- one entry for each stretch of water over each seabed: two patches of deep water in
    -- the same stretch over the same seabed are one place to dive, the nearer one (Route
    -- 126 listed "Dive Spot to water at the north edge" twice, 17 cells apart)
    local here = hereWater[t.y * width + t.x]
    local key = tostring(here or ("p" .. tostring(divePatch[t.y * width + t.x]))) .. ":" .. tostring(below)
    local group = groups[key]
    if not group then
      group = { key = key, cells = {}, below = below, here = here }
      groups[key] = group
      order[#order + 1] = group
    end
    group.cells[#group.cells + 1] = { x = t.x, y = t.y }
  end
  for _, group in ipairs(order) do
    local label
    if map.underwater then
      local above = describe(other, otherDef, otherWater, group.below, otherId, otherOpen)
      label = "Way Up to " .. ((above.open and above.place) or above.rest)
    else
      -- the seabed's own doors, then the other waters it comes up in
      local leads, seen = {}, {}
      local seabed = describe(other, otherDef, otherWater, group.below, otherId, otherOpen)
      if seabed.doors then leads[#leads + 1] = seabed.doors seen[seabed.doors] = true end
      for _, sibling in ipairs(order) do
        if sibling.below == group.below and sibling.here ~= group.here then
          local water = describe(map, def, hereWater, sibling.here, mapId, hereOpen)
          local name = (water.open and "the open water") or water.rest
          if not seen[name] then seen[name] = true leads[#leads + 1] = name end
        end
      end
      -- a seabed that is a place of its own (Underwater Marine Cave), not this map's
      local below = self:regionalDestinationName(otherId)
      local ownPlace = #leads == 0 and below ~= "Underwater " .. self:regionalDestinationName(mapId)
      if ownPlace then leads[1] = below end
      label = #leads > 0 and ("Dive Spot to " .. joinNames(leads, 3)) or "Dive Spot, seabed only"
      -- somewhere a player sets out for from further off (Navigation:farDiveSpots)
      group.named = seabed.doors ~= nil or ownPlace
    end
    -- the cells a route can end on: the patch's rim (a route from outside meets it first)
    local inGroup = {}
    for _, cell in ipairs(group.cells) do inGroup[cell.y * width + cell.x] = true end
    local rim = {}
    for _, cell in ipairs(group.cells) do
      for _, d in pairs(DELTA) do
        local nx, ny = cell.x + d[1], cell.y + d[2]
        if nx < 0 or ny < 0 or nx >= width or ny >= map.heightCells or not inGroup[ny * width + nx] then
          rim[#rim + 1] = cell
          break
        end
      end
    end
    spots[#spots + 1] = { id = "dive_spot:" .. mapId .. ":" .. group.key, label = label,
      cells = group.cells, rim = rim, inGroup = inGroup, emerge = map.underwater == true,
      named = group.named == true }
  end
  -- several that lead to the same kind of place are numbered, as a map's doors are
  -- ("entrance 2 of 6"): Route 124 has six "seabed only", and a number is what a player
  -- can keep ("the third one had the shard")
  local count, nth = {}, {}
  for _, spot in ipairs(spots) do count[spot.label] = (count[spot.label] or 0) + 1 end
  for _, spot in ipairs(spots) do
    local total = count[spot.label]
    if total > 1 then
      nth[spot.label] = (nth[spot.label] or 0) + 1
      spot.label = spot.label .. ", " .. nth[spot.label] .. " of " .. total
    end
  end
  return spots
end

function Navigation:diveSpotById(world, id)
  for _, spot in ipairs(self:diveSpots(world)) do
    if spot.id == id then return spot end
  end
  return nil
end

-- One map as the journey search sees it: its world (the live one for the
-- map the player is on), its movement graph with every transition cell
-- (and, on the target map, every target cell) as a goal, its transitions
-- by cell.  nil when the map cannot be planned.
function Navigation:journeyMap(mapId, policy, target, live, special)
  local world
  if live and not self.journeySupposing and self:currentMapIdOf(live) == mapId then
    world = live
  else
    world = self:regionalStaticWorld(mapId, { x = 0, y = 0 })
  end
  if not world then return nil end
  -- planning past boulders: "others" on the floors ahead, where the player will meet
  -- them with the puzzle at hand; "all" also here (journeyOpeningGoals)
  if self.journeyBoulderFree == "all" or (self.journeyBoulderFree and world ~= live) then
    world = self:withoutBoulders(world)
  end
  local byCell, goals = {}, {}
  for _, transition in ipairs(self:regionalTransitions(mapId)) do
    local key = cellKey(transition.x, transition.y)
    if not byCell[key] then
      byCell[key] = {}
      goals[#goals + 1] = { x = transition.x, y = transition.y }
    end
    table.insert(byCell[key], transition)
  end
  local function add(transition)
    local key = cellKey(transition.x, transition.y)
    if not byCell[key] then
      byCell[key] = {}
      goals[#goals + 1] = { x = transition.x, y = transition.y }
    end
    table.insert(byCell[key], transition)
  end
  if special then
    for _, transition in ipairs(self:elevatorTransitions(world, policy)) do add(transition) end
    for _, transition in ipairs(self:fallTransitions(world)) do add(transition) end
    for _, transition in ipairs(self:diveTransitions(world, policy)) do add(transition) end
  end
  local targetSet = {}
  if mapId == target.mapId then
    for _, goal in ipairs(target.goals) do
      targetSet[cellKey(goal.x, goal.y)] = true
      goals[#goals + 1] = { x = goal.x, y = goal.y }
    end
  end
  if #goals == 0 then goals[1] = { x = 0, y = 0 } end
  local options = self:routeOptionsFor(world, goals, policy)
  if not options then return nil end
  return { world = world, map = world.map, neighbors = options.neighbors, byCell = byCell,
    targetSet = targetSet }
end

-- The cheapest journey from `start` ({ mapId, x, y }) to any of the
-- target's cells ({ mapId, goals }), at one route policy, over the maps
-- `allowed` admits (nil: any), with elevators and falls through thin ice
-- when `special` is set.  Returns { firstTransition, final, cost, legs }
-- (legs: the steps walked on each map, for requirements), or nil and why
-- ("no regional path", "regional search timed out").
function Navigation:journeySearch(start, target, policy, allowed, maxSeconds, special)
  local live = self:worldForCommand()
  local deadline = os.clock() + (maxSeconds or 1.5)
  local maps = {}
  local function mapOf(mapId)
    local entry = maps[mapId]
    if entry == nil then
      entry = self:journeyMap(mapId, policy, target, live, special) or false
      maps[mapId] = entry
    end
    return entry or nil
  end
  -- A node is a cell on a map, reached either by walking (`arrived` false:
  -- a door or ladder entered fires) or by a transition (`arrived` true:
  -- the player stands on the warp they came out of and may walk off it).
  local function nodeKey(mapId, x, y, arrived)
    return mapId .. ":" .. x .. "," .. y .. (arrived and "a" or "w")
  end
  local seq = 1
  local first = { mapId = start.mapId, x = start.x, y = start.y, arrived = true,
    cost = 0, hops = 0, seq = seq }
  local heap, best = { first }, { [nodeKey(start.mapId, start.x, start.y, true)] = 0 }
  local function reach(node)
    local key = nodeKey(node.mapId, node.x, node.y, node.arrived)
    if best[key] ~= nil and best[key] <= node.cost then return end
    best[key] = node.cost
    seq = seq + 1
    node.seq = seq
    heapPush(heap, node)
  end
  local function finish(node)
    local legs, cursor = {}, node
    local needs = {}
    while cursor.parent do
      if cursor.needs then needs[cursor.needs] = true end
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
      cost = node.cost, legs = legs, maps = maps, needs = needs }
  end
  local expanded = 0
  while #heap > 0 do
    local node = heapPop(heap)
    local key = nodeKey(node.mapId, node.x, node.y, node.arrived)
    if best[key] == node.cost then
      expanded = expanded + 1
      if expanded % 64 == 0 and os.clock() > deadline then return nil, "regional search timed out" end
      local entry = mapOf(node.mapId)
      if entry then
        local cell = cellKey(node.x, node.y)
        if node.mapId == target.mapId and (target.anywhere or entry.targetSet[cell]) then return finish(node) end
        local map = entry.map
        local fires = not node.arrived and map:warpAt(node.x, node.y) ~= nil
          and not map:standingWarp(node.x, node.y)
        -- cracked ice gives way under the player: no walking on from it
        if not node.arrived and (map:behavior(node.x, node.y) == Terrain.MB.CRACKED_ICE
            or (Terrain.isCrackedFloor(map:behavior(node.x, node.y)) and policy < 3 and not self:onMachBike())) then
          fires = true
        end
        -- transitions: a warp fires on arrival by walking (or, for exit mats,
        -- arrows and stairs, while their direction is pressed); a
        -- connection is crossed by stepping off the edge
        for _, transition in ipairs(entry.byCell[cell] or {}) do
          local usable = transition.kind == "connection" or transition.kind == "elevator"
            or transition.kind == "fall" or transition.kind == "dive"
            or fires or map:standingWarp(node.x, node.y) ~= nil
          if usable and (not allowed or allowed[transition.destMap]) then
            -- a menu is dearer than a walk (stairs win when they are close,
            -- and after a floor is chosen the car's exit beats the panel);
            -- thin ice takes a few steps more than a warp
            local extra = (transition.kind == "elevator" and 20) or (transition.kind == "fall" and 4)
              or (transition.kind == "dive" and 12) or 1
            reach({ mapId = transition.destMap, x = transition.destX, y = transition.destY,
              arrived = true, cost = node.cost + extra, hops = node.hops + 1, parent = node,
              firstTransition = node.firstTransition or transition, needs = transition.needs })
          end
        end
        -- walking on, unless the cell was a warp that fired
        if not fires then
          for _, edge in ipairs(entry.neighbors(node.x, node.y)) do
            reach({ mapId = node.mapId, x = edge.x, y = edge.y, arrived = false,
              cost = node.cost + (edge.cost or 1), hops = node.hops, parent = node,
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

-- The maps a journey may cross: those of the target's area (decision 25:
-- an Area target is on a map sharing the first words of the player's map
-- id), plus the map the player is on; nil (any map) for a target outside
-- the player's area.
function Navigation:journeyMaps(fromMapId, targetMapId)
  local areaKeyOf = Navigation.areaKey -- defined with the Area category below
  local key = areaKeyOf(targetMapId)
  if not key or areaKeyOf(fromMapId) ~= key then return nil end
  local allowed = { [fromMapId] = true }
  for mapId in pairs(self.game and self.game.data and self.game.data.maps or {}) do
    if type(mapId) == "string" then
      local mapKey = areaKeyOf(mapId)
      -- the town around an island's buildings is on the way between them
      if mapKey == key or (mapKey and key:sub(1, #mapKey + 1) == mapKey .. "_") then allowed[mapId] = true end
    end
  end
  return allowed
end

-- The maps a way round may cross (regionalNextLeg): the area's own, the maps this map's
-- doors lead to, and the other floors of those places.  Connections are left out: a walk
-- into the next town and on is no way round, it is another trip.
function Navigation:wayRoundMaps(mapId, allowed)
  local areaKeyOf = Navigation.areaKey
  local round, keys, added = {}, {}, false
  for id in pairs(allowed or {}) do round[id] = true end
  round[mapId] = true
  for _, transition in ipairs(self:regionalTransitions(mapId) or {}) do
    local dest = transition.destMap
    if transition.kind ~= "connection" and type(dest) == "string" and not round[dest] then
      round[dest], added = true, true
      local key = areaKeyOf(dest)
      if key then keys[key] = true end
    end
  end
  if not added then return nil end
  for id in pairs(self.game and self.game.data and self.game.data.maps or {}) do
    if type(id) == "string" and not round[id] then
      local key = areaKeyOf(id)
      if key and keys[key] then round[id] = true end
    end
  end
  return round
end

-- A way round through the map next door: out over an edge of this map and back in over
-- the same edge further along.  FireRed's Route 5 is two strips that join only at
-- Cerulean City's south edge: the Day Care from the Saffron gate is up the east strip,
-- eleven steps along Cerulean's bottom row, and down the west one (it said "Cannot reach
-- yet").  Only this map's own neighbours are searched, with what the party can do now:
-- a way that needs the neighbour's doors, or a map beyond it, is another trip.
function Navigation:wayRoundNextDoor(start, target, allowed)
  if not allowed or target.mapId ~= start.mapId then return nil end
  local near, added = {}, false
  for id in pairs(allowed) do near[id] = true end
  for _, transition in ipairs(self:regionalTransitions(start.mapId) or {}) do
    if transition.kind == "connection" and type(transition.destMap) == "string" and not near[transition.destMap] then
      near[transition.destMap], added = true, true
    end
  end
  if not added then return nil end
  local ok, found = pcall(self.journeySearch, self, start, target, 2, near, 1, false)
  if ok and found and not found.final then
    self.journeyPastBoulders = false
    return found
  end
  return nil
end

-- A Secret Switch anywhere in the target's area that would open a way (Pokemon Mansion:
-- one flag, one switch per floor, and the way to the basement only from the third floor's
-- side).  The flags a switch's script changes are supposed flipped, and the journey from
-- the switch to the target planned with the floors as they would then load.  Returns
-- { mapId, label, x, y, goals, cost } for the cheapest, or nil.
function Navigation:remoteSwitch(item, goals, world)
  local here = self:currentMapIdOf(world)
  local targetMap = item.mapId or here
  local allowed = self:journeyMaps(here, targetMap)
  if not allowed then return nil end
  local start = { mapId = here, x = world.player.cellX, y = world.player.cellY }
  local target = { mapId = targetMap, goals = goals, anywhere = goals.anywhere }
  local best
  for mapId in pairs(allowed) do
    local def = self:regionalMapDef(mapId)
    for _, event in ipairs(def and def.bgEvents or {}) do
      if event.type == "sign" and type(event.x) == "number"
         and select(2, Scripts.signRole(event.scriptKey)) == "secret_switch" then
        local view = World.loadedView(self.game, def)
        -- the sides its script answers from (bg event kind: 1 up, 2 down, 3 right, 4 left)
        local cells = {}
        for kind, d in pairs({ { 0, -1 }, { 0, 1 }, { 1, 0 }, { -1, 0 } }) do
          local x, y = event.x - d[1], event.y - d[2]
          local side = tonumber(event.kind) or 0
          if (side == 0 or side == kind) and view and view:isWalkableCell(x, y) and not view:warpAt(x, y) then
            cells[#cells + 1] = { x = x, y = y }
          end
        end
        local toSwitch = #cells > 0 and self:journeySearch(start, { mapId = mapId, goals = cells }, 2, allowed, nil, true)
        if toSwitch then
          local supposed = {}
          for flag in pairs(Scripts.reach(event.scriptKey, 8).flagsSet) do supposed[flag] = not flagSet(flag) end
          World.supposedFlags, self.journeySupposing = supposed, true
          local ok, onward = pcall(self.journeySearch, self, { mapId = mapId, x = cells[1].x, y = cells[1].y },
            target, 2, allowed, nil, true)
          World.supposedFlags, self.journeySupposing = nil, nil
          if ok and onward then
            local cost = toSwitch.cost + onward.cost
            if not best or cost < best.cost then
              best = { mapId = mapId, label = "Secret Switch " .. event.x .. "," .. event.y,
                x = event.x, y = event.y, goals = cells, cost = cost }
            end
          end
        end
      end
    end
  end
  return best
end

-- The warp on this floor a journey needs, if only boulders here keep it from the player.
function Navigation:journeyOpeningGoals(item, world)
  local goals = select(2, self:selectedRouteGoals())
  local mapId = self:currentMapIdOf(world)
  local targetMap = item.mapId or mapId
  if type(goals) ~= "table" or #goals == 0 then return nil end
  self.journeyBoulderFree = "all"
  local ok, result = pcall(self.journeySearch, self,
    { mapId = mapId, x = world.player.cellX, y = world.player.cellY },
    { mapId = targetMap, goals = goals, anywhere = goals.anywhere }, 2, self:journeyMaps(mapId, targetMap), nil, true)
  self.journeyBoulderFree = nil
  if not (ok and result) then return nil end
  -- no warp in between: the target itself, on this floor
  if result.final then return mapId == targetMap and not goals.anywhere and goals or nil end
  local transition = result.firstTransition
  if not transition then return nil end
  return { { x = transition.x, y = transition.y } }
end

-- Why guided navigation cannot reach a place on this floor.  The shared check knows the
-- field moves only; the journey planner also knows the bikes, Dive and the Card Key, and
-- auto-walk says its reason ("Needs Mach Bike" past Granite Cave B1F's cracked floor),
-- so guided navigation asks it too rather than say "Cannot reach yet"
-- (the shared Navigation:advancePendingRoute calls this when every policy failed).
function Navigation:unreachableReason(goals)
  local world = self:worldForCommand()
  if not world or type(goals) ~= "table" or #goals == 0 then return nil end
  -- someone standing in the only way ("Blocked by Team Aqua Grunt"), as auto-walk says it
  local okPeople, blocked = pcall(self.routeNeeds, self, goals)
  if okPeople and blocked then return blocked end
  local ok, leg, reason = pcall(self.regionalNextLeg, self,
    { targetMapId = self:currentMapIdOf(world), targetGoals = goals })
  -- the planner's own codes ("no regional path", a time limit) say nothing to a player;
  -- anything else is a sentence: "Needs ...", "Blocked by ...", a story door
  if ok and not leg and type(reason) == "string" and reason:match("^%u") then return reason end
  -- a way that counts on boulders being pushed, or a floor that switches redraw: both
  -- are auto-walk's puzzles (BoulderWalk, SwitchWalk), as the spinning gates are
  if ok and leg and self.journeyPastBoulders then return "Boulders in the way: use auto walk" end
  local okSwitches, switches = pcall(self.floorSwitchCells, self, world)
  if okSwitches and type(switches) == "table" and #switches > 0 then
    return "Floor switches change this floor: use auto walk"
  end
  -- Pokémon Mansion's Secret Switches, Ruby and Sapphire's Mossdeep Gym: SwitchWalk tries them
  local okSigns, signs = pcall(self.switchSigns, self, world)
  if okSigns and type(signs) == "table" and #signs > 0 then
    return "Switches change this floor: use auto walk"
  end
  return self:closedReason(goals)
end

-- Seafoam Islands (FireRed, LeafGreen): Route 20's two halves, and the cave's own east
-- and west sides, join only across B3F and B4F, whose currents carry a surfer off until
-- the boulders on the floors above have been pushed down their holes into the water
-- (pokefirered data/maps/SeafoamIslands_B3F/scripts.inc).  No route is planned through
-- a puzzle on other floors, so the refusal says what to do.  Said only while a boulder is
-- still to come down onto B3F (its copy there is hidden until it falls); afterwards the
-- plain "reached from" sentence stands.  Probed on a fresh profile with the hide flags a
-- new game sets (66 to 71, 76, 77): no way through is planned, with or without the
-- boulders set aside.  Whether the planner crosses once they are all down is not known.
local THROUGH_PUZZLE = {
  { map = "^ROUTE_20$", via = "Seafoam Islands", currentsOn = "SEAFOAM_ISLANDS_B3F",
    reason = "The way is through Seafoam Islands, past its currents: push the boulders down the holes on each floor first" },
  { map = "^SEAFOAM_ISLANDS_", via = "Seafoam Islands", currentsOn = "SEAFOAM_ISLANDS_B3F",
    reason = "The way is past the currents below: push the boulders down the holes on each floor first" },
}

-- The last reasons, when no route, no missing move and no person explains a refusal:
-- what the story or the clock keeps shut, then a part of the map that is reached only
-- from another way in.  Auto-walk asks this too before it says "No route".
function Navigation:closedReason(goals)
  local world = self:worldForCommand()
  if not world or type(goals) ~= "table" or #goals == 0 then return nil end
  local reason = self:closedForNow(world, goals)
  if reason then return reason end
  local ok, otherSide, names = pcall(self.otherWayIn, self, world, goals)
  if not (ok and otherSide) then return nil end
  -- a way in that is the far side of a cave whose puzzle is still to do
  local bare = GameData.bareMapId(self:currentMapIdOf(world)) or ""
  for _, entry in ipairs(THROUGH_PUZZLE) do
    local applies = bare:find(entry.map) ~= nil and self:boulderStillToCome(GameData.mapPrefix() .. entry.currentsOn)
    for _, name in ipairs(applies and names or {}) do
      if name:find(entry.via, 1, true) == 1 then return entry.reason end
    end
  end
  return otherSide
end

-- Whether a boulder the game keeps hidden on this map is still to arrive: one that drops
-- in from the floor above is an object here from the start, hidden until it has fallen.
function Navigation:boulderStillToCome(mapId)
  local def = self:regionalMapDef(mapId)
  for _, object in ipairs(def and def.objects or {}) do
    if tonumber(object.graphicsId) == GFX.BOULDER and not regionalObjectVisible(object) then return true end
  end
  return false
end

-- A part of this map that no way from here reaches, though a way in from elsewhere
-- does: past one-way ledges (Route 123's east end from its west, Route 112's pocket
-- under Jagged Pass), behind a row of rocks (Route 125's north-west water), back up a
-- current (Routes 132 to 134).  The movement graph is turned round and searched back
-- from the target, with what the party can do now and everyone where they stand: every
-- door or edge of the map from which the target can be reached is a place to come in
-- from, and is named ("Not from here: this part is reached from Route 122").  The
-- target's own way in is named only when there is no other.  Nil when nothing reaches it.
local OTHER_WAY_MAX_CELLS = 16000

function Navigation:otherWayIn(world, goals)
  local map = world and world.map
  local mapId = self:currentMapIdOf(world)
  if not (map and type(mapId) == "string") then return nil end
  local width, height = map.widthCells, map.heightCells
  if width * height > OTHER_WAY_MAX_CELLS then return nil end
  local options = self:routeOptionsFor(world, goals, 2)
  if not options then return nil end
  local reverse = {}
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if map:isWalkableCell(x, y) or map:isWater(x, y) or map:warpAt(x, y) then
        for _, edge in ipairs(options.neighbors(x, y)) do
          local key = edge.y * width + edge.x
          local list = reverse[key]
          if not list then
            list = {}
            reverse[key] = list
          end
          list[#list + 1] = y * width + x
        end
      end
    end
  end
  local reaches, queue, head = {}, {}, 1
  for _, goal in ipairs(goals) do
    local key = goal.y * width + goal.x
    if map:inBounds(goal.x, goal.y) and not reaches[key] then
      reaches[key] = "goal"
      queue[#queue + 1] = key
    end
  end
  while queue[head] do
    for _, from in ipairs(reverse[queue[head]] or {}) do
      if not reaches[from] then
        reaches[from] = true
        queue[#queue + 1] = from
      end
    end
    head = head + 1
  end
  -- a way from where the player stands: not this reason's case
  if reaches[world.player.cellY * width + world.player.cellX] then return nil end
  -- (a way in is "another" when any of its cells is not one of the target's own)
  local others, own, seen = {}, {}, {}
  local transitions = self:regionalTransitions(mapId)
  for _, wanted in ipairs({ true, "goal" }) do
    for _, transition in ipairs(transitions) do
      local name = reaches[transition.y * width + transition.x] == wanted
        and self:regionalDestinationName(transition.destMap)
      if name and not seen[name] then
        seen[name] = true
        local list = wanted == "goal" and own or others
        list[#list + 1] = name
      end
    end
  end
  local names = #others > 0 and others or own
  if #names == 0 then return nil end
  local said = names[1]
  if #names == 2 then
    said = names[1] .. " or " .. names[2]
  elseif #names > 2 then
    said = names[1] .. ", " .. names[2] .. " or " .. names[3]
  end
  return "Not from here: this part is reached from " .. said, names
end

-- Places the story or the clock keeps shut, where no route and no missing move explains
-- the refusal.  Each is the game's own rule, said as a player would be told it:
--   Lilycove's Wailmer (pokeemerald data/maps/LilycoveCity/scripts.inc, drawn by the load
--     script until the story sends Team Aqua's away) close the cove and the way east;
--   the three sealed chambers open by what their braille says;
--   Shoal Cave's two tides each reach rooms the other does not;
--   the Mystery Events House's stairs are walled off in the map itself.
local CLOSED_FOR_NOW = {
  { map = "^LILYCOVE_CITY$", byWater = true, overrides = true, reason = "Blocked by a group of Wailmer" },
  { map = "^DESERT_RUINS$", reason = "Sealed: the braille on the far wall says how to open it" },
  { map = "^ISLAND_CAVE$", reason = "Sealed: the braille on the far wall says how to open it" },
  { map = "^ANCIENT_TOMB$", reason = "Sealed: the braille on the far wall says how to open it" },
  -- (the rooms keep their "low tide" map at either tide: the tide is FLAG_SYS_SHOAL_TIDE,
  -- set at high tide, which swaps their layout, pokeemerald time_events.c)
  { map = "^SHOAL_CAVE_", tide = true, reason = "Not at low tide: this part is reached at high tide",
    highReason = "Not at high tide: this part is reached at low tide" },
  { map = "MYSTERY_EVENTS_HOUSE_1F$", reason = "The stairs are closed off" },
}

function Navigation:closedForNow(world, goals)
  local map = world and world.map
  local bare = map and GameData.bareMapId(self:currentMapIdOf(world))
  if type(bare) ~= "string" then return nil end
  for _, entry in ipairs(CLOSED_FOR_NOW) do
    if bare:find(entry.map) then
      local applies = true
      if entry.byWater then
        -- only for a target on or beside the water: the town's own doors are not the Wailmer's
        applies = false
        for _, goal in ipairs(goals) do
          if map:isWater(goal.x, goal.y) or map:isWater(goal.x, goal.y + 1) or goal.x == map.widthCells - 1 then
            applies = true
            break
          end
        end
      end
      if applies and entry.overrides then
        applies = false
        for y = 0, map.heightCells - 1 do
          for x = 0, map.widthCells - 1 do
            if map:overrideBlocked(x, y) then applies = true break end
          end
          if applies then break end
        end
      end
      if applies and entry.tide and self:shoalHighTide() then return entry.highReason end
      if applies then return entry.reason end
    end
  end
  return nil
end

-- Shoal Cave's tide as the game has it now (tests replace this).
function Navigation:shoalHighTide()
  local flag = GameData.flag("FLAG_SYS_SHOAL_TIDE")
  return flag ~= nil and flagSet(flag)
end

-- Who stands in a journey planned with people set aside: the first person on its way,
-- with the place when that is not this map ("Snorlax", "Super Nerd in Mt. Moon B2F").
-- Nil when no one on it can be named.
function Navigation:journeyBlocker(result, currentMapId)
  for _, leg in ipairs(result and result.legs or {}) do
    local entry = result.maps and result.maps[leg.mapId]
    local okCells, occupied = pcall(occupancy, entry and entry.world or {})
    if okCells and type(occupied) == "table" then
      for _, step in ipairs(leg.steps or {}) do
        local found = occupied[cellKey(step.x, step.y)]
        if found and found.kind == "object" then
          local name
          if found.actor.invisible then
            -- a buried trainer (Lavaridge Gym), as routeNeeds says it on the player's own floor
            local hiddenDef = type(found.actor.def) == "table" and found.actor.def or {}
            name = tonumber(hiddenDef.trainerType) == 3 and "a hidden trainer" or "something hidden"
          else
            local okLabel, label = pcall(Snapshot.objectLabel, found.actor, {})
            name = okLabel and label or "someone"
          end
          if leg.mapId ~= currentMapId then name = name .. " in " .. self:regionalDestinationName(leg.mapId) end
          return name, found.actor
        end
      end
    end
  end
  return nil
end

-- The one the way cannot do without.  The shortest way with everyone set aside walks
-- through whoever is nearest (a Youngster in Mt. Moon 1F who can be walked round), so
-- each person on it is stood back up in turn and the journey searched again (`search`,
-- with people set aside but for those): the first whose return leaves no way is named.
function Navigation:essentialBlocker(search, first, currentMapId)
  local solid, result = {}, first
  for _ = 1, 8 do
    local name, actor = self:journeyBlocker(result, currentMapId)
    if not actor then return nil end
    solid[actor.def or actor] = true
    self.routeIgnoringPeople, self.routeSolidPeople = true, solid
    local ok, again = pcall(search)
    self.routeIgnoringPeople, self.routeSolidPeople = nil, nil
    if not (ok and again) then return name end
    result = again
  end
  return nil
end

-- What a journey that is possible only with everything (policy 3) still
-- needs, as Gen 1 says it for a route on one map ("Needs Card Key").
function Navigation:journeyRequirement(result)
  local needed = {}
  for _, leg in ipairs(result and result.legs or {}) do
    local entry = result.maps[leg.mapId]
    if entry then
      for key, value in pairs(self:routeRequirements(entry.world, { steps = leg.steps })) do
        if value then needed[key] = true end
      end
    end
  end
  for label in pairs(result and result.needs or {}) do
    needed[(label:upper():gsub(" ", "_"))] = true
  end
  if next(needed) == nil then return nil end
  return Shared.requirementPhrase(needed)
end

-- The next leg of a journey (the shared contract: { final, goals,
-- nextMapId, appendInstructions }, or nil and a reason).  Walks first, then
-- uses what the party can (policy 2, as auto-walk does on one map); when
-- only a field move or the Card Key the player lacks would open the way,
-- the reason says so.
-- Doors a script opens, which a journey cannot plan through.  New Mauville's
-- (pokeemerald data/maps/NewMauville_Entrance/scripts.inc; the same in Ruby and
-- Sapphire): while VAR_NEW_MAUVILLE_STATE is 0 the load script closes the door,
-- and stepping in front of it with the Basement Key opens it.
local STORY_DOORS = {
  { maps = { NEW_MAUVILLE_ENTRANCE = true, NEW_MAUVILLE_INSIDE = true }, target = "NEW_MAUVILLE_INSIDE",
    var = "VAR_NEW_MAUVILLE_STATE", closed = 0, item = "ITEM_BASEMENT_KEY",
    withItem = "New Mauville's door is locked: walk up to it and the Basement Key opens it",
    without = "New Mauville's door is locked: needs the Basement Key" },
}

function Navigation:storyDoor(fromMapId, targetMapId)
  local target = GameData.bareMapId(targetMapId)
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  for _, door in ipairs(STORY_DOORS) do
    if target == door.target or (door.maps[GameData.bareMapId(fromMapId)] and door.maps[target]) then
      local varId = GameData.var(door.var)
      local value = varId and Space and Space.store and Flags
        and tonumber(call(Flags.getVar, Space.store, nil, varId)) or nil
      if value == door.closed then
        local set = GameData.constants()
        local itemId = set and set.items and set.items.byName and set.items.byName[door.item]
        local session = self:session()
        return (itemId and bagHas(session and session.bag, itemId)) and door.withItem or door.without
      end
    end
  end
  return nil
end

-- A door on the way that a key opens (Scripts.keyDoor; the Abandoned Ship's rooms).
-- Each one still locked on the journey's maps is supposed open in turn, its flag set and
-- the floor read as it would then load: when the journey exists that way, the door is
-- what stands in it, and the refusal names its key, and says how it opens when the key
-- is in the bag (the game's script answers an A press facing the door).
function Navigation:lockedDoor(start, target, allowed)
  local mapIds, seen = {}, {}
  local function add(id)
    if type(id) == "string" and not seen[id] then
      seen[id] = true
      mapIds[#mapIds + 1] = id
    end
  end
  add(start.mapId)
  add(target.mapId)
  for id in pairs(allowed or {}) do add(id) end
  table.sort(mapIds)
  for _, id in ipairs(mapIds) do
    local def = self:regionalMapDef(id)
    for _, event in ipairs(def and def.bgEvents or {}) do
      local door = event.type == "sign" and Scripts.keyDoor(event.scriptKey) or nil
      if door and not flagSet(door.flag) then
        World.supposedFlags, self.journeySupposing = { [door.flag] = true }, true
        local ok, found = pcall(self.journeySearch, self, start, target, 2, allowed, 1, true)
        World.supposedFlags, self.journeySupposing = nil, nil
        if ok and found then
          local name = Scripts.itemLabel(door.item) or "its key"
          local session = self:session()
          if bagHas(session and session.bag, door.item) then
            return "A door on the way is locked: face it and press A, the " .. name .. " opens it"
          end
          return "A door on the way is locked: needs the " .. name
        end
      end
    end
  end
  return nil
end

function Navigation:regionalNextLeg(navigation)
  local live = self:worldForCommand()
  if not live then return nil, "Not on a map" end
  local mapId = self:currentMapIdOf(live)
  local start = { mapId = mapId, x = live.player.cellX, y = live.player.cellY }
  local target = { mapId = navigation.targetMapId, goals = navigation.targetGoals,
    anywhere = navigation.targetGoals and navigation.targetGoals.anywhere }
  if type(target.mapId) ~= "string" or type(target.goals) ~= "table" or #target.goals == 0 then
    return nil, "no regional path"
  end
  -- the maps a target names for its own journey (a far dive spot's), else its area's
  local allowed = target.goals.journeyAllowed or self:journeyMaps(mapId, target.mapId)
  local result, reason
  -- a journey that can be walked is walked: an elevator's menu and a fall
  -- that cannot be undone come only when nothing else gets there
  -- last, past boulders: on floors ahead, then here too (a way out and back onto this
  -- floor, Mt. Ember's Fire Stone); the floors' puzzles open them when the walk gets there
  self.journeyPastBoulders = nil
  for _, try in ipairs({ { 1, false }, { 2, false }, { 2, true }, { 2, true, "others" }, { 2, true, "all" } }) do
    self.journeyBoulderFree = try[3]
    local ok
    ok, result, reason = pcall(self.journeySearch, self, start, target, try[1], allowed, nil, try[2])
    self.journeyBoulderFree = nil
    if not ok then error(result) end
    -- guided navigation asks whether the way found counts on boulders being moved
    if result then self.journeyPastBoulders = try[3] ~= nil end
    if result or reason ~= "no regional path" then break end
  end
  if not result then
    if reason == "no regional path" then
      local everything = self:journeySearch(start, target, 3, allowed, nil, true)
      local needs = everything and self:journeyRequirement(everything)
      if needs then return nil, needs end
      local door = self:storyDoor(mapId, target.mapId)
      if door then return nil, door end
      local locked = self:lockedDoor(start, target, allowed)
      if locked then return nil, locked end
      -- people the story moves later (the grunts at a hideout's door): the journey with
      -- them set aside names the one in the way here, or says they are further on
      -- (then with the boulders set aside as well: Magma Hideout's far rooms from its
      -- door are past 1F's boulders and, on 4F, the people the story stands in the one
      -- corridor; with the boulders in the plan no one was named and it said nothing)
      local aside, asideFree
      for _, free in ipairs({ false, "all" }) do
        self.routeIgnoringPeople, self.journeyBoulderFree = true, free or nil
        local okAside, found = pcall(self.journeySearch, self, start, target, 2, allowed, nil, true)
        self.routeIgnoringPeople, self.journeyBoulderFree = nil, nil
        if okAside and found then
          aside, asideFree = found, free or nil
          break
        end
      end
      if aside then
        local way = aside.firstTransition
        local here = (way and self:routeNeeds({ { x = way.x, y = way.y } }))
          or (aside.final and self:routeNeeds(target.goals)) or nil
        local who = not here and self:essentialBlocker(function()
          self.journeyBoulderFree = asideFree
          local okAgain, again = pcall(self.journeySearch, self, start, target, 2, allowed, nil, true)
          self.journeyBoulderFree = nil
          return okAgain and again or nil
        end, aside, mapId) or nil
        return nil, here or (who and ("Blocked by " .. who)) or "Blocked by someone further on"
      end
      -- The way round.  A route's two halves often join only through another place:
      -- Route 104 through Petalburg Woods, Ever Grande City through Victory Road,
      -- FireRed's Route 4 through Mt. Moon and Route 10 through Rock Tunnel.  When
      -- nothing in the area gets there, with or without what the player lacks, the
      -- search is run once more over the places this map's own doors lead to
      -- (Navigation:wayRoundMaps), with what the party can do now; then with boulders
      -- set aside, as above (Victory Road's are pushed when the walk gets to them);
      -- then with people set aside, to name who stands in that way.  Any map at all was
      -- tried first: with Mt. Moon's Super Nerd in the corridor it led from Route 4 to
      -- Cerulean through Pewter, Diglett's Cave, Vermilion and the Underground Path.
      local round = allowed and self:wayRoundMaps(mapId, allowed) or nil
      if round then
        for _, free in ipairs({ false, "all" }) do
          self.journeyBoulderFree = free or nil
          local okRound, found = pcall(self.journeySearch, self, start, target, 2, round, 2, true)
          self.journeyBoulderFree = nil
          if okRound and found and not found.final then
            result = found
            self.journeyPastBoulders = free ~= false
            break
          end
        end
        -- (the same through the next map's edge, before anyone is blamed: below)
        if not result then result = self:wayRoundNextDoor(start, target, allowed) end
        if not result then
          self.routeIgnoringPeople = true
          local okFree, free = pcall(self.journeySearch, self, start, target, 2, round, 2, true)
          self.routeIgnoringPeople = nil
          if okFree and free and not free.final then
            local way = free.firstTransition
            local here = way and self:routeNeeds({ { x = way.x, y = way.y } }) or nil
            local who = not here and self:essentialBlocker(function()
              return self:journeySearch(start, target, 2, round, 2, true)
            end, free, mapId) or nil
            return nil, here or ("The way is through " .. self:regionalDestinationName(way.destMap)
              .. ", blocked by " .. (who or "someone further on"))
          end
        end
      end
      if not result then result = self:wayRoundNextDoor(start, target, allowed) end
    end
    if not result then return nil, reason end
  end
  if result.final then
    -- a floor as the target: being on it is the arrival
    if target.anywhere then
      return { final = true, goals = { { x = start.x, y = start.y } }, arrived = true,
        appendInstructions = navigation.targetAppendInstructions }
    end
    -- an Area target's cells were worked out on the map the journey began
    -- on; one outside this map (Silph Co. 5F is shorter than 1F) made the
    -- last leg's route fail outright ("Cannot reach Card Key")
    local goals = {}
    for _, goal in ipairs(navigation.targetGoals) do
      if live.map:inBounds(goal.x, goal.y) then goals[#goals + 1] = goal end
    end
    -- what to do there, when the target says (a far dive spot: the game's button)
    local hint = navigation.targetGoals.arrivalHint
    return { final = true, goals = #goals > 0 and goals or navigation.targetGoals,
      appendInstructions = navigation.targetAppendInstructions
        or (hint and function(parts) parts[#parts + 1] = hint end) or nil }
  end
  local transition = result.firstTransition
  local destinationName = self:regionalDestinationName(transition.destMap)
  local instruction = transition.kind == "connection"
    and ("Continue " .. transition.direction .. " to " .. destinationName)
    or ("Continue to " .. destinationName)
  local stopText, danceText
  if transition.kind == "elevator" then
    -- the rest of the name after the words the elevator shares with it:
    -- "B4F" in the Rocket Hideout Elevator, as its menu lists it
    local car = self:regionalDestinationName(mapId)
    local floorName = destinationName
    local carWords = {}
    for word in car:gmatch("%S+") do carWords[#carWords + 1] = word end
    local index = 1
    for word in destinationName:gmatch("%S+") do
      if carWords[index] == word then
        floorName = floorName:sub(#word + 2)
        index = index + 1
      else
        break
      end
    end
    if floorName == "" then floorName = destinationName end
    instruction = "Face " .. transition.facing .. " and use the floor panel; take the elevator to "
      .. floorName
    stopText = "Arrived at the floor panel. Face " .. transition.facing
      .. " and take the elevator to " .. floorName
  elseif transition.kind == "dive" then
    -- pokeemerald field_control_avatar.c: A dives from deep water, B surfaces
    local verb = transition.emerge and "surface" or "dive"
    local button = transition.emerge and "B" or "A"
    instruction = "Press " .. button .. " to " .. verb .. " to " .. destinationName
    stopText = "Arrived at the " .. (transition.emerge and "way up" or "deep water") .. ". Press " .. button
      .. " and answer yes to " .. verb .. " to " .. destinationName
  elseif transition.kind == "fall" and not transition.cracked then
    instruction = "Step off the thin ice and back onto it: it cracks and you fall through to "
      .. destinationName
    danceText = "Stepping off the thin ice and back on, to fall through to " .. destinationName
  elseif transition.kind == "fall" then
    instruction = "Step onto the cracked ice to fall through to " .. destinationName
  end
  return {
    final = false,
    goals = { { x = transition.x, y = transition.y } },
    nextMapId = transition.destMap,
    -- the way off the map at a connection: a walk that is already on the edge cell (a
    -- current set it down there, Route 132's west edge) presses it, where it used to
    -- stop with "Could not go through"
    edgeDirection = transition.kind == "connection" and CONNECTION_STEP_OF[transition.direction] or nil,
    -- auto-walk ends here and says what to do: the game's menu or the ice
    -- is the player's (AutoWalk: stopAtGoal)
    stopAtGoal = stopText ~= nil, stopText = stopText,
    -- thin ice is only steps: auto-walk takes them (AutoWalk: danceAtGoal)
    danceAtGoal = danceText ~= nil, danceText = danceText,
    appendInstructions = function(parts) parts[#parts + 1] = instruction end,
  }
end

-- The Area category (decision 25) on FireRed maps: item balls the game
-- would still show on the other maps of the building or zone.  Maps share
-- an area when they share the first two words of their id (SILPH_CO_*,
-- SAFARI_ZONE_*, ROCKET_HIDEOUT_*); on the Sevii Islands, where every map
-- starts with the island, the first three (FIVE_ISLAND_LOST_CAVE_*).
local function areaKey(mapId)
  if type(mapId) ~= "string" then return nil end
  local id = GameData.bareMapId(mapId)
  if GameData.isHoenn() then
    -- every Secret Base map is a room of its own; a route and its seabed are one area
    if id:match("^SECRET_BASE") or id:match("^BATTLE_PYRAMID_SQUARE") then return nil end
    id = GameData.RS_UNDERWATER[id] or id:gsub("^UNDERWATER_", "")
    local route = id:match("^(ROUTE%d+)$")
    if route then return route end
  end
  if id:match("^%u+_ISLAND_") then
    return id:match("^(%u+_ISLAND_[%u%d]+)")
  end
  return id:match("^([%u%d]+_[%u%d]+)")
end
Navigation.areaKey = areaKey

-- Which way a map's currents carry the player, as a connection's direction ("west"), and
-- how many cells of current it has.  Read from the map's cells once.
local STEP_COMPASS = { up = "north", down = "south", left = "west", right = "east" }
-- a map "has currents" from this many cells of them: Routes 132 to 134 have hundreds
local CURRENT_MAP_CELLS = 8

function Navigation:currentFlow(def)
  if type(def) ~= "table" then return nil, 0 end
  self.gen3CurrentFlow = self.gen3CurrentFlow or setmetatable({}, { __mode = "k" })
  local cached = self.gen3CurrentFlow[def]
  if not cached then
    cached = { count = 0 }
    self.gen3CurrentFlow[def] = cached
    local view = World.plannedView(self.game, def)
    local counts = {}
    for y = 0, (view and view.heightCells or 0) - 1 do
      for x = 0, view.widthCells - 1 do
        local direction = Terrain.CURRENT[view:behavior(x, y)]
        if direction then
          counts[direction] = (counts[direction] or 0) + 1
          cached.count = cached.count + 1
        end
      end
    end
    local most
    for _, direction in ipairs(ORDER) do
      if counts[direction] and (not most or counts[direction] > counts[most]) then most = direction end
    end
    cached.direction = most and STEP_COMPASS[most] or nil
  end
  return cached.direction, cached.count
end

-- The surface maps up to three connections from this one, nearest first, and which of
-- them lie down a current from here: a map with currents, entered the way they run,
-- through maps that were themselves entered that way (Routes 132, 133 and 134 from
-- Pacifidlog; none of them from Slateport, which is at the far end).  Worked out once a map.
--   returns { within = { [mapId] = true }, order = { mapId, ... }, downstream = { [mapId] = true } }
function Navigation:farMaps(world)
  local here = self:currentMapIdOf(world)
  local map = world and world.map
  local none = { within = {}, order = {}, downstream = {} }
  if type(here) ~= "string" or not map or map.underwater then return none end
  self.gen3FarMaps = self.gen3FarMaps or {}
  local cached = self.gen3FarMaps[here]
  if cached then return cached end
  local Connections = loaded("src.core.game3.connections")
  if not (Connections and Connections.each) then return none end
  local far = { within = { [here] = true }, order = {}, downstream = {} }
  self.gen3FarMaps[here] = far
  local frontier = { here }
  for _ = 1, 3 do
    local nextFrontier = {}
    for _, id in ipairs(frontier) do
      local def = self:regionalMapDef(id)
      local _, cells = self:currentFlow(def)
      -- a map with currents passes the player on only when it was entered with them
      local passesOn = id == here or cells < CURRENT_MAP_CELLS or far.downstream[id] == true
      for _, row in ipairs(def and call(Connections.each, def) or {}) do
        local nextDef = type(row.map) == "string" and self:regionalMapDef(row.map) or nil
        local nextId = nextDef and nextDef.id
        if type(nextId) == "string" and not far.within[nextId] then
          far.within[nextId] = true
          nextFrontier[#nextFrontier + 1] = nextId
          far.order[#far.order + 1] = nextId
          local flow, nextCells = self:currentFlow(nextDef)
          far.downstream[nextId] = (passesOn and nextCells >= CURRENT_MAP_CELLS and flow == row.dir) or nil
        end
      end
    end
    frontier = nextFrontier
  end
  return far
end

local DIVE_HINT = "Press A and answer yes to dive"

-- What a player sets out for from further off, for the Area list: on the maps up to
-- three connections from this one,
--   * dive spots that lead to a place of their own (Sootopolis City, Seafloor Cavern,
--     the Sealed Chamber);
--   * the item balls on maps down a current from here (Navigation:farMaps).
-- The sea west of Pacifidlog is why: its currents carry the player through Routes 132
-- and 133 in whichever lane they entered, and only some lanes reach the water over the
-- Sealed Chamber on Route 134, or the sandbar an item lies on.  Chosen there, the list
-- says "No route"; chosen from upstream, the journey is planned across the three routes
-- and takes the right lane.  Item balls are limited to maps with currents so that an
-- ordinary route's Area list does not fill with its neighbours' items.  Built each time:
-- a ball taken is gone from the list, and a dive spot's label follows its balls.
function Navigation:farTargets(world)
  local far = self:farMaps(world)
  local items = {}
  for _, id in ipairs(far.order) do
    local def = self:regionalMapDef(id)
    local view = def and World.plannedView(self.game, def)
    local place = tostring(self:regionalDestinationName(id))
    local okSpots, spots = pcall(self.diveSpots, self, view and { map = view, npcs = {}, player = { cellX = -1, cellY = -1 } })
    -- a map with currents is no use from its far end: from Slateport the Sealed Chamber's
    -- spot was listed and answered "No route" after two thirds of a second
    local _, currentCells = self:currentFlow(def)
    local against = currentCells >= CURRENT_MAP_CELLS and not far.downstream[id]
    for _, spot in ipairs(okSpots and not against and spots or {}) do
      if spot.named and not spot.emerge and spot.rim[1] then
        local label = spot.label .. ", " .. place
        local rim = {}
        for _, cell in ipairs(spot.rim) do rim[#rim + 1] = { x = cell.x, y = cell.y } end
        -- the journey's own maps, and what guided navigation adds on arrival
        rim.journeyAllowed, rim.arrivalHint = far.within, DIVE_HINT
        items[#items + 1] = { id = "area:" .. spot.id, type = "area", category = "area", label = label,
          description = label, mapId = id, x = spot.rim[1].x, y = spot.rim[1].y, farDiveRim = rim }
      end
    end
    if far.downstream[id] then
      for _, object in ipairs(def.objects or {}) do
        if tonumber(object.graphicsId) == GFX.ITEM_BALL and regionalObjectVisible(object)
           and type(object.x) == "number" and type(object.y) == "number" then
          local itemId = Scripts.itemBallItem(object.scriptKey)
          local itemName = itemId and Scripts.itemLabel(itemId)
          if itemName then
            local label = itemName .. ", " .. place
            items[#items + 1] = {
              id = "area:" .. id .. ":" .. tostring(object.index or object.localId),
              type = "area", category = "area", label = label, description = label,
              mapId = id, x = object.x, y = object.y, journeyAllowed = far.within,
            }
          end
        end
      end
    end
  end
  return items
end

function Navigation:areaBrowse(world)
  local items = self:areaFloors(world)
  local listed = {}
  for _, item in ipairs(items) do listed[item.id] = true end
  local okFar, far = pcall(self.farTargets, self, world)
  local needsDive = self:fieldMoveRequirement("DIVE")
  for _, item in ipairs(okFar and far or {}) do
    -- (a map of this same area is in the list already, with its items)
    if not listed[item.id] then
      if item.farDiveRim then item.requirement = needsDive end
      items[#items + 1] = item
    end
  end
  return items
end

function Navigation:areaFloors(world)
  local data = self.game and self.game.data
  local maps = data and data.maps or {}
  local here = self:currentMapIdOf(world)
  local key = areaKey(here)
  local items = {}
  if not key then return items end
  local members = {}
  for mapId in pairs(maps) do
    -- (ownsMap: One Island's maps carry SEVII_, not FR_, and were never members)
    if type(mapId) == "string" and GameData.ownsMap(mapId) and areaKey(mapId) == key then
      members[#members + 1] = mapId
    end
  end
  if #members < 2 then return items end
  table.sort(members)
  for _, mapId in ipairs(members) do
    if mapId ~= here then
      local mapName = self:regionalDestinationName(mapId)
      -- the floor itself is a target, with or without items left on it
      items[#items + 1] = {
        id = "area:" .. mapId, type = "area", category = "area", floorEntry = true,
        label = tostring(mapName), description = tostring(mapName),
        mapId = mapId, x = 0, y = 0,
      }
      for _, object in ipairs(maps[mapId].objects or {}) do
        if tonumber(object.graphicsId) == GFX.ITEM_BALL and regionalObjectVisible(object) then
          local itemId = Scripts.itemBallItem(object.scriptKey)
          local itemName = itemId and Scripts.itemLabel(itemId)
          if itemName then
            local label = itemName .. ", " .. tostring(mapName)
            items[#items + 1] = {
              id = "area:" .. mapId .. ":" .. tostring(object.index or object.localId),
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

-- A floor picked from the Area list is reached as soon as the journey arrives on it,
-- whichever way in that takes (journeySearch, target.anywhere).
--
-- A journey to something on the player's own map through other floors (Victory Road's far
-- door, from its near one) loses its selection on the first new floor: the list there does
-- not have it.  The walk itself carries its target, but whatever takes over on the way
-- (a floor's boulders, its switches, a walk resumed after a trainer) asks for the selection
-- again and found none: "Cannot reach ..., auto walk stopped" on Victory Road B1F.  So the
-- journey's target is kept (AutoWalk calls rememberJourneyTarget) and stands in as the
-- selection, shaped like an Area target, until the player arrives or chooses another.
function Navigation:rememberJourneyTarget(item, journey)
  if type(item) ~= "table" or type(journey) ~= "table" or type(journey.targetGoals) ~= "table" then return end
  self.journeyTarget = {
    sourceId = item.id, goals = journey.targetGoals,
    item = { id = item.id, type = "area", category = "area", label = item.label,
      description = item.description or item.label, mapId = journey.targetMapId,
      x = item.x, y = item.y, journeyStandIn = true,
      arrivalMapId = item.type == "warp" and item.destinationMapId or nil },
  }
end

function Navigation:keptJourneyTarget()
  local kept = self.journeyTarget
  if not kept then return nil end
  local overworld = self:worldForCommand()
  local here = overworld and self:currentMapIdOf(overworld)
  if not here then return nil end
  -- the player chose something else, went through the door, or stands on the target
  local chosen = self.browseSelectionId
  if (chosen ~= nil and chosen ~= kept.sourceId) or here == kept.item.arrivalMapId then
    self.journeyTarget = nil
    return nil
  end
  if here == kept.item.mapId then
    for _, goal in ipairs(kept.goals) do
      if goal.x == overworld.player.cellX and goal.y == overworld.player.cellY then
        self.journeyTarget = nil
        return nil
      end
    end
    -- on its own map, with the selection still on it: the list's own item
    if chosen == kept.sourceId then return nil end
  end
  local goals = {}
  for i, goal in ipairs(kept.goals) do goals[i] = { x = goal.x, y = goal.y } end
  goals.anywhere = kept.goals.anywhere
  return kept.item, goals, overworld
end

function Navigation:selectedRouteGoals()
  local keptItem, keptGoals, keptWorld = self:keptJourneyTarget()
  if keptItem then return keptItem, keptGoals, nil, nil, keptWorld end
  local item, goals, instructions, connection, overworld = Shared.selectedRouteGoals(self)
  if type(item) == "table" and item.floorEntry and type(goals) == "table" then goals.anywhere = true end
  -- a dive spot on a map further on: any cell of its rim, over the maps between; the
  -- arrival says the game's button, as the spot's own entry does on its map
  if type(item) == "table" and item.farDiveRim then
    goals = item.farDiveRim
    instructions = setmetatable({}, { __index = function() return DIVE_HINT end })
  elseif type(item) == "table" and item.type == "area" and not item.floorEntry
     and not item.journeyStandIn and type(goals) == "table" then
    -- an item ball on another map: the journey's own maps when it names them (one down
    -- a current), and which way the ball is from the cell the walk ends on
    goals.journeyAllowed = item.journeyAllowed
    instructions = {}
    for facing, d in pairs(DELTA) do
      instructions[cellKey(item.x - d[1], item.y - d[2])] = "Face " .. facing .. " and interact"
    end
  end
  -- a dive spot is reached by being on any of its cells; then the game's own button
  if type(item) == "table" and item.semanticKind == "dive_spot" and overworld then
    local spot = self:diveSpotById(overworld, item.id)
    if spot then
      local player = overworld.player
      goals = {}
      if spot.inGroup[player.cellY * overworld.map.widthCells + player.cellX] then
        goals[1] = { x = player.cellX, y = player.cellY }
      else
        for _, cell in ipairs(spot.rim) do goals[#goals + 1] = { x = cell.x, y = cell.y } end
      end
      local hint = spot.emerge and "Press B and answer yes to surface" or "Press A and answer yes to dive"
      instructions = setmetatable({}, { __index = function() return hint end })
    end
  end
  return item, goals, instructions, connection, overworld
end

function Navigation:commandAllowed()
  return self:worldForCommand() ~= nil
end

-- F8 help: the camera line only when it is on, as in Gen 1.
function Navigation:handleCommand(actionId)
  return Shared.handleCommand(self, actionId)
end

return Navigation
