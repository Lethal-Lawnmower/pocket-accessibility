-- Crystal randomizer: evolutions.
--
-- Two options, both rebuilt on every `ctx.onSave` from a vanilla copy taken the
-- first time this module runs, and put back exactly when the save is not
-- randomized (or the options are off), so loading another save in the same
-- process never keeps the previous save's evolutions.
--
-- 1. Trade evolutions without trading (`evolutions_trade`).  Every
--    EVOLVE_TRADE row becomes something a player on their own can do:
--      - a trade that needs a held item (ONIX and SCYTHER with METAL COAT,
--        POLIWHIRL and SLOWPOKE with KING'S ROCK, SEADRA with DRAGON SCALE,
--        PORYGON with UP-GRADE) becomes an item evolution with that same item:
--        use it from the PACK on the POKéMON, as with a stone.  An item use
--        rather than a level because two of these share a species with
--        another evolution (POLIWHIRL's WATER STONE, SLOWPOKE's level 37), so
--        a level could not tell the two apart, and because the item is what
--        the cart asks the player to find.
--      - a trade with no item (KADABRA, MACHOKE, GRAVELER, HAUNTER) becomes a
--        level evolution at TRADE_LEVEL (37), the level most randomizers use.
--    Rows are derived from the data, so a mod's own trade evolution converts
--    the same way.  For the item uses to work from the PACK, this module also
--    owns, per save, the `fieldMenu` of each such item in `data.items` (set to
--    ITEMMENU_PARTY, the stones' value) and its entry in
--    `data.gen2ItemEffects` (the engine's own stone record), and restores
--    both exactly.  Without that the PACK says "This isn't the time to use
--    that!" for a KING'S ROCK.
--
-- 2. Random evolutions (`evolutions`, with `evolutions_types`).  Every row
--    keeps its method and condition (level, stone, happiness, time of day,
--    TYROGUE's stat comparison); only `into` changes, to a random species.
--    Stages stay sane by construction: each species has a vanilla "height",
--    the most evolutions still ahead of it (BULBASAUR 2, IVYSAUR 1, VENUSAUR
--    and every species that never evolves 0).  A row's new target has the
--    same height as its vanilla target.  So every species keeps its height,
--    each evolution lowers it by exactly one, no chain can loop, and no chain
--    is longer than the longest vanilla one (three species).  A species that
--    starts a three-stage line in vanilla is never anyone's evolution.
--      - Never into a legendary: species the game marks genderless and unable
--        to breed (both egg groups EGG_NONE, gender ratio 255), which in
--        Crystal is exactly the eleven legendaries and UNOWN.
--      - "Keep at least one type in common": the target shares a type with
--        the species evolving (its current types, so after the pokemon
--        module's type shuffle when that is on).
--      - Two branches of one species (EEVEE's five, TYROGUE's three) evolve
--        into different species.
--      - Preferred, not required: a target at least as strong (base stat
--        total) as the species evolving, so an evolution is not a step down.
--        Each preference is dropped only when nothing meets it.
--    Each species draws from its own stream, so a result never depends on the
--    order species are visited.
--
-- What it owns, and nothing else: `def.evolutions` of every species (replaced
-- by a new list of new rows; the vanilla list table itself is restored), and
-- the two item fields above.  The shape stays the engine's: rows of
-- { method, into, level?, item?, time?, comparison? }, so the starters and
-- trainers modules, breeding (Breeding.preEvolution) and Mon.evolutionAtLevel
-- read it as they read vanilla.
--
-- Nothing in Crystal's POKéDEX or summary says how a species evolves, so
-- there is nothing to update there.  The evolution screen names the species
-- the row actually turned into.

local TRADE_LEVEL = 37
local USABLE_FIELD_MENU = "ITEMMENU_PARTY"
local NOUSE = "ITEMMENU_NOUSE"
local GENDER_UNKNOWN, NO_EGGS_RAW = 255, 255
local STAT_KEYS = { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }

local M = {
  id = "evolutions",
  TRADE_LEVEL = TRADE_LEVEL,
  questions = {
    { key = "evolutions_trade", kind = "yesno", text = "Trade evolutions\nwithout trading?",
      recommended = true, everything = true },
    { key = "evolutions", kind = "yesno", text = "Shuffle what\nPOKéMON evolve to?",
      recommended = false, everything = true },
    { key = "evolutions_types", kind = "yesno", onlyIf = "evolutions",
      text = "Keep at least one\ntype in common?", recommended = true, everything = false },
  },
}

-- ------------------------------------------------------------------ data

local function baseStatTotal(def)
  local stats = type(def) == "table" and def.baseStats
  if type(stats) ~= "table" then return nil end
  local total = 0
  for _, key in ipairs(STAT_KEYS) do
    local value = stats[key]
    if type(value) ~= "number" then return nil end
    total = total + value
  end
  return total
end

-- A species record the game can build, as opposed to the other tables
-- pokemon.lua carries at the top level (tutorMoves, tmhmMoves, growthRates).
local function isSpecies(def)
  return type(def) == "table" and type(def.index) == "number" and def.index >= 1
    and def.index % 1 == 0 and type(def.name) == "string" and baseStatTotal(def) ~= nil
end

-- The same shape the wild module leaves out (Breeding.isNoEggs plus genderless).
function M.isLegendaryShape(def)
  if def.genderRatio ~= GENDER_UNKNOWN then return false end
  if type(def.eggGroupsRaw) == "number" then return def.eggGroupsRaw == NO_EGGS_RAW end
  local groups = def.eggGroups
  return type(groups) == "table" and groups[1] == "EGG_NONE" and groups[2] == "EGG_NONE"
end

local function copyRow(row)
  local out = {}
  for k, v in pairs(row) do out[k] = v end
  return out
end

-- Species ids sorted by dex index, then id: never pairs() order.
local function sortedSpecies(pokemon)
  local list = {}
  for id, def in pairs(pokemon) do
    if type(id) == "string" and isSpecies(def) then list[#list + 1] = id end
  end
  table.sort(list, function(a, b)
    local ia, ib = pokemon[a].index, pokemon[b].index
    if ia ~= ib then return ia < ib end
    return a < b
  end)
  return list
end

-- The vanilla copy: each species' own list table (restored by reference) and
-- value copies of its rows (built from, so nothing a later write does to a
-- live row can leak into the next build).
local function snapshot(pokemon)
  local vanilla, order = {}, sortedSpecies(pokemon)
  for _, id in ipairs(order) do
    local def = pokemon[id]
    local rows = {}
    for i, row in ipairs(type(def.evolutions) == "table" and def.evolutions or {}) do
      rows[i] = copyRow(row)
    end
    vanilla[id] = { list = def.evolutions, rows = rows }
  end
  return vanilla, order
end

-- Height: the most evolutions still ahead of a species in vanilla.  Guarded
-- against a looping mod dataset (a loop counts as height 0 where it closes).
local function heights(vanilla, order)
  local out, visiting = {}, {}
  local function height(id)
    if out[id] then return out[id] end
    if visiting[id] or not vanilla[id] then return 0 end
    visiting[id] = true
    local best = 0
    for _, row in ipairs(vanilla[id].rows) do
      if row.into and vanilla[row.into] then best = math.max(best, 1 + height(row.into)) end
    end
    visiting[id] = nil
    out[id] = best
    return best
  end
  for _, id in ipairs(order) do height(id) end
  return out
end

-- Species a random evolution may land on, by height, in dex order.
local function targetPools(pokemon, order, height)
  local pools = {}
  for _, id in ipairs(order) do
    if not M.isLegendaryShape(pokemon[id]) then
      local h = height[id]
      pools[h] = pools[h] or {}
      table.insert(pools[h], id)
    end
  end
  return pools
end

-- ------------------------------------------------------- trade evolutions

-- The row a trade row becomes.  `items` is data.items (an item the game does
-- not know cannot be used, so that row becomes a level evolution instead).
function M.convertTradeRow(row, items)
  if row.method ~= "EVOLVE_TRADE" then return row end
  local out = { into = row.into }
  if row.item and type(items) == "table" and type(items[row.item]) == "table" then
    out.method, out.item = "EVOLVE_ITEM", row.item
  else
    out.method, out.level = "EVOLVE_LEVEL", TRADE_LEVEL
  end
  return out
end

-- ------------------------------------------------------- random evolutions

local function sharesType(a, b)
  local ta, tb = a.types or {}, b.types or {}
  for _, x in ipairs(ta) do
    for _, y in ipairs(tb) do
      if x == y then return true end
    end
  end
  return false
end

-- New `into` for each of `rows` (rows of species `id`).
local function shuffleTargets(ctx, pokemon, state, id, rows, keepType)
  local rng = ctx.rng("evolutions", id)
  local def = pokemon[id]
  local strength = baseStatTotal(def) or 0
  local used = {}
  for _, row in ipairs(rows) do
    local vanillaInto = row.into
    local pool = vanillaInto and state.pools[state.height[vanillaInto] or -1]
    if pool then
      local tiers = { {}, {}, {}, {} }
      for _, candidate in ipairs(pool) do
        if candidate ~= id and not used[candidate] then
          local cdef = pokemon[candidate]
          local typed = (not keepType) or sharesType(def, cdef)
          local strong = (baseStatTotal(cdef) or 0) >= strength
          if typed and strong then table.insert(tiers[1], candidate) end
          if typed then table.insert(tiers[2], candidate) end
          if strong then table.insert(tiers[3], candidate) end
          table.insert(tiers[4], candidate)
        end
      end
      for _, tier in ipairs(tiers) do
        if #tier > 0 then
          row.into = rng:pick(tier)
          break
        end
      end
      used[row.into] = true
    end
  end
end

-- ------------------------------------------------------------ item fields

-- The record an evolution item gets: the engine's own stone record when it
-- is reachable (so the evolution.check hook and the Everstone rule are the
-- engine's), else an equivalent (tests run without the engine).
local function stoneRecord(state)
  if state.stoneRecord then return state.stoneRecord end
  local ok, ItemEffects = pcall(require, "src.core.gen2.ItemEffects")
  local engine = ok and type(ItemEffects) == "table" and ItemEffects.RECORDS
    and ItemEffects.RECORDS.WATER_STONE
  local use
  if type(engine) == "table" and type(engine.use) == "function" then
    use = engine.use
  else
    use = function(useCtx)
      local mon, data = useCtx.mon, useCtx.data
      local def = data and data.pokemon and mon and data.pokemon[mon.species]
      if mon and mon.item ~= "EVERSTONE" and def then
        for _, row in ipairs(def.evolutions or {}) do
          if row.method == "EVOLVE_ITEM" and row.item == useCtx.item then
            return { used = true, evolution = row }
          end
        end
      end
      return { used = false, text = "It won't have any\neffect." }
    end
  end
  state.stoneRecord = { use = use, action = "stone", field = true, needsTarget = true,
    randomizer = "evolutions" }
  return state.stoneRecord
end

-- Put back every item field this module set.
local function restoreItems(data, state)
  for itemId, saved in pairs(state.itemsChanged or {}) do
    local def = data.items and data.items[itemId]
    if type(def) == "table" then def.fieldMenu = saved.fieldMenu end
    local effects = data.gen2ItemEffects
    if type(effects) == "table" then effects[itemId] = saved.effect end
  end
  if state.createdEffects and data.gen2ItemEffects == state.createdEffects then
    data.gen2ItemEffects = nil
  end
  state.itemsChanged, state.createdEffects = {}, nil
end

-- Make `itemId` usable from the PACK on a party POKéMON, as a stone is.
local function enableItem(data, state, itemId)
  local def = data.items and data.items[itemId]
  if type(def) ~= "table" or def.fieldMenu ~= NOUSE then return false end
  if state.itemsChanged[itemId] then return true end
  local effects = data.gen2ItemEffects
  if effects ~= nil and type(effects) ~= "table" then return false end
  if effects == nil then
    effects = {}
    data.gen2ItemEffects = effects
    state.createdEffects = effects
  end
  -- An item that already has a party action (a mod's) is left alone.
  if effects[itemId] ~= nil then return false end
  state.itemsChanged[itemId] = { fieldMenu = def.fieldMenu, effect = effects[itemId] }
  def.fieldMenu = USABLE_FIELD_MENU
  effects[itemId] = stoneRecord(state)
  return true
end

-- ------------------------------------------------------------- the build

-- Rebuild (or restore) evolutions for the save that just became known.
-- `state` keeps the vanilla copy between calls.  Returns a short summary.
function M.apply(data, ctx, state)
  local pokemon = data and data.pokemon
  if type(pokemon) ~= "table" then return "no data.pokemon" end
  if not state.vanilla then
    state.vanilla, state.order = snapshot(pokemon)
    state.height = heights(state.vanilla, state.order)
    state.pools = targetPools(pokemon, state.order, state.height)
    state.itemsChanged = {}
  end
  restoreItems(data, state)

  local active = ctx.active()
  local convert = active and ctx.option("evolutions_trade") == true
  local shuffle = active and ctx.option("evolutions") == true
  local keepType = ctx.option("evolutions_types") == true

  local converted, shuffled, items = 0, 0, {}
  for _, id in ipairs(state.order) do
    local v, def = state.vanilla[id], pokemon[id]
    if def then
      if (convert or shuffle) and #v.rows > 0 then
        local rows = {}
        for i, row in ipairs(v.rows) do
          rows[i] = copyRow(row)
          if convert and row.method == "EVOLVE_TRADE" then
            rows[i] = M.convertTradeRow(rows[i], data.items)
            converted = converted + 1
            if rows[i].method == "EVOLVE_ITEM" then items[rows[i].item] = true end
          end
        end
        if shuffle then
          shuffleTargets(ctx, pokemon, state, id, rows, keepType)
          shuffled = shuffled + 1
        end
        def.evolutions = rows
      else
        def.evolutions = v.list
      end
    end
  end
  local enabled = {}
  for itemId in pairs(items) do
    if enableItem(data, state, itemId) then enabled[#enabled + 1] = itemId end
  end
  table.sort(enabled)
  return ("trade rows %s (%d), targets %s (%d species%s), items usable: %s"):format(
    convert and "converted" or "vanilla", converted,
    shuffle and "shuffled" or "vanilla", shuffled,
    shuffle and (keepType and ", shared type" or ", any type") or "",
    #enabled > 0 and table.concat(enabled, ",") or "none")
end

function M.install(mod, ctx)
  local state = {}
  ctx.onSave(function()
    local ok, game = pcall(function() return mod and mod.game end)
    local data = ok and game and game.data
    if not data then
      ctx.log("evolutions: no game data yet; nothing changed")
      return
    end
    -- A different data table (a new boot of the dataset) needs a new copy.
    if state.data ~= data then
      for k in pairs(state) do state[k] = nil end
      state.data = data
    end
    ctx.log("evolutions: %s", M.apply(data, ctx, state))
  end)
end

return M
