-- Reused from the old Pocket Accessibility project (src/world/CutTrees.lua at
-- commit 71cdd419e) under decision 20; read-only use by navigation.

-- Shared Cut eligibility and block-swap lookup.
--
-- The ids in field.cutTreeSwaps are tileset-local block ids.  They are only
-- replacement mechanics after UsedCut has accepted the collision tile in
-- front of the player; treating them as global identifiers corrupts indoor
-- maps whose unrelated blocks happen to use the same number.

local CutTrees = {}

local UPSTREAM_CUT_TILES = { OVERWORLD = { 0x3d }, GYM = { 0x50 } }

local function contains(list, value)
  if type(list) ~= "table" then return false end
  for _, item in ipairs(list) do
    if item == value then return true end
  end
  return false
end

local function appliesToTileset(swap, tilesetId)
  if swap.tileset ~= nil and swap.tileset ~= tilesetId then return false end
  if swap.tilesets ~= nil and not contains(swap.tilesets, tilesetId) then return false end
  return true
end

-- Return the valid swap for one live cell, or nil.  Map/tileset metadata may
-- override the generated rules, allowing content mods to define Cut without
-- inheriting Kanto's numeric tile ids.
function CutTrees.swapAt(map, field, x, y)
  if type(map) ~= "table" or type(field) ~= "table"
     or type(x) ~= "number" or type(y) ~= "number" then return nil end
  if type(map.inBounds) == "function" and not map:inBounds(x, y) then return nil end

  local def = type(map.def) == "table" and map.def or {}
  local tileset = type(map.tileset) == "table" and map.tileset or {}
  local tilesetId = def.tileset or tileset.id
  local cutTiles = def.cutTiles
  if cutTiles == nil then cutTiles = tileset.cutTiles end
  if cutTiles == nil and type(field.cutTiles) == "table" then
    cutTiles = field.cutTiles[tilesetId]
  end
  -- v0.3.98 adaptation: upstream generates no cutTiles data; its own Cut
  -- check (OverworldState:tryCut, engine/overworld/cut.asm UsedCut) fixes
  -- the tree tiles in code: OVERWORLD 0x3d and GYM 0x50.
  if cutTiles == nil then cutTiles = UPSTREAM_CUT_TILES[tilesetId] end
  local bx, by = math.floor(x / 2), math.floor(y / 2)
  local block = map:blockAt(bx, by)
  local blockTiles = type(tileset.blocks) == "table" and tileset.blocks[block + 1]
  local hasCutTile = false
  if type(blockTiles) == "table" then
    for _, tile in ipairs(blockTiles) do
      if contains(cutTiles, tile) then hasCutTile = true break end
    end
  else
    -- Lightweight mod/test maps may expose only the collision-tile query.
    hasCutTile = contains(cutTiles, map:cellTile(x, y))
  end
  if not hasCutTile then return nil end

  for _, swap in ipairs(field.cutTreeSwaps or {}) do
    if type(swap) == "table" and swap.before == block
       and appliesToTileset(swap, tilesetId) then
      -- Never let malformed or mod-authored data install a block the active
      -- tileset cannot render.  This is the last defense before mutation.
      if type(tileset.blocks) == "table" and tileset.blocks[swap.after + 1] == nil then
        return nil
      end
      return swap
    end
  end
  return nil
end

return CutTrees
