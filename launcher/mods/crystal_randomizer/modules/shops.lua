-- Crystal randomizer: what the marts sell.
--
-- Where a shop's list comes from: the extractor writes data/items/marts.asm's
-- `Marts` table as data.gen2Marts.lists, a 1-based array in MART_* order (mart
-- id 0, MART_CHERRYGROVE, is lists[1]).  The `pokemart` script command opens
-- src/ui/gen2/MartMenu.lua through World:openMart, which passes the world's
-- `marts` (the same table as data.gen2Marts, held by reference in
-- World:dataTable).  MartMenu.new builds its `entries` from
-- lists[martId + 1] each time a clerk is spoken to, prices each row from the
-- item's own `price`, draws those rows, sells those rows, and the screen
-- reader's mart presenter (src/access/screens/gen2/Items.lua martRow) speaks
-- those same `entries`.  So this module swaps whole shelves in that one table,
-- and what is drawn, spoken and sold is one list.  A shop already open when a
-- save switches keeps its list, but a save cannot switch inside a shop.
--
-- Per save, in ctx.onSave: every shelf this module replaced is put back (the
-- cart's own list tables, by reference), then, for a randomized save that
-- asked for it, new shelves are built from that save's seed.  The vanilla
-- tables are never edited, only replaced and put back.
--
-- What is decided (owner request 2026-11-08; the choices are this module's):
--
-- * Kinds of shelf, read from the vanilla stock rather than typed in.  A
--   "general" shelf sells any BALL or one of the cart's DefaultMart items
--   (POKE_BALL, POTION: GetMart's fallback shop in data/items/marts.asm).
--   That is every town mart, the Cianwood pharmacy, Mahogany's shop and both
--   department stores' 2F counters.  Every other shelf (the department
--   stores' X item, vitamin and TM floors, Celadon 4F, the Mt. Moon shop and
--   the Underground herb shop) is a specialty shelf.
-- * Shuffle (`shops`): every slot of every shelf is redrawn from the items of
--   the same kind, where a kind is the item's pocket plus its battle and field
--   menu actions (so a medicine slot gets something used on a POKeMON, a BALL
--   slot a BALL, a TM slot a TM).  No item twice on one shelf; a shelf keeps
--   its length.
-- * Better marts (`shops_better`), on the vanilla stock or the shuffled one:
--   every general shelf also sells the next BALL and the next potion above the
--   best it already has (the ladders are the BALLs and HP-restoring medicines
--   that at least three vanilla shelves sell: POKE, GREAT, ULTRA BALL and
--   POTION, SUPER, HYPER, MAX POTION on Crystal), and the shelves whose whole
--   vanilla stock is the same kind as the evolution stones (the vitamin floors,
--   Goldenrod 4F and Celadon 5F) also sell every item an EVOLVE_ITEM
--   evolution uses, read from the current evolutions at switch time.
-- * With either option, every general shelf sells POKE_BALL and POTION (a missing
--   BALL goes first, a missing POTION after the BALLs).  That includes Cherrygrove before the POKeDEX, which
--   sells no BALL on the cart: the owner asked for BALLs from the start.
-- * Never sold: key items, anything that cannot be tossed (the HMs), items
--   priced 0 (MASTER BALL, PARK BALL and, on Crystal, MOON STONE) and the
--   cart's unused entries (priced $9999, or named like one).
-- * Untouched: the Goldenrod bargain shop (its rows carry their own prices,
--   one of each) and the Game Corner prize counters (script menus, not mart
--   data).  Prices are always the item's own, as MartMenu charges them.

local M = {
  id = "shops",
  questions = {
    { key = "shops", kind = "yesno", text = "Shuffle what the\nmarts sell?",
      recommended = false, everything = true },
    { key = "shops_better", kind = "yesno",
      text = "Better marts: more\nBALLS, healing and\vstones. Want it?",
      recommended = true, everything = true },
  },
}

-- GetMart's DefaultMart, in shelf order: what every general shelf must sell.
M.ESSENTIALS = { "POKE_BALL", "POTION" }
-- An item on this many vanilla shelves is common enough to be a ladder rung.
M.COMMON = 3
-- ItemAttributes' price for the cart's unused item slots ($9999).
local PLACEHOLDER_PRICE = 0x9999

local function sortedIds(items)
  local ids = {}
  for id, def in pairs(items or {}) do
    if type(def) == "table" and type(id) == "string" then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b)
    local ia, ib = tonumber(items[a].index) or 1e9, tonumber(items[b].index) or 1e9
    if ia ~= ib then return ia < ib end
    return a < b
  end)
  return ids
end

-- The upstream rule for a placeholder name (src/box/Items.lua).
local function placeholderName(name)
  return type(name) ~= "string" or name == "" or name:match("^%?+$") ~= nil or name == "TERU-SAMA"
end

-- True when a mart may sell the item.
function M.sellable(def)
  if type(def) ~= "table" then return false end
  if def.pocket == "KEY_ITEM" or def.canToss == false then return false end
  local price = tonumber(def.price)
  if not price or price <= 0 or price == PLACEHOLDER_PRICE then return false end
  if placeholderName(def.name) then return false end
  return true
end

-- An item's kind: its pocket and what it does from the battle and field menus.
function M.kind(def)
  return tostring(def.pocket) .. "|" .. tostring(def.battleMenu) .. "|" .. tostring(def.fieldMenu)
end

-- The shelves of a data.gen2Marts table, as MartMenu.inventory reads them.
function M.shelves(marts)
  if type(marts) ~= "table" then return nil end
  if type(marts.lists) == "table" then return marts.lists end
  return nil
end

local function contains(list, id)
  for i, v in ipairs(list) do if v == id then return i end end
  return nil
end

local function copy(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

-- Reads the vanilla shelves once: which are general, which hold one kind
-- only, and how many shelves sell each item.
function M.survey(lists, items)
  local general, singleKind, sold = {}, {}, {}
  local essential = {}
  for _, id in ipairs(M.ESSENTIALS) do essential[id] = true end
  for i, list in ipairs(lists) do
    local kinds, seen = {}, {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
      local def = items[id]
      if essential[id] or (type(def) == "table" and def.pocket == "BALL") then general[i] = true end
      if type(def) == "table" then kinds[M.kind(def)] = true end
      if not seen[id] then seen[id] = true; sold[id] = (sold[id] or 0) + 1 end
    end
    local only, count = nil, 0
    for k in pairs(kinds) do only, count = k, count + 1 end
    if count == 1 then singleKind[i] = only end
  end
  return { general = general, singleKind = singleKind, sold = sold }
end

-- The BALL ladder and the potion ladder, cheapest first.
function M.ladders(items, survey)
  local balls, potions = {}, {}
  local potion = items[M.ESSENTIALS[2]]
  local potionKind = type(potion) == "table" and M.kind(potion) or nil
  for _, id in ipairs(sortedIds(items)) do
    local def = items[id]
    if (survey.sold[id] or 0) >= M.COMMON and M.sellable(def) then
      if def.pocket == "BALL" then
        balls[#balls + 1] = id
      elseif potionKind and M.kind(def) == potionKind and (tonumber(def.heldParameter) or 0) > 0
          and (def.heldEffect == nil or def.heldEffect == "HELD_NONE") then
        potions[#potions + 1] = id
      end
    end
  end
  local byPrice = function(a, b)
    if items[a].price ~= items[b].price then return items[a].price < items[b].price end
    return (items[a].index or 0) < (items[b].index or 0)
  end
  table.sort(balls, byPrice)
  table.sort(potions, byPrice)
  return balls, potions
end

-- Every sellable item an EVOLVE_ITEM evolution uses, in item order.
function M.evolutionItems(items, pokemon)
  local wanted = {}
  for _, def in pairs(pokemon or {}) do
    for _, evo in ipairs(type(def) == "table" and type(def.evolutions) == "table" and def.evolutions or {}) do
      if type(evo) == "table" and evo.method == "EVOLVE_ITEM" and type(evo.item) == "string" then
        wanted[evo.item] = true
      end
    end
  end
  local out = {}
  for _, id in ipairs(sortedIds(items)) do
    if wanted[id] and M.sellable(items[id]) then out[#out + 1] = id end
  end
  return out
end

-- An unused item from `candidates`, starting at a random place.
local function draw(rng, candidates, used)
  local n = #candidates
  if n == 0 then return nil end
  local start = rng:int(1, n)
  for k = 0, n - 1 do
    local id = candidates[(start + k - 1) % n + 1]
    if not used[id] then return id end
  end
  return nil
end

-- One shelf redrawn: each slot gets an item of the same kind.
function M.shuffleShelf(list, items, pool, byKind, rng)
  local out, used = {}, {}
  for _, id in ipairs(list) do
    local def = items[id]
    local pick
    if type(def) ~= "table" then
      pick = not used[id] and id or nil -- an id the data does not know is left as it is
    else
      pick = draw(rng, byKind[M.kind(def)] or {}, used) or draw(rng, pool, used)
    end
    if pick then out[#out + 1] = pick; used[pick] = true end
  end
  return out
end

-- Puts the rung above the best one `shelf` sells right after it.
local function climb(shelf, ladder)
  local best, at = 0, nil
  for r, id in ipairs(ladder) do
    local i = contains(shelf, id)
    if i then best, at = r, i end
  end
  local nextId = ladder[best + 1]
  if best > 0 and nextId and not contains(shelf, nextId) then
    table.insert(shelf, at + 1, nextId)
  end
end

-- The new shelves for these options: { [i] = list } for every shelf, built
-- from the vanilla `lists` without changing them.  `rngFor(i)` gives shelf
-- i's generator.  options: { shops = bool, better = bool }.
function M.plan(lists, items, pokemon, options, rngFor)
  local survey = M.survey(lists, items)
  local pool, byKind = {}, {}
  for _, id in ipairs(sortedIds(items)) do
    local def = items[id]
    if M.sellable(def) then
      pool[#pool + 1] = id
      local k = M.kind(def)
      byKind[k] = byKind[k] or {}
      table.insert(byKind[k], id)
    end
  end
  local balls, potions, stones
  if options.better then
    balls, potions = M.ladders(items, survey)
    stones = M.evolutionItems(items, pokemon)
  end
  local stoneKind
  for _, id in ipairs(stones or {}) do
    stoneKind = stoneKind or {}
    stoneKind[M.kind(items[id])] = true
  end

  local out = {}
  for i, list in ipairs(lists) do
    local shelf = type(list) == "table" and copy(list) or {}
    if options.shops then shelf = M.shuffleShelf(shelf, items, pool, byKind, rngFor(i)) end
    if survey.general[i] then
      -- a missing BALL goes first (the cheapest BALL leads, as on the cart),
      -- anything else right after the shelf's last BALL
      for _, id in ipairs(M.ESSENTIALS) do
        local def = items[id]
        if M.sellable(def) and not contains(shelf, id) then
          local at = 1
          if def.pocket ~= "BALL" then
            for j, other in ipairs(shelf) do
              if type(items[other]) == "table" and items[other].pocket == "BALL" then at = j + 1 end
            end
          end
          table.insert(shelf, at, id)
        end
      end
      if options.better then
        climb(shelf, balls)
        climb(shelf, potions)
      end
    elseif options.better and stoneKind and survey.singleKind[i] and stoneKind[survey.singleKind[i]] then
      for _, id in ipairs(stones) do
        if not contains(shelf, id) then shelf[#shelf + 1] = id end
      end
    end
    out[i] = shelf
  end
  return out, survey
end

local function sameList(a, b)
  if type(a) ~= "table" or #a ~= #b then return false end
  for i = 1, #b do if a[i] ~= b[i] then return false end end
  return true
end

function M.install(mod, ctx)
  -- { lists, index, vanilla } rows: the shelves this module replaced.
  local replaced = {}

  local function restore()
    for i = #replaced, 1, -1 do
      local row = replaced[i]
      row.lists[row.index] = row.vanilla
    end
    replaced = {}
  end

  local function gameData()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    if type(data) == "table" and type(data.items) == "table" and M.shelves(data.gen2Marts) then
      return data
    end
    return nil
  end

  local function apply()
    local data = gameData()
    if not data then
      ctx.log("shops: no mart data yet; nothing changed")
      return
    end
    local lists = M.shelves(data.gen2Marts)
    local options = { shops = ctx.option("shops") and true or false,
      better = ctx.option("shops_better") and true or false }
    local planned = M.plan(lists, data.items, data.pokemon, options,
      function(i) return ctx.rng("shops", "shelf", i) end)
    local changed = 0
    for i, shelf in ipairs(planned) do
      if not sameList(lists[i], shelf) then
        replaced[#replaced + 1] = { lists = lists, index = i, vanilla = lists[i] }
        lists[i] = shelf
        changed = changed + 1
      end
    end
    ctx.log("shops: %d of %d shelves changed (shuffle %s, better %s)", changed, #lists,
      tostring(options.shops), tostring(options.better))
  end

  ctx.onSave(function(active)
    restore()
    if active and (ctx.option("shops") or ctx.option("shops_better")) then apply() end
  end)
end

return M
