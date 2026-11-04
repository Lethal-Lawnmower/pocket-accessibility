-- The ROM import of a packaged build, which has no src/import/RomImporter.lua
-- (see PackagedBuild.lua).  License Term 2 covers that file's launcher interface;
-- its import, verification and extraction logic remains under the GPL, and the
-- steps below follow it: isReady, startData, _startExtractThread, _pumpExtract,
-- _completeImport.  Left out because only upstream's launcher needs them: archives,
-- remembering where the ROM was, the coroutine path for hosts without threads, and
-- portable folders.  Our launcher identifies the dump first and passes a plain file.

local CacheContract = require("src.import.CacheContract")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local PackagedBuild = require("src.access.PackagedBuild")

local PackagedImporter = {}
PackagedImporter.__index = PackagedImporter

local ROM_SIZES = { [1024 * 1024] = true, [2 * 1024 * 1024] = true, [16 * 1024 * 1024] = true }

local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then digest = digest:getString() end
  return love.data.encode("string", "hex", digest)
end

local function removeSaveDirTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeSaveDirTree(path .. "/" .. child)
    end
    love.filesystem.remove(path)
    return
  end
  local SaveData = require("src.core.SaveData")
  local real = love.filesystem.getSaveDirectory() .. "/" .. path
  local file = SaveData.openNative(real, "rb")
  if not file then return end -- it came from the game folder, not the save folder
  file:close()
  local ok, err = SaveData.removeNative(real)
  if not ok then error("could not remove stale cache " .. real .. ": " .. tostring(err)) end
end

function PackagedImporter.isReady(version)
  local CacheFs = require("src.import.CacheFs")
  -- older saves keep Red's cache at the root; upstream moves it before checking
  CacheFs.migrateLegacyRedCache()
  return CacheContract.isReady(version or "red", CacheFs)
end

function PackagedImporter.new(onComplete)
  return PackagedBuild.fillImporterMethods(setmetatable({
    onComplete = onComplete,
    status = "Waiting",
    progress = 0,
  }, PackagedImporter))
end

function PackagedImporter:setError(message)
  self.failed = true
  self.extract = nil
  Logger.error("import failed: %s", tostring(message))
  require("src.import.CacheFs").prefix = ""
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
    love.event.quit(1)
  else
    PackagedBuild.refuse("The import did not finish: " .. tostring(message))
  end
end

function PackagedImporter:startPath(path)
  self.started = true
  local file, openError = require("src.core.SaveData").openNative(path, "rb")
  if not file then return self:setError("could not read the file: " .. tostring(openError)) end
  local data = file:read("*a")
  file:close()
  if not data or not ROM_SIZES[#data] then
    return self:setError("the file is not the size of a supported cartridge dump")
  end
  local hash = sha1(data)
  local version = GameVersion.forSha1(hash)
  if not version then return self:setError("the file is not a supported cartridge dump") end
  self:startData(data, version, hash)
end

function PackagedImporter:startData(data, version, hash)
  local CacheFs = require("src.import.CacheFs")
  local prefix = GameVersion.info(version).cachePrefix
  self.romSha1 = hash
  self.status = "Importing " .. GameVersion.info(version).displayName
  -- Clear the old cache before anything writes: delete, fill, then mark.
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local cleared, clearError = pcall(function()
    removeSaveDirTree(prefix .. "data/generated")
    removeSaveDirTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(CacheContract.MARKER_PATH)
  end)
  CacheFs.prefix = savedPrefix
  if not cleared then return self:setError(clearError) end

  local progressName, resultName = "rom_import_progress", "rom_import_result"
  love.thread.getChannel(progressName):clear()
  love.thread.getChannel(resultName):clear()
  local thread = love.thread.newThread("src/import/ExtractThread.lua")
  thread:start(version, prefix, data, progressName, resultName, hash)
  self.extract = {
    thread = thread, version = version, prefix = prefix,
    progress = love.thread.getChannel(progressName),
    result = love.thread.getChannel(resultName),
  }
end

function PackagedImporter:complete(version, prefix)
  local CacheFs = require("src.import.CacheFs")
  -- Written last: the marker is what isReady checks.
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local ok, writeError = CacheContract.publish(version, CacheFs, self.romSha1)
  CacheFs.prefix = savedPrefix
  if not ok then error("could not finish the private cache: " .. tostring(writeError)) end
  local SaveConvert = package.loaded["src.save_convert.SaveConvert"]
  if GameVersion.generation(version) == 2 and SaveConvert then
    SaveConvert.invalidateGen2Data(version)
  end
  self.status = "Ready"
  self.progress = 1
  if self.onComplete then self.onComplete(version) end
end

function PackagedImporter:update()
  if not self.started then
    -- A scripted start for a game with no cache and no ROM to import from.
    self.started = true
    return self:setError("the game is not imported")
  end
  local job = self.extract
  if not job then return end
  local message = job.progress:pop()
  while message do
    self.status = message.stage
    self.progress = message.progress / message.total
    message = job.progress:pop()
  end
  local result = job.result:pop()
  if not result then
    local threadError = job.thread:getError()
    if threadError then self:setError(threadError) end
    return
  end
  self.extract = nil
  if not result.ok then return self:setError(result.error) end
  local ok, err = pcall(self.complete, self, job.version, job.prefix)
  if not ok then self:setError(err) end
end

function PackagedImporter:draw()
  love.graphics.print(("%s: %d%%"):format(tostring(self.status), math.floor(self.progress * 100)), 16, 16)
end

return PackagedImporter
