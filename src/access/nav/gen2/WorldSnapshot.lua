-- Reused from the old Pocket Accessibility project
-- (src/accessibility/gen2/WorldSnapshot.lua at commit 71cdd419e, upstream
-- v0.3.32) under decision 20; adapted for v0.3.98.  Read-only.

-- Gold, Silver and Crystal projected into the shared object-list vocabulary
-- (../WorldSnapshot.lua).  The live map, NPCs and definitions are never
-- changed: the projection copies what it relabels.
--
-- What the projection supplies that the shared module cannot read from a
-- Gen 2 map:
--   * signs from `bgEvents`, named "Signpost N" by the event's own ordinal
--     (Pokemon Access's naming).  A sign's script key is a ROM address
--     ("1e:6c15") and is never spoken.  Facing-only signs carry their
--     facing; if-set and if-not-set signs are listed only while the game
--     would read them.  Hidden items are not listed, as in Gen 1, which lists
--     no hidden items either.
--   * pit warps marked as holes (COLL_PIT 0x60 / 0x68 under the warp).
--   * the "return where you came from" warp (destination warp 0xFF) resolved
--     through the world's backup warp, as World:resolveWarp does; before the
--     game has recorded one the warp is named "Exit" rather than given the
--     map it names, which is the room itself.
--   * item balls named by their item (Gen 1 names item balls by item too),
--     variable sprites by the sheet the game resolved, and Kanto's Red's Mom.

local Shared = require("src.access.nav.WorldSnapshot")

local Snapshot = {}
for key, value in pairs(Shared) do Snapshot[key] = value end

local function gen2Options(opts)
  local copy = {}
  for key, value in pairs(opts or {}) do copy[key] = value end
  copy.generation = 2
  return copy
end

function Snapshot.locationName(mapOrDef, fallbackId, customName, playerName)
  return Shared.locationName(mapOrDef, fallbackId, customName, playerName, 2)
end

local PIT = { [0x60] = true, [0x68] = true }
local SIGN_FACING = { [1] = "up", [2] = "down", [3] = "right", [4] = "left" }

-- World:bgEventAt's flag test for kinds 5 (if set) and 6 (if not set), read
-- without running anything.  An event with no flag is not guessed at.
local function conditionalActive(event, world)
  local events = type(world) == "table" and world.events or nil
  if not (event.event and events and type(events.get) == "function") then return false end
  local ok, set = pcall(events.get, events, event.event)
  if not ok then return false end
  return (event.kind == 5) == (set and true or false)
end

-- A bg event standing on a bookshelf, TV or other standard tile is that
-- object (the A press runs the event instead of the tile's own script), so it
-- takes the tile's name; any other is "Signpost N".
local function projectSigns(def, world, map)
  local Terrain = require("src.access.nav.gen2.TerrainSemantics")
  local signs = {}
  for index, event in ipairs(def.bgEvents or {}) do
    local kind = event.kind or 0
    local listed = kind == 0 or SIGN_FACING[kind] ~= nil
      or ((kind == 5 or kind == 6) and conditionalActive(event, world))
    if listed then
      local tile
      if type(map) == "table" and type(map.cellCollision) == "function" then
        local ok, coll = pcall(map.cellCollision, map, event.x, event.y)
        tile = ok and Terrain.STD_TILES[coll] or nil
      end
      signs[#signs + 1] = {
        x = event.x, y = event.y,
        name = event.accessibilityLabel or tile or ("Signpost " .. index),
        accessibilityId = event.accessibilityId
          or ("bg_event:" .. tostring(def.id) .. ":" .. index),
        requiredFacing = SIGN_FACING[kind],
      }
    end
  end
  return signs
end

-- The warp's real destination when it is the 0xFF "go back" warp, or nil
-- when the game has not recorded where back is yet.
local function returnWarpDestination(world, warp)
  local backup = type(world) == "table" and world.backupWarp or nil
  local maps = type(world) == "table" and world.maps or nil
  if type(backup) == "table" and type(backup.map) == "string"
     and type(maps) == "table" and maps[backup.map] then
    return backup.map, backup.warp
  end
  return nil
end

local function projectWarps(map, def, world, holes)
  local warps = {}
  for i, warp in ipairs(def.warps or {}) do
    local marked
    local function copy()
      if marked then return marked end
      marked = {}
      for key, value in pairs(warp) do marked[key] = value end
      return marked
    end
    local ok, coll = pcall(map.cellCollision, map, warp.x, warp.y)
    if ok and PIT[coll] and warp.kind == nil then copy().kind = "hole" end
    -- a stone-table hole is its own object, named by its table row, with the
    -- puzzle's state (gen2/PuzzleAssistance.lua)
    local hole = type(holes) == "table"
      and holes[tostring(warp.x) .. "," .. tostring(warp.y)] or nil
    if hole and ok and PIT[coll] then
      copy().accessibilityTargetId = "stone_hole:" .. tostring(def.id) .. ":" .. i
      marked.accessibilityLabel = warp.accessibilityLabel or hole.label
      marked.accessibilityStateText = hole.state
    end
    if warp.destWarp == 0xff then
      local destMap, destWarp = returnWarpDestination(world, warp)
      if destMap then
        copy()
        marked.destMap, marked.destWarp = destMap, destWarp
      else
        copy().accessibilityLabel = warp.accessibilityLabel or "Exit"
        marked.unresolvedReturn = true
      end
    end
    warps[i] = marked or warp
  end
  return warps
end

local function mapProxy(map, world, opts)
  local def = type(map.def) == "table" and map.def or {}
  local projected = {}
  for key, value in pairs(def) do projected[key] = value end
  if type(map.cellCollision) == "function" then
    projected.warps = projectWarps(map, def, world, opts and opts.holeTargets)
  end
  projected.signs = projectSigns(def, world, map)
  return setmetatable({
    def = projected,
    -- a deliberate native projection: the COLL byte, never a Gen 1 tile id
    cellTile = function(_, x, y) return map:cellCollision(x, y) end,
  }, { __index = map })
end

local function nonempty(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

local function hasAuthoredLabel(record)
  if type(record) ~= "table" then return false end
  local a11y = record.accessibility
  return nonempty(record.accessibilityLabel) or nonempty(record.displayName)
    or nonempty(record.label) or (type(a11y) == "table"
      and (nonempty(a11y.label) or nonempty(a11y.role)))
end

-- The item an item ball holds: Gen 2 stores the item's index, so it is looked
-- up the way the game does (World:itemIdByIndex), never spoken as a number.
local function itemBallItem(world, def)
  local ball = type(def.itemball) == "table" and def.itemball or nil
  if not ball or ball.item == nil then return nil end
  if type(ball.item) == "string" then return ball.item end
  local native = type(world) == "table" and (world.native or world) or nil
  if native and type(native.itemIdByIndex) == "function" then
    local ok, id = pcall(native.itemIdByIndex, native, ball.item)
    if ok and type(id) == "string" then return id end
  end
  return nil
end

local function projectActor(world, actor)
  local def = actor.def
  if type(def) ~= "table" or def.owner or def.runtime == true
     or hasAuthoredLabel(actor) or hasAuthoredLabel(def) then
    return actor
  end
  local relabel = {}
  local item = def.item == nil and itemBallItem(world, def) or nil
  if item then relabel.item = item end
  -- A sprite slot number (variable sprites, decorations) names the sheet the
  -- game resolved for it.
  if type(def.sprite) ~= "string" then
    local sheet = type(actor.spriteDef) == "table" and actor.spriteDef.id or nil
    if type(sheet) == "string" then relabel.sprite = sheet end
  end
  -- The Kanto character Pokemon Access calls "[red]'s Mom"; the player's own
  -- SPRITE_MOM follows the saved Mom name in the shared module instead.
  if def.sprite == "SPRITE_REDS_MOM" then relabel.accessibilityLabel = "Red's Mom" end
  if next(relabel) == nil then return actor end
  local defCopy = setmetatable(relabel, { __index = def })
  return setmetatable({ def = defCopy }, { __index = actor })
end

local function worldProxy(world, opts)
  local projected = { map = mapProxy(world.map, world, opts) }
  local actors = {}
  local function project(actor)
    if actor == world.player or type(actor) ~= "table" then return actor end
    if not actors[actor] then actors[actor] = projectActor(world, actor) end
    return actors[actor]
  end
  for _, field in ipairs({ "npcs", "entities" }) do
    if type(world[field]) == "table" then
      local list = {}
      for i, actor in ipairs(world[field]) do list[i] = project(actor) end
      projected[field] = list
    end
  end
  return setmetatable(projected, { __index = world })
end

function Snapshot.browse(world, opts)
  return Shared.browse(worldProxy(world, opts), gen2Options(opts))
end

function Snapshot.capture(world, opts)
  return Shared.capture(worldProxy(world, opts), gen2Options(opts))
end

-- Exposed for the coordinator (cross-map labels) and tests.
Snapshot.projectWarps = projectWarps
Snapshot.projectSigns = projectSigns
Snapshot.returnWarpDestination = returnWarpDestination

return Snapshot
