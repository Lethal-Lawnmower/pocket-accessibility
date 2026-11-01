-- Presenters for Gen 1 information screens: Pokemon summary, move pickers,
-- trainer card, Pokedex list and entry, options and town map.  Same
-- contract as Presenters.lua (matches / poll); each reads what the upstream
-- screen draws, citing the draw code it mirrors.

local InfoScreens = {}

local function matcher(path)
  return function(state)
    local mod = package.loaded[path]
    return mod ~= nil and getmetatable(state) == mod
  end
end

local function speakable(text)
  text = tostring(text or "")
  text = text:gsub("<PK>", "PK"):gsub("<MN>", "MN"):gsub("{[A-Z_]+}", "")
  return (text:gsub("%s*[\n\v\f]%s*", " "))
end

local function position(index, count)
  return string.format("%d of %d", index, count)
end

local function count(n, singular, plural)
  return string.format("%d %s", n, n == 1 and singular or plural)
end

-- Joins the non-empty parts with commas.  Parts may be nil (an optional
-- detail), so walk to table.maxn instead of stopping at the first hole.
local function join(parts)
  local out = {}
  for i = 1, table.maxn(parts) do
    local p = parts[i]
    if p ~= nil and p ~= "" then out[#out + 1] = tostring(p) end
  end
  return table.concat(out, ", ")
end

local function speciesDef(game, species)
  local data = game and game.data
  return data and data.pokemon and data.pokemon[species] or {}
end

local function statusLabel(game, mon)
  if (mon.hp or 1) <= 0 then return "fainted" end
  if not mon.status then return "status OK" end
  local ok, Status = pcall(require, "src.battle.Status")
  local label = ok and game.data and Status.hudLabelFor(game.data.statuses, mon.status)
  return "status " .. speakable(label or mon.status)
end

local function typeNames(game, def)
  local ok, TypeChart = pcall(require, "src.battle.TypeChart")
  local names = {}
  for i, t in ipairs(def.types or {}) do
    names[i] = ok and TypeChart.displayName(t, game.data) or tostring(t)
  end
  return table.concat(names, " and ")
end

-- One move slot as summary and move pickers show it: name and PP.
local function moveText(game, mv)
  if type(mv) ~= "table" then return "empty" end
  local mdef = game.data.moves and game.data.moves[mv.id] or {}
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  local maxPP = okP and mdef.pp and Pokemon.maxPP(mdef.pp, mv.ppUps) or mdef.pp
  return join({ speakable(mdef.name or mv.id),
    maxPP and string.format("PP %d of %d", mv.pp or 0, maxPP) or nil })
end
InfoScreens.moveText = moveText

-- Summary (src/ui/SummaryMenu.lua:draw): page 1 is identity, HP, status,
-- stats, types and trainer; page 2 is experience and moves.
local function summaryPage(state)
  local game, mon = state.game, state.mon
  local def = speciesDef(game, mon.species)
  local s = mon.stats or {}
  if state.page == 2 then
    local nextExp
    if mon.level < 100 then
      local okG, Growth = pcall(require, "src.pokemon.Growth")
      if okG then
        nextExp = Growth.expForLevel(def.growthRate, mon.level + 1, game.data.growth_rates) - mon.exp
      end
    end
    local moves = {}
    for i = 1, 4 do moves[i] = moveText(game, mon.moves and mon.moves[i]) end
    return join({ speakable(def.name), "experience " .. tostring(mon.exp),
      nextExp and string.format("%d to level %d", math.max(0, nextExp), mon.level + 1) or nil,
      "moves: " .. table.concat(moves, "; ") })
  end
  local save = game.save or {}
  return join({ speakable(mon.nickname or def.name), "number " .. tostring(def.dex or 0),
    "level " .. tostring(mon.level),
    string.format("HP %d of %d", mon.hp or 0, s.hp or 0), statusLabel(game, mon),
    "attack " .. tostring(s.attack), "defense " .. tostring(s.defense),
    "speed " .. tostring(s.speed), "special " .. tostring(s.special),
    "type " .. typeNames(game, def),
    "ID " .. tostring(mon.otId or (save.player and save.player.id) or 0),
    "trainer " .. speakable(mon.ot or (save.player and save.player.name) or "") })
end

InfoScreens.summary = {
  matches = matcher("src.ui.SummaryMenu"),
  poll = function(state, memo)
    if memo.page == state.page then return nil end
    memo.page = state.page
    return summaryPage(state), true
  end,
}

-- Move pickers: forgetting a move when learning (MoveLearnMenu, only once
-- its list is up) and choosing a move for an item (MoveSelectMenu).
local function movePicker(path, ready)
  return {
    matches = matcher(path),
    poll = function(state, memo, entering)
      if not ready(state) then memo.index = nil return nil end
      if memo.index == state.index and not entering then return nil end
      local first = memo.index == nil or entering
      memo.index = state.index
      local moves = state.mon and state.mon.moves or {}
      local text = moveText(state.game, moves[state.index])
      if first then text = text .. ", " .. position(state.index, #moves) end
      return text, true
    end,
  }
end
InfoScreens.moveLearn = movePicker("src.ui.MoveLearnMenu", function(s) return s.selecting end)
InfoScreens.moveSelect = movePicker("src.ui.MoveSelectMenu", function(s) return s.ready end)

-- Trainer card (src/ui/TrainerCard.lua:draw): name, money, time, badges.
InfoScreens.trainerCard = {
  matches = matcher("src.ui.TrainerCard"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local game = state.game
    local save = game.save or {}
    local t = math.floor(save.playTime or 0)
    local owned = {}
    local okB, Badges = pcall(require, "src.inventory.Badges")
    if okB then
      for _, badge in ipairs(Badges.list(game.data)) do
        if save.inventory and save.inventory[Badges.itemFor(badge)] then
          owned[#owned + 1] = speakable(badge.name or Badges.itemFor(badge))
        end
      end
    end
    return join({ "Trainer card", speakable(save.player and save.player.name),
      "money ¥" .. tostring(save.money or 0),
      "time " .. count(math.floor(t / 3600), "hour", "hours") .. " "
        .. count(math.floor(t / 60) % 60, "minute", "minutes"),
      #owned == 0 and "no badges"
        or (count(#owned, "badge", "badges") .. ": " .. table.concat(owned, ", ")) }), true
  end,
}

-- Pokedex list (src/ui/PokedexMenu.lua): number and name, owned or seen.
InfoScreens.pokedexList = {
  matches = matcher("src.ui.PokedexMenu"),
  poll = function(state, memo, entering)
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local items = state.items or {}
    local item = items[state.index]
    if not item then return entering and "Pokédex. Empty" or nil, true end
    local known = item.value ~= nil
    local text = join({ tostring(item.num), known and speakable(item.name) or "unknown",
      item.ball and "owned" or (known and "seen" or nil), position(state.index, #items) })
    if entering then
      text = join({ "Pokédex", string.format("seen %d, owned %d", state.seenCount or 0,
        state.ownedCount or 0), text })
    end
    return text, true
  end,
}

-- Description pages, split the way DexEntryMenu's descPages does: \f
-- separates pages, \v and \n separate lines.  Shown only when owned.
local function dexPages(state)
  local game, def = state.game, state.def
  local entry = def.dexEntry or {}
  local owned = state.forceOwned
    or (game.save and game.save.pokedex and game.save.pokedex.owned[def.id])
  local text = owned and entry.text and game.data.text and game.data.text[entry.text]
  if not text then return {}, owned end
  -- DexEntryMenu adds the closing period unless the text ends in {DONE}
  local dexEnd = text:sub(-6) ~= "{DONE}"
  local pages = {}
  for chunk in (text:gsub("{DONE}$", "") .. "\f"):gmatch("(.-)\f") do
    local page = speakable(chunk)
    if page:match("%S") then pages[#pages + 1] = page end
  end
  if dexEnd and #pages > 0 then pages[#pages] = pages[#pages] .. "." end
  return pages, owned
end

InfoScreens.dexEntry = {
  matches = matcher("src.ui.DexEntryMenu"),
  poll = function(state, memo)
    if memo.page == state.page then return nil end
    local first = memo.page == nil
    memo.page = state.page
    local def = state.def or {}
    local pages, owned = dexPages(state)
    local text = pages[state.page]
    if first then
      local entry = def.dexEntry or {}
      local size
      if owned and entry.heightFt then
        size = string.format("height %d feet %d inches, weight %.1f pounds",
          entry.heightFt, entry.heightIn or 0, (entry.weight or 0) / 10)
      elseif owned and entry.heightM then
        size = string.format("height %.1f meters, weight %.1f kilograms",
          entry.heightM, entry.weightKg or 0)
      end
      text = join({ speakable(def.name), speakable(entry.kind), "number " .. tostring(def.dex or 0),
        size, text })
    end
    return text, true
  end,
}

-- Options (src/ui/OptionsMenu.lua, rows from src/ui/OptionRows.lua): label
-- and current value; the fixed BACK row sits after the last row.
local function optionValue(state, row)
  if type(row.value) ~= "function" then return nil end
  local ok, value = pcall(row.value, state.game)
  return ok and value ~= nil and speakable(value) or nil
end

InfoScreens.options = {
  matches = matcher("src.ui.OptionsMenu"),
  poll = function(state, memo, entering)
    local rows = state.view or state.rows or {}
    local row = rows[state.index]
    local value = row and optionValue(state, row)
    if not entering and memo.index == state.index and memo.value == value then return nil end
    local moved = memo.index ~= state.index
    memo.index, memo.value = state.index, value
    local total = #rows + 1
    local text
    if not row then
      text = "BACK"
    elseif moved or entering then
      text = join({ speakable(row.label), value })
    else
      text = value -- the value changed on the same row
    end
    if entering or moved then text = join({ text, position(state.index, total) }) end
    if entering then text = "Options. " .. text end
    return text, true
  end,
}

-- Town map and fly destination list (src/ui/TownMap.lua): the selected
-- location's banner text, which already says "To ..." when flying.
-- Pokedex AREA (TownMap with nestSpecies): "<name>'s NEST" and every nest
-- location, or AREA UNKNOWN, as TownMap:draw shows them.  state.nests has
-- no fixed order (encounter-table iteration) and the map's own order is
-- geographic, which reads as a jumble, so names are sorted naturally:
-- ROUTE 2 before ROUTE 12.
local function naturalLess(a, b)
  local pa, na = a:match("^(.-)%s*(%d+)$")
  local pb, nb = b:match("^(.-)%s*(%d+)$")
  if pa and pb and pa == pb then return tonumber(na) < tonumber(nb) end
  return (pa or a) < (pb or b) or ((pa or a) == (pb or b) and a < b)
end
InfoScreens.naturalLess = naturalLess

local function nestText(state)
  local def = speciesDef(state.game, state.nestSpecies)
  local title = speakable(def.name or state.nestSpecies) .. "'s NEST"
  local names = {}
  for _, loc in ipairs(state.nests or {}) do names[#names + 1] = speakable(loc.name) end
  if #names == 0 then return title .. ". AREA UNKNOWN" end
  table.sort(names, naturalLess)
  return title .. ". " .. table.concat(names, ", ")
end

InfoScreens.townMap = {
  matches = matcher("src.ui.TownMap"),
  poll = function(state, memo, entering)
    if state.nestSpecies then
      if memo.said then return nil end
      memo.said = true
      return nestText(state), true
    end
    if not entering and memo.sel == state.sel then return nil end
    memo.sel = state.sel
    local loc = state.locs and state.locs[state.sel]
    if not loc then return nil end
    local ok, banner = pcall(state.bannerText, state, loc)
    local text = speakable(ok and banner or loc.name)
    if loc == state.playerLoc then text = text .. ", you are here" end
    if entering then text = (state.fly and "Fly. " or "Town map. ") .. text end
    return text, true
  end,
}

InfoScreens.ordered = {
  InfoScreens.summary,
  InfoScreens.moveLearn,
  InfoScreens.moveSelect,
  InfoScreens.trainerCard,
  InfoScreens.pokedexList,
  InfoScreens.dexEntry,
  InfoScreens.options,
  InfoScreens.townMap,
}

return InfoScreens
