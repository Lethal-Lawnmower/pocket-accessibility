-- Turns upstream's shared UI primitives into speech.
--
-- Each presenter reads an upstream state table without changing it:
--   matches(state)     is this state one of ours?
--   key(state)         cheap change marker (numbers or a string already in
--                      the state); speech is rebuilt only when it changes
--   speak(state, entering) -> text, interrupt
-- `entering` is true the first frame a state is on top, so context (a list's
-- title, a menu's position) is said once on entry and not on every move.
--
-- Upstream classes are required lazily so a presenter never forces a UI
-- module to load before the game would.

local Presenters = {}

local function class(path)
  local ok, mod = pcall(require, path)
  return ok and mod or nil
end

local function isInstance(state, path)
  local mod = class(path)
  return mod ~= nil and getmetatable(state) == mod
end

local function position(index, count)
  return string.format("%d of %d", index, count)
end

-- One row's spoken text: label first, then whichever detail the row draws
-- (src/ui/ListMenu.lua draws level, sub, price, count or right, in that order).
local function rowText(item)
  if type(item) ~= "table" then return nil end
  local parts = { tostring(item.label or "") }
  if item.level then
    parts[#parts + 1] = "level " .. tostring(item.level)
  elseif item.sub then
    parts[#parts + 1] = tostring(item.sub)
  elseif item.price then
    parts[#parts + 1] = tostring(item.price)
  elseif item.count then
    parts[#parts + 1] = "quantity " .. tostring(item.count)
  elseif item.right then
    parts[#parts + 1] = tostring(item.right)
  end
  return table.concat(parts, ", ")
end
Presenters.rowText = rowText

-- Joins a page's lines into one sentence.  A line ending in a hyphen is a
-- word the original split across lines ("grand-" / "son"), so it is joined
-- without a space and reads as one word.
local function joinLines(lines)
  local out = ""
  for i, line in ipairs(lines) do
    line = tostring(line)
    if i == 1 then
      out = line
    elseif out:sub(-1) == "-" then
      out = out .. line
    else
      out = out .. " " .. line
    end
  end
  return out
end
Presenters.joinLines = joinLines

-- Dialogue box: the whole current page at once, never letter by letter.
-- pages[p] is a list of already-substituted lines (TextBox.paginate).
Presenters.textBox = {
  matches = function(state) return isInstance(state, "src.render.TextBox") end,
  key = function(state) return state.pageIndex end,
  -- a Yes/No box closing must not make the question repeat
  repeatOnReturn = false,
  speak = function(state)
    local page = state.pages and state.pages[state.pageIndex]
    if type(page) ~= "table" or #page == 0 then return nil end
    return joinLines(page), true
  end,
}

-- Bordered menus (start menu, PC, shop root, script choices).
Presenters.menu = {
  matches = function(state) return isInstance(state, "src.ui.Menu") end,
  key = function(state) return state.index end,
  speak = function(state, entering)
    local items = state.items or {}
    local text = rowText(items[state.index])
    if not text then return nil end
    if entering then
      text = text .. ", " .. position(state.index, #items)
      if state.title then text = tostring(state.title) .. ". " .. text end
    end
    return text, true
  end,
}

-- Scrolling lists (bag, PC boxes, shop lists, Pokedex, fly).
Presenters.listMenu = {
  matches = function(state) return isInstance(state, "src.ui.ListMenu") end,
  key = function(state) return state.index end,
  speak = function(state, entering)
    local items = state.items or {}
    if #items == 0 then
      return (state.title and (tostring(state.title) .. ". ") or "") .. "Empty", true
    end
    local text = rowText(items[state.index])
    if not text then return nil end
    text = text .. ", " .. position(state.index, #items)
    if entering and state.title then text = tostring(state.title) .. ". " .. text end
    return text, true
  end,
}

-- Yes/No box over a dialogue page.  On entry it queues behind the question
-- that was just spoken instead of cutting it off; later moves interrupt.
Presenters.choiceBox = {
  matches = function(state) return isInstance(state, "src.ui.ChoiceBox") end,
  key = function(state) return state.index end,
  speak = function(state, entering)
    local labels = state.labels or { "YES", "NO" }
    local label = labels[state.index]
    if not label then return nil end
    return tostring(label), not entering
  end,
}

Presenters.ordered = {
  Presenters.textBox,
  Presenters.menu,
  Presenters.listMenu,
  Presenters.choiceBox,
}

function Presenters.find(state)
  if type(state) ~= "table" then return nil end
  for _, presenter in ipairs(Presenters.ordered) do
    if presenter.matches(state) then return presenter end
  end
  return nil
end

return Presenters
