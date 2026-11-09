-- Crystal randomizer: the other ways of moving, made to agree with shuffled
-- doors (MAPS.md, the `mapmoves` piece).  This module has no questions.
--
-- `maps` rewrites the warps themselves (data.gen2Maps[map].warps) and publishes
-- ctx.shared.maps.placement[doorId] = doorId', door ids "MAP:warpNumber".  Most
-- movement already follows from those rewritten warps; this module corrects
-- only what does not, by wrapping three World methods on the class
-- (src/world/gen2/World.lua), so every World the game builds sees them.  The
-- wrappers are put on while a placement is active and taken off again when the
-- save switches to one without (or are inert pass-throughs, if another mod has
-- wrapped the same method on top of them in the meantime).
--
-- Each way of moving, and what it needs (checked against World.lua, Vm.lua,
-- UnionCenter2F.lua, UnionSafety.lua and the imported Crystal data):
--
--   Escape Rope and Dig.  World:escapeRopeTarget answers lastOutdoor first,
--   then the banked triple backupWarp.  World:recordWarpBackup writes that
--   triple every time the player walks from a ROUTE or TOWN map into any
--   indoor map, and it writes the OUTDOOR side: the very door used.  Outdoor
--   maps are never shuffled, so that door still stands where it did, and it is
--   a spot the player walked to.  lastOutdoor is the Gen 1 memory, set in Gen 2
--   only by rescues and mod scripts, and it follows no door.  So while a
--   placement is active the rope and Dig take the banked door first when it is
--   a door on an outdoor map; otherwise the vanilla answer stands.
--   (wrapped: escapeRopeTarget)
--
--   Blacking out and Teleport.  Both land through World:healPoint.  Walking
--   into a Pokémon Center from an outdoor map stores the outdoor map in
--   save.blackoutMap (World:updateWhiteoutSpawn), and healPoint turns that map
--   into the SPAWN_* row of that map.  With the center door shuffled the map
--   left may be a route with no row at all, where vanilla falls back to the
--   route's FIRST warp: an arbitrary door, possibly in a part of the route the
--   player cannot leave.  Or it is a town whose row stands outside a door that
--   now leads elsewhere.  So while a placement is active a blackout lands on
--   the moved door that leads into the center the player used, the spot
--   walking out of that center puts them on, read from (in order)
--     1. the door this session saw them walk through into a center from the
--        blackout map (noted by the recordWarpBackup wrapper);
--     2. save.backupWarp, when it still names such a door (it does until the
--        player next walks indoors, and it rides the save);
--     3. a town's own SPAWN_* row, as vanilla, when the map has one;
--     4. otherwise the first moved door on that map that now leads into a
--        center (a route has no row, and vanilla's first warp is worse).
--   (wrapped: healPoint, recordWarpBackup, which only observes)
--
--   Fly.  World:flyTo lands on the town's SPAWN_* cell; towns are outdoor maps
--   and never move, so Fly reaches every town as before.  The town's center
--   door may lead elsewhere now, which is the shuffle itself.  Nothing needed.
--
--   Elevators.  Every elevator door is destWarp 0xff and resolves through
--   backupWarp, which Elevator_GoToFloor (World:openElevator) writes with the
--   floor chosen; all of it is inside one building, which the shuffle moves
--   as a whole.  Script_warpmod (World:setWarpMod) only stores save.warpMod,
--   which nothing reads, and no Crystal script runs `warpmod`.  Nothing needed.
--
--   The shared POKECENTER_2F.  Its stairs are destWarp 0xff: arriving on them
--   banks the 1F map and stairs, and leaving goes back down there.  The 1F's
--   explicit exits are what `maps` rewrites, so the stairs lead back into the
--   right center and its doors out to the door used.  The Union Room / Trade
--   Center / Colosseum return (UnionCenter2F.noteWarp, UnionSafety) remembers
--   the 1F map and its nurse, inside the center, never an outdoor door.
--   Nothing needed.
--
--   Saved positions.  save.position is a cell, not a door.  save.backupWarp
--   names an outdoor door or a 1F staircase, both still valid.  save.warpMod
--   is unread.  save.blackoutMap is handled above.  Nothing else needed.
--
--   Bill's PC and the Day-Care.  Neither moves the player or remembers a
--   door.  Nothing needed.
--
--   Scripted and event warps.  Script_warp / warpfacing land on fixed cells:
--   in Crystal those are OLIVINE_PORT, VERMILION_PORT, NEW_BARK_TOWN,
--   ECRUTEAK_CITY and NATIONAL_PARK_BUG_CONTEST (outdoor maps, never moved),
--   and KURTS_HOUSE, ROUTE_36_NATIONAL_PARK_GATE, FAST_SHIP_1F, HALL_OF_FAME
--   and BATTLE_TOWER_1F (inside complexes, whose exits `maps` points at the
--   doors that lead into them now).  `warpcheck` and the Magnet Train's
--   `newloadmap` take the warp under the player, rewritten or not, through
--   resolveWarp.  No scripted warp lands in a cave, so the rope's banked door
--   is never stale because of one.  Nothing this module can correct; see the
--   note on story complexes below.
--
-- Not this module's to decide, and reported instead: a scripted warp INTO a
-- complex whose doors moved lets the player out at those moved doors, which
-- may stand somewhere they have not walked to.  maprules should keep
-- KURTS_HOUSE, ROUTE_36_NATIONAL_PARK_GATE, BATTLE_TOWER_1F, the Fast Ship
-- and HALL_OF_FAME's complexes fixed (M.SCRIPTED_WARP_ROOMS lists them).

local M = { id = "mapmoves" }

M.RETURN_WARP = 0xff
M.CENTER_TILESET = "TILESET_POKECENTER"
-- CheckOutdoorMap (ROUTE or TOWN), as World:recordWarpBackup reads it
M.OUTDOOR = { ROUTE = true, TOWN = true }
-- EnterMapWarp's .SaveDigWarp exceptions: outdoor maps inside caves
M.DIG_EXCLUDED = { MOUNT_MOON_SQUARE = true, TIN_TOWER_ROOF = true }
-- Maps a Crystal script warps into directly (not through a door).
M.SCRIPTED_WARP_ROOMS = { "KURTS_HOUSE", "ROUTE_36_NATIONAL_PARK_GATE", "BATTLE_TOWER_1F",
  "FAST_SHIP_1F", "HALL_OF_FAME" }
M.WRAPPED = { "escapeRopeTarget", "healPoint", "recordWarpBackup" }

function M.doorId(mapId, warp) return tostring(mapId) .. ":" .. tostring(warp) end

-- The active placement, or nil.
function M.placementOf(ctx)
  local shared = ctx and ctx.shared
  local maps = type(shared) == "table" and shared.maps or nil
  local placement = type(maps) == "table" and maps.placement or nil
  if type(placement) ~= "table" or next(placement) == nil then return nil end
  return placement
end

-- True when door `mapId:warp` leads somewhere other than its own vanilla place.
function M.moved(placement, mapId, warp)
  local id = M.doorId(mapId, warp)
  local target = placement[id]
  return target ~= nil and target ~= id
end

-- World:updateWhiteoutSpawn's test for the map entered.
function M.isCenter(def)
  return type(def) == "table" and def.environment == "INDOOR" and def.tileset == M.CENTER_TILESET
end

local function warpOf(maps, mapId, index)
  local def = type(maps) == "table" and mapId and maps[mapId] or nil
  local warps = type(def) == "table" and def.warps or nil
  local warp = type(warps) == "table" and index and warps[index] or nil
  return type(warp) == "table" and warp or nil, def
end

-- The warp `index` on `mapId`, when it is a moved door that leads into a
-- Pokémon Center now; else nil.
function M.movedCenterDoor(maps, placement, mapId, index)
  local warp = warpOf(maps, mapId, index)
  if not warp or warp.destWarp == M.RETURN_WARP then return nil end
  if not M.moved(placement, mapId, index) then return nil end
  if not M.isCenter(maps[warp.destMap]) then return nil end
  return warp
end

-- Per World: the door the player was last seen walking through from an outdoor
-- map into a center.  Weak keys, and replaced on every save switch.
local seen = setmetatable({}, { __mode = "k" })
function M.forget() seen = setmetatable({}, { __mode = "k" }) end
function M.seenDoor(world) return seen[world] end

-- Where a blackout or Teleport lands while `placement` is active: a
-- { map, x, y } on a moved center door, or nil to keep the vanilla answer
-- `vanilla` (healPoint's own).  The order is the one in the header.
function M.centerLanding(world, placement, vanilla)
  local save = world and world.game and world.game.save
  local mapId = save and save.blackoutMap
  local maps = world and world.maps
  if not (mapId and type(maps) == "table" and maps[mapId]) then return nil end
  local function landing(index)
    local warp = M.movedCenterDoor(maps, placement, mapId, index)
    if warp then return { map = mapId, x = warp.x, y = warp.y, door = M.doorId(mapId, index) } end
  end
  local memo = seen[world]
  if memo and memo.map == mapId then
    local at = landing(memo.warp)
    if at then return at end
  end
  local backup = world.backupWarp
  if type(backup) == "table" and backup.map == mapId then
    local at = landing(backup.warp)
    if at then return at end
  end
  if type(vanilla) == "table" and vanilla.spawn and vanilla.map == mapId then return nil end
  for index in ipairs(maps[mapId].warps or {}) do
    local at = landing(index)
    if at then return at end
  end
  return nil
end

-- The door Escape Rope and Dig lead out through while `placement` is active,
-- as (mapId, warp), or nil to keep the vanilla answer.
function M.ropeDoor(world)
  local env = world and world.map and world.map.def and world.map.def.environment
  if env ~= "CAVE" and env ~= "DUNGEON" then return nil end
  local backup = world.backupWarp
  if type(backup) ~= "table" or M.DIG_EXCLUDED[backup.map] then return nil end
  local warp, def = warpOf(world.maps, backup.map, backup.warp)
  if not (warp and def and M.OUTDOOR[def.environment]) then return nil end
  return backup.map, warp
end

-- ---- wrapping the World class ----------------------------------------------

local attached = nil  -- { class = World, originals = { name = fn }, wrappers = { name = fn } }

function M.attach(World, ctx)
  if attached and attached.class == World then return true end
  if attached then M.detach() end
  if type(World) ~= "table" then return false end
  for _, name in ipairs(M.WRAPPED) do
    if type(World[name]) ~= "function" then
      if ctx and ctx.log then ctx.log("mapmoves: World has no %s; other ways of moving stay vanilla", name) end
      return false
    end
  end
  local originals, wrappers = {}, {}
  for _, name in ipairs(M.WRAPPED) do originals[name] = World[name] end

  wrappers.escapeRopeTarget = function(self, ...)
    if M.placementOf(ctx) then
      local mapId, warp = M.ropeDoor(self)
      if mapId then return mapId, warp end
    end
    return originals.escapeRopeTarget(self, ...)
  end

  wrappers.healPoint = function(self, ...)
    local vanilla = originals.healPoint(self, ...)
    local placement = M.placementOf(ctx)
    if not placement then return vanilla end
    return M.centerLanding(self, placement, vanilla) or vanilla
  end

  -- Observes only: the arguments and the result pass straight through.
  wrappers.recordWarpBackup = function(self, prevMapId, prevWarpIndex, arrivalWarp, destMapId, ...)
    local result = originals.recordWarpBackup(self, prevMapId, prevWarpIndex, arrivalWarp, destMapId, ...)
    if M.placementOf(ctx) and prevMapId and prevWarpIndex and type(self.maps) == "table" then
      local from, into = self.maps[prevMapId], destMapId and self.maps[destMapId]
      if type(from) == "table" and M.OUTDOOR[from.environment] and M.isCenter(into) then
        seen[self] = { map = prevMapId, warp = prevWarpIndex }
      end
    end
    return result
  end

  for _, name in ipairs(M.WRAPPED) do World[name] = wrappers[name] end
  attached = { class = World, originals = originals, wrappers = wrappers }
  return true
end

-- Puts back every method that is still ours.  One another mod has wrapped on
-- top of ours stays, and ours below it passes straight through once no
-- placement is active.
function M.detach()
  if not attached then return end
  local World = attached.class
  for _, name in ipairs(M.WRAPPED) do
    if World[name] == attached.wrappers[name] then World[name] = attached.originals[name] end
  end
  attached = nil
end

function M.isAttached(World) return attached ~= nil and (World == nil or attached.class == World) end

function M.install(mod, ctx)
  local World = nil
  local function worldClass()
    if World == nil then
      local ok, class = pcall(require, "src.world.gen2.World")
      World = ok and type(class) == "table" and class or false
      if not World then ctx.log("mapmoves: the Gen 2 World did not load: %s", tostring(class)) end
    end
    return World or nil
  end
  ctx.onSave(function(active)
    M.forget()
    if active and M.placementOf(ctx) then
      local class = worldClass()
      if class and M.attach(class, ctx) then
        ctx.log("mapmoves: Escape Rope, Dig, blackouts and Teleport follow the shuffled doors")
      end
    else
      M.detach()
    end
  end)
end

return M
