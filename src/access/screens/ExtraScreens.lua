-- Presenters for screens the PC port adds beyond the original games: the
-- in-game mod manager (src/mods/ManagerState.lua) and the save load report
-- (src/ui/QuarantineReport.lua).  Same contract as Presenters.lua.
-- The launcher's own mod screen (src/mods/LauncherMods.lua) is upstream's
-- proprietary launcher and never part of our build, so it is not covered.

local ExtraScreens = {}

local function matcher(path)
  return function(state)
    local mod = package.loaded[path]
    return mod ~= nil and getmetatable(state) == mod
  end
end

local function speakable(text)
  text = tostring(text or "")
  return (text:gsub("%s*[\n\v\f]%s*", " "))
end

local function call(state, method, ...)
  local fn = state[method]
  if type(fn) ~= "function" then return nil end
  local ok, result = pcall(fn, state, ...)
  return ok and result or nil
end

-- ------------------------------------------------------------ mod manager

local TAB_NAMES = { "Mods", "Profiles", "Errors" }
local SCREEN_NAMES = { detail = "Mod details", errors = "Errors",
  permissions = "Permissions", apply = "Apply changes", options = "Mod options" }

-- A mod's state in words, following ManagerState:glyphFor's order.
local function modState(state, m)
  if call(state, "isStaged", m) then return "change pending restart" end
  if not m.enabled then return "disabled" end
  if m.state == "wrong_generation" or call(state, "runsHere", m) == false then
    return "not for this game"
  end
  if m.state == "blocked_dependency" then return "missing dependency" end
  if m.error then return "error" end
  return "enabled"
end

local function rowsOf(state)
  if state.screen == "options" then return state.optionRows or {} end
  return call(state, "rowsForScreen") or {}
end

local function rowText(state, row)
  if type(row) ~= "table" then return nil end
  local text = speakable(row.label)
  if row.mod then text = text .. ", " .. modState(state, row.mod) end
  if type(row.value) == "function" then
    local ok, value = pcall(row.value)
    if ok and value ~= nil then text = text .. ", " .. speakable(value) end
  end
  return text
end

-- Position among rows the cursor can land on (headers and inert lines are
-- skipped by ManagerState's cursor).
local function position(rows, cursor)
  local index, total = 0, 0
  for i, row in ipairs(rows) do
    if not row.header and not row.inert then
      total = total + 1
      if i <= cursor then index = total end
    end
  end
  if total == 0 then return nil end
  return string.format("%d of %d", index, total)
end

-- Context said when the screen or tab changes: the tab, or the detail
-- header ManagerState:drawDetail shows (name, version, status, description).
local function context(state)
  if state.screen == "list" then
    return "Mod manager, " .. (TAB_NAMES[state.tab] or "Mods") .. " tab"
  end
  if state.screen == "detail" and state.currentMod then
    local m = state.currentMod
    local body = m.error and ("Failed: " .. m.error)
      or (m.note and ("Skipped: " .. m.note)) or m.description
    local parts = { speakable((m.name or m.id) .. " " .. (m.version or "")),
      modState(state, m) }
    if body and body ~= "" then parts[#parts + 1] = speakable(body) end
    return table.concat(parts, ". ")
  end
  if state.screen == "options" and state.currentMod then
    return "Options for " .. speakable(state.currentMod.name or state.currentMod.id)
  end
  return SCREEN_NAMES[state.screen] or tostring(state.screen)
end

local function rowValue(rows, cursor)
  local row = rows[cursor]
  if type(row) ~= "table" or type(row.value) ~= "function" then return nil end
  local ok, value = pcall(row.value)
  return ok and value or nil
end

ExtraScreens.modManager = {
  matches = matcher("src.mods.ManagerState"),
  poll = function(state, memo, entering)
    -- confirmation and message boxes over the screen
    local overlay = state.overlay
    if overlay ~= memo.overlay then
      memo.overlay, memo.overlayIndex = overlay, overlay and overlay.index
      if overlay then
        local text = speakable(table.concat(overlay.lines or {}, " "))
        if overlay.kind == "confirm" then
          text = text .. ". " .. (overlay.index == 1 and "YES" or "NO")
        end
        return text, true
      end
      entering = true -- back on the screen underneath: repeat context
    elseif overlay then
      if overlay.index ~= memo.overlayIndex then
        memo.overlayIndex = overlay.index
        return overlay.index == 1 and "YES" or "NO", true
      end
      return nil
    end

    -- short notices ("Saved", "Restart to apply")
    if state.notice ~= memo.notice then
      memo.notice = state.notice
      if state.notice then return speakable(state.notice), false end
    end

    local rows = nil
    local contextChanged = entering or state.screen ~= memo.screen or state.tab ~= memo.tab
    local moved = state.cursor ~= memo.cursor
    local value = nil
    if state.screen == "options" then
      rows = rowsOf(state)
      value = rowValue(rows, state.cursor)
    end
    if not contextChanged and not moved and value == memo.value then return nil end
    rows = rows or rowsOf(state)
    memo.screen, memo.tab, memo.cursor, memo.value = state.screen, state.tab, state.cursor, value

    if not contextChanged and not moved then return speakable(value), true end
    local text = rowText(state, rows[state.cursor]) or ""
    local where = position(rows, state.cursor)
    if where then text = text .. ", " .. where end
    if contextChanged then text = (context(state):gsub("[%.!?]$", "")) .. ". " .. text end
    return text, true
  end,
}

-- ------------------------------------------------------------ load report

-- QuarantineReport lists what save validation moved aside; its lines are
-- read whole once (the screen is a page of text dismissed with A).
ExtraScreens.quarantineReport = {
  matches = matcher("src.ui.QuarantineReport"),
  poll = function(state, memo)
    if memo.said then return nil end
    memo.said = true
    local lines = call(state, "lines") or state.lines
    if type(lines) ~= "table" or #lines == 0 then return "Save load report. Press A to continue.", true end
    local out = {}
    for i, line in ipairs(lines) do out[i] = speakable(type(line) == "table" and line.text or line) end
    return "Save load report. " .. table.concat(out, ". "), true
  end,
}

ExtraScreens.ordered = {
  ExtraScreens.modManager,
  ExtraScreens.quarantineReport,
}

return ExtraScreens
