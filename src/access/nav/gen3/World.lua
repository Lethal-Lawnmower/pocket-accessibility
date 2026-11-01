-- FireRed's field as navigation sees it (decision 29).  Read-only.
--
-- Gen 3 has no world object: the field is module singletons in
-- src/core/game3/ (player, collision, map, objects).  This module builds:
--
--   World.facade(game)        one stable table per game with `map`, `player`,
--                             `npcs` and `entities`, the shape the shared
--                             coordinator, auto-walk and the snapshot read
--   World.liveView()          the bound map (Collision's grid, live warps,
--                             live behaviour and elevation)
--   World.plannedView(game, def)  any other map, from its def (midLayout),
--                             for cross-map plans
--
-- Both views answer the same questions, so one movement graph serves the
-- walked map and planned ones (nav/gen3/Navigation.lua, routeOptionsFor):
-- the COLL byte, the metatile behaviour (MB), the elevation, water,
-- directional walls, active warps and how each warp fires.  They also carry
-- the Gen 1 map query surface the shared snapshot and coordinator use
-- (cellCollision, isWalkableCell, isWaterCell, isCounterCell, warpAtCell,
-- isWarpTileCell, inBounds, widthCells, heightCells, def).
--
-- The synchronisation check (Map.current, Collision._mapId and
-- Objects._mapId agree before the map is trusted) comes from the old
-- project's Gen 3 WorldSnapshot (purple-gen3-integration,
-- src/accessibility/gen3/WorldSnapshot.lua, commit 244150e22, upstream
-- v0.3.32), reused under decision 20.

local World = {}

local function loaded(path) return package.loaded[path] end

local function lazy(path)
  local module = package.loaded[path]
  if type(module) == "table" then return module end
  local ok, value = pcall(require, path)
  return ok and value or nil
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
World.DELTA = DELTA

local COLL_COUNTER = 0x90
local MB_COUNTER = 0x80 -- MB_COUNTER: talk across it (pokefirered metatile_behaviors.h)

local function collisionModule() return lazy("src.core.game3.collision") end
local function permissions() return lazy("src.world.gen2.Permissions") end

local function isWarpColl(coll)
  return type(coll) == "number" and coll >= 0x60 and coll <= 0x7F
end
World.isWarpColl = isWarpColl

-- ------------------------------------------------------------ map views

local View = {}
View.__index = View

function View:inBounds(x, y)
  return type(x) == "number" and type(y) == "number"
    and x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells
end

function View:behavior(x, y)
  if not self:inBounds(x, y) then return nil end
  local C = collisionModule()
  return C and call(C.behaviorOn, self.def, x, y) or nil
end

function View:elevation(x, y)
  if not self:inBounds(x, y) then return nil end
  local C = collisionModule()
  return C and call(C.elevationOn, self.def, x, y) or nil
end

-- The COLL byte as movement reads it.  Live: the bound grid (with the
-- door repairs Collision.installWarps made).  Planned: the layout, with the
-- same repair applied read-only to warp cells (installWarps writes it).
function View:coll(x, y)
  if not self:inBounds(x, y) then return 0xff end
  if self.live then
    local C = collisionModule()
    if C and C._mapDef == self.def then return C.cell(x, y) end
  end
  local layout = self.def and self.def.midLayout
  if not layout then return 0xff end
  local coll = layout:collAt(x, y)
  local warp = self.warpCells and self.warpCells[y * 1024 + x]
  if warp and not isWarpColl(coll) then
    local beh = self:behavior(x, y)
    local C = collisionModule()
    local repair = beh == nil or (C and C.isWarpMetatileBehavior(beh))
    if repair and (coll == nil or coll == 0x07 or coll == 0xff or (beh ~= nil and coll == 0x00)) then
      return 0x71
    end
  end
  return coll
end
View.cellCollision = View.coll

function View:isLedgeCell(x, y)
  local P = permissions()
  return P ~= nil and P.isLedge(self:coll(x, y)) == true
end

function View:ledgeFacings(x, y)
  local P = permissions()
  return P and P.ledgeFacings(self:coll(x, y)) or nil
end

-- Land the player may stand on: the COLL rule Collision.isWalkable applies
-- (a ledge is never stood on; only the hop crosses it).
function View:walkableColl(x, y)
  if not self:inBounds(x, y) then return false end
  local coll = self:coll(x, y)
  local P = permissions()
  if not P then return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29 end
  if P.isLedge(coll) then return false end
  return P.isWalkable(coll) == true
end

function View:isWater(x, y)
  if not self:inBounds(x, y) then return false end
  local C = collisionModule()
  return C ~= nil and call(C.isWaterOn, self.def, x, y, self:coll(x, y)) == true
end

function View:isGrass(x, y)
  local P = permissions()
  return P ~= nil and P.isGrass(self:coll(x, y)) == true
end

-- MB walls on the cell left and the cell entered
-- (IsMetatileDirectionallyImpassable).
function View:dirBlocked(fromX, fromY, x, y, direction)
  local C = collisionModule()
  return C ~= nil and call(C.directionallyImpassableOn, self.def, fromX, fromY, x, y, direction) == true
end

-- A script made this cell impassable (Field.setMetatile's impassable flag);
-- only known for the bound map.
function View:overrideBlocked(x, y)
  if not self.live then return false end
  local Field = loaded("src.core.game3.field")
  if not (Field and type(Field.metatileOverrideAt) == "function") then return false end
  local o = call(Field.metatileOverrideAt, self.id, x, y)
  return type(o) == "table" and o.impassable == true
end

-- The active warp on a cell and its index in def.warps, or nil.  Live: the
-- set Collision.installWarps indexed (dead header warps left out).
-- Planned: the same rule re-derived without writing anything.
function View:warpAt(x, y)
  if not self:inBounds(x, y) then return nil end
  local index = self.warpIndex[y * 1024 + x]
  if not index then return nil end
  local warp = self.def.warps[index]
  if self.live then
    local C = collisionModule()
    if C and C._mapDef == self.def then
      local live = C.warpAt(x, y)
      if not live then return nil end
      return live, index
    end
  end
  -- installWarps: active on a warp COLL byte after its door repair (which
  -- View:coll mirrors)
  if isWarpColl(self:coll(x, y)) then return warp, index end
  return nil
end

function View:warpAtCell(x, y)
  local warp, index = self:warpAt(x, y)
  if not warp then return nil end
  return { index = index, def = warp }
end

function View:isWarpTileCell(x, y)
  return self:warpAt(x, y) ~= nil
end

-- Where a warp leads: map id and landing cell.  Dynamic warps (elevators,
-- link rooms) resolve through the session's dynamic warp, as the game does.
function View:warpDestination(warp)
  local C = collisionModule()
  if not (C and C.resolveWarpDestination and type(warp) == "table") then return nil end
  local ok, map, x, y = pcall(C.resolveWarpDestination, self.game, warp)
  if not ok or type(map) ~= "string" then return nil end
  return map, x, y
end

local function doorEntry(mapId, x, y)
  local Doors = lazy("src.core.game3.doors")
  if not (Doors and Doors.getDoorEntryAt) then return nil end
  return call(Doors.getDoorEntryAt, mapId, x, y)
end

-- How a warp fires (src/core/game3/player.lua stepTriggers, finishStep):
--   door        moving up into it from the cell below (an animated door)
--   exit_mat    standing on it, pressing down (leads to an outdoor door)
--   arrow       standing on it, pressing its arrow direction
--   stair       standing on it, pressing left or right
--   escalator   moving into it
--   hole        stepping onto it drops the player to the floor below
--   pad         stepping onto it teleports
--   step        stepping onto it (ladders, cave doors)
-- and, for the standing kinds, the direction to press.
function View:warpKind(x, y)
  local warp = self:warpAt(x, y)
  if not warp then return nil end
  local C = collisionModule()
  local beh = self:behavior(x, y)
  if C then
    if C.isStairWarpBehavior(beh) then return "stair", C.stairWarpDir(beh) end
    if C.isArrowWarpBehavior(beh) then return "arrow", C.arrowWarpDir(beh) end
  end
  if doorEntry(self.id, x, y) then return "door", "up" end
  local destMap, destX, destY = self:warpDestination(warp)
  if destMap and doorEntry(destMap, destX, destY) then return "exit_mat", "down" end
  if C then
    if C.isEscalator(beh) then return "escalator" end
    if C.isFallWarp(beh) then return "hole" end
    if C.isWarpPad(beh) then return "pad" end
  end
  return "step"
end

-- Auto-walk's last cell of a walk to a standing warp: the direction to
-- hold there (nil when stepping on is enough).
function View:pressDirection(x, y)
  local kind, press = self:warpKind(x, y)
  if kind == "exit_mat" or kind == "arrow" or kind == "stair" then return press end
  return nil
end

-- The Gen 1 query surface the shared snapshot and coordinator use.
function View:isWalkableCell(x, y)
  if not self:walkableColl(x, y) then return false end
  if self:isWater(x, y) then return false end
  return not self:overrideBlocked(x, y)
end

function View:isWaterCell(x, y) return self:isWater(x, y) end
function View:isGrassCell(x, y) return self:isGrass(x, y) end

function View:isCounterCell(x, y)
  if not self:inBounds(x, y) then return false end
  return self:coll(x, y) == COLL_COUNTER or self:behavior(x, y) == MB_COUNTER
end

function View:signAtCell() return nil end

-- The behaviour byte stands in for Gen 1's tile number (sonar, E key).
function View:cellTile(x, y) return self:behavior(x, y) end

local function newView(game, def, mapId, live)
  local layout = def and def.midLayout
  if not layout then return nil end
  local view = setmetatable({
    game = game, def = def, id = mapId or def.id, live = live == true,
    widthCells = layout.width, heightCells = layout.height,
    warpIndex = {}, warpCells = {},
  }, View)
  for index, warp in ipairs(def.warps or {}) do
    local x, y = tonumber(warp.x), tonumber(warp.y)
    if x and y then
      view.warpIndex[y * 1024 + x] = view.warpIndex[y * 1024 + x] or index
      view.warpCells[y * 1024 + x] = true
    end
  end
  return view
end

local liveViews = setmetatable({}, { __mode = "k" })
local plannedViews = setmetatable({}, { __mode = "k" })

-- The map the field has bound, when Map, Collision and Objects agree; nil
-- while a map is loading.
function World.liveView(game)
  local Map = loaded("src.core.game3.map")
  local C = loaded("src.core.game3.collision")
  local Objects = loaded("src.core.game3.objects")
  if not (Map and C) then return nil end
  local mapId, def = Map.current, C._mapDef
  if type(mapId) ~= "string" or C._mapId ~= mapId or type(def) ~= "table"
     or type(C._grid) ~= "table" or C._grid[1] == nil then return nil end
  if Objects and Objects._mapId ~= nil and Objects._mapId ~= mapId then return nil end
  local view = liveViews[def]
  if view and view.id == mapId then return view end
  view = newView(game, def, mapId, true)
  liveViews[def] = view
  return view
end

-- A map the player is not on, from its def.  Reading `midLayout` decodes
-- the layout on first use (Dataset's lazy loader); nothing else is touched.
function World.plannedView(game, def)
  if type(def) ~= "table" then return nil end
  local view = plannedViews[def]
  if view ~= nil then return view or nil end
  local ok, built = pcall(newView, game, def, def.id, false)
  plannedViews[def] = ok and built or false
  return ok and built or nil
end

-- ------------------------------------------------------------ the facade

-- The live player, with Gen 1's spelling of the fields the shared code
-- reads (`onBike`).
local playerProxy = setmetatable({}, {
  __index = function(_, key)
    local Player = loaded("src.core.game3.player")
    if not Player then return nil end
    if key == "onBike" then return Player.biking == true end
    if key == "surfing" then return Player.surfing == true end
    return Player[key]
  end,
})
World.player = playerProxy

-- Live objects in list order: visible and not hidden (Objects.listActive's
-- rule).  Invisible objects (movement type 0x4C) still block movement, as
-- Objects.blocks counts them, so they stay in the list with `invisible`.
function World.actors()
  local Objects = loaded("src.core.game3.objects")
  local list = {}
  if not (Objects and type(Objects._order) == "table") then return list end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId and Objects._byId[lid]
    if type(eo) == "table" and eo.visible and not eo.hidden then list[#list + 1] = eo end
  end
  return list
end

local facades = setmetatable({}, { __mode = "k" })

function World.facade(game)
  if type(game) ~= "table" then return nil end
  local facade = facades[game]
  if facade then return facade end
  local state = { lastView = nil }
  facade = setmetatable({ isOverworld = true, game = game, player = playerProxy }, {
    __index = function(_, key)
      if key == "map" then
        -- a loading map keeps the last synchronised view, so readers never
        -- see a world without a map
        local view = World.liveView(game)
        if view then state.lastView = view end
        return state.lastView
      elseif key == "npcs" then
        return World.actors()
      elseif key == "entities" then
        local list = { playerProxy }
        for _, eo in ipairs(World.actors()) do list[#list + 1] = eo end
        return list
      elseif key == "surfing" then
        return playerProxy.surfing
      end
      return nil
    end,
  })
  facades[game] = facade
  return facade
end

-- The live session (party, bag, names, dynamic warp).
function World.session(game)
  local Runtime = loaded("src.core.game3.runtime")
  local session = Runtime and call(Runtime.getSession) or nil
  return session or (game and game.session) or nil
end

return World
