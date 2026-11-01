-- Reused from the old Pocket Accessibility project
-- (src/accessibility/gen2/TerrainSemantics.lua at commit 71cdd419e, upstream
-- v0.3.32) under decision 20; adapted for v0.3.98.  Read-only.

-- Gold, Silver and Crystal terrain classification.  The cell's COLL_* byte
-- (src/world/gen2/Permissions.lua) is authoritative; feeding these bytes
-- through Gen 1's tile tables would silently misclassify overlapping
-- numbers.  Mod-authored terrain metadata is resolved through the shared
-- boundary in ../TerrainSemantics.lua with this generation's vocabulary.

local Permissions = require("src.world.gen2.Permissions")
local AuthoredTerrain = require("src.access.nav.TerrainSemantics")

local Terrain = { SCHEMA = 1 }

local PROFILE = {
  default = { label = "path", cue = "default" },
  grass = { label = "tall grass", cue = "grass" },
  water = { label = "water", cue = "water" },
  ice = { label = "ice", cue = "ice" },
  current = { label = "water current", cue = "current", hazard = true },
  waterfall = { label = "waterfall", cue = "waterfall", hazard = true },
  whirlpool = { label = "whirlpool", cue = "whirlpool", hazard = true },
  cut_tree = { label = "cuttable tree", cue = "bush" },
  headbutt_tree = { label = "headbutt tree", cue = "bush" },
  ledge = { label = "ledge", cue = "ledge" },
  boulder = { label = "boulder", cue = "boulder" },
  counter = { label = "counter", cue = "wall" },
  door = { label = "door", cue = "door" },
  staircase = { label = "staircase", cue = "stair" },
  stairs_up = { label = "stairs up", cue = "stair_up" },
  stairs_down = { label = "stairs down", cue = "stair_down" },
  cave = { label = "cave entrance", cue = "door" },
  ladder = { label = "ladder", cue = "stair" },
  warp_panel = { label = "warp panel", cue = "door" },
  hole = { label = "hole", cue = "hole", hazard = true },
  wall = { label = "wall", cue = "wall" },
  unknown = { label = "unknown terrain", cue = "default" },
}

-- The authored-record vocabulary is generation-specific even though the
-- metadata lookup and validation boundary is shared.  In particular a Gen 2
-- current must not become Gen 1's directional_floor alias.
local AUTHORED = {
  profiles = PROFILE,
  aliases = {
    tall_grass = "grass", cuttable_bush = "cut_tree",
    cuttable_tree = "cut_tree", tree = "cut_tree",
    path = "default", ground = "default",
    stair_up = "stairs_up", up_stairs = "stairs_up",
    stair_down = "stairs_down", down_stairs = "stairs_down",
    blocked = "wall", walkable = "default",
  },
}

local function entityAt(world, options, x, y)
  local entities = type(options) == "table" and options.entities or nil
  if type(entities) == "table" then
    for _, npc in ipairs(entities) do
      if type(npc) == "table" and npc ~= (world and world.player)
         and npc.cellX == x and npc.cellY == y then
        return npc
      end
    end
    return nil
  end
  if type(world) ~= "table" then return nil end
  local native = world.native or world
  if type(native.npcAt) == "function" then
    local ok, npc = pcall(native.npcAt, native, x, y)
    if ok then return npc end
  end
  for _, npc in ipairs(world.npcs or {}) do
    if npc.cellX == x and npc.cellY == y then return npc end
  end
  return nil
end

-- SPRITEMOVEDATA_STRENGTH_BOULDER, the engine's own test (World.isStrengthBoulder,
-- CmdQueue.BOULDER_MOVEDATA).  Not the sprite: Ice Path B2F (Mahogany side)
-- draws four unpushable decorations with SPRITE_BOULDER (old project's
-- cartridge check), and a mod's `pushable` flag is honoured either way.
local function isBoulder(npc)
  local def = type(npc) == "table" and npc.def or nil
  if type(def) ~= "table" then return false end
  if def.pushable ~= nil then return def.pushable == true end
  return def.movement == 0x19
end

-- Warp collision kinds (constants/collision_constants.asm): Gen 2 names its
-- ladders ($72) outright, unlike Gen 1.
local PIT = { [0x60] = true, [0x68] = true }
local STAIRCASE = { [0x7a] = true, [0x73] = true }
local CAVE = { [0x7b] = true, [0x74] = true }
local WARP_PANEL = { [0x7c] = true }
local LADDER = { [0x72] = true }

-- A floor number from a map id suffix (_2F, _B1F), for telling stairs up from
-- stairs down without hand tables.
local function floorOf(id)
  if type(id) ~= "string" then return nil end
  local below = id:match("_B(%d+)F$")
  if below then return -tonumber(below) end
  local above = id:match("_(%d+)F$")
  return above and tonumber(above) or nil
end

local function warpKind(map, coll, x, y)
  if CAVE[coll] then return "cave" end
  if WARP_PANEL[coll] then return "warp_panel" end
  if LADDER[coll] then return "ladder" end
  if not STAIRCASE[coll] then return "door" end
  local okWarp, warp = pcall(map.warpAt, map, x, y)
  local def = okWarp and warp and warp.def or nil
  local here = floorOf(map.id or (type(map.def) == "table" and map.def.id))
  local there = floorOf(def and def.destMap)
  if here and there and there ~= here then
    return there > here and "stairs_up" or "stairs_down"
  end
  return "staircase"
end

local LEDGE_ORDER = { "down", "left", "right", "up" }

local function ledgeDescription(facings)
  local words = {}
  for _, dir in ipairs(LEDGE_ORDER) do
    if facings and facings[dir] then words[#words + 1] = dir end
  end
  if #words == 0 then return nil end
  return "Jump " .. table.concat(words, " or ")
end

local function record(kind, x, y, coll, passable, extra)
  local profile = PROFILE[kind] or PROFILE.unknown
  local out = {
    schema = Terrain.SCHEMA, x = x, y = y, tile = coll, kind = kind,
    label = profile.label, cue = profile.cue, hazard = profile.hazard == true,
    passable = passable, confidence = "native", source = "gen2.COLL",
    features = {}, diagnostics = {},
  }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

local function classifyNative(source, x, y, options)
  options = type(options) == "table" and options or {}
  local world = type(source) == "table" and source.map and source or nil
  local map = world and world.map or source
  if type(map) ~= "table" or type(map.inBounds) ~= "function"
     or type(map.cellCollision) ~= "function" or not map:inBounds(x, y) then
    return record("wall", x, y, nil, false, { label = "map edge" })
  end

  local coll = map:cellCollision(x, y)
  local npc = entityAt(world, options, x, y)
  if isBoulder(npc) then
    return record("boulder", x, y, coll, false,
      { entity = npc, features = { boulder = true } })
  end
  if Permissions.isIce(coll) then return record("ice", x, y, coll, true) end
  if Permissions.isWhirlpool(coll) then return record("whirlpool", x, y, coll, false) end
  if Permissions.isWaterfall(coll) then
    return record("waterfall", x, y, coll, false,
      { direction = Permissions.currentDirection(coll) })
  end
  local current = Permissions.currentDirection(coll)
  if current then return record("current", x, y, coll, true, { direction = current }) end
  if Permissions.isCutTree(coll) then return record("cut_tree", x, y, coll, false) end
  if Permissions.isHeadbuttTree(coll) then
    return record("headbutt_tree", x, y, coll, Permissions.isWalkable(coll))
  end
  if Permissions.isLedge(coll) then
    local facings = Permissions.ledgeFacings(coll)
    return record("ledge", x, y, coll, true,
      { facings = facings, description = ledgeDescription(facings) })
  end
  if Permissions.isCounter(coll) then return record("counter", x, y, coll, false) end
  if Permissions.isWarpCollision(coll) then
    local okWarp, warp = pcall(map.warpAt, map, x, y)
    local hasWarp = okWarp and warp ~= nil
    local kind = PIT[coll] and "hole" or warpKind(map, coll, x, y)
    return record(kind, x, y, coll, true, { features = { warp = hasWarp } })
  end
  if Permissions.isGrass(coll) then return record("grass", x, y, coll, true) end
  if Permissions.isWater(coll) then
    local surfing = options.surfing
    if surfing == nil and world then
      surfing = world.surfing == true
        or (type(world.player) == "table" and world.player.surfing == true)
    end
    return record("water", x, y, coll, surfing == true)
  end
  -- The engine's encounter set includes values its narrower visual grass set
  -- leaves out; speech follows the encounter gate.
  if Permissions.isWalkable(coll) and Permissions.isEncounterCollision(coll) then
    return record("grass", x, y, coll, true)
  end
  if Permissions.isWalkable(coll) then return record("default", x, y, coll, true) end
  if Permissions.isWall(coll) then return record("wall", x, y, coll, false) end
  return record("unknown", x, y, coll, options.passable)
end

function Terrain.classify(source, x, y, options)
  options = type(options) == "table" and options or {}
  local result = classifyNative(source, x, y, options)
  -- No metadata can turn an out-of-bounds cell into a destination; never run
  -- Gen 1's tile classifier on this byte.
  if result.tile == nil then return result end

  local world = type(source) == "table" and source.map and source or nil
  local map = world and world.map or source
  local entity = result.entity or entityAt(world, options, x, y)
  local warp
  if type(map.warpAt) == "function" then
    local ok, value = pcall(map.warpAt, map, x, y)
    if ok then warp = value end
  end
  local def = type(map.def) == "table" and map.def or nil
  local tileset = type(map.tileset) == "table" and map.tileset or nil
  local context = {
    schema = Terrain.SCHEMA, map = map, overworld = world,
    data = options.data, field = options.field,
    mapId = map.id or (def and def.id),
    tilesetId = tileset and tileset.id or (def and def.tileset),
    x = x, y = y, tile = result.tile, collision = result.tile,
    entity = entity, warp = warp,
    player = options.player or (world and world.player),
  }
  local authored = AuthoredTerrain.resolveAuthored(result, context,
    { map = map, def = def, tileset = tileset, entity = entity, warp = warp },
    options, AUTHORED)
  if not authored then return result end

  result.kind, result.label, result.description = authored.kind,
    authored.label, authored.description
  result.cue, result.direction = authored.cue, authored.direction
  result.variant, result.semanticId = authored.variant, authored.semanticId
  result.hazard = authored.hazard == true
  result.source, result.confidence = authored.source, authored.confidence
  if authored.passable ~= nil and type(options.passable) ~= "boolean" then
    result.passable = authored.passable
    result.passabilitySource = "accessibilityTerrain"
  end
  if result.passable == true then
    result.traversal, result.traversalCue = "pass", "pass"
  elseif result.passable == false then
    result.traversal, result.traversalCue = "wall", "wall"
  else
    result.traversal, result.traversalCue = "unknown", nil
  end
  return result
end

-- The collision tiles an A press reads by themselves (World.lua
-- TILE_COLLISION_STD_SCRIPTS): what the object list calls them.
Terrain.STD_TILES = {
  [0x91] = "Bookshelf", [0x93] = "PC", [0x94] = "Radio",
  [0x95] = "Town Map", [0x96] = "Mart Shelf", [0x97] = "TV",
  [0x9d] = "Window", [0x9f] = "Incense Burner",
}

Terrain.isBoulder = isBoulder
Terrain.floorOf = floorOf
Terrain.PROFILE = PROFILE

return Terrain
