local T = require("tests.harness")
local S = T.suite("accessibility interactive world objects")
local Accessibility = require("src.access.nav.Navigation")

local function fakeMap(id, width, height, blocks, walkable)
  local map = {
    id = id, widthCells = width, heightCells = height,
    def = { id = id, tileset = "MOD_TILESET" },
    tileset = { id = "MOD_TILESET" },
  }
  function map:inBounds(x, y)
    return x >= 0 and y >= 0 and x < width and y < height
  end
  function map:blockAt(x, y) return blocks[y .. "," .. x] or 0 end
  function map:isWalkableCell(x, y)
    return walkable and walkable[y .. "," .. x] == true or false
  end
  function map:cellTile() return 0 end
  function map:warpAtCell() return nil end
  function map:signAtCell() return nil end
  function map:isWarpTileCell() return false end
  function map:isCounterCell() return false end
  function map:isGrassCell() return false end
  function map:isWaterCell() return false end
  return map
end

local cans = {}
for i = 0, 14 do
  cans[#cans + 1] = { can = i, x = 1 + math.floor(i / 3) * 2,
                      y = 7 + (i % 3) * 2 }
end
local field = {
  cutTiles = { MOD_TILESET = { 0 } },
  cutTreeSwaps = { { before = 50, after = 109 } },
  hiddenExtras = { trashCans = {
    cans = cans, adjacent = { [0] = { 1, 3 }, [4] = { 1, 3, 5, 7 } },
  } },
}
local access = setmetatable({
  game = { data = { field = field }, save = {
    options = { puzzleAssistance = true }, flags = {}, trashPuzzle = {},
  } },
  terrainSemantics = {
    classify = function() return { kind = "bush", label = "cuttable bush" } end,
  },
}, Accessibility)

local gym = fakeMap("VERMILION_GYM", 20, 20, {})
local gymObjects = access:interactiveBrowseObjects({ map = gym })
S.eq(#gymObjects, 15, "all fifteen Vermilion Gym cans are browse objects")
S.same({ gymObjects[1].id, gymObjects[1].label,
         gymObjects[1].stateText, gymObjects[15].x, gymObjects[15].y },
       { "trash_can:VERMILION_GYM:0", "Trash Can 1", "not checked", 9, 11 },
  "default puzzle assistance numbers cans and reports live search state")
access.game.save.options.puzzleAssistance = false
gymObjects = access:interactiveBrowseObjects({ map = gym })
S.same({ gymObjects[1].label, gymObjects[1].stateText },
       { "Trash Can", nil },
  "disabling puzzle assistance restores strict Pokemon Access can labels")
access.game.save.options.puzzleAssistance = true
access.game.save.trashPuzzle.checked = { [1] = true }
gymObjects = access:interactiveBrowseObjects({ map = gym })
S.eq(gymObjects[1].stateText, "checked, no switch",
  "assistance remembers a confirmed empty can during the current roll")
access.game.save.flags.EVENT_1ST_LOCK_OPENED = true
access.game.save.trashPuzzle = { activatedFirst = 4, second = 7 }
gymObjects = access:interactiveBrowseObjects({ map = gym })
S.eq(gymObjects[5].stateText, "first hidden switch toggled",
  "assistance identifies the activated first switch")
S.eq(gymObjects[1].stateText, "possible second hidden switch, not toggled",
  "assistance preserves the canonical underflow candidate after lock one")

local cutMap = fakeMap("MOD_GARDEN", 4, 4, { ["1,1"] = 50 })
cutMap.def.accessibilityObjects = {
  { id = "mod_fountain", label = "Musical Fountain", x = 3, y = 3,
    interaction = "inspect" },
}
local cutWorld = { map = cutMap, player = { cellX = 3, cellY = 1 } }
local cutObjects = access:interactiveBrowseObjects(cutWorld)
S.eq(#cutObjects, 2,
  "one Cut block plus one mod-authored interactable produce two objects")
S.same({ cutObjects[1].id, cutObjects[1].x, cutObjects[1].y,
         cutObjects[1].label, #cutObjects[1].interactionCells },
       { "cut_tree:MOD_GARDEN:1,1", 3, 2, "cuttable bush", 4 },
  "a Cut block is deduplicated but retains its full nearest-facing footprint")
S.eq(cutObjects[2].id, "mod_fountain",
  "mods can add semantic coordinate objects without native actors")

-- Once the native block changes to its post-Cut value, no stale browse entry
-- survives the next snapshot.
cutMap.blockAt = function() return 109 end
local afterCut = access:interactiveBrowseObjects(cutWorld)
S.eq(#afterCut, 1, "a completed Cut action removes the synthetic tree object")
S.eq(afterCut[1].id, "mod_fountain",
  "unrelated authored interactables remain after the native map mutation")

-- Real GYM coverage: this is the live Celadon regression.  In particular it
-- must also pass when Data loads an older private ROM cache whose field.lua
-- predates cutTiles and receives the rule from FieldDefaults.seed.
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.CELADON_GYM) then Data:load() end
local Map = require("src.world.Map")
local gymMap = Map.new(Data.maps.CELADON_GYM, Data.tilesets.GYM)
local realAccess = setmetatable({
  game = { data = Data },
  terrainSemantics = require("src.access.nav.TerrainSemantics"),
}, Accessibility)
local realObjects = realAccess:interactiveBrowseObjects({
  map = gymMap, entities = {}, player = { cellX = 5, cellY = 8 },
})
local realTrees = 0
for _, object in ipairs(realObjects) do
  if object.id:find("cut_tree:CELADON_GYM:", 1, true) == 1 then
    realTrees = realTrees + 1
  end
end
S.check(realTrees > 0, "Celadon Gym's genuine bushes remain in the entity list")

local bedroomMap = Map.new(Data.maps.REDS_HOUSE_2F,
  Data.tilesets.REDS_HOUSE_2)
local bedroomObjects = realAccess:interactiveBrowseObjects({
  map = bedroomMap, entities = {}, player = { cellX = 0, cellY = 2 },
})
local bedroomLabels = {}
for _, object in ipairs(bedroomObjects) do bedroomLabels[object.label] = true end
S.check(bedroomLabels["Player's PC"] and bedroomLabels.SNES,
  "the bedroom PC and SNES both appear in the navigation entity list")

S.finish()
