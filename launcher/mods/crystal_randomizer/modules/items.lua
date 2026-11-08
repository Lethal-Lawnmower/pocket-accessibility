-- Crystal randomizer: items found on the ground.
--
-- An item ball is a map object whose `itemball = { item, quantity }` the
-- extractor read out of the cart (data.gen2Maps[map].objects[i]); a hidden item
-- is a bg event whose `hiddenItem = { item, event }` it read the same way.  The
-- world builds the pickup script from those two fields each time the player
-- presses A (src/world/gen2/World.lua, src/world/gen2/HiddenItems.lua), and the
-- navigation layer names a ball's item from the same field
-- (src/access/nav/gen2/WorldSnapshot.lua itemBallItem).  So this module changes
-- those fields in place, and both what the player is told is there and what
-- they pick up come from one value.
--
-- It is a per-save rebuild in ctx.onSave: every change it made is put back
-- first, and then, only for a randomized save that asked for it, the items are
-- shuffled again from that save's seed.  A vanilla save therefore sees the
-- cart's own tables.
--
-- Shuffle, not replace: the contents of every eligible ball are dealt out again
-- among the eligible balls (item and quantity travel together), and hidden
-- items among hidden items, so the game holds the same items as before, in
-- other places.  Never moved, and never moved onto: key items (pocket
-- KEY_ITEM) and anything the bag will not let the player toss (the HMs, the
-- MACHINE PART, the SQUIRTBOTTLE, ...), which is what the story checks for.
-- A location whose item the game data does not name is left alone too.

local M = {
  id = "items",
  questions = {
    -- Both on in either setup (owner, 2026-11-08).
    { key = "items", kind = "yesno", text = "Shuffle the items\non the ground?",
      recommended = true, everything = true },
    { key = "items_hidden", kind = "yesno", onlyIf = "items",
      text = "Shuffle hidden\nitems too?", recommended = true, everything = true },
  },
}

-- index -> item id for a data.items table.
local function itemsByIndex(items)
  local out = {}
  for id, def in pairs(items or {}) do
    if type(def) == "table" and type(def.index) == "number" then out[def.index] = id end
  end
  return out
end

-- True when an item may be moved: the game data names it, it is not a key
-- item, and it can be tossed (HMs and story items cannot).
function M.movable(def)
  if type(def) ~= "table" then return false end
  if def.pocket == "KEY_ITEM" then return false end
  if def.canToss == false then return false end
  return true
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- Every eligible location, sorted by a fixed key, as
-- { key, target = the itemball / hiddenItem table, item, quantity }.
function M.locations(maps, items, wantHidden)
  local byIndex = itemsByIndex(items)
  local balls, hidden = {}, {}
  for _, mapId in ipairs(sortedKeys(maps)) do
    local map = maps[mapId]
    if type(map) == "table" then
      for i, object in ipairs(map.objects or {}) do
        local ball = type(object) == "table" and object.itemball
        if type(ball) == "table" and type(ball.item) == "number" then
          local id = byIndex[ball.item]
          if id and M.movable(items[id]) then
            balls[#balls + 1] = {
              key = string.format("%s#%03d", tostring(mapId), object.index or i),
              target = ball, item = ball.item, quantity = ball.quantity,
            }
          end
        end
      end
      if wantHidden then
        for i, ev in ipairs(map.bgEvents or {}) do
          local data = type(ev) == "table" and ev.hiddenItem
          if type(data) == "table" and type(data.item) == "number" then
            local id = byIndex[data.item]
            if id and M.movable(items[id]) then
              hidden[#hidden + 1] = {
                -- the found flag is unique per hidden item; the map and slot
                -- break a tie should a mod reuse one
                key = string.format("%05d#%s#%03d", tonumber(data.event) or 0,
                  tostring(mapId), i),
                target = data, item = data.item,
              }
            end
          end
        end
      end
    end
  end
  local byKey = function(a, b) return a.key < b.key end
  table.sort(balls, byKey)
  table.sort(hidden, byKey)
  return balls, hidden
end

-- The new contents for `list`: a permutation of its own contents from the
-- stream named `stream`.  Returns { [i] = { item, quantity } }.
function M.deal(ctx, stream, list)
  local contents = {}
  for i, loc in ipairs(list) do contents[i] = { item = loc.item, quantity = loc.quantity } end
  return ctx.rng("items", stream):shuffled(contents)
end

function M.install(mod, ctx)
  -- What this module changed: { target, field, vanilla } rows, put back by
  -- restore().  Cleared once restored, so a second restore does nothing.
  local changed = {}

  local function restore()
    for i = #changed, 1, -1 do
      local row = changed[i]
      row.target[row.field] = row.vanilla
    end
    changed = {}
  end

  local function set(target, field, value)
    if target[field] == value then return end
    changed[#changed + 1] = { target = target, field = field, vanilla = target[field] }
    target[field] = value
  end

  local function gameData()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    if type(data) == "table" and type(data.gen2Maps) == "table"
       and type(data.items) == "table" then
      return data
    end
    return nil
  end

  local function apply()
    local data = gameData()
    if not data then
      ctx.log("items: no game data yet; nothing shuffled")
      return
    end
    local balls, hidden = M.locations(data.gen2Maps, data.items,
      ctx.option("items_hidden") and true or false)
    local dealt = M.deal(ctx, "balls", balls)
    for i, loc in ipairs(balls) do
      set(loc.target, "item", dealt[i].item)
      set(loc.target, "quantity", dealt[i].quantity)
    end
    if ctx.option("items_hidden") then
      local dealtHidden = M.deal(ctx, "hidden", hidden)
      for i, loc in ipairs(hidden) do set(loc.target, "item", dealtHidden[i].item) end
    end
    ctx.log("items: shuffled %d balls, %d hidden", #balls,
      ctx.option("items_hidden") and #hidden or 0)
  end

  ctx.onSave(function(active)
    restore()
    if active and ctx.option("items") then apply() end
  end)
end

return M
