local T = require("tests.harness")
local S = T.suite("accessibility terrain semantics")
local Terrain = require("src.access.nav.TerrainSemantics")

local function hasDiagnostic(result, code)
  for _, item in ipairs(result.diagnostics or {}) do
    if item.code == code then return true end
  end
  return false
end

local function fixture(spec)
  spec = spec or {}
  local map = {
    id = spec.mapId or "MOD_MAP",
    widthCells = spec.width or 8,
    heightCells = spec.height or 8,
    def = {
      id = spec.mapId or "MOD_MAP",
      tileset = spec.tilesetId or "MOD_TILESET",
      accessibilityTerrain = spec.mapTerrain,
    },
    tileset = {
      id = spec.tilesetId or "MOD_TILESET",
      doorTiles = spec.doorTiles or {},
      accessibilityTerrain = spec.tilesetTerrain,
    },
    doorTiles = {},
  }
  for _, tile in ipairs(spec.doorTiles or {}) do map.doorTiles[tile] = true end

  function map:inBounds(x, y)
    if spec.boundsError then error("bad bounds callback") end
    return x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells
  end
  function map:cellTile()
    if spec.tileError then error("bad tile callback") end
    return spec.tile == nil and 1 or spec.tile
  end
  function map:blockAt()
    if spec.blockError then error("bad block callback") end
    return spec.block == nil and 0 or spec.block
  end
  function map:isWalkableCell()
    if spec.walkError then error("bad walk callback") end
    return spec.walkable ~= false
  end
  function map:isGrassCell() return spec.grass == true end
  function map:isWaterCell() return spec.water == true end
  function map:warpAtCell()
    if not spec.warp then return nil end
    return { index = spec.warpIndex or 1, def = spec.warpDef or {
      destMap = "DESTINATION", destWarp = 2,
    } }
  end
  function map:isWarpTileCell() return spec.warpTile == true end
  return map
end

-- The result shape and ordinary traversal layering are stable.
local result = Terrain.classify(fixture(), 2, 3)
S.eq(result.schema, 1, "terrain records declare schema 1")
S.eq(result.kind, "default", "ordinary walkable ground gets the default terrain")
S.eq(result.cue, "default", "ordinary ground keeps the default footstep cue")
S.eq(result.passable, true, "ordinary ground reports native passability")
S.eq(result.traversal, "pass", "walkable terrain exposes a separate pass verdict")
S.eq(result.traversalCue, "pass", "walkable terrain exposes the sonar pass cue")
S.eq(result.mapId, "MOD_MAP", "result carries a stable map id")
S.eq(result.tilesetId, "MOD_TILESET", "result carries a stable tileset id")
S.eq(result.tile, 1, "result carries the live collision tile")
S.eq(result.block, 0, "result carries the live block id")

result = Terrain.classify(fixture({ walkable = false }), 2, 3)
S.eq(result.kind, "wall", "ordinary blocked ground is a wall")
S.eq(result.cue, "wall", "blocked ground exposes the wall cue")
S.eq(result.traversal, "wall", "blocked ground exposes a wall traversal verdict")
S.eq(result.passable, false, "blocked ground is not passable")

result = Terrain.classify(fixture(), -1, 0)
S.eq(result.kind, "wall", "out-of-bounds cells are map-edge walls")
S.eq(result.label, "map edge", "out-of-bounds labels do not pretend to be terrain")
S.eq(result.source, "map.inBounds", "map bounds are the authoritative edge source")

result = Terrain.classify(nil, 0, 0)
S.eq(result.kind, "unknown", "a missing map fails soft")
S.check(hasDiagnostic(result, "map_missing"), "a missing map has a stable diagnostic")
result = Terrain.classify(fixture(), 0.5, 0)
S.eq(result.kind, "unknown", "fractional cell coordinates fail soft")
S.check(hasDiagnostic(result, "invalid_coordinates"),
  "invalid coordinates have a stable diagnostic")

-- Native predicates retain Pokémon Access's base terrain vocabulary.
result = Terrain.classify(fixture({ grass = true }), 1, 1)
S.eq(result.kind, "grass", "live grass predicates produce grass")
S.eq(result.label, "tall grass", "grass has a screen-reader label")
S.eq(result.cue, "grass", "grass has the grass cue")
result = Terrain.classify(fixture({ water = true, walkable = false }), 1, 1)
S.eq(result.kind, "water", "live water predicates produce water")
S.eq(result.traversal, "conditional",
  "water without a mover does not invent a pass/wall verdict")
result = Terrain.classify({
  map = fixture({ water = true, walkable = false }),
  player = { cellX = 0, cellY = 0, surfing = true },
}, 1, 1)
S.eq(result.kind, "water", "surfing retains water terrain semantics")
S.eq(result.passable, true, "water is passable for the live surfing mover")
S.eq(result.traversalCue, "pass", "surfing water gets the pass traversal layer")

-- Door sets are more precise than generic warp membership.
result = Terrain.classify(fixture({
  tile = 9, doorTiles = { 9 }, warp = true, warpTile = true,
}), 1, 1)
S.eq(result.kind, "door", "a live door tile is classified as a door")
S.eq(result.cue, "door", "doors use the door cue")
S.check(result.features.warp and result.features.warpTile,
  "door records retain their warp features")
result = Terrain.classify(fixture({ tile = 8, warp = true, warpIndex = 4 }), 1, 1)
S.eq(result.kind, "warp", "a non-door warp remains a generic warp")
S.eq(result.warpIndex, 4, "warp classification keeps its live index")
S.eq(result.destinationMap, "DESTINATION", "warp destination metadata is retained")
S.eq(result.destinationWarp, 2, "destination warp index is retained")

-- Dynamic pushable entities are native boulders; an explicit false override
-- on the entity definition defeats the legacy sprite fallback just like Map.
local boulder = {
  cellX = 2, cellY = 3,
  def = { sprite = "SPRITE_BOULDER", name = "MOD_BOULDER" },
}
result = Terrain.classify({ map = fixture(), entities = { boulder } }, 2, 3)
S.eq(result.kind, "boulder", "a live pushable entity is a boulder")
S.eq(result.cue, "boulder", "boulders use their own cue")
S.eq(result.passable, false, "a boulder occupies and blocks its cell")
S.check(result.features.boulder, "the feature set records the boulder overlay")
local disabled = {
  cellX = 2, cellY = 3,
  def = { sprite = "SPRITE_BOULDER", pushable = false },
}
result = Terrain.classify({ map = fixture(), entities = { disabled } }, 2, 3)
S.eq(result.kind, "default", "pushable=false defeats the boulder sprite fallback")

-- Generated field records classify native hazards without reading graphics.
local field = {
  cutTiles = { MOD_TILESET = { 1 } },
  cutTreeSwaps = { { before = 12, after = 13 } },
  spinners = {
    MOD_MAP = { { x = 4, y = 5, moves = { { dir = "left", count = 3 } } } },
  },
  seafoam = {
    MOD_MAP = {
      holeDestination = "LOWER_FLOOR",
      holes = { { x = 6, y = 1, boulderEvent = "EVENT_HOLE" } },
      currents = { { x = 6, y = 2, moves = { { dir = "down", count = 4 } } } },
    },
    OWNER_FLOOR = {
      pluggedByHolesOn = {
        map = "MOD_MAP",
        holes = { { x = 7, y = 1, boulderEvent = "EVENT_NESTED_HOLE" } },
      },
    },
  },
  cardKeyDoors = {
    doorTiles = { 24, 36 },
    maps = { "SILPH_MAP" },
    doors = { SILPH_MAP = { { x = 5, y = 5 } } },
    closedDoors = {
      SILPH_MAP = { { bx = 2, by = 2, block = 12, open = 14 } },
    },
    silphCo11F = { doorTile = 94 },
  },
  forcedMovement = { slopeMaps = { "SLOPE_MAP" }, tiles = {} },
}
result = Terrain.classify(fixture({ block = 12, walkable = false }), 1, 1,
  { field = field })
S.eq(result.kind, "bush", "Cut block swaps plus blocked cells identify a bush")
S.eq(result.source, "field.cutTreeSwaps", "Cut semantics come from gameplay data")
S.eq(result.cue, "bush", "cuttable bushes use the bush cue")
local vanillaCut = {
  cutTiles = { OVERWORLD = { 0x3D, 0x52 }, GYM = { 0x50 } },
  cutTreeSwaps = { { before = 52, after = 111 }, { before = 63, after = 53 } },
}
result = Terrain.classify(fixture({ tilesetId = "LOBBY", tile = 0x3D,
  block = 52, walkable = false }), 1, 1, { field = vanillaCut })
S.eq(result.kind, "wall",
  "Game Corner block 52 is not a bush despite colliding with an outdoor swap id")
result = Terrain.classify(fixture({ tilesetId = "CEMETERY", tile = 0x3D,
  block = 63, walkable = false }), 1, 1, { field = vanillaCut })
S.eq(result.kind, "wall",
  "Pokemon Tower block 63 is not a bush despite colliding with a gym swap id")
local invalidTarget = fixture({ tilesetId = "OVERWORLD", tile = 0x3D,
  block = 52, walkable = false })
invalidTarget.tileset.blocks = {}
invalidTarget.tileset.blocks[53] = { 0x3D }
result = Terrain.classify(invalidTarget, 1, 1, { field = vanillaCut })
S.eq(result.kind, "wall",
  "a Cut swap whose replacement block is absent fails closed before mutation")
result = Terrain.classify(fixture(), 4, 5, { field = field })
S.eq(result.kind, "directional_floor", "spinner coordinates identify a directional floor")
S.eq(result.direction, "left", "spinner direction comes from its first movement")
S.eq(result.variant, "spinner", "spinner subtype is machine-readable")
S.eq(result.cue, "move_left", "spinner direction selects a directional cue id")
S.eq(result.label, "spinner toward left", "spinner narration includes direction")
result = Terrain.classify(fixture({ walkable = false }), 6, 1, { field = field })
S.eq(result.kind, "hole", "Seafoam hole coordinates identify a hole")
S.eq(result.destinationMap, "LOWER_FLOOR", "hole records keep a declared destination")
result = Terrain.classify(fixture({ walkable = false }), 7, 1, { field = field })
S.eq(result.kind, "hole", "nested plugged-hole records apply to their declared map")
result = Terrain.classify(fixture({ water = true, walkable = false }), 6, 2,
  { field = field })
S.eq(result.kind, "directional_floor", "Seafoam current mouths are directional floors")
S.eq(result.direction, "down", "current direction comes from gameplay movement")
S.eq(result.variant, "current", "current subtype is machine-readable")
S.eq(result.label, "water current toward down", "current narration includes direction")
result = Terrain.classify(fixture({ mapId = "SILPH_MAP", tile = 24,
  block = 12, walkable = false }), 5, 5,
  { field = field })
S.eq(result.kind, "door", "exact card-key coordinates and tiles identify a closed door")
S.eq(result.source, "field.cardKeyDoors", "card-key door authority is attributed")
result = Terrain.classify(fixture({ mapId = "SILPH_MAP", tile = 36,
  walkable = false }), 2, 3,
  { field = field })
S.eq(result.kind, "wall",
  "a shared locked tile outside a recorded Silph gate stays a wall")
result = Terrain.classify(fixture({ mapId = "SLOPE_MAP" }), 2, 2,
  { field = field, onBike = true })
S.eq(result.kind, "directional_floor", "Cycling Road slope maps expose forced direction")
S.eq(result.direction, "down", "Cycling Road direction is down")
S.eq(result.condition, "bicycle", "conditional slope mechanics declare their condition")
S.eq(result.active, true, "caller-provided bicycle state marks the slope active")

-- Declarative metadata wins over native/fallback inference and is copied rather
-- than mutated. Both coordinate and tile schemas work for zero-based cells.
local direct = {
  kind = "hole", label = "Trap door", description = "Drops to the basement",
  cue = "custom_drop", hazard = true, passable = true, id = "mod:trapdoor",
}
result = Terrain.classify(fixture({ grass = true, warp = true }), 1, 1,
  { metadata = direct })
S.eq(result.kind, "hole", "caller-resolved metadata has highest precedence")
S.eq(result.label, "Trap door", "authored accessible labels are preserved")
S.eq(result.description, "Drops to the basement", "authored descriptions are preserved")
S.eq(result.cue, "custom_drop", "authored cue ids are preserved")
S.eq(result.semanticId, "mod:trapdoor", "authored semantic ids are preserved")
S.eq(result.confidence, "authored", "declarative metadata is marked authored")
S.eq(result.traversal, "pass", "authored passability controls traversal semantics")
S.same(direct, {
  kind = "hole", label = "Trap door", description = "Drops to the basement",
  cue = "custom_drop", hazard = true, passable = true, id = "mod:trapdoor",
}, "classification does not mutate caller-owned metadata")

local mapTerrain = {
  cells = {
    ["0,0"] = { kind = "switch", accessibilityLabel = "Orange switch" },
  },
}
result = Terrain.classify(fixture({ mapTerrain = mapTerrain }), 0, 0)
S.eq(result.kind, "switch", "map cell metadata supports zero-based coordinate keys")
S.eq(result.label, "Orange switch", "map cell accessibilityLabel wins")
S.check(result.source:find("map.def.accessibilityTerrain.cells", 1, true) ~= nil,
  "map-cell metadata has useful provenance")
local tileTerrain = {
  tiles = { [77] = { kind = "stairs_up", label = "Ladder to roof" } },
}
result = Terrain.classify(fixture({ tile = 77, tilesetTerrain = tileTerrain }), 1, 1)
S.eq(result.kind, "stairs_up", "tileset metadata labels reusable collision tiles")
S.eq(result.cue, "stair_up", "authored up stairs inherit the up-stair cue")
S.eq(result.label, "Ladder to roof", "authored stair label is retained")

local semanticBoulder = {
  cellX = 1, cellY = 2,
  def = {
    sprite = "SPRITE_BOULDER",
    accessibilityTerrain = {
      kind = "switch", label = "Movable weight on pressure plate",
    },
  },
}
result = Terrain.classify({ map = fixture(), entities = { semanticBoulder } }, 1, 2)
S.eq(result.kind, "switch", "an entity's explicit semantic metadata beats its sprite role")
S.eq(result.label, "Movable weight on pressure plate",
  "entity semantic labels describe novel mechanics")
S.check(result.features.boulder, "explicit entity semantics retain the boulder feature")

-- Providers are ordered, pcall-contained, type-checked, and can fall through.
local providerCalls = {}
result = Terrain.classify(fixture({ grass = true }), 3, 4, {
  providers = {
    { id = "broken", describe = function(ctx)
      providerCalls[#providerCalls + 1] = ctx.mapId
      error("provider exploded")
    end },
    { id = "bad_result", describe = function() return "pixels" end },
    { id = "working", describe = function(ctx)
      S.eq(ctx.tile, 1, "providers receive semantic collision data")
      return { kind = "directional_floor", direction = "right",
               label = "Conveyor east" }
    end },
  },
})
S.eq(result.kind, "directional_floor", "a later valid provider survives earlier failures")
S.eq(result.direction, "right", "provider direction is normalized")
S.eq(result.cue, "move_right", "provider directional floors inherit directional cues")
S.eq(result.source, "provider:working", "provider provenance includes its stable id")
S.check(hasDiagnostic(result, "provider_failed"), "provider exceptions are diagnosed")
S.check(hasDiagnostic(result, "metadata_invalid"), "malformed provider results are diagnosed")
S.same(providerCalls, { "MOD_MAP" }, "providers receive the stable map context once")

local throwingMapMetadata = {
  provider = function() error("inline metadata exploded") end,
}
result = Terrain.classify(fixture({ grass = true, mapTerrain = throwingMapMetadata }), 1, 1)
S.eq(result.kind, "grass", "throwing inline providers fall back to native semantics")
S.check(hasDiagnostic(result, "provider_failed"),
  "throwing inline metadata has a controlled diagnostic")

result = Terrain.classify(fixture(), 1, 1, {
  metadata = { kind = "crystal_floor", label = "Singing crystal" },
})
S.eq(result.kind, "crystal_floor", "unknown mod semantic kinds remain machine-readable")
S.eq(result.label, "Singing crystal", "unknown mod kinds retain authored labels")
S.eq(result.cue, "default", "unknown mod kinds fail soft to the default cue")
S.check(hasDiagnostic(result, "unknown_semantic_kind"),
  "unknown mod kinds request an auditable metadata improvement")
result = Terrain.classify(fixture(), 1, 1, {
  metadata = { kind = "directional_floor", direction = "diagonal",
               hazard = "yes", passable = "maybe" },
})
S.eq(result.kind, "directional_floor", "partially malformed metadata preserves known meaning")
S.eq(result.direction, nil, "invalid directions are not invented")
S.eq(result.cue, "default", "directionless floors use a conservative cue")
S.check(hasDiagnostic(result, "direction_invalid")
  and hasDiagnostic(result, "direction_unknown")
  and hasDiagnostic(result, "metadata_field_invalid"),
  "malformed fields produce stable diagnostics without throwing")

-- Broken map callbacks cannot unwind classification. Dimensions provide a
-- bounds fallback, and an explicit semantic record can still carry meaning.
local broken = fixture({ boundsError = true, tileError = true, blockError = true,
  walkError = true })
result = Terrain.classify(broken, 1, 1, {
  metadata = { kind = "switch", label = "Safe fallback switch" },
})
S.eq(result.kind, "switch", "authored metadata survives broken native predicates")
S.check(hasDiagnostic(result, "query_failed"), "broken map queries are diagnosed")
S.check(hasDiagnostic(result, "bounds_fallback"), "map dimensions safely recover bounds")
local hostileField = setmetatable({}, {
  __index = function() error("hostile merged field metadata") end,
})
result = Terrain.classify(fixture(), 1, 1, { field = hostileField })
S.eq(result.kind, "default", "hostile field metadata falls back to live map semantics")
S.check(hasDiagnostic(result, "metadata_resolution_failed"),
  "hostile field metadata is contained and diagnosed")

-- Pokémon Access's raw Red/Blue distinctions remain available only as clearly
-- marked low-confidence fallbacks where the target lacks authored tile roles.
result = Terrain.classify(fixture({ tile = 0x13, tilesetId = "INTERIOR" }), 1, 1)
S.eq(result.kind, "stairs_up", "legacy tile 0x13 identifies up stairs")
S.eq(result.confidence, "legacy", "raw stair inference never claims native confidence")
S.check(hasDiagnostic(result, "legacy_tile_fallback"), "legacy stair inference is diagnosed")
result = Terrain.classify(fixture({ tile = 0x1b, tilesetId = "INTERIOR" }), 1, 1)
S.eq(result.kind, "stairs_down", "legacy tile 0x1b identifies down stairs")
result = Terrain.classify(fixture({ tile = 0x13, tilesetId = "NEW_MOD_TILESET" }), 1, 1)
S.eq(result.kind, "default",
  "legacy global tile ids never leak into a brand-new mod tileset")
S.check(not hasDiagnostic(result, "legacy_tile_fallback"),
  "new mod tilesets do not receive a misleading legacy fallback")
result = Terrain.classify(fixture({ tile = 0x22, tilesetId = "CAVERN",
  walkable = false }), 1, 1)
S.eq(result.kind, "hole", "legacy Cavern tile 0x22 identifies a hole")
result = Terrain.classify(fixture({ tile = 0x2d, tilesetId = "CAVERN" }), 1, 1)
S.eq(result.kind, "switch", "legacy Cavern tile 0x2d identifies a switch")
result = Terrain.classify(fixture({ tile = 0x3f, tilesetId = "GYM",
  walkable = false }), 1, 1)
S.eq(result.kind, "door", "legacy Gym blocked-passage tile identifies a door")
S.eq(result.passable, false, "legacy closed doors remain blocked")

result = Terrain.classify(fixture({ block = 12, walkable = false }), 1, 1,
  { field = field, passable = true })
S.eq(result.kind, "bush", "caller traversal verdict does not erase bush terrain")
S.eq(result.passable, true, "an actual caller collision verdict beats static bush blocking")
S.eq(result.traversal, "pass", "caller-authoritative traversal is layered as pass")
S.eq(result.passabilitySource, "caller", "caller traversal provenance is retained")

-- Real generated fixtures prove the classifier follows the target registries,
-- not only test doubles.
local Map = require("src.world.Map")
local maps = require("data.generated.maps")
local tilesets = require("data.generated.tilesets")
local generatedField = require("data.generated.field")
local function liveMap(id)
  local def = assert(maps[id], "missing generated map " .. id)
  return Map.new(def, assert(tilesets[def.tileset]))
end

local rocket = liveMap("ROCKET_HIDEOUT_B2F")
result = Terrain.classify(rocket, 4, 9, { field = generatedField })
S.eq(result.kind, "directional_floor", "real Rocket Hideout spinner is semantic")
S.eq(result.direction, "left", "real generated spinner movement supplies direction")
S.eq(result.source, "field.spinners", "real spinner uses the generated gameplay registry")

local viridian = liveMap("VIRIDIAN_CITY")
result = Terrain.classify(viridian, 14, 4, { field = generatedField })
S.eq(result.kind, "bush", "real Viridian Cut block is a cuttable bush")
S.eq(result.block, 52, "real Cut fixture retains its block id")
S.eq(result.tile, 61, "real Cut fixture retains its collision tile")

local seafoam = liveMap("SEAFOAM_ISLANDS_1F")
result = Terrain.classify(seafoam, 17, 6, { field = generatedField })
S.eq(result.kind, "hole", "real generated Seafoam hole is semantic")
S.eq(result.destinationMap, "SEAFOAM_ISLANDS_B1F",
  "real Seafoam hole retains its generated destination")

local bedroom = liveMap("REDS_HOUSE_1F")
result = Terrain.classify(bedroom, 2, 7, { field = generatedField })
S.eq(result.kind, "warp", "real bedroom exit is a native warp")
S.eq(result.destinationMap, "LAST_MAP", "real warp keeps LAST_MAP semantics")
S.eq(result.confidence, "native", "real warp needs no legacy inference")

S.finish()
