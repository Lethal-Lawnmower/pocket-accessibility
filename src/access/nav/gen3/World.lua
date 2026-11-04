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

-- Per-cell answers are kept until the layout changes: a script's
-- setmetatile (Silph Co. doors, Victory Road barriers, Icefall ice) goes
-- through LayoutNative:applyOverride, which bumps the layout's revision.
-- Routes ask the same cells many times, and cross-map plans many maps.
local NONE = {}
local function cached(self, name, x, y, compute)
  local layout = self.def.midLayout
  local revision = layout and layout._revision or 0
  if self.revision ~= revision then
    self.revision = revision
    self.cache = {}
  end
  local field = self.cache[name]
  if not field then
    field = {}
    self.cache[name] = field
  end
  local key = y * 1024 + x
  local value = field[key]
  if value == nil then
    value = compute(self, x, y)
    if value == nil then value = NONE end
    field[key] = value
  end
  if value == NONE then return nil end
  return value
end

local function computeBehavior(self, x, y)
  local C = collisionModule()
  return C and call(C.behaviorOn, self.def, x, y) or nil
end

function View:behavior(x, y)
  if not self:inBounds(x, y) then return nil end
  return cached(self, "beh", x, y, computeBehavior)
end

local function computeElevation(self, x, y)
  local C = collisionModule()
  return C and call(C.elevationOn, self.def, x, y) or nil
end

function View:elevation(x, y)
  if not self:inBounds(x, y) then return nil end
  return cached(self, "elev", x, y, computeElevation)
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
  return cached(self, "coll", x, y, View.layoutColl)
end

function View:layoutColl(x, y)
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

local function computeWater(self, x, y)
  local C = collisionModule()
  return C ~= nil and call(C.isWaterOn, self.def, x, y, self:coll(x, y)) == true
end

function View:isWater(x, y)
  if not self:inBounds(x, y) then return false end
  return cached(self, "water", x, y, computeWater) == true
end

function View:isGrass(x, y)
  local P = permissions()
  return P ~= nil and P.isGrass(self:coll(x, y)) == true
end

-- MB walls on the cell left and the cell entered
-- (IsMetatileDirectionallyImpassable).
-- pokefirered metatile_behavior.c: MB_IMPASSABLE_* (0x30-0x37), which side
-- each one closes.  Read through the cached behaviour; the same rule as
-- Collision.directionallyImpassableOn.
local CLOSED = {
  [0x30] = { east = true }, [0x31] = { west = true }, [0x32] = { north = true },
  [0x33] = { south = true }, [0x34] = { north = true, east = true },
  [0x35] = { north = true, west = true }, [0x36] = { south = true, east = true },
  [0x37] = { south = true, west = true },
}
local LEAVE_SIDE = { down = "south", up = "north", left = "west", right = "east" }
local ENTER_SIDE = { down = "north", up = "south", left = "east", right = "west" }

function View:dirBlocked(fromX, fromY, x, y, direction)
  local leave, enter = LEAVE_SIDE[direction], ENTER_SIDE[direction]
  if not leave then return false end
  if fromX and fromY then
    local closed = CLOSED[self:behavior(fromX, fromY)]
    if closed and closed[leave] then return true end
  end
  if x and y then
    local closed = CLOSED[self:behavior(x, y)]
    if closed and closed[enter] then return true end
  end
  return false
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
  -- Ruby, Sapphire and Emerald: Dive's water doors and their kin fire on behaviour alone
  -- (installWarps' RSE_WARP; their collision byte is water or floor)
  local beh = self:behavior(x, y)
  local C = collisionModule()
  if C and beh and beh >= 0x100 and C.isWarpMetatileBehavior(beh) then return warp, index end
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
  if not self:inBounds(x, y) then return nil end
  -- the answer depends only on the map's data (and the session's dynamic
  -- warp for elevators), so it is kept per view
  local key = y * 1024 + x
  local cached = self.kindCache[key]
  if cached ~= nil then
    if cached == false then return nil end
    return cached[1], cached[2]
  end
  local kind, press = self:computeWarpKind(x, y)
  self.kindCache[key] = kind and { kind, press } or false
  return kind, press
end

-- A warp the player may stand on and walk across: it fires only while its
-- own direction is pressed (exit mats, arrow warps, stair warps).  Returns
-- that direction, or nil.
function View:standingWarp(x, y)
  local kind, press = self:warpKind(x, y)
  if kind == "exit_mat" or kind == "arrow" or kind == "stair" then return press end
  return nil
end

function View:computeWarpKind(x, y)
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
    -- Lavaridge Gym's and Mt. Pyre's holes, Mossdeep Gym's pads and Lavaridge's
    -- springs (the springs and pads carry the player; the holes drop them)
    if C.isMtPyreHole and (C.isMtPyreHole(beh) or C.isLavaridge1FWarp(beh) or C.isCrackedFloorHole(beh)) then
      return "hole"
    end
    if C.isMossdeepGymWarp and (C.isMossdeepGymWarp(beh) or C.isLavaridgeB1FWarp(beh)) then return "pad" end
  end
  return "step"
end

-- Auto-walk's last cell of a walk to a standing warp: the direction to
-- hold there (nil when stepping on is enough).
function View:pressDirection(x, y)
  return self:standingWarp(x, y)
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
    -- pokeemerald/include/constants/map_types.h: MAP_TYPE_UNDERWATER, moved through
    -- as water with no Surf to start (Dive.isUnderwaterMap)
    underwater = tonumber(def.mapType) == 5,
    widthCells = layout.width, heightCells = layout.height,
    warpIndex = {}, warpCells = {}, kindCache = {},
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

-- ------------------------------------------------------------ load state

-- A planned map as it would be once its load scripts ran.  The layout of
-- a map the player is not on is the one the ROM stores; its transition and
-- load scripts may swap the whole layout (Seafoam B3F and B4F calm their
-- currents with setmaplayoutindex) or set metatiles by flag (Pokemon
-- Mansion gates, Silph Co. doors).  Scripts.loadState reads what they
-- would do; the view here reads that on top of the layout's own base
-- cells (not the overrides a past visit left behind).  A map whose load
-- scripts cannot be read keeps the plain planned view.

local function lazyFlags()
  local Space = loaded("src.core.game3.scripting.space")
  local Flags = loaded("src.core.game3.scripting.flags")
  if not (Space and Space.store and Flags) then return nil, nil end
  local function flag(id)
    -- a planned "what if this switch were flipped" (Navigation:remoteSwitch)
    local supposed = World.supposedFlags and World.supposedFlags[id]
    if supposed ~= nil then return supposed end
    return call(Flags.getFlag, Space.store, nil, id) == true
  end
  local function var(id) return tonumber(call(Flags.getVar, Space.store, nil, id)) or 0 end
  return flag, var
end

-- An alternate layout (setmaplayoutindex) as upstream bakes it for FireRed:
-- native/layouts/alt_<id>.mid in the extracted data (scripting/ops_a.lua
-- set_map_layout reads the same file).  Decoded once per id; nil when it
-- is not there.
local alternates = {}
World.alternateReader = nil -- tests: function(id) -> { width, height, cells }
function World.alternateLayout(layoutId)
  if alternates[layoutId] ~= nil then return alternates[layoutId] or nil end
  local decoded
  if World.alternateReader then
    decoded = World.alternateReader(layoutId)
  else
    local ok, value = pcall(function()
      local Extract = require("src.import.gba.extract_island1")
      local Dataset = require("src.core.game3.dataset")
      local root = Extract.NATIVE_ROOT or ((Extract.CACHE_ROOT or "data/generated/gba") .. "/native")
      local blob = Dataset.cache():read(root .. "/layouts/alt_" .. layoutId .. ".mid")
      return blob and require("src.import.gba.native_pack").decodeMidLayout(blob) or nil
    end)
    decoded = ok and value or nil
  end
  alternates[layoutId] = decoded or false
  return decoded
end

local function loadedLayout(def, state, alternate)
  local base = def.midLayout
  local width = base.width
  local native = type(base.cells) == "table" and type(base.overrides) == "table"
  local pair = def.pair or base.pair
  local Interaction = lazy("src.core.game3.scripting.interaction_scripts")
  local ScriptColl = lazy("src.core.game3.scripting.collision")
  local layout = setmetatable({ _revision = 0 }, { __index = base })
  local function cell(x, y)
    if x < 0 or y < 0 or x >= base.width or y >= base.height then return nil end
    local set = state.cells[y * 1024 + x]
    if set then
      if set.coll == nil then
        local beh = Interaction and Interaction.behaviors and Interaction.behaviors[pair]
          and Interaction.behaviors[pair][set.mid]
        local coll = 0x00
        if set.impassable then
          coll = 0x07
        elseif beh ~= nil and ScriptColl and ScriptColl.fromCell then
          local ok, value = pcall(ScriptColl.fromCell, set.mid, 0, beh, def.kind)
          coll = ok and value or 0x00
        end
        set.coll = coll
      end
      return set.mid, set.coll, nil
    end
    local alt = alternate and alternate.cells[y * width + x + 1]
    if alt then return alt.mid, alt.coll, alt.elev end
    if native then
      local own = base.cells[y * width + x + 1]
      if own then return own.mid, own.coll, own.elev end
    end
    return nil
  end
  function layout:midAt(x, y)
    local mid = cell(x, y)
    if mid ~= nil then return mid end
    return base:midAt(x, y)
  end
  function layout:collAt(x, y)
    local _, coll = cell(x, y)
    if coll ~= nil then return coll end
    return base:collAt(x, y)
  end
  function layout:elevAt(x, y)
    local _, _, elev = cell(x, y)
    if elev ~= nil then return elev end
    if native and x >= 0 and y >= 0 and x < base.width and y < base.height then
      local own = base.cells[y * width + x + 1]
      if own then return own.elev end
    end
    return base:elevAt(x, y)
  end
  return layout
end

local loadedViews = setmetatable({}, { __mode = "k" })

-- The planned view of `def` with its load scripts' effect, or the plain
-- planned view when they cannot be read (or change nothing).
function World.loadedView(game, def)
  if type(def) ~= "table" or not def.midLayout then return World.plannedView(game, def) end
  local Scripts = lazy("src.access.nav.gen3.Scripts")
  local flag, var = lazyFlags()
  local state = Scripts and Scripts.loadState(def, flag, var) or nil
  if not state then return World.plannedView(game, def) end
  if next(state.cells) == nil and not state.layoutIndex then
    -- nothing to apply; but what a past visit left on the layout (gates a
    -- switch has since moved back) no longer holds
    local overrides = def.midLayout.overrides
    if type(overrides) ~= "table" or next(overrides) == nil then return World.plannedView(game, def) end
  end
  local alternate
  if state.layoutIndex then
    alternate = World.alternateLayout(state.layoutIndex)
    if not (alternate and alternate.width == def.midLayout.width
            and alternate.height == def.midLayout.height) then
      return World.plannedView(game, def)
    end
  end
  local cached = loadedViews[def]
  if cached and cached.key == state.key then return cached.view end
  local shadow = setmetatable({ midLayout = loadedLayout(def, state, alternate) }, { __index = def })
  local view = newView(game, shadow, def.id, false)
  view.loadState = state
  loadedViews[def] = { key = state.key, view = view }
  return view
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
    if key == "underwater" then return Player.underwater == true end
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
