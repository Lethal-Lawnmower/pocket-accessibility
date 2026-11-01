-- Reused from the old Pocket Accessibility project (src/accessibility/TerrainSemantics.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Pure semantic classification for one live overworld cell.
--
-- This module reads the same Map/tileset/field records as gameplay.  It never
-- inspects pixels, calls a renderer, changes a map, or invokes Runtime hooks.
-- Mod callbacks accepted below are protected with pcall and are expected to be
-- read-only semantic providers.
--
-- Internal integration API (schema and mod-provider surface are provisional):
--   TerrainSemantics.classify(mapOrOverworld, cellX, cellY, options) -> record
--
-- `mapOrOverworld` may be a Map or an OverworldState containing `.map`.
-- Useful options are `data`/`field`, `entities`, `player`, `passable`, and:
--
--   metadata = { kind="hole", label="Cracked floor", cue="hole" }
--   providers = {
--     { id="my_mod:tiles", describe=function(context) return record end },
--   }
--
-- Inline declarative metadata is also recognized:
--
--   map.def.accessibilityTerrain = {
--     cells = { ["4,7"] = { kind="switch", label="Blue switch" } },
--     provider = function(context) ... end, -- optional, protected
--   }
--   map.tileset.accessibilityTerrain = {
--     tiles = { [0x40] = { kind="ice", label="Slippery ice" } },
--   }
--
-- A result always has schema/kind/label/cue/confidence/source/diagnostics.
-- `traversal` and `traversalCue` independently describe pass/wall status so a
-- sonar can layer the movement verdict with the terrain cue.  Unknown mod kinds
-- are preserved verbatim and receive the default cue plus a diagnostic unless
-- the mod supplies its own cue.

local CutTrees = require("src.access.nav.CutTrees")

local TerrainSemantics = {}

TerrainSemantics.SCHEMA = 1

local DIRECTIONS = { up = true, down = true, left = true, right = true }

local KIND_ALIASES = {
  tall_grass = "grass",
  cuttable_bush = "bush",
  cuttable_tree = "bush",
  tree = "bush",
  spinner = "directional_floor",
  current = "directional_floor",
  directional = "directional_floor",
  stair_up = "stairs_up",
  up_stairs = "stairs_up",
  stair_down = "stairs_down",
  down_stairs = "stairs_down",
  blocked = "wall",
  walkable = "pass",
  path = "default",
  ground = "default",
}

local PROFILES = {
  grass = { label = "tall grass", cue = "grass" },
  bush = { label = "cuttable bush", cue = "bush", hazard = true },
  water = { label = "water", cue = "water", hazard = true },
  directional_floor = {
    label = "directional floor", cue = "default", hazard = true,
  },
  warp = { label = "warp", cue = "door" },
  door = { label = "door", cue = "door" },
  stairs_up = { label = "stairs up", cue = "stair_up" },
  stairs_down = { label = "stairs down", cue = "stair_down" },
  hole = { label = "hole", cue = "hole", hazard = true },
  switch = { label = "switch", cue = "switch", hazard = true },
  boulder = { label = "boulder", cue = "boulder", hazard = true },
  pass = { label = "passable", cue = "pass", passable = true },
  wall = { label = "wall", cue = "wall", passable = false },
  default = { label = "ground", cue = "default" },
  unknown = { label = "unknown terrain", cue = "default" },
}

TerrainSemantics.PROFILES = PROFILES

local function trim(value)
  if type(value) ~= "string" then return nil end
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  return value ~= "" and value or nil
end

local function humanize(value)
  value = trim(value)
  if not value then return nil end
  value = value:gsub("([a-z0-9])([A-Z])", "%1 %2")
  value = value:gsub("[_%-]+", " "):gsub("%s+", " ")
  return value:lower()
end

local function finiteInteger(value)
  return type(value) == "number" and value == value
     and value ~= math.huge and value ~= -math.huge
     and value % 1 == 0
end

local function diagnostic(result, code, source, message)
  local item = { code = code, source = source }
  if message ~= nil then item.message = tostring(message) end
  result.diagnostics[#result.diagnostics + 1] = item
end

local function protectedGet(result, object, key, source)
  if type(object) ~= "table" then return nil end
  local ok, value = pcall(function() return object[key] end)
  if not ok then
    diagnostic(result, "metadata_read_failed", source .. "." .. tostring(key), value)
    return nil
  end
  return value
end

local function invoke(result, object, method, source, ...)
  if type(object) ~= "table" then return nil end
  local okGet, fn = pcall(function() return object[method] end)
  if not okGet then
    diagnostic(result, "query_failed", source .. "." .. method, fn)
    return nil
  end
  if type(fn) ~= "function" then
    diagnostic(result, "query_missing", source .. "." .. method)
    return nil
  end
  local ok, value = pcall(fn, object, ...)
  if not ok then
    diagnostic(result, "query_failed", source .. "." .. method, value)
    return nil
  end
  return value
end

local function callProvider(result, fn, context, source)
  if type(fn) ~= "function" then
    diagnostic(result, "metadata_invalid", source, "provider is not a function")
    return nil
  end
  local ok, value = pcall(fn, context)
  if not ok then
    diagnostic(result, "provider_failed", source, value)
    return nil
  end
  if value == nil or value == false then return nil end
  if type(value) ~= "table" then
    diagnostic(result, "metadata_invalid", source,
      "provider result must be a semantic record or nil")
    return nil
  end
  return value
end

local function coordinateRecord(result, container, x, y, source)
  if type(container) ~= "table" then return nil end
  local cells = protectedGet(result, container, "cells", source)
  if cells == nil then cells = container end
  if type(cells) ~= "table" then
    diagnostic(result, "metadata_invalid", source .. ".cells", "cells must be a table")
    return nil
  end
  local key = tostring(x) .. "," .. tostring(y)
  local direct = protectedGet(result, cells, key, source .. ".cells")
  if direct ~= nil then return direct, source .. ".cells[" .. key .. "]" end
  local row = protectedGet(result, cells, y, source .. ".cells")
  if type(row) == "table" then
    local value = protectedGet(result, row, x, source .. ".cells[" .. tostring(y) .. "]")
    if value ~= nil then
      return value, source .. ".cells[" .. tostring(y) .. "][" .. tostring(x) .. "]"
    end
  end
  return nil
end

local function tileRecord(result, container, tile, source)
  if type(container) ~= "table" or tile == nil then return nil end
  local tiles = protectedGet(result, container, "tiles", source)
  if tiles == nil then tiles = container end
  if type(tiles) ~= "table" then
    diagnostic(result, "metadata_invalid", source .. ".tiles", "tiles must be a table")
    return nil
  end
  local value = protectedGet(result, tiles, tile, source .. ".tiles")
  if value ~= nil then
    return value, source .. ".tiles[" .. tostring(tile) .. "]"
  end
  return nil
end

local function looksSemantic(record)
  return type(record) == "table"
     and (record.kind ~= nil or record.cue ~= nil or record.label ~= nil
       or record.accessibilityLabel ~= nil or record.description ~= nil
       or record.accessibilityDescription ~= nil)
end

local function normalizeRecord(result, record, source, confidence, semantics)
  if type(record) ~= "table" then
    diagnostic(result, "metadata_invalid", source, "semantic metadata must be a table")
    return nil
  end

  local rawKind = protectedGet(result, record, "kind", source)
    or protectedGet(result, record, "role", source)
  rawKind = trim(rawKind)
  if not rawKind then
    diagnostic(result, "metadata_invalid", source, "semantic kind is missing")
    return nil
  end
  local lowered = rawKind:lower():gsub("[%s%-]+", "_")
  local aliases = semantics and semantics.aliases or KIND_ALIASES
  local profiles = semantics and semantics.profiles or PROFILES
  local kind = aliases[lowered] or lowered
  local profile = profiles[kind]
  if not profile then
    diagnostic(result, "unknown_semantic_kind", source, kind)
  end

  local label = trim(protectedGet(result, record, "accessibilityLabel", source))
    or trim(protectedGet(result, record, "label", source))
    or trim(protectedGet(result, record, "name", source))
    or (profile and profile.label) or humanize(kind) or PROFILES.unknown.label
  local description = trim(
    protectedGet(result, record, "accessibilityDescription", source))
    or trim(protectedGet(result, record, "description", source))
  local cueValue = protectedGet(result, record, "accessibilityCue", source)
  if cueValue == nil then cueValue = protectedGet(result, record, "cue", source) end
  local cue = trim(cueValue)
  local direction = protectedGet(result, record, "direction", source)
  if direction ~= nil then
    direction = type(direction) == "string" and direction:lower() or direction
    if not DIRECTIONS[direction] then
      diagnostic(result, "direction_invalid", source, direction)
      direction = nil
    end
  end
  if kind == "directional_floor" then
    if direction and not cue then cue = "move_" .. direction end
    if not direction then
      diagnostic(result, "direction_unknown", source,
        "directional floor has no valid direction")
    end
  end
  cue = cue or (profile and profile.cue) or "default"

  local hazard = protectedGet(result, record, "hazard", source)
  if hazard ~= nil and type(hazard) ~= "boolean" then
    diagnostic(result, "metadata_field_invalid", source .. ".hazard", "expected boolean")
    hazard = nil
  end
  if hazard == nil and profile then hazard = profile.hazard == true end

  local passable = protectedGet(result, record, "passable", source)
  if passable ~= nil and type(passable) ~= "boolean" then
    diagnostic(result, "metadata_field_invalid", source .. ".passable", "expected boolean")
    passable = nil
  end
  if passable == nil and profile then passable = profile.passable end

  return {
    kind = kind,
    label = label,
    description = description,
    cue = cue,
    direction = direction,
    hazard = hazard == true,
    passable = passable,
    variant = trim(protectedGet(result, record, "variant", source)),
    semanticId = trim(protectedGet(result, record, "id", source)),
    source = source,
    confidence = confidence or "authored",
  }
end

local function resolveMap(source, options, result)
  local map = source
  local overworld = options.overworld
  if type(source) == "table" then
    local candidate = protectedGet(result, source, "map", "input")
    if type(candidate) == "table" then
      map, overworld = candidate, source
    end
  end
  if type(map) ~= "table" then return nil, overworld end
  return map, overworld
end

local function resolveData(options, overworld, result)
  local data = options.data
  if type(data) ~= "table" and type(options.game) == "table" then
    data = protectedGet(result, options.game, "data", "options.game")
  end
  if type(data) ~= "table" and type(overworld) == "table" then
    data = protectedGet(result, overworld, "data", "overworld")
    if type(data) ~= "table" then
      local game = protectedGet(result, overworld, "game", "overworld")
      if type(game) == "table" then
        data = protectedGet(result, game, "data", "overworld.game")
      end
    end
  end
  return type(data) == "table" and data or nil
end

local function eachArray(value, fn)
  if type(value) ~= "table" then return end
  local index = 1
  while true do
    local item = rawget(value, index)
    if item == nil then return end
    fn(item, index)
    index = index + 1
  end
end

local function contains(value, wanted)
  local found = false
  eachArray(value, function(item)
    if item == wanted then found = true end
  end)
  return found
end

local function matchingCoordinate(list, x, y)
  local match
  eachArray(list, function(item)
    if not match and type(item) == "table"
       and item.x == x and item.y == y then match = item end
  end)
  return match
end

local function firstDirection(moves)
  local direction
  eachArray(moves, function(move)
    if not direction and type(move) == "table"
       and DIRECTIONS[move.dir] then direction = move.dir end
  end)
  return direction
end

local function mapIdentity(map, result)
  local def = protectedGet(result, map, "def", "map")
  local tileset = protectedGet(result, map, "tileset", "map")
  local mapId = protectedGet(result, map, "id", "map")
  if mapId == nil and type(def) == "table" then mapId = def.id end
  local tilesetId = type(def) == "table" and def.tileset or nil
  if tilesetId == nil and type(tileset) == "table" then tilesetId = tileset.id end
  return def, tileset, mapId, tilesetId
end

local function pushable(entity)
  if type(entity) ~= "table" then return false end
  local def = rawget(entity, "def")
  if type(def) ~= "table" then return false end
  if def.pushable ~= nil then return def.pushable == true end
  return def.sprite == "SPRITE_BOULDER"
end

local function entityAt(result, overworld, options, x, y)
  local callback = options.entityAt
  if callback ~= nil then
    if type(callback) ~= "function" then
      diagnostic(result, "metadata_invalid", "options.entityAt", "expected function")
    else
      local ok, value = pcall(callback, x, y)
      if ok then
        if value ~= nil and type(value) ~= "table" then
          diagnostic(result, "metadata_invalid", "options.entityAt",
            "callback result must be an entity or nil")
        elseif value ~= nil then
          return value
        end
      else
        diagnostic(result, "provider_failed", "options.entityAt", value)
      end
    end
  end

  local entities = options.entities
  if type(entities) ~= "table" and type(overworld) == "table" then
    entities = protectedGet(result, overworld, "entities", "overworld")
      or protectedGet(result, overworld, "npcs", "overworld")
  end
  local match
  eachArray(entities, function(entity)
    if not match and type(entity) == "table"
       and ((entity.cellX == x and entity.cellY == y)
         or (entity.targetX == x and entity.targetY == y)) then
      match = entity
    end
  end)
  return match
end

local function builtIn(kind, source, confidence, extra)
  local profile = assert(PROFILES[kind], "unknown built-in semantic kind")
  local record = {
    kind = kind,
    label = profile.label,
    cue = profile.cue,
    hazard = profile.hazard == true,
    passable = profile.passable,
    source = source,
    confidence = confidence,
  }
  for key, value in pairs(extra or {}) do record[key] = value end
  if kind == "directional_floor" and record.direction then
    if not (extra and extra.label) then
      record.label = record.label .. " toward " .. record.direction
    end
    if not (extra and extra.cue) then record.cue = "move_" .. record.direction end
  end
  return record
end

local function fieldSpecial(result, field, map, mapId, tilesetId, tile, block,
                           walkable, x, y, options)
  if type(field) ~= "table" or type(mapId) ~= "string" then return nil end

  -- Exact generated spinner coordinates are the gameplay authority.
  local spinners = type(field.spinners) == "table" and field.spinners[mapId]
  local spinner = matchingCoordinate(spinners, x, y)
  if spinner then
    local direction = firstDirection(spinner.moves)
    if not direction then diagnostic(result, "direction_unknown", "field.spinners") end
    return builtIn("directional_floor", "field.spinners", "native", {
      direction = direction, variant = "spinner",
      label = direction and ("spinner toward " .. direction) or "spinner",
      cue = direction and ("move_" .. direction) or "default",
    })
  end

  -- Seafoam holes/currents are also explicit generated gameplay records.
  local seafoam = field.seafoam
  local floor = type(seafoam) == "table" and seafoam[mapId]
  local hole = type(floor) == "table" and matchingCoordinate(floor.holes, x, y)
  if not hole and type(seafoam) == "table" then
    for _, owner in pairs(seafoam) do
      local nested = type(owner) == "table" and owner.pluggedByHolesOn
      if type(nested) == "table" and nested.map == mapId then
        hole = matchingCoordinate(nested.holes, x, y)
        if hole then break end
      end
    end
  end
  if hole then
    return builtIn("hole", "field.seafoam.holes", "native", {
      destinationMap = type(floor) == "table" and floor.holeDestination or nil,
    })
  end
  if type(floor) == "table" then
    local current = matchingCoordinate(floor.currents, x, y)
    if not current and type(floor.entryCurrent) == "table"
       and floor.entryCurrent.x == x and floor.entryCurrent.y == y then
      current = floor.entryCurrent
    end
    if current then
      local direction = firstDirection(current.moves)
      if not direction then diagnostic(result, "direction_unknown", "field.seafoam.currents") end
      return builtIn("directional_floor", "field.seafoam.currents", "native", {
        direction = direction, variant = "current",
        label = direction and ("water current toward " .. direction) or "water current",
        cue = direction and ("move_" .. direction) or "water",
      })
    end
  end

  -- Closed Silph shutters render as wall sections, but ordinary blocked cells
  -- are not gates. A floor-wide `walkable == false` fallback therefore turns
  -- every real wall into an imaginary door. The live closed-block records are
  -- authoritative: they cover every restored gate (including ones absent from
  -- the retail coordinate table), support content mods, and stop matching as
  -- soon as the gate block is opened.
  local card = field.cardKeyDoors
  local floorDoors = type(card) == "table" and type(card.closedDoors) == "table"
    and card.closedDoors[mapId]
  local gate
  for _, door in ipairs(floorDoors or {}) do
    if door.bx == math.floor(x / 2) and door.by == math.floor(y / 2)
       and door.block == block then
      gate = door
      break
    end
  end
  if gate then
    local closed = contains(card.doorTiles, tile)
      or (type(card.silphCo11F) == "table"
        and card.silphCo11F.doorTile == tile)
    if closed and walkable == false then
      return builtIn("door", "field.cardKeyDoors", "native", { passable = false })
    end
  end

  -- Cut uses block swaps plus a non-walkable facing cell in gameplay; using
  -- that identical predicate keeps content mods that extend the field table.
  local cut = CutTrees.swapAt(map, field, x, y) ~= nil
  if cut and walkable == false then
    return builtIn("bush", "field.cutTreeSwaps", "native", { passable = false })
  end

  -- Cycling Road's generated slope rule is map-wide and conditionally active
  -- on a bicycle.  Keep that condition explicit instead of claiming it always
  -- moves an arbitrary debug-warped player.
  local forced = field.forcedMovement
  if type(forced) == "table" and contains(forced.slopeMaps, mapId) then
    local player = options.player
    local active = type(player) == "table" and player.onBike == true
      or options.onBike == true
    return builtIn("directional_floor", "field.forcedMovement.slopeMaps", "native", {
      direction = "down", variant = "bicycle_slope", active = active,
      condition = "bicycle", label = "bicycle slope toward down",
      cue = "move_down",
    })
  end

  return nil
end

-- Legacy Red/Blue sonar distinctions that the current generated target does
-- not yet encode declaratively.  These are deliberately low-confidence and
-- every match receives `legacy_tile_fallback`; callers can surface/audit it.
local LEGACY = {
  CAVERN = {
    [0x22] = { kind = "hole" },
    [0x2d] = { kind = "switch" },
  },
  FACILITY = {
    [0x11] = { kind = "hole" },
    [0x18] = { kind = "door", passable = false },
    [0x24] = { kind = "door", passable = false },
    [0x5e] = { kind = "door", passable = false },
  },
  GYM = {
    [0x3f] = { kind = "door", passable = false },
  },
}

local LEGACY_GLOBAL = {
  [0x13] = { kind = "stairs_up" },
  [0x43] = { kind = "stairs_up" },
  [0x1b] = { kind = "stairs_down" },
}

-- Global stair ids were global only inside the 24 canonical Gen-I tilesets.
-- Applying them to a brand-new mod tileset would turn an unrelated tile 0x13
-- into stairs, exactly the kind of false confidence this layer must avoid.
local VANILLA_TILESETS = {
  OVERWORLD = true, REDS_HOUSE_1 = true, MART = true, FOREST = true,
  REDS_HOUSE_2 = true, DOJO = true, POKECENTER = true, GYM = true,
  HOUSE = true, FOREST_GATE = true, MUSEUM = true, UNDERGROUND = true,
  GATE = true, SHIP = true, SHIP_PORT = true, CEMETERY = true,
  INTERIOR = true, CAVERN = true, LOBBY = true, MANSION = true,
  LAB = true, CLUB = true, FACILITY = true, PLATEAU = true,
}

local function legacySpecial(result, tilesetId, tile)
  if type(tile) ~= "number" then return nil end
  local spec = type(tilesetId) == "string" and LEGACY[tilesetId]
    and LEGACY[tilesetId][tile] or nil
  if not spec and VANILLA_TILESETS[tilesetId] then spec = LEGACY_GLOBAL[tile] end
  if not spec then return nil end
  diagnostic(result, "legacy_tile_fallback", "pokemon_access.rby",
    tostring(tilesetId) .. ":" .. tostring(tile))
  return builtIn(spec.kind, "pokemon_access.rby.tile_fallback", "legacy", {
    passable = spec.passable,
  })
end

local function apply(result, record)
  result.kind = record.kind
  result.label = record.label
  result.description = record.description
  result.cue = record.cue
  result.direction = record.direction
  result.variant = record.variant
  result.semanticId = record.semanticId
  result.hazard = record.hazard == true
  result.source = record.source
  result.confidence = record.confidence
  if record.destinationMap ~= nil then result.destinationMap = record.destinationMap end
  if record.condition ~= nil then result.condition = record.condition end
  if record.active ~= nil then result.active = record.active end
  if record.passable ~= nil and result.passabilitySource ~= "caller" then
    result.passable = record.passable
  end

  if result.passable == true then
    result.traversal, result.traversalCue = "pass", "pass"
  elseif result.passable == false then
    result.traversal, result.traversalCue = "wall", "wall"
  elseif result.kind == "water" then
    result.traversal, result.traversalCue = "conditional", nil
  else
    result.traversal, result.traversalCue = "unknown", nil
  end
  return result
end

local function explicitMetadata(result, context, map, def, tileset, entity, warp,
                                options, semantics)
  local direct = options.metadata
  if direct ~= nil then
    if type(direct) == "function" then
      direct = callProvider(result, direct, context, "options.metadata")
    end
    local normalized = direct and normalizeRecord(
      result, direct, "options.metadata", "authored", semantics)
    if normalized then return normalized end
  end

  local providers = options.providers
  if providers ~= nil and type(providers) ~= "table" then
    diagnostic(result, "metadata_invalid", "options.providers", "providers must be a list")
  else
    eachArray(providers, function(provider, index)
      if context.explicitResult then return end
      local id, fn
      if type(provider) == "function" then
        id, fn = tostring(index), provider
      elseif type(provider) == "table" then
        id = trim(provider.id) or tostring(index)
        fn = provider.describe or provider.provider
      else
        diagnostic(result, "metadata_invalid",
          "options.providers[" .. tostring(index) .. "]", "invalid provider")
        return
      end
      local source = "provider:" .. id
      local value = callProvider(result, fn, context, source)
      local normalized = value and normalizeRecord(result, value, source,
        "authored", semantics)
      if normalized then context.explicitResult = normalized end
    end)
    if context.explicitResult then return context.explicitResult end
  end

  local function inline(owner, source, lookup)
    if type(owner) ~= "table" then return nil end
    local container = protectedGet(result, owner, "accessibilityTerrain", source)
    if container == nil then return nil end
    if type(container) == "function" then
      local value = callProvider(result, container, context,
        source .. ".accessibilityTerrain")
      return value and normalizeRecord(result, value,
        source .. ".accessibilityTerrain", "authored", semantics)
    end
    if type(container) ~= "table" then
      diagnostic(result, "metadata_invalid", source .. ".accessibilityTerrain",
        "expected table or function")
      return nil
    end
    local value, valueSource = lookup(container, source .. ".accessibilityTerrain")
    if value ~= nil then
      local normalized = normalizeRecord(result, value, valueSource,
        "authored", semantics)
      if normalized then return normalized end
    end
    local fn = protectedGet(result, container, "provider",
      source .. ".accessibilityTerrain")
      or protectedGet(result, container, "describe",
        source .. ".accessibilityTerrain")
    if fn ~= nil then
      value = callProvider(result, fn, context,
        source .. ".accessibilityTerrain.provider")
      local normalized = value and normalizeRecord(result, value,
        source .. ".accessibilityTerrain.provider", "authored", semantics)
      if normalized then return normalized end
    end
    if looksSemantic(container) then
      return normalizeRecord(result, container,
        source .. ".accessibilityTerrain", "authored", semantics)
    end
  end

  -- A live entity's declaration describes the occupied cell before its tile.
  local found = inline(type(entity) == "table" and entity.def or nil, "entity.def",
    function(container, source) return container, source end)
  if found then return found end
  found = inline(def, "map.def", function(container, source)
    return coordinateRecord(result, container, context.x, context.y, source)
  end)
  if found then return found end
  found = inline(tileset, "map.tileset", function(container, source)
    return tileRecord(result, container, context.tile, source)
  end)
  if found then return found end
  found = inline(type(warp) == "table" and warp.def or nil, "warp.def",
    function(container, source) return container, source end)
  return found
end

-- Shared read-only metadata boundary for generation-specific classifiers.
-- Callers provide their own native cell record and vocabulary; this resolver
-- never classifies a tile or collision byte on their behalf. Diagnostics are
-- appended to result, while a bad provider falls through to native terrain.
function TerrainSemantics.resolveAuthored(result, context, owners, options,
                                          semantics)
  owners = type(owners) == "table" and owners or {}
  options = type(options) == "table" and options or {}
  local ok, authored = pcall(explicitMetadata, result, context,
    owners.map, owners.def, owners.tileset, owners.entity, owners.warp,
    options, semantics)
  if not ok then
    diagnostic(result, "metadata_resolution_failed", "accessibilityTerrain",
      authored)
    return nil
  end
  return authored
end

function TerrainSemantics.classify(source, x, y, options)
  options = type(options) == "table" and options or {}
  local result = {
    schema = TerrainSemantics.SCHEMA,
    x = x, y = y,
    kind = "unknown",
    label = PROFILES.unknown.label,
    cue = PROFILES.unknown.cue,
    hazard = false,
    confidence = "unknown",
    source = "input",
    traversal = "unknown",
    diagnostics = {},
    features = {},
  }

  if not finiteInteger(x) or not finiteInteger(y) then
    diagnostic(result, "invalid_coordinates", "input",
      "cell coordinates must be finite integers")
    return result
  end

  local map, overworld = resolveMap(source, options, result)
  if not map then
    diagnostic(result, "map_missing", "input", "a live Map or OverworldState is required")
    return result
  end
  local def, tileset, mapId, tilesetId = mapIdentity(map, result)
  result.mapId, result.tilesetId = mapId, tilesetId

  local inBounds = invoke(result, map, "inBounds", "map", x, y)
  if inBounds == nil then
    local width = protectedGet(result, map, "widthCells", "map")
    local height = protectedGet(result, map, "heightCells", "map")
    if type(width) == "number" and type(height) == "number" then
      inBounds = x >= 0 and y >= 0 and x < width and y < height
      diagnostic(result, "bounds_fallback", "map.dimensions")
    end
  end
  result.inBounds = inBounds == true
  if inBounds == false then
    result.passable = false
    return apply(result, builtIn("wall", "map.inBounds", "native",
      { label = "map edge", passable = false }))
  elseif inBounds ~= true then
    diagnostic(result, "bounds_unknown", "map")
    return result
  end

  result.tile = invoke(result, map, "cellTile", "map", x, y)
  result.block = invoke(result, map, "blockAt", "map",
    math.floor(x / 2), math.floor(y / 2))
  local walkable = invoke(result, map, "isWalkableCell", "map", x, y)
  local grass = invoke(result, map, "isGrassCell", "map", x, y)
  local water = invoke(result, map, "isWaterCell", "map", x, y)
  local warp = invoke(result, map, "warpAtCell", "map", x, y)
  local warpTile = invoke(result, map, "isWarpTileCell", "map", x, y)
  result.walkable = walkable == true
  result.grass, result.water = grass == true, water == true
  result.features.warp = warp ~= nil and warp ~= false
  result.features.warpTile = warpTile == true
  if type(warp) == "table" then
    result.warpIndex = protectedGet(result, warp, "index", "warp")
    local warpDef = protectedGet(result, warp, "def", "warp")
    if type(warpDef) == "table" then
      result.destinationMap = protectedGet(result, warpDef, "destMap", "warp.def")
      result.destinationWarp = protectedGet(result, warpDef, "destWarp", "warp.def")
    end
  end

  local entityOK, entity = pcall(entityAt, result, overworld, options, x, y)
  if not entityOK then
    diagnostic(result, "metadata_resolution_failed", "overworld.entities", entity)
    entity = nil
  end
  result.features.boulder = pushable(entity)
  if entity ~= nil then result.entity = entity end

  local explicitPassable = options.passable
  if explicitPassable ~= nil and type(explicitPassable) ~= "boolean" then
    diagnostic(result, "metadata_field_invalid", "options.passable", "expected boolean")
    explicitPassable = nil
  end
  if explicitPassable ~= nil then
    result.passable = explicitPassable
    result.passabilitySource = "caller"
  elseif result.features.boulder then
    result.passable = false
    result.passabilitySource = "entity"
  elseif walkable ~= nil then
    result.passable = walkable == true
    result.passabilitySource = "map.isWalkableCell"
  end
  local player = options.player
  if type(player) ~= "table" and type(overworld) == "table" then
    player = protectedGet(result, overworld, "player", "overworld")
  end
  if result.passable == false and water == true then
    if type(player) == "table" then
      result.passable = player.surfing == true
      result.passabilitySource = "player.surfing"
    else
      -- Water is not ordinary land, but whether it is traversable depends on
      -- the mover's surfing state.  Without that live fact, do not call it a
      -- wall merely because isWalkableCell is false.
      result.passable = nil
      result.passabilitySource = "conditional"
    end
  end

  local data = resolveData(options, overworld, result)
  local field = options.field
  if type(field) ~= "table" and type(data) == "table" then field = data.field end
  local context = {
    schema = TerrainSemantics.SCHEMA,
    map = map, overworld = overworld, data = data, field = field,
    mapId = mapId, tilesetId = tilesetId,
    x = x, y = y, tile = result.tile, block = result.block,
    walkable = walkable, grass = grass, water = water,
    warp = warp, warpTile = warpTile, entity = entity, player = player,
  }

  local explicit = TerrainSemantics.resolveAuthored(result, context,
    { map = map, def = def, tileset = tileset, entity = entity, warp = warp },
    options)
  if explicit then return apply(result, explicit) end

  if result.features.boulder then
    return apply(result, builtIn("boulder", "overworld.entities", "native",
      { passable = false }))
  end

  local fieldOK, special = pcall(fieldSpecial, result, field, map, mapId, tilesetId,
    result.tile, result.block, walkable, x, y,
    { player = player, onBike = options.onBike })
  if not fieldOK then
    diagnostic(result, "metadata_resolution_failed", "field", special)
    special = nil
  end
  if special then return apply(result, special) end

  local door = false
  local mapDoorTiles = protectedGet(result, map, "doorTiles", "map")
  if type(mapDoorTiles) == "table" and mapDoorTiles[result.tile] == true then
    door = true
  elseif type(tileset) == "table" then
    door = contains(tileset.doorTiles, result.tile)
  end
  result.features.door = door
  if door then
    return apply(result, builtIn("door", "map.doorTiles", "native"))
  end

  -- Legacy special detail is more specific than a generic warp, but is always
  -- marked as fallback because the target has no authored stair/hole role yet.
  -- Authoritative live door sets above still win when raw ids overlap.
  special = legacySpecial(result, tilesetId, result.tile)
  if special then return apply(result, special) end
  if result.features.warp or result.features.warpTile then
    return apply(result, builtIn("warp", "map.warpAtCell", "native"))
  end

  -- Preserve Pokémon Access's terrain priority for overlapping predicates.
  if grass == true then
    return apply(result, builtIn("grass", "map.isGrassCell", "native"))
  end
  if water == true then
    return apply(result, builtIn("water", "map.isWaterCell", "native"))
  end
  if walkable == true then
    return apply(result, builtIn("default", "map.isWalkableCell", "native",
      { passable = result.passable }))
  end
  if walkable == false then
    return apply(result, builtIn("wall", "map.isWalkableCell", "native",
      { passable = false }))
  end

  diagnostic(result, "classification_unknown", "map",
    "no authoritative predicate or metadata classified this cell")
  return result
end

return TerrainSemantics
