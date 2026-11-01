local T = require("tests.harness")
local S = T.suite("accessibility world snapshot")
local WorldSnapshot = require("src.access.nav.WorldSnapshot")

local function key(x, y) return tostring(x) .. "," .. tostring(y) end

local cells = {
  [key(3, 3)] = { tile = 7, grass = true, walkable = true },
  [key(3, 2)] = { tile = 20, water = true },
  [key(1, 1)] = { tile = 12, warpTile = true, walkable = true },
  [key(2, 1)] = { tile = 13, sign = true, walkable = true },
  [key(3, 1)] = { tile = 14, counter = true },
  [key(4, 1)] = { tile = 15, walkable = true },
  [key(5, 1)] = { tile = 16 },
}

local predicateCalls = {}
local map = {
  id = "MOD_CAVE",
  widthCells = 10,
  heightCells = 8,
  def = {
    id = "MOD_CAVE",
    label = "ModCave",
    accessibility = { label = "Crystal Cavern" },
    warps = {
      { x = 1, y = 1, destMap = "MOD_HOUSE", destWarp = 1 },
      { x = 9, y = 7, destMap = "LAST_MAP", destWarp = 2 },
    },
    -- Deliberately authored out of compass order.  Snapshot order may not
    -- depend on Lua table iteration.
    connections = {
      west = { map = "WEST_WOODS", offset = -2 },
      east = { map = "EAST_ROAD", offset = 3 },
      south = { map = "SOUTH_PORT", offset = 1 },
      north = { map = "ROUTE_1", offset = 0 },
    },
    signs = {
      { x = 2, y = 1, text = "TEXT_MODCAVE_TIPS",
        accessibilityLabel = "Trainer Tips" },
      { x = 6, y = 4, text = "TEXT_MODCAVE_SWITCH" },
    },
    -- This definition is not live and must not leak into browse results.
    objects = {
      { index = 99, name = "MODCAVE_REMOVED_OBJECT", x = 0, y = 0 },
    },
  },
}

local function cell(x, y) return cells[key(x, y)] or { tile = 99 } end
function map:inBounds(x, y)
  predicateCalls.inBounds = (predicateCalls.inBounds or 0) + 1
  return x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells
end
function map:cellTile(x, y)
  predicateCalls.cellTile = (predicateCalls.cellTile or 0) + 1
  return cell(x, y).tile
end
function map:warpAtCell(x, y)
  predicateCalls.warpAtCell = (predicateCalls.warpAtCell or 0) + 1
  if x == 1 and y == 1 then return { index = 1, def = self.def.warps[1] } end
end
function map:signAtCell(x, y)
  predicateCalls.signAtCell = (predicateCalls.signAtCell or 0) + 1
  if cell(x, y).sign then return self.def.signs[1] end
end
function map:isWarpTileCell(x, y)
  predicateCalls.isWarpTileCell = (predicateCalls.isWarpTileCell or 0) + 1
  return cell(x, y).warpTile or false
end
function map:isCounterCell(x, y)
  predicateCalls.isCounterCell = (predicateCalls.isCounterCell or 0) + 1
  return cell(x, y).counter or false
end
function map:isGrassCell(x, y)
  predicateCalls.isGrassCell = (predicateCalls.isGrassCell or 0) + 1
  return cell(x, y).grass or false
end
function map:isWaterCell(x, y)
  predicateCalls.isWaterCell = (predicateCalls.isWaterCell or 0) + 1
  return cell(x, y).water or false
end
function map:isWalkableCell(x, y)
  predicateCalls.isWalkableCell = (predicateCalls.isWalkableCell or 0) + 1
  return cell(x, y).walkable or false
end

local player = {
  name = "RED", cellX = 3, cellY = 3, facing = "up", moving = false,
}
local scientist = {
  id = "MOD_CAVE_obj_4",
  cellX = 8, cellY = 7, facing = "left", moving = true,
  def = {
    index = 4, name = "MODCAVE_SCIENTIST", sprite = "SPRITE_SCIENTIST",
    x = 1, y = 2,
  },
}
local runtimeItem = {
  id = "MOD_CAVE_obj_100",
  cellX = 2, cellY = 3, facing = "down", moving = false,
  def = {
    index = 100, name = "MODCAVE_GIFT", sprite = "SPRITE_POKE_BALL",
    item = "MAX_POTION", runtime = true, owner = "fixture_mod",
    x = 9, y = 6,
  },
}
local overworld = {
  map = map,
  player = player,
  npcs = { scientist, runtimeItem },
  entities = { player, scientist, runtimeItem },
  lastOutdoor = { id = "LAST_TOWN", x = 4, y = 4 },
}
local maps = {
  MOD_HOUSE = { id = "MOD_HOUSE", label = "ModHouse" },
  LAST_TOWN = { id = "LAST_TOWN", label = "LastTown" },
  ROUTE_1 = { id = "ROUTE_1", label = "Route1" },
  SOUTH_PORT = { id = "SOUTH_PORT" },
  EAST_ROAD = { id = "EAST_ROAD" },
  WEST_WOODS = { id = "WEST_WOODS" },
}

S.eq(WorldSnapshot.locationName(map), "Crystal Cavern",
  "authored accessibility location label wins")
S.eq(WorldSnapshot.locationName({ id = "ROCK_TUNNEL_1F", label = "RockTunnel1F" }),
  "Rock Tunnel 1F", "registry id is a deterministic readable fallback")
S.eq(WorldSnapshot.locationName({ label = "SecretLab" }), "Secret Lab",
  "assembler label is humanized when no registry id exists")
S.eq(WorldSnapshot.locationName({}), "Unknown location",
  "missing mod location metadata has a nonempty fallback")
S.eq(WorldSnapshot.locationName({ id = "REDS_HOUSE_2F" }, nil, nil, "Alex"),
  "Alex's House 2F", "the player's house uses the chosen player name")
S.eq(WorldSnapshot.locationName({ id = "REDS_HOUSE_1F" }, nil,
  "Home", "Alex"), "Home", "an authored custom map name still wins")
local houseBrowse = assert(WorldSnapshot.browse({
  map = { id = "TEST", def = { id = "TEST", warps = {
    { x = 0, y = 0, destMap = "REDS_HOUSE_1F", destWarp = 1 },
  } } },
  player = { cellX = 1, cellY = 1 },
}, { maps = { REDS_HOUSE_1F = { id = "REDS_HOUSE_1F" } },
     playerName = "Alex" }))
S.eq(houseBrowse[1].label, "Alex's House 1F",
  "navigation destinations also use the chosen player name")
local sharedDestinationBrowse = assert(WorldSnapshot.browse({
  map = { id = "PLAZA", def = { id = "PLAZA", warps = {
    { x = 8, y = 8, destMap = "MOD_HOUSE", destWarp = 1 },
    { x = 2, y = 1, destMap = "MOD_HOUSE", destWarp = 2 },
    { x = 9, y = 1, destMap = "OTHER_HOUSE", destWarp = 1 },
  } } },
  player = { cellX = 1, cellY = 1 },
}, { maps = {
  MOD_HOUSE = { id = "MOD_HOUSE", label = "ModHouse" },
  OTHER_HOUSE = { id = "OTHER_HOUSE", label = "OtherHouse" },
} }))
S.eq(#sharedDestinationBrowse, 2,
  "physical entrances to one semantic destination become one browse item")
S.eq(#sharedDestinationBrowse[1].navigationCells, 2,
  "the merged destination retains every physical entrance candidate")
S.same({ sharedDestinationBrowse[1].x, sharedDestinationBrowse[1].y }, { 2, 1 },
  "browse bearing uses the nearest entrance without discarding the other")
S.eq(sharedDestinationBrowse[1].id, "warp:PLAZA:1",
  "merged destinations preserve the first legacy selection id")
S.eq(sharedDestinationBrowse[2].label, "Other House",
  "different destinations never merge merely because they are warps")
local internalPassages = assert(WorldSnapshot.browse({
  map = { id = "TEST_CAVE_1F", def = { id = "TEST_CAVE_1F", warps = {
    { x = 2, y = 2, destMap = "TEST_CAVE_B1F", destWarp = 1 },
    { x = 8, y = 2, destMap = "TEST_CAVE_B1F", destWarp = 3 },
    { x = 8, y = 3, destMap = "TEST_CAVE_B1F", destWarp = 4 },
    { x = 14, y = 2, destMap = "TEST_CAVE_B1F", destWarp = 6 },
  } } },
  player = { cellX = 1, cellY = 1 },
}, { maps = { TEST_CAVE_B1F = { id = "TEST_CAVE_B1F" } } }))
S.eq(#internalPassages, 3,
  "separate dungeon ladders survive destination grouping")
S.eq(#internalPassages[2].navigationCells, 2,
  "contiguous tiles for one internal passage remain one browse item")
S.same({ internalPassages[1].label, internalPassages[2].label,
         internalPassages[3].label },
  { "Test Cave B1F, entrance 1 of 3", "Test Cave B1F, entrance 2 of 3",
    "Test Cave B1F, entrance 3 of 3" },
  "same-floor destinations receive stable distinguishing numbers")

local generatedMaps = require("data.generated.maps")
local function generatedBrowse(mapId)
  local def = generatedMaps[mapId]
  return assert(WorldSnapshot.browse({
    map = { id = mapId, def = def,
      widthCells = def.width * 2, heightCells = def.height * 2 },
    player = { cellX = 1, cellY = 1 },
  }, { maps = generatedMaps }))
end
local moonB1F = {}
for _, item in ipairs(generatedBrowse("MT_MOON_1F")) do
  if item.type == "warp" and item.destinationMapId == "MT_MOON_B1F" then
    moonB1F[#moonB1F + 1] = item
  end
end
S.eq(#moonB1F, 3,
  "all three real Mt. Moon 1F ladders remain separately browseable")
S.same({ moonB1F[1].label, moonB1F[2].label, moonB1F[3].label },
  { "Mt. Moon B1F, entrance 1 of 3", "Mt. Moon B1F, entrance 2 of 3",
    "Mt. Moon B1F, entrance 3 of 3" },
  "real Mt. Moon ladders have distinct spoken identities")

local safariNorth = {}
for _, item in ipairs(generatedBrowse("SAFARI_ZONE_WEST")) do
  if item.type == "warp" and item.destinationMapId == "SAFARI_ZONE_NORTH" then
    safariNorth[#safariNorth + 1] = item
  end
end
S.eq(#safariNorth, 2,
  "Safari Zone West preserves its two separate northern passages")
S.same({ #safariNorth[1].navigationCells, #safariNorth[2].navigationCells },
  { 2, 2 }, "each Safari passage still merges its two contiguous edge tiles")
local oppositeEdgeBrowse = assert(WorldSnapshot.browse({
  map = { id = "HALL", widthCells = 10, heightCells = 10,
    def = { id = "HALL", warps = {
      { x = 4, y = 0, destMap = "MOD_HOUSE", destWarp = 1 },
      { x = 4, y = 9, destMap = "MOD_HOUSE", destWarp = 2 },
    } } },
  player = { cellX = 4, cellY = 8 },
}, { maps = { MOD_HOUSE = { id = "MOD_HOUSE", label = "ModHouse" } } }))
S.eq(#oppositeEdgeBrowse, 1,
  "opposite exits to one destination remain one browse item")
S.same({ oppositeEdgeBrowse[1].navigationCells[1].transitionInstruction,
         oppositeEdgeBrowse[1].navigationCells[2].transitionInstruction },
       { "Continue up to Mod House", "Continue down to Mod House" },
  "each merged physical exit retains its own outward instruction")
S.eq(WorldSnapshot.humanize("SS_ANNE_B1F"), "S.S. Anne B1F",
  "common map abbreviations and floors remain intelligible")

local relative = assert(WorldSnapshot.relative(5, 5, 2, 8))
S.same(relative, {
  dx = -3, dy = 3, horizontal = "left", horizontalDistance = 3,
  vertical = "down", verticalDistance = 3, distance = 6, here = false,
}, "relative result exposes signed axes and Manhattan distance")
S.eq(WorldSnapshot.formatRelative(5, 5, 2, 8), "3 down 3 left",
  "relative speech preserves vertical-then-horizontal Pokemon Access order")
S.eq(WorldSnapshot.formatRelative(5, 5, 5, 5), "here",
  "zero displacement has an explicit description")
local badRelative, relativeErr = WorldSnapshot.relative(0, nil, 1, 1)
S.check(badRelative == nil and relativeErr:find("numbers", 1, true),
  "invalid relative coordinates return a controlled error")

S.eq(WorldSnapshot.classifyCell(map, 1, 1).kind, "warp",
  "warp predicate has first semantic priority")
S.eq(WorldSnapshot.classifyCell(map, 2, 1).kind, "signpost",
  "sign lookup identifies a signpost cell")
S.eq(WorldSnapshot.classifyCell(map, 3, 1).kind, "counter",
  "counter predicate identifies a counter cell")
S.eq(WorldSnapshot.classifyCell(map, 3, 3).kind, "grass",
  "grass predicate refines a walkable cell")
S.eq(WorldSnapshot.classifyCell(map, 3, 2).kind, "water",
  "water predicate identifies water")
S.eq(WorldSnapshot.classifyCell(map, 4, 1).kind, "walkable",
  "generic walkable cell remains a path")
S.eq(WorldSnapshot.classifyCell(map, 5, 1).kind, "blocked",
  "a fully queried impassable cell is blocked")
local edge = WorldSnapshot.classifyCell(map, -1, 1)
S.eq(edge.kind, "edge", "out-of-bounds facing cells become map edges")
S.eq(predicateCalls.cellTile, 7,
  "out-of-bounds classification never asks Map for a border tile")
S.check((predicateCalls.isWaterCell or 0) > 0
        and (predicateCalls.isWalkableCell or 0) > 0,
  "classification derives terrain from native Map predicates")

local broken = {
  widthCells = 1, heightCells = 1,
  inBounds = function() return true end,
  cellTile = function() error("bad mod tile") end,
}
local ok, brokenCell = pcall(WorldSnapshot.classifyCell, broken, 0, 0)
S.check(ok and brokenCell.kind == "unknown" and #brokenCell.errors > 0,
  "broken or incomplete mod predicates cannot crash semantic capture")

local snapshot = assert(WorldSnapshot.capture(overworld, { maps = maps }))
S.eq(snapshot.mapId, "MOD_CAVE", "capture identifies the active merged map")
S.eq(snapshot.locationName, "Crystal Cavern", "capture includes location name")
S.same(snapshot.player, {
  id = "player:MOD_CAVE", type = "player", category = "player", label = "Red",
  x = 3, y = 3, facing = "up", moving = false, runtime = false,
}, "player coordinates and facing are copied semantically")
S.eq(snapshot.currentCell.kind, "grass", "current cell is classified")
S.eq(snapshot.facingCell.kind, "water", "facing cell is classified")
S.eq(#snapshot.entities, 3, "player and every live NPC are described")
S.eq(#snapshot.npcs, 2, "live NPC list excludes removed static definitions")
S.eq(snapshot.npcs[1].label, "Scientist", "map prefix is removed from object name")
S.eq(snapshot.npcs[1].x, 8, "NPC uses live coordinates, not spawn coordinates")
S.eq(snapshot.npcs[1].facing, "left", "NPC live facing is retained")
S.eq(snapshot.npcs[2].label, "Max Potion", "item metadata gives a graceful label")
S.check(snapshot.npcs[2].runtime and snapshot.npcs[2].owner == "fixture_mod",
  "runtime mod entity provenance is retained")

local chaosSnapshot = assert(WorldSnapshot.capture(overworld, {
  maps = maps, chaosCut = true,
}))
S.eq(chaosSnapshot.npcs[1].label, "Cuttable Bush (Scientist)",
  "Chaos Cut gives an ordinary actor the intentionally comic label")
S.eq(chaosSnapshot.npcs[1].interaction, "cut",
  "Chaos Cut exposes the actor's Cut interaction semantically")
S.eq(chaosSnapshot.npcs[2].label, "Max Potion",
  "Chaos Cut never relabels an item ball")
S.eq(chaosSnapshot.browse[9].label, "Cuttable Bush (Scientist)",
  "the navigable entity list uses the same Chaos Cut label")

local boulder = {
  id = "MOD_CAVE_obj_5", cellX = 5, cellY = 6, facing = "up",
  def = { index = 5, name = "MODCAVE_BOULDER", sprite = "SPRITE_BOULDER" },
}
overworld.entities[#overworld.entities + 1] = boulder
local entitySnapshot = assert(WorldSnapshot.capture(overworld, { maps = maps }))
S.eq(#entitySnapshot.npcs, 2,
  "the NPC snapshot remains an actor-specific compatibility list")
S.eq(#entitySnapshot.entities, 4,
  "the complete entity snapshot includes a live boulder outside npcs")
S.eq(entitySnapshot.browse[#entitySnapshot.browse].label, "Boulder",
  "the object browser uses the authoritative live entity list")
overworld.entities[#overworld.entities] = nil

S.eq(#snapshot.browse, 10, "all four browse categories are represented")
S.same({ snapshot.browse[1].type, snapshot.browse[2].type,
         snapshot.browse[3].type, snapshot.browse[7].type,
         snapshot.browse[9].type },
       { "warp", "warp", "connection", "signpost", "object" },
  "browse order is warps, connections, signposts, objects")
S.same({ snapshot.browse[3].direction, snapshot.browse[4].direction,
         snapshot.browse[5].direction, snapshot.browse[6].direction },
       { "north", "south", "east", "west" },
  "connection order matches Pokemon Access independent of table iteration")
S.eq(snapshot.browse[1].id, "warp:MOD_CAVE:1", "warp id is stable")
S.eq(snapshot.browse[1].label, "Mod House", "warp names its destination")
S.eq(snapshot.browse[1].relativeText, "2 up 2 left",
  "browse entry includes relative speech")
S.eq(snapshot.browse[2].label, "Last Town",
  "LAST_MAP warp resolves against live last-outdoor state")
S.eq(snapshot.browse[3].id, "connection:MOD_CAVE:north",
  "connection id is stable by compass direction")
S.eq(snapshot.browse[3].label, "North connection to Route 1",
  "connection label includes direction and destination")
S.eq(snapshot.browse[7].id, "signpost:MOD_CAVE:1", "signpost id is stable")
S.eq(snapshot.browse[7].label, "Trainer Tips", "authored sign label wins")
S.eq(snapshot.browse[8].label, "Switch", "sign text id has a graceful fallback")
S.eq(snapshot.browse[9].id, "MOD_CAVE_obj_4", "native live NPC id remains stable")
S.eq(snapshot.browse[9].description, "Scientist: 4 down 5 right; facing left",
  "entity description combines label, relative position, and facing")

local semanticSnapshot = assert(WorldSnapshot.capture(overworld, {
  maps = maps,
  interactiveObjects = {
    { id = "cut_tree:MOD_CAVE:2,2", label = "Cuttable Tree",
      x = 4, y = 4, interaction = "cut", semanticKind = "cut_tree" },
  },
}))
S.eq(semanticSnapshot.browse[9].id, "cut_tree:MOD_CAVE:2,2",
  "a native tile interactable is inserted before live actor objects")
S.eq(semanticSnapshot.browse[9].description, "Cuttable Tree: 1 down 1 right",
  "synthetic objects receive normal relative browse speech")
S.check(semanticSnapshot.browse[9].synthetic
        and semanticSnapshot.browse[9].interaction == "cut",
  "synthetic object semantics retain their interaction role")

local specialSnapshot = assert(WorldSnapshot.capture(overworld, {
  maps = maps,
  specialTraversal = {
    specialWarps = {
      { id = "mod_hole", x = 4, y = 4, kind = "hole",
        destinationMap = "MOD_HOUSE", destinationX = 1, destinationY = 2 },
    },
    switches = {
      { id = "mod_switch", x = 4, y = 1, label = "Secret switch",
        requiredFacing = "up" },
    },
  },
}))
S.eq(#specialSnapshot.browse, 12,
  "special traversal records extend rather than replace ordinary browse data")
S.same({ specialSnapshot.browse[3].type,
         specialSnapshot.browse[4].type,
         specialSnapshot.browse[10].type,
         specialSnapshot.browse[11].type },
       { "warp", "connection", "object", "object" },
  "special holes stay with warps and switches join Pokemon Access objects")
S.eq(specialSnapshot.browse[3].label, "Drop to Mod House",
  "special hole fallback names its native destination")
S.eq(specialSnapshot.browse[3].transitionInstruction, "Drop to Mod House",
  "special hole retains its final transition instruction")
S.eq(specialSnapshot.browse[10].requiredFacing, "up",
  "special switch retains its native facing requirement")
S.eq(#assert(WorldSnapshot.browse(overworld, {
  maps = maps, filter = "warps",
  specialTraversal = specialSnapshot and {
    specialWarps = { { x = 4, y = 4, kind = "hole",
                       destinationMap = "MOD_HOUSE" } },
  },
})), 3, "warp filter includes special traversal exits")

local objects = assert(WorldSnapshot.browse(overworld, { maps = maps, filter = 5 }))
S.eq(#objects, 2, "numeric Pokemon Access filter position selects objects")
S.check(objects[1].type == "object" and objects[2].type == "object",
  "object filter excludes all other categories")
local signs = assert(WorldSnapshot.browse(overworld,
  { maps = maps, filter = "signs" }))
S.eq(#signs, 2, "singular/plural filter aliases are accepted")
-- v0.3.98 addition: Area is the last category (off-map items of the area)
S.eq(WorldSnapshot.nextFilter("objects", 1), "area", "Area follows Objects")
S.eq(WorldSnapshot.nextFilter("area", 1), "all",
  "filter cycling wraps forward")
S.eq(WorldSnapshot.nextFilter("all", -1), "area",
  "filter cycling wraps backward")
local noItems, filterErr = WorldSnapshot.browse(overworld, { filter = "bogus" })
S.check(noItems == nil and filterErr:find("unknown browse filter", 1, true),
  "unknown filters return a controlled error")

snapshot.npcs[1].x = 100
snapshot.browse[1].label = "Changed"
S.eq(scientist.cellX, 8, "editing entity snapshot cannot mutate live NPC")
S.check(map.def.warps[1].label == nil,
  "editing browse snapshot cannot mutate merged map definitions")
S.check(type(snapshot.currentCell.warp) == "boolean",
  "cell snapshot never leaks a live warp record")

local noWorld, noWorldErr = WorldSnapshot.capture(nil)
S.check(noWorld == nil and noWorldErr == "no overworld",
  "capture outside the overworld is a controlled no-op")
local noPlayer, noPlayerErr = WorldSnapshot.capture({ map = map })
S.check(noPlayer == nil and noPlayerErr == "no player",
  "capture without a player is a controlled no-op")
local oddFacing = { map = map, player = {
  cellX = 1, cellY = 1, facing = "sideways",
}, npcs = {} }
local oddSnapshot = assert(WorldSnapshot.capture(oddFacing))
S.check(oddSnapshot.facingCell == nil
        and oddSnapshot.facingError:find("sideways", 1, true),
  "unknown mod facing values are reported without throwing")

S.finish()
