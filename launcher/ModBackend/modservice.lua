-- What answers the launcher's Mods window, whichever way requests arrive: stdin
-- and stdout on Windows (main.lua), a local socket on Android
-- (src/access/AndroidSaveBackend.lua).  The feed, its cache, compatibility
-- warnings, manifest checks and enable-state are all upstream's (src/mods/ModIndex,
-- Manifest, ModTargets; src/core/SaveData).  The caller sets up the module paths.
local Json = require("src.link.Json")

local Service = {}

-- The folder's manifest as the game's loader would judge it: the table, or nil and why.
local function readManifest(folder)
  local raw, readError = love.filesystem.read(folder .. "/manifest.json")
  if not raw then return nil, readError or "no manifest.json" end
  local data, decodeError = Json.decode(raw)
  if not data then return nil, decodeError end
  local ok, manifest = pcall(require("src.mods.Manifest").validate, data, folder)
  if not ok then return nil, tostring(manifest) end
  return manifest
end

-- Every folder in the mods folder with a manifest, valid or not, found the way the loader
-- finds them.  The game folder is mounted too, so this includes the mods that ship with
-- the game (the loader sees those as well); only the save folder's can be removed.
local function scanInstalled()
  local rows = {}
  local saveDir = love.filesystem.getSaveDirectory():gsub("\\", "/")
  for _, name in ipairs(love.filesystem.getDirectoryItems("mods")) do
    local folder = "mods/" .. name
    local info = love.filesystem.getInfo(folder)
    if info and (info.type == "directory" or info.type == "symlink")
        and love.filesystem.getInfo(folder .. "/manifest.json") then
      local manifest, problem = readManifest(folder)
      local realDir = (love.filesystem.getRealDirectory(folder) or ""):gsub("\\", "/")
      rows[#rows + 1] = { folder = name, manifest = manifest, problem = problem, removable = realDir == saveDir }
    end
  end
  return rows
end

local function listOrNil(list)
  return type(list) == "table" and #list > 0 and list or nil
end

-- Whether a mod is on for `version`.  An absent answer means on, except for experimental
-- mods, the same default the loader applies.
local function isEnabled(options, manifest, version)
  local SaveData = require("src.core.SaveData")
  local enabled = SaveData.modEnabled(options, manifest.id, SaveData.modScope(version))
  if enabled == nil then return manifest.experimental ~= true end
  return enabled
end

local handlers = {}

-- The installed mods and whether each runs on `version`.
function handlers.installed(request)
  local SaveData = require("src.core.SaveData")
  local ModTargets = require("src.mods.ModTargets")
  local options = SaveData.loadOptions()
  local mods = {}
  for _, row in ipairs(scanInstalled()) do
    local manifest = row.manifest
    if manifest then
      mods[#mods + 1] = {
        id = manifest.id, folder = row.folder, name = manifest.name or manifest.id,
        version = manifest.version, author = manifest.author, description = manifest.description,
        enabled = isEnabled(options, manifest, request.version),
        forThisGame = ModTargets.supports(manifest, request.version),
        games = ModTargets.label(manifest),
        permissions = listOrNil(manifest.permissions),
        removable = row.removable,
      }
    else
      mods[#mods + 1] = { folder = row.folder, name = row.folder, problem = row.problem, removable = row.removable }
    end
  end
  table.sort(mods, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
  return { mods = mods }
end

-- The built-in index first, so another index can never replace one of its listings.
local function orderedSources()
  local ModIndex = require("src.mods.ModIndex")
  local ordered = {}
  for _, source in ipairs(ModIndex.sources()) do
    if ModIndex.isBuiltIn(source.feed) then table.insert(ordered, 1, source)
    else ordered[#ordered + 1] = source end
  end
  return ordered
end

-- Every mod listed by the built-in index and the player's others.  A mod two sources
-- list keeps the first source's row.  Carts ride the same feed and are left out.  Many
-- listings name no games (the feed only copies `games` when its author supplied it),
-- which says nothing about the mod, so gamesListed separates that from "not this game".
function handlers.index(request)
  local ModIndex = require("src.mods.ModIndex")
  local ModTargets = require("src.mods.ModTargets")
  local Version = require("src.core.Version")
  local installed = {}
  for _, row in ipairs(scanInstalled()) do
    if row.manifest then installed[row.manifest.id] = row.manifest.version or "?" end
  end
  local context = {
    modApi = Version.modApi,
    -- a development build skips engine ranges, as the loader does
    engineVersion = not Version.isDev() and Version.engine or nil,
    installed = installed,
  }
  local mods, seen, problems, stale = {}, {}, {}, false
  for _, source in ipairs(orderedSources()) do
    local index, problem, meta = ModIndex.fetch(source, { force = request.force == true })
    if problem then problems[#problems + 1] = (source.label or source.feed) .. ": " .. tostring(problem) end
    if meta and meta.stale then stale = true end
    for _, entry in ipairs(index and index.mods or {}) do
      if not seen[entry.id] then
        seen[entry.id] = true
        local url, unavailable = ModIndex.installUrl(entry)
        local warnings = {}
        for _, issue in ipairs(ModIndex.compatIssues(entry, context)) do
          warnings[#warnings + 1] = issue.text
        end
        local listed = ModIndex.targets(entry)
        local targets = { games = listed }
        mods[#mods + 1] = {
          id = entry.id, title = entry.title or entry.id, author = entry.author,
          version = ModIndex.displayVersion(entry), summary = entry.summary,
          license = entry.license, repo = entry.repo,
          categories = listOrNil(entry.categories),
          url = url, unavailable = not url and unavailable or nil,
          installedVersion = installed[entry.id],
          gamesListed = #listed > 0,
          forThisGame = #listed > 0 and ModTargets.supports(targets, request.version),
          games = #listed > 0 and ModTargets.label(targets) or nil,
          source = not ModIndex.isBuiltIn(source.feed) and (source.label or source.feed) or nil,
          warnings = listOrNil(warnings),
        }
      end
    end
  end
  return { mods = mods, stale = stale, problems = listOrNil(problems) }
end

function handlers.sources()
  local ModIndex = require("src.mods.ModIndex")
  local rows = {}
  for _, source in ipairs(orderedSources()) do
    rows[#rows + 1] = { label = source.label or source.feed, feed = source.feed, builtIn = ModIndex.isBuiltIn(source.feed) }
  end
  return { sources = rows }
end

function handlers.addSource(request)
  local ModIndex = require("src.mods.ModIndex")
  local input = tostring(request.input or "")
  -- upstream's resolver also takes plain http, which anyone on the network could rewrite
  if input:lower():match("^http:") then error("Use a secure (https) address.", 0) end
  local row, problem = ModIndex.addSource(input)
  if not row then error(tostring(problem), 0) end
  return { label = row.label or row.feed }
end

function handlers.removeSource(request)
  local removed, problem = require("src.mods.ModIndex").removeSource(request.feed)
  if not removed then error(tostring(problem), 0) end
  return {}
end

-- One game's answer, in the file the loader reads it from.
function handlers.setEnabled(request)
  local SaveData = require("src.core.SaveData")
  local options = SaveData.loadOptions()
  SaveData.setModEnabled(options, request.modId, request.enabled == true,
    SaveData.modScope(request.version))
  assert(SaveData.saveOptions(options), "the options file could not be written")
  return {}
end

-- Judges an unpacked folder in the save folder before it joins the mods folder.
function handlers.check(request)
  local manifest, problem = readManifest(request.folder)
  if not manifest then return { valid = false, problem = problem } end
  local ModTargets = require("src.mods.ModTargets")
  return {
    valid = true, modId = manifest.id, version = manifest.version, name = manifest.name or manifest.id,
    forThisGame = ModTargets.supports(manifest, request.version), games = ModTargets.label(manifest),
    enabled = isEnabled(require("src.core.SaveData").loadOptions(), manifest, request.version),
  }
end

-- Unpacking a downloaded zip, for the iPhone launcher (docs/access/ios.md, "Save editor
-- and mods"), which has no zip reader of its own; Windows and Android unpack in the
-- launcher (ModInstaller.cs, ModInstaller.java) and never send this.  The same rules:
-- the shallowest manifest.json marks the mod's root, only files under it are written,
-- more than one mod at that depth or more than 4 GiB unpacked is refused.  LÖVE mounts
-- the zip read-only, and PhysFS refuses names that climb out of it ("..", absolute
-- paths), so nothing can be written outside `into`.
local MANIFEST = "manifest.json"
local MAX_UNPACKED_BYTES = 4 * 1024 * 1024 * 1024
local COPY_CHUNK = 1024 * 1024

-- Every file under `dir` (a mounted path), as paths relative to it.
local function walk(dir, prefix, out)
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
    local path, relative = dir .. "/" .. name, prefix .. name
    local info = love.filesystem.getInfo(path)
    if info and info.type == "directory" then
      walk(path, relative .. "/", out)
    elseif info and info.type == "file" then
      out[#out + 1] = { relative = relative, size = info.size or 0 }
    end
  end
  return out
end

-- Plain folder names only (the same test as ModInstaller.java's PLAIN_NAME), so the
-- request can only name scratch places in the save folder.
local function plainPath(path)
  if type(path) ~= "string" or path == "" or path:find("%.%.") or path:find("^/") or path:find(":") then
    return false
  end
  for part in path:gmatch("[^/]+") do
    if not part:match("^[%w_@][%w_@%.%- ]*$") then return false end
  end
  return true
end

local function copyFile(from, to)
  local source = love.filesystem.newFile(from, "r")
  local target = love.filesystem.newFile(to, "w")
  local ok, problem = pcall(function()
    while true do
      local chunk, size = source:read(COPY_CHUNK)
      if not chunk or size == 0 then break end
      assert(target:write(chunk, size))
    end
  end)
  source:close()
  target:close()
  if not ok then error("could not write " .. to .. ": " .. tostring(problem), 0) end
end

function handlers.unpack(request)
  local zip, into = request.zip, request.into
  if not (plainPath(zip) and plainPath(into) and zip:sub(1, #"mods-incoming/") == "mods-incoming/"
          and into:sub(1, #"mods-incoming/") == "mods-incoming/") then
    error("unpack only works inside mods-incoming", 0)
  end
  local mountPoint = "pocket-unpack-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000000))
  if not love.filesystem.mount(zip, mountPoint) then
    error("The download is not a zip file the game can open.", 0)
  end
  local ok, result = pcall(function()
    local files = walk(mountPoint, "", {})
    local root, depth, atDepth = nil, math.huge, 0
    for _, file in ipairs(files) do
      local name = file.relative
      if name == MANIFEST or name:sub(-#MANIFEST - 1) == "/" .. MANIFEST then
        local candidate = name:sub(1, #name - #MANIFEST)
        local _, slashes = candidate:gsub("/", "")
        if slashes < depth then
          root, depth, atDepth = candidate, slashes, 1
        elseif slashes == depth then
          atDepth = atDepth + 1
        end
      end
    end
    if not root then error("The download has no manifest.json, so it is not a mod.", 0) end
    if atDepth > 1 then error("The download holds more than one mod, so it was not installed.", 0) end
    local total, written = 0, 0
    for _, file in ipairs(files) do
      if file.relative:sub(1, #root) == root then
        total = total + file.size
        if total > MAX_UNPACKED_BYTES then
          error("The mod unpacks to more than 4 gigabytes, so it was not installed.", 0)
        end
      end
    end
    assert(love.filesystem.createDirectory(into), "could not create " .. into)
    for _, file in ipairs(files) do
      if file.relative:sub(1, #root) == root then
        local relative = file.relative:sub(#root + 1)
        local target = into .. "/" .. relative
        local parent = target:match("^(.*)/[^/]+$")
        if parent then love.filesystem.createDirectory(parent) end
        copyFile(mountPoint .. "/" .. file.relative, target)
        written = written + 1
      end
    end
    return { files = written }
  end)
  love.filesystem.unmount(zip)
  if not ok then error(result, 0) end
  return result
end

-- One request as a line of JSON; one answer as a table, ready to encode.
function Service.answer(line)
  local request = Json.decode(line)
  local handler = handlers[request.cmd]
  local ok, result = xpcall(function()
    if not handler then error("unknown command " .. tostring(request.cmd), 0) end
    return handler(request)
  end, function(err) return debug.traceback(tostring(err), 2) end)
  local response = ok and result or {}
  response.id, response.ok = request.id, ok
  if not ok then
    response.error = result:match("^[^\n]*")
    print("[backend] " .. tostring(result))
  end
  return response
end

return Service
