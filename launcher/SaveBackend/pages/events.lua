-- The Events page: flags, defeated trainers, taken items, object toggles, system
-- flags and script variables, per generation as upstream's panels/Events.lua offers
-- them.  Gen 1 keeps trainers and items as keys in the save, Gen 2 has flags only,
-- Gen 3 has fixed catalogues.  Every edit is upstream's Ops.
local Ops = require("Ops")
local Gen = require("Gen")
local Catalog = require("Catalog")

local Page = {}

local TABS_GEN1 = {
  { value = "flags", label = "Flags" },
  { value = "trainers", label = "Trainers" },
  { value = "items", label = "Items taken" },
  { value = "toggles", label = "Object toggles" },
}

local TABS_GEN3 = {
  { value = "story", label = "Story flags" },
  { value = "trainers", label = "Trainers" },
  { value = "items", label = "Items taken" },
  { value = "toggles", label = "Object toggles" },
  { value = "system", label = "System and badges" },
  { value = "vars", label = "Variables" },
}

-- What each sub-tab holds, in upstream's words where the words still fit a list.
local HINTS_GEN1 = {
  flags = "Story flags scraped from data/scripts and the trainer headers, plus any MOD_ flags a loaded mod defines.",
  trainers = "Keys look like MAP_obj_N: checked means that trainer stays beaten.",
  items = "Keys look like MAP_obj_N: checked means that ground item is gone.",
  toggles = "Per-map object visibility overrides, grouped by map.",
}

local HINTS_GEN3 = {
  story = "Story and narrative event flags: NPC gifts, quest progress, boss clears, and mod flags.",
  trainers = "Trainer defeat flags: checked means that trainer stays beaten.",
  items = "Overworld item balls and hidden items: checked means item taken.",
  toggles = "NPC, sprite, and obstacle hide flags: checked means the object is hidden.",
  system = "System flags, Gym Badges, National Dex, and more.",
  vars = "16-bit script and story progression variables.",
}

local EMPTY_HINT = "Nothing recorded here yet."

local CLEARS = {
  -- arming ids are upstream's: Ops.clearTrainers and friends in Gen 3,
  -- Ops.clearTable with the save's table name in Gen 1
  trainers = { label = "Clear all trainers", what = "defeated trainers", fn = "clearTrainers",
    arm = { "clear-defeatedTrainers", "clear-trainers" } },
  items = { label = "Clear all items taken", what = "items taken", fn = "clearItems",
    arm = { "clear-itemsTaken", "clear-items" } },
  toggles = { label = "Clear all toggles", what = "object toggles", fn = "clearToggles",
    arm = { nil, "clear-toggles" } },
}

local function tabsFor(S)
  local generation = Gen.ofState(S)
  if generation == 3 then return TABS_GEN3 end
  if generation == 2 then return { TABS_GEN1[1] } end
  return TABS_GEN1
end

local function currentTab(S, state)
  local tabs = tabsFor(S)
  for _, tab in ipairs(tabs) do
    if tab.value == state.tab then return tab.value end
  end
  state.tab = tabs[1].value
  return state.tab
end

local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- ------------------------------------------------------------------- rows
-- A row: id (a unique string), text, checked; set(on) edits it; var rows carry varId.

local function addRow(rows, id, text, checked, set)
  -- two flag names can share an id; rows must not
  if rows.byId[id] then id = id .. "#" .. (#rows + 1) end
  local row = { id = id, text = text, checked = checked, set = set }
  rows[#rows + 1] = row
  rows.byId[id] = row
  return row
end

-- FireRed's catalogue reads trainer names from a pret header a player does not have
-- and falls back to numbers, though the game's own constants hold the same names.
local function trainerNames()
  local ok, names = pcall(function()
    local set = require("src.core.game3.constants").of(require("src.core.GameVersion").get())
    return set.trainers.byId.TRAINER_
  end)
  return ok and names or {}
end

local function gen3Rows(S, tab)
  local categories = S.game3Events or Catalog.game3Categories(S.modRoots)
  S.game3Events = categories
  local rows = { byId = {} }
  local names = tab == "trainers" and trainerNames() or {}
  local list = categories[tab == "flags" and "story" or tab] or {}
  for _, entry in ipairs(list) do
    if tab == "vars" then
      local value = Gen.getVar(S.save, entry.id)
      local row = addRow(rows, tostring(entry.name or entry.id), ("%s: %d"):format(entry.label, value), false)
      row.varId, row.value, row.name = entry.id, value, entry.label
    else
      -- the same key upstream's rows read and write, per category
      local key
      if tab == "story" then
        key = entry.name or entry.id
      elseif tab == "trainers" then
        key = entry.flagId
      else
        key = entry.id or entry.name
      end
      local label = entry.label or entry.name
      if tab == "trainers" and tostring(entry.name):find("^TRAINER_0x") and names[entry.id] then
        label = ("%s (0x%03X)"):format(names[entry.id], key)
      end
      addRow(rows, tostring(entry.name or key), label, Gen.getFlag(S.save, key) == true, function(on)
        Ops.setFlag(S, key, on)
        S.status = label .. (on and ": on" or ": off")
      end)
    end
  end
  return rows
end

-- Gen 1 and Gen 2 flags: the names upstream scraped, read and written by name.
local function namedFlagRows(S)
  local rows = { byId = {} }
  for _, name in ipairs(S.events or {}) do
    addRow(rows, name, name, Gen.getFlag(S.save, name) == true, function(on)
      Ops.setFlag(S, name, on)
      S.status = name .. (on and ": on" or ": off")
    end)
  end
  return rows
end

-- Gen 1's trainers and items are save keys that vanish when cleared.  `known` keeps
-- a cleared key in the list until Reload, so unchecking cannot lose the row, or the
-- way back, under the player's cursor.
local function gen1KeyRows(S, state, tableKey)
  local rows = { byId = {} }
  local present = S.save[tableKey] or {}
  state.known = state.known or {}
  local known = state.known[tableKey] or {}
  state.known[tableKey] = known
  for key in pairs(present) do known[key] = true end
  for _, key in ipairs(sortedKeys(known)) do
    addRow(rows, tostring(key), tostring(key), present[key] == true, function(on)
      Ops.setKey(S, tableKey, key, on)
      S.status = tostring(key) .. (on and ": on" or ": off")
    end)
  end
  return rows
end

local function gen1Rows(S, state, tab)
  local rows = { byId = {} }
  if tab == "flags" then
    return namedFlagRows(S)
  elseif tab == "trainers" then
    return gen1KeyRows(S, state, "defeatedTrainers")
  elseif tab == "items" then
    return gen1KeyRows(S, state, "itemsTaken")
  else
    local toggles = S.save.objectToggles or {}
    for _, mapId in ipairs(sortedKeys(toggles)) do
      for _, name in ipairs(sortedKeys(toggles[mapId])) do
        addRow(rows, tostring(mapId) .. "|" .. tostring(name), tostring(mapId) .. ", " .. tostring(name),
          toggles[mapId][name] == true, function(on)
            Ops.setToggle(S, mapId, name, on)
            S.status = tostring(mapId) .. ", " .. tostring(name) .. (on and ": on" or ": off")
          end)
      end
    end
  end
  return rows
end

-- The rows only change with an edit, so one set per edit and sub-tab.
local function rowsFor(S, state, tab)
  if state.rows and state.rowsTab == tab and state.rowsRevision == S.revision and state.rowsSave == S.save then
    return state.rows
  end
  local generation, rows = Gen.ofState(S), nil
  if generation == 3 then
    rows = gen3Rows(S, tab)
  elseif generation == 2 then
    rows = namedFlagRows(S)
  else
    rows = gen1Rows(S, state, tab)
  end
  state.rows, state.rowsTab, state.rowsRevision, state.rowsSave = rows, tab, S.revision, S.save
  return rows
end

local function clearFor(S, tab)
  local clear = CLEARS[tab]
  local generation = Gen.ofState(S)
  if not clear or generation == 2 then return nil end
  -- upstream offers no bulk clear for Gen 1's toggles
  if tab == "toggles" and generation ~= 3 then return nil end
  return clear
end

-- ------------------------------------------------------------------ model

function Page.model(S, state)
  local tabs = tabsFor(S)
  local tab = currentTab(S, state)
  local rows = rowsFor(S, state, tab)
  local isVars = tab == "vars"
  state.selected = state.selected or {}
  local selected = rows.byId[tostring(state.selected[tab])] or rows[1]

  local listRows, checkedCount = {}, 0
  for i, row in ipairs(rows) do
    if isVars then
      listRows[i] = { id = row.id, text = row.text }
    else
      listRows[i] = { id = row.id, text = row.text, checked = row.checked }
      if row.checked then checkedCount = checkedCount + 1 end
    end
  end

  local hints = Gen.ofState(S) == 3 and HINTS_GEN3 or HINTS_GEN1
  local lines = {}
  -- once on the page, not with every sub-tab's text, and gone after the first edit
  if not state.warned then
    lines[#lines + 1] = "Warning: changing these can break the story. Use Undo or Reload if something goes wrong."
  end
  lines[#lines + 1] = hints[tab] or ""
  if #rows == 0 then
    lines[#lines + 1] = EMPTY_HINT
  elseif isVars then
    lines[#lines + 1] = ("%d variables."):format(#rows)
  else
    lines[#lines + 1] = ("%d of %d on."):format(checkedCount, #rows)
  end

  local fields, actions = {}, {}
  if isVars and selected then
    fields[1] = { id = "value", label = "Value of " .. selected.name, kind = "number",
      value = selected.value, lo = 0, hi = 65535 }
  end
  local clear = clearFor(S, tab)
  if clear then
    actions[1] = { id = "clear", label = clear.label,
      confirm = ("Clear all %s? %d on now."):format(clear.what, checkedCount) }
  end

  local pickers = nil
  if #tabs > 1 then
    pickers = { { id = "tab", label = "Event category", value = tab, options = tabs } }
  end
  local label
  for _, entry in ipairs(tabs) do
    if entry.value == tab then label = entry.label end
  end
  return {
    pickers = pickers,
    summary = table.concat(lines, "\n"),
    list = { label = label, rows = listRows, selected = selected and selected.id or nil,
      checks = not isVars, filter = true },
    fields = fields,
    actions = actions,
  }
end

-- --------------------------------------------------------------- commands

function Page.pick(S, state, request)
  if request.picker == "tab" then
    state.tab = request.value
    currentTab(S, state)
  end
end

function Page.select(S, state, request)
  state.selected = state.selected or {}
  state.selected[currentTab(S, state)] = request.row
end

function Page.toggle(S, state, request)
  local rows = rowsFor(S, state, currentTab(S, state))
  local row = rows.byId[tostring(request.row)]
  -- a row from before a Reload or another sub-tab is simply gone
  if not (row and row.set) then return end
  row.set(request.checked == true)
  state.warned = true
end

function Page.set(S, state, request)
  if request.field ~= "value" then return end
  local tab = currentTab(S, state)
  local rows = rowsFor(S, state, tab)
  state.selected = state.selected or {}
  local row = rows.byId[tostring(state.selected[tab])] or rows[1]
  if not (row and row.varId) then return end
  Ops.setVar(S, row.varId, request.value)
  S.status = ("%s: %d"):format(row.name, Gen.getVar(S.save, row.varId))
  state.warned = true
end

function Page.action(S, state, request)
  if request.action ~= "clear" then return end
  local clear = clearFor(S, currentTab(S, state))
  if not clear then return end
  -- the client has already asked yes or no, so upstream's first click is taken as made
  S.armed, S.armedAt = clear.arm[Gen.ofState(S) == 3 and 2 or 1], nil
  Ops[clear.fn](S)
  S.armed, S.armedAt = nil, nil
  state.warned = true
end

return Page
