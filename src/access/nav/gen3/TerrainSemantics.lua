-- FireRed terrain classification (decision 29).  Read-only.
--
-- The metatile behaviour (MB) byte is authoritative: every special mechanic
-- in FRLG (ice, currents, spinners, waterfalls, ledges, the six kinds of
-- warp, Strength buttons, furniture) is an MB value, and the COLL byte the
-- extractor derived from it is only a coarse walkability class.  COLL is the
-- fallback for walls, water and grass.  world.stepped's `tile` on Gen 3 is
-- this same MB value.
--
-- Pokemon Access's FRLG table was read for behaviour (decision 7, nothing
-- copied): it gives ice, thin ice, cracked ice, stairs, escalators,
-- currents, spinners and the stop tile their own sounds, and warns when the
-- player stands next to a ledge they could jump.

local Terrain = { SCHEMA = 1 }

local PROFILE = {
  default = { label = "path", cue = "default" },
  grass = { label = "tall grass", cue = "grass" },
  water = { label = "water", cue = "water" },
  waterfall = { label = "waterfall", cue = "waterfall", hazard = true },
  current = { label = "water current", cue = "current", hazard = true },
  ice = { label = "ice", cue = "ice" },
  thin_ice = { label = "thin ice", cue = "ice" },
  cracked_ice = { label = "cracked ice", cue = "hole", hazard = true },
  spinner = { label = "spinner", cue = "current", hazard = true },
  stop_spinner = { label = "spinner stop", cue = "pass" },
  moving_floor = { label = "moving floor", cue = "current", hazard = true },
  slope = { label = "slope", cue = "current" },
  ledge = { label = "ledge", cue = "ledge" },
  door = { label = "door", cue = "door" },
  doormat = { label = "doormat", cue = "door" },
  cave = { label = "cave entrance", cue = "door" },
  ladder = { label = "ladder", cue = "stair" },
  stairs = { label = "stairs", cue = "stair" },
  stairs_up = { label = "stairs up", cue = "stair_up" },
  stairs_down = { label = "stairs down", cue = "stair_down" },
  escalator_up = { label = "escalator up", cue = "stair_up" },
  escalator_down = { label = "escalator down", cue = "stair_down" },
  warp_panel = { label = "warp panel", cue = "door" },
  hole = { label = "hole", cue = "hole", hazard = true },
  switch = { label = "floor switch", cue = "switch" },
  counter = { label = "counter", cue = "wall" },
  boulder = { label = "boulder", cue = "boulder" },
  cut_tree = { label = "cuttable tree", cue = "bush" },
  rock = { label = "smashable rock", cue = "boulder" },
  wall = { label = "wall", cue = "wall" },
  edge = { label = "map edge", cue = "wall" },
  unknown = { label = "unknown terrain", cue = "default" },
}
Terrain.PROFILE = PROFILE

-- pokefirered include/constants/metatile_behaviors.h
local MB = {
  WATERFALL = 0x13, STRENGTH_BUTTON = 0x20, ICE = 0x23, THIN_ICE = 0x26,
  CRACKED_ICE = 0x27, COUNTER = 0x80,
  CAVE_DOOR = 0x60, LADDER = 0x61, FALL_WARP = 0x66, REGULAR_WARP = 0x67,
  WARP_DOOR = 0x69, UP_ESCALATOR = 0x6A, DOWN_ESCALATOR = 0x6B,
}
Terrain.MB = MB

local CURRENT = { [0x50] = "right", [0x51] = "left", [0x52] = "up", [0x53] = "down" }
local SPIN = { [0x54] = "right", [0x55] = "left", [0x56] = "up", [0x57] = "down" }
local WALK = { [0x40] = "right", [0x41] = "left", [0x42] = "up", [0x43] = "down" }
local SLIDE = { [0x44] = "right", [0x45] = "left", [0x46] = "up", [0x47] = "down" }
local STAIR_UP = { [0x6C] = true, [0x6D] = true }
local STAIR_DOWN = { [0x6E] = true, [0x6F] = true }
local ARROW = { [0x62] = true, [0x63] = true, [0x64] = true, [0x65] = true }
local CYCLING_SLOPE = { [0xD0] = true, [0xD1] = true }

Terrain.CURRENT, Terrain.SPIN, Terrain.WALK, Terrain.SLIDE = CURRENT, SPIN, WALK, SLIDE
Terrain.STOP_SPINNING = 0x58

-- The direction a forced-movement tile carries the player in, its kind,
-- or nil.  Ice keeps the direction of travel (nil direction, "ice").
function Terrain.forced(beh)
  if beh == nil then return nil end
  if beh == MB.ICE then return nil, "ice" end
  if CURRENT[beh] then return CURRENT[beh], "current" end
  if SPIN[beh] then return SPIN[beh], "spinner" end
  if WALK[beh] then return WALK[beh], "moving_floor" end
  if SLIDE[beh] then return SLIDE[beh], "moving_floor" end
  if beh == MB.WATERFALL then return "down", "waterfall" end
  return nil
end

local function entityAt(world, x, y)
  for _, entity in ipairs(type(world) == "table" and world.npcs or {}) do
    if type(entity) == "table" and entity.cellX == x and entity.cellY == y
       and not entity.invisible then
      return entity
    end
  end
  return nil
end

local GFX_CUT_TREE, GFX_ROCK, GFX_BOULDER = 95, 96, 97
Terrain.GFX = { ITEM_BALL = 92, CUT_TREE = GFX_CUT_TREE, ROCK = GFX_ROCK, BOULDER = GFX_BOULDER }

function Terrain.isBoulder(entity)
  local def = type(entity) == "table" and entity.def or nil
  local gfx = type(entity) == "table" and (entity.graphicsId or (def and (def.graphicsId or def.gfx))) or nil
  return tonumber(gfx) == GFX_BOULDER and entity.passable ~= true
end

local function record(kind, x, y, extra)
  local profile = PROFILE[kind] or PROFILE.unknown
  local result = {
    schema = Terrain.SCHEMA, x = x, y = y, kind = kind,
    label = profile.label, cue = profile.cue, hazard = profile.hazard == true,
    confidence = "native", source = "gen3", features = {},
  }
  for key, value in pairs(extra or {}) do result[key] = value end
  return result
end

-- Classify one cell of a map view (nav/gen3/World.lua).  `opts.entities`
-- (or world.npcs) supplies objects standing there.
function Terrain.classify(world, x, y, opts)
  opts = opts or {}
  local map = type(world) == "table" and world.map or nil
  if type(map) ~= "table" or type(map.inBounds) ~= "function" then
    return record("unknown", x, y)
  end
  if not map:inBounds(x, y) then return record("edge", x, y, { passable = false }) end
  local beh = map:behavior(x, y)
  local entity = entityAt(world, x, y)
  if entity then
    local gfx = tonumber(entity.graphicsId or (entity.def and entity.def.graphicsId))
    if gfx == GFX_BOULDER then return record("boulder", x, y, { passable = false, entity = entity }) end
    if gfx == GFX_CUT_TREE then return record("cut_tree", x, y, { passable = false, entity = entity }) end
    if gfx == GFX_ROCK then return record("rock", x, y, { passable = false, entity = entity }) end
  end
  local warpKind = map.warpKind and map:warpKind(x, y) or nil
  if warpKind then
    local kind = "doormat"
    if warpKind == "door" then kind = "door"
    elseif warpKind == "hole" then kind = "hole"
    elseif warpKind == "pad" then kind = "warp_panel"
    elseif warpKind == "escalator" then kind = beh == MB.DOWN_ESCALATOR and "escalator_down" or "escalator_up"
    elseif warpKind == "stair" then kind = STAIR_DOWN[beh] and "stairs_down" or "stairs_up"
    elseif beh == MB.LADDER then kind = "ladder"
    elseif beh == MB.CAVE_DOOR then kind = "cave"
    elseif ARROW[beh] then kind = "doormat"
    end
    return record(kind, x, y, { passable = true, warp = true, warpKind = warpKind })
  end
  if beh == MB.FALL_WARP then return record("hole", x, y, { passable = true }) end
  if beh == MB.WATERFALL then return record("waterfall", x, y) end
  if CURRENT[beh] then return record("current", x, y, { direction = CURRENT[beh] }) end
  if SPIN[beh] then return record("spinner", x, y, { direction = SPIN[beh] }) end
  if beh == Terrain.STOP_SPINNING then return record("stop_spinner", x, y) end
  if WALK[beh] or SLIDE[beh] then
    return record("moving_floor", x, y, { direction = WALK[beh] or SLIDE[beh] })
  end
  if beh == MB.ICE then return record("ice", x, y) end
  if beh == MB.THIN_ICE then return record("thin_ice", x, y) end
  if beh == MB.CRACKED_ICE then return record("cracked_ice", x, y) end
  if beh == MB.STRENGTH_BUTTON then return record("switch", x, y, { passable = true }) end
  if CYCLING_SLOPE[beh] then return record("slope", x, y, { direction = "down" }) end
  if map.isLedgeCell and map:isLedgeCell(x, y) then
    local facings = map:ledgeFacings(x, y) or {}
    local direction = next(facings)
    return record("ledge", x, y, { passable = false, direction = direction })
  end
  if map:isCounterCell(x, y) then return record("counter", x, y, { passable = false }) end
  if map:isWater(x, y) then return record("water", x, y) end
  if map:isGrass(x, y) then return record("grass", x, y, { passable = true }) end
  if map:walkableColl(x, y) and not map:overrideBlocked(x, y) then
    return record("default", x, y, { passable = true })
  end
  return record("wall", x, y, { passable = false })
end

-- Furniture the A button reads (src/core/game3/scripting/interaction_scripts.lua
-- FLAVOR and CODE rows, keyed by MB), with spoken names derived from the
-- behaviour names.  `faceUp`: only read when the player faces up.
Terrain.FURNITURE = {
  [0x81] = { label = "Bookshelf" }, [0x82] = { label = "Mart Shelf" },
  [0x83] = { label = "PC" }, [0x85] = { label = "Town Map" },
  [0x86] = { label = "TV", faceUp = true },
  [0x87] = { label = "Pok\195\169mon Center Sign", faceUp = true },
  [0x88] = { label = "Mart Sign", faceUp = true },
  [0x89] = { label = "Cabinet" }, [0x8A] = { label = "Kitchen" },
  [0x8B] = { label = "Dresser" }, [0x8C] = { label = "Snacks" },
  [0x8E] = { label = "Battle Records", faceUp = true },
  [0x8F] = { label = "Questionnaire" },
  [0x90] = { label = "Food" }, [0x93] = { label = "Blueprints" },
  [0x94] = { label = "Painting" }, [0x95] = { label = "Machine" },
  [0x96] = { label = "Telephone" }, [0x97] = { label = "Computer" },
  [0x98] = { label = "Poster" }, [0x99] = { label = "Food" },
  [0x9A] = { label = "Trash Can" }, [0x9B] = { label = "Cup" },
  [0x9C] = { label = "Window" }, [0x9D] = { label = "Window" },
  [0x9E] = { label = "Blinking Lights" }, [0x9F] = { label = "Tools" },
  [0xA0] = { label = "Machine" }, [0xA1] = { label = "Video Game" },
}

return Terrain
