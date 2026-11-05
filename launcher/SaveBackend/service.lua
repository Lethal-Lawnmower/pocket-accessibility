-- What answers the launcher's native save editor, whichever way its requests arrive:
-- stdin and stdout on Windows (main.lua), a local socket on Android
-- (src/access/AndroidSaveBackend.lua).  Every edit goes through upstream's Ops, so
-- ranges, undo, backups and save export are upstream's.  docs/access/save-editor.md
-- holds the protocol.  The caller sets up the module paths first.
local Json = require("src.link.Json")

local Service = {}

local PAGE_ORDER = {
  { "party", "Party" }, { "boxes", "Boxes" }, { "items", "Items" }, { "trainer", "Trainer" },
  { "map", "Map" }, { "dex", "Pokédex" }, { "events", "Events" }, { "checks", "Checks" },
}

local App
local pages, pageStates = {}, {}

local function exists(path)
  local file = path and io.open(path, "rb")
  if file then file:close() end
  return file ~= nil and file ~= false
end

-- The file the game loads for `version`.  Upstream's standalone default is a
-- pre-slots path, so this asks SaveData, as upstream's Edit button does.  The
-- lookup can move a flat save into slot1: upstream's own migration, which the
-- next game start would run too.
local function activeSavePath(version)
  local SaveData = require("src.core.SaveData")
  local recovered, recoveryError = require("src.box.Transaction").recover(SaveData.persistenceFs())
  if not recovered then error(recoveryError, 0) end
  local slot = SaveData.activeSlot(version)
  local path = slot and SaveData.slotDiskPath(version, slot)
  if exists(path) then return path end
  local flat = love.filesystem.getSaveDirectory() .. package.config:sub(1, 1) .. SaveData.saveFilename(version)
  if exists(flat) then return flat end
  return path
end

local function loadPages()
  local list = {}
  for _, entry in ipairs(PAGE_ORDER) do
    local ok, page = pcall(require, "pages." .. entry[1])
    if ok then
      pages[entry[1]], pageStates[entry[1]] = page, {}
      list[#list + 1] = { id = entry[1], label = entry[2] }
    elseif not tostring(page):find("module 'pages%." .. entry[1] .. "' not found") then
      error(page, 0)
    end
  end
  return list
end

local handlers = {}

function handlers.open(request)
  local version = request.version
  require("src.core.GameVersion").set(version)
  require("src.import.CacheFs").mountVersion(version)
  App = require("App")
  local path = request.path or activeSavePath(version)
  App.load(path, { version = version })
  local S = App.getState()
  local info = require("src.core.GameVersion").info(version)
  return {
    title = (info and info.label or version) .. " save",
    path = S.path,
    missingCache = S.missingCache,
    corrupt = S.loadError or nil,
    pages = S.missingCache and {} or loadPages(),
  }
end

local function pageOf(request)
  local page = pages[request.page]
  if not page then error("unknown page " .. tostring(request.page), 0) end
  return page, pageStates[request.page]
end

function handlers.model(request)
  local page, state = pageOf(request)
  return { model = page.model(App.getState(), state) }
end

-- The commands a page answers.  Each is followed by a fresh model.
local function pageCommand(name, default)
  handlers[name] = function(request)
    local page, state = pageOf(request)
    local S = App.getState()
    if page[name] then
      page[name](S, state, request)
    elseif default then
      default(S, state, request)
    else
      error(request.page .. " does not handle " .. name, 0)
    end
    return { model = page.model(S, state) }
  end
end
pageCommand("select", function(_, state, request) state.selected = request.row end)
pageCommand("pick", function(_, state, request) state[request.picker] = request.value end)
pageCommand("set")
pageCommand("toggle")
pageCommand("action")

function handlers.save() return { saved = App.save() == true } end
function handlers.undo() return { changed = require("History").undo(App.getState()) } end
function handlers.redo() return { changed = require("History").redo(App.getState()) } end
function handlers.reload()
  for id in pairs(pageStates) do pageStates[id] = {} end
  return { changed = App.reload() }
end

local function statusOf()
  local S = App and App.getState()
  if not S then return {} end
  return {
    status = S.status,
    dirty = S.dirty == true,
    canUndo = S.undoStack ~= nil and #S.undoStack > 0,
    canRedo = S.redoStack ~= nil and #S.redoStack > 0,
    canSave = S.allowSave == true and S.dirty == true,
  }
end

-- One request as a line of JSON; one answer as a table, ready to encode.
function Service.answer(line)
  local request = Json.decode(line)
  local S = App and App.getState()
  local before = S and S.status
  -- upstream reuses a toast repeated within its display time, so a second
  -- identical refusal would look like no news
  if S and request.cmd ~= "model" then S.toast = nil end
  local handler = handlers[request.cmd]
  local ok, result = xpcall(function()
    if not handler then error("unknown command " .. tostring(request.cmd), 0) end
    return handler(request)
  end, function(err) return debug.traceback(tostring(err), 2) end)
  local response = ok and result or {}
  response.id, response.ok = request.id, ok
  if not ok then
    response.error = result
    print("[backend] " .. tostring(result))
  end
  for key, value in pairs(statusOf()) do response[key] = value end
  S = App and App.getState()
  -- something new to say: the status changed, or the same words were said again
  if S and request.cmd ~= "model" and (S.status ~= before or S.toast ~= nil) then
    response.message = S.status
    response.messageKind = S.toast and S.toast.kind or "info"
  end
  return response
end

return Service
