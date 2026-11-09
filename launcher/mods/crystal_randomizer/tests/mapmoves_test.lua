-- luajit launcher/mods/crystal_randomizer/tests/mapmoves_test.lua   (from the repository root)
--
-- mapmoves against the REAL Gen 2 World methods (src/world/gen2/World.lua is
-- loaded and its class wrapped), on a small hand-made map table, with a
-- stubbed placement and the warps rewritten the way `maps` rewrites them:
--   1. vanilla: no placement, nothing wrapped, the engine's own answers;
--   2. a Pokémon Center door moved onto a route: blackout and Teleport land on
--      that door, from this session's memory, from save.backupWarp after a
--      reload, and from the route's moved center door when both are gone;
--   3. a center door moved within a town: the door used, then the town's own
--      spawn when nothing remembers the door;
--   4. Escape Rope and Dig: the banked door, ahead of lastOutdoor; nil outside
--      caves; the vanilla answer when the bank is not an outdoor door;
--   5. the 0xff warps (center upstairs, elevator) and Fly untouched;
--   6. switching to a vanilla save puts every method back, and forgets.
package.path = "./?.lua;./?/init.lua;" .. package.path
local World = require("src.world.gen2.World")
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Moves = dofile("launcher/mods/crystal_randomizer/modules/mapmoves.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
  return cond
end
local function eq(a, b, msg) return ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ORIGINAL = {}
for _, name in ipairs(Moves.WRAPPED) do ORIGINAL[name] = World[name] end
local FLY, RESOLVE = World.flyTo, World.resolveWarp

-- ---------------------------------------------------------------- the maps
local function w(x, y, destMap, destWarp) return { x = x, y = y, destMap = destMap, destWarp = destWarp } end
local function mapsTable()
  local maps = {
    TOWN_A = { environment = "TOWN", width = 10, height = 10, tileset = "TILESET_JOHTO",
      warps = { w(5, 5, "CENTER_A", 1), w(8, 5, "HOUSE_A", 1), w(2, 2, "STORE_1F", 1) } },
    ROUTE_B = { environment = "ROUTE", width = 10, height = 10, tileset = "TILESET_JOHTO",
      warps = { w(7, 7, "CAVE_C", 1), w(3, 3, "HOUSE_B", 1) } },
    CENTER_A = { environment = "INDOOR", width = 5, height = 4, tileset = "TILESET_POKECENTER",
      warps = { w(3, 7, "TOWN_A", 1), w(4, 7, "TOWN_A", 1), w(0, 7, "CENTER_2F", 1) } },
    CENTER_2F = { environment = "INDOOR", width = 5, height = 4, tileset = "TILESET_POKECENTER",
      warps = { w(0, 7, "CENTER_2F", 0xff) } },
    HOUSE_A = { environment = "INDOOR", width = 4, height = 4, tileset = "TILESET_HOUSE",
      warps = { w(2, 7, "TOWN_A", 2) } },
    HOUSE_B = { environment = "INDOOR", width = 4, height = 4, tileset = "TILESET_HOUSE",
      warps = { w(2, 7, "ROUTE_B", 2) } },
    CAVE_C = { environment = "CAVE", width = 10, height = 10, tileset = "TILESET_CAVE",
      warps = { w(4, 9, "ROUTE_B", 1) } },
    STORE_1F = { environment = "INDOOR", width = 8, height = 4, tileset = "TILESET_MART",
      warps = { w(2, 7, "TOWN_A", 3), w(6, 0, "ELEVATOR", 1) } },
    STORE_2F = { environment = "INDOOR", width = 8, height = 4, tileset = "TILESET_MART",
      warps = { w(6, 0, "ELEVATOR", 1) } },
    ELEVATOR = { environment = "INDOOR", width = 2, height = 2, tileset = "TILESET_MART",
      warps = { w(1, 3, "STORE_1F", 0xff) } },
    MOUNT_MOON_SQUARE = { environment = "ROUTE", width = 10, height = 10, tileset = "TILESET_CAVE",
      warps = { w(1, 1, "CAVE_C", 1) } },
  }
  for id, def in pairs(maps) do def.id = id end
  return maps
end
local SPAWNS = { SPAWN_A = { map = "TOWN_A", x = 5, y = 6 } }

-- What `maps` does for a swap of doors A and B: each outdoor warp takes the
-- other's destination, and the explicit exits inside follow.  Returns undo.
local function swap(maps, a, b)
  local undo = {}
  local function set(t, k, v) undo[#undo + 1] = { t, k, t[k] }; t[k] = v end
  local am, ai = a:match("^(.-):(%d+)$"); local bm, bi = b:match("^(.-):(%d+)$")
  ai, bi = tonumber(ai), tonumber(bi)
  local wa, wb = maps[am].warps[ai], maps[bm].warps[bi]
  local da, db = { wa.destMap, wa.destWarp }, { wb.destMap, wb.destWarp }
  local function exitsOf(destMap, map, index)
    local list = {}
    for _, e in ipairs(maps[destMap].warps) do
      if e.destMap == map and e.destWarp == index then list[#list + 1] = e end
    end
    return list
  end
  local exitsA, exitsB = exitsOf(da[1], am, ai), exitsOf(db[1], bm, bi)
  set(wa, "destMap", db[1]); set(wa, "destWarp", db[2])
  set(wb, "destMap", da[1]); set(wb, "destWarp", da[2])
  for _, e in ipairs(exitsB) do set(e, "destMap", am); set(e, "destWarp", ai) end
  for _, e in ipairs(exitsA) do set(e, "destMap", bm); set(e, "destWarp", bi) end
  return function() for i = #undo, 1, -1 do local u = undo[i]; u[1][u[2]] = u[3] end end
end

-- A World with only what these methods read, on map `mapId`.
local function newWorld(maps, mapId, save)
  local world = setmetatable({
    maps = maps, landmarks = { spawns = SPAWNS },
    game = { save = save or {}, data = {} },
  }, World)
  world.map = { id = mapId, def = maps[mapId] }
  world.landed = {}
  world.setMap = function(self, id, x, y, facing)
    self.landed[#self.landed + 1] = { map = id, x = x, y = y }
    self.map = { id = id, def = self.maps[id] }
    return true
  end
  return world
end

-- World:takeWarp's bookkeeping, in its order: setMap (whose
-- updateWhiteoutSpawn reads the map being left), then recordWarpBackup.
local function walk(world, index)
  local from = world.map.id
  local warp = world.maps[from].warps[index]
  local destMap, destWarp = world:resolveWarp(warp)
  local arrival = world.maps[destMap].warps[destWarp]
  world:updateWhiteoutSpawn(world.maps[destMap], destMap)
  world.map = { id = destMap, def = world.maps[destMap] }
  world:recordWarpBackup(from, index, arrival, destMap)
  return destMap, destWarp
end

local function landing(world)
  local here = world.map
  world.landed = {}
  world:warpToSpawn()
  world.map = here  -- probes only: the player stays put
  local at = world.landed[1]
  return at and (at.map .. " " .. at.x .. "," .. at.y) or "nowhere"
end

local ctx = Fake.new({ seed = "mapmoves", options = { maps = "houses" } })
Moves.install({}, ctx)
local function switch(placement)
  ctx.shared = {}
  if placement then ctx.shared.maps = { placement = placement, report = {} } end
  ctx.setActive(placement ~= nil)
end

-- ----------------------------------------------------------- 1. vanilla
do
  switch(nil)
  for _, name in ipairs(Moves.WRAPPED) do eq(World[name], ORIGINAL[name], "vanilla: " .. name .. " is the engine's") end
  local maps = mapsTable()
  local world = newWorld(maps, "TOWN_A")
  walk(world, 1)
  eq(world.map.id, "CENTER_A", "vanilla: TOWN_A door 1 is the center")
  eq(world.game.save.blackoutMap, "TOWN_A", "vanilla: blackout map is the town")
  eq(landing(world), "TOWN_A 5,6", "vanilla: blackout lands on the town's spawn")
  local cave = newWorld(maps, "ROUTE_B")
  walk(cave, 1)
  eq(cave.map.id, "CAVE_C", "vanilla: into the cave")
  cave.lastOutdoor = { id = "TOWN_A", x = 1, y = 1 }
  local id, warp = cave:escapeRopeTarget()
  eq(id .. " " .. warp.x .. "," .. warp.y, "TOWN_A 1,1", "vanilla: the rope prefers lastOutdoor")
end

-- ------------------------------------- 2. a center door moved onto a route
local placement2 = { ["TOWN_A:1"] = "ROUTE_B:2", ["ROUTE_B:2"] = "TOWN_A:1" }
do
  local maps = mapsTable()
  local undo = swap(maps, "TOWN_A:1", "ROUTE_B:2")
  -- the engine alone, on the rewritten warps: the failure this module fixes
  switch(nil)
  local raw = newWorld(maps, "ROUTE_B")
  walk(raw, 2)
  eq(raw.map.id, "CENTER_A", "rewritten: ROUTE_B door 2 leads into the center")
  eq(raw.game.save.blackoutMap, "ROUTE_B", "rewritten: blackout map is the route")
  eq(landing(raw), "ROUTE_B 7,7", "unwrapped: a blackout lands on the route's first warp (the cave mouth)")

  switch(placement2)
  ok(Moves.isAttached(World), "active: attached")
  local world = newWorld(maps, "ROUTE_B")
  walk(world, 2)
  eq(landing(world), "ROUTE_B 3,3", "active: blackout lands on the door into the center")
  -- Teleport: TeleportFunction runs the same warpToSpawn
  world.showText = function(_, _, done) done() end
  world.setNickname, world.playSfxNamed, world.applyPlayerState = function() end, function() end, function() end
  world.runMapSetup = function(_, _, load) return load() end
  world.landed = {}
  local here = world.map
  world:runTeleport({ text = "x" })
  world.map = here
  eq(world.landed[1] and (world.landed[1].map .. " " .. world.landed[1].x .. "," .. world.landed[1].y), "ROUTE_B 3,3",
    "active: Teleport lands on the door into the center")
  -- upstairs and back: the 0xff stairs return to the 1F, exits to the route
  walk(world, 3)
  eq(world.map.id, "CENTER_2F", "active: upstairs")
  local down = walk(world, 1)
  eq(down, "CENTER_A", "active: the shared upstairs leads back into this center")
  local out, outWarp = walk(world, 1)
  eq(out .. ":" .. outWarp, "ROUTE_B:2", "active: the center lets out at the moved door")
  -- a reload: the session memory is gone, save.backupWarp still has the door
  walk(world, 2)  -- back into the center: backupWarp = ROUTE_B:2
  Moves.forget()
  eq(world.backupWarp.map .. ":" .. world.backupWarp.warp, "ROUTE_B:2", "reload: backupWarp names the door")
  eq(landing(world), "ROUTE_B 3,3", "reload: blackout lands on the door from backupWarp")
  -- the bank moves on (the player walks into the cave): the route's moved center door
  world.map = { id = "ROUTE_B", def = maps.ROUTE_B }
  walk(world, 1)
  Moves.forget()
  eq(world.backupWarp.map .. ":" .. world.backupWarp.warp, "ROUTE_B:1", "cave: backupWarp is the cave door")
  eq(landing(world), "ROUTE_B 3,3", "nothing remembered: the route's moved center door")
  -- Escape Rope and Dig from the cave: the door came in by
  world.lastOutdoor = { id = "TOWN_A", x = 1, y = 1 }
  local id, warp = world:escapeRopeTarget()
  eq(id .. " " .. warp.x .. "," .. warp.y, "ROUTE_B 7,7", "active: the rope leads out the cave door, not lastOutdoor")
  -- blackoutmod onto a map with no center door at all keeps vanilla
  world.game.save.blackoutMap = "CAVE_C"
  eq(Moves.centerLanding(world, placement2, nil), nil, "blackoutmod elsewhere: vanilla")
  undo()
end

-- ------------------------------------- 3. a center door moved within a town
local placement3 = { ["TOWN_A:1"] = "TOWN_A:2", ["TOWN_A:2"] = "TOWN_A:1" }
do
  local maps = mapsTable()
  local undo = swap(maps, "TOWN_A:1", "TOWN_A:2")
  switch(placement3)
  local world = newWorld(maps, "TOWN_A")
  walk(world, 2)
  eq(world.map.id, "CENTER_A", "town: door 2 leads into the center")
  eq(landing(world), "TOWN_A 8,5", "town: blackout lands on the door used, not the old spawn")
  world.map = { id = "TOWN_A", def = maps.TOWN_A }
  walk(world, 3)  -- the store: backupWarp moves on
  Moves.forget()
  eq(landing(world), "TOWN_A 5,6", "town, nothing remembered: the town's own spawn")
  undo()
end

-- ---------------------------------------------------- 4. Escape Rope and Dig
do
  local maps = mapsTable()
  switch(placement2)
  local world = newWorld(maps, "TOWN_A")
  eq(world:escapeRopeTarget(), nil, "rope: refused outside a cave")
  world.map = { id = "CAVE_C", def = maps.CAVE_C }
  world.backupWarp = { map = "CENTER_A", warp = 3 }
  local id = world:escapeRopeTarget()
  eq(id, "CENTER_A", "rope: a bank that is not an outdoor door keeps the vanilla answer")
  world.backupWarp = { map = "MOUNT_MOON_SQUARE", warp = 1 }
  world.lastOutdoor = { id = "TOWN_A", x = 1, y = 1 }
  eq((world:escapeRopeTarget()), "TOWN_A", "rope: an excluded square keeps the vanilla answer")
  world.backupWarp = { map = "ROUTE_B", warp = 1 }
  -- Dig's FieldMoves check reads the same method (World:fieldContext's canEscapeRope)
  eq((world:escapeRopeTarget()), "ROUTE_B", "rope and Dig: the banked outdoor door, ahead of lastOutdoor")
end

-- --------------------------------------- 5. 0xff warps, elevator, Fly untouched
do
  local maps = mapsTable()
  switch(placement2)
  eq(World.flyTo, FLY, "Fly: flyTo is not wrapped")
  eq(World.resolveWarp, RESOLVE, "0xff: resolveWarp is not wrapped")
  local world = newWorld(maps, "STORE_1F")
  walk(world, 2)
  eq(world.backupWarp.map .. ":" .. world.backupWarp.warp, "STORE_1F:2", "elevator: entering banks the floor")
  world.backupWarp = { map = "STORE_2F", warp = 1 }  -- Elevator_GoToFloor's write
  local dest = walk(world, 1)
  eq(dest, "STORE_2F", "elevator: the 0xff door leads to the floor chosen")
end

-- ------------------------------------------- 6. back to vanilla, and stacking
do
  switch(placement2)
  local world = newWorld(mapsTable(), "TOWN_A")
  walk(world, 1)
  ok(Moves.seenDoor(world) ~= nil, "switch: a door was noted")
  switch(nil)
  eq(Moves.seenDoor(world), nil, "switch: the note is forgotten")
  for _, name in ipairs(Moves.WRAPPED) do eq(World[name], ORIGINAL[name], "switch: " .. name .. " put back") end
  ok(not Moves.isAttached(), "switch: detached")
  -- another mod wraps on top while we are attached: ours stays below, inert
  switch(placement2)
  local ours = World.healPoint
  local theirs = function(self, ...) return ours(self, ...) end
  World.healPoint = theirs
  switch(nil)
  eq(World.healPoint, theirs, "stacked: another mod's wrapper is left in place")
  local maps = mapsTable()
  local undo = swap(maps, "TOWN_A:1", "ROUTE_B:2")
  local raw = newWorld(maps, "ROUTE_B")
  walk(raw, 2)
  eq(landing(raw), "ROUTE_B 7,7", "stacked: inactive, ours passes straight through")
  undo()
  World.healPoint = ORIGINAL.healPoint
end

print(("mapmoves: %d checks, %d failures"):format(checks, failures))
if failures > 0 then os.exit(1) end
