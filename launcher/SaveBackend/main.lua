-- The save backend: upstream's save-editor logic (tools/save-editor) running with
-- no window, answering the launcher's native editor one JSON line at a time on
-- stdin and stdout.  Every edit goes through upstream's Ops, so ranges, undo,
-- backups and save export are upstream's.  docs/access/save-editor.md holds the
-- protocol.  Lines not starting with RESPONSE_PREFIX are upstream's logging and
-- the launcher ignores them.
local RESPONSE_PREFIX = "@@PA "

local gameDir = (os.getenv("POCKET_GAME_DIR") or ""):gsub("\\", "/")
local backendDir = love.filesystem.getSource():gsub("\\", "/")

local PAGE_ORDER = {
  { "party", "Party" }, { "boxes", "Boxes" }, { "items", "Items" }, { "trainer", "Trainer" },
  { "map", "Map" }, { "dex", "Pokédex" }, { "events", "Events" }, { "checks", "Checks" },
}

local App, Json
local pages, pageStates = {}, {}

local function setUpPaths()
  local ffi = require("ffi")
  ffi.cdef("int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  -- the game's data and scripts read through love.filesystem, like its code
  assert(ffi.load("love").PHYSFS_mount(gameDir, "/", 1) ~= 0, "could not mount the game folder")
  package.path = backendDir .. "/?.lua;" .. gameDir .. "/?.lua;" .. gameDir .. "/?/init.lua;"
    .. gameDir .. "/tools/save-editor/?.lua;" .. gameDir .. "/tools/save-editor/panels/?.lua;" .. package.path
  Json = require("src.link.Json")
end

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

local function answer(line)
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

function love.run()
  setUpPaths()
  print = function(...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
    io.stderr:write(table.concat(parts, "\t"), "\n")
  end
  io.stdout:setvbuf("no")
  io.stdout:write(RESPONSE_PREFIX, Json.encode({ ready = true }), "\n")
  for line in io.stdin:lines() do
    if line ~= "" then
      local ok, response = pcall(answer, line)
      if not ok then response = { ok = false, error = tostring(response) } end
      io.stdout:write(RESPONSE_PREFIX, Json.encode(response), "\n")
    end
  end
  return function() return 0 end
end
