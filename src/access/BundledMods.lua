-- The mods that come with Pocket Accessibility (decision 61): the owner's own PC Clock
-- and Crystal Randomizer, an exception to "no bundled mods" (decision 42) for these two.
--
-- They ship in the package under launcher/mods and are copied into the save folder's
-- mods folder at start, so they are ordinary installed mods: both launchers list them,
-- and players turn them on or off, or remove them, like any other.  On first copy the
-- PC Clock is left on (the game's default for a mod) and the randomizer is written as
-- off for every game, so a New Game in Crystal only asks Oak's questions when the
-- player chose it.
--
-- A newer bundled version replaces an older installed copy (keeping its baseroms).
-- A mod the player removed is not put back: every id seen is recorded in SEEN_FILE.
-- A copy that is already there, such as one installed by hand, is left as it is,
-- including whether it is on.

local BundledMods = {}

BundledMods.SOURCE = "launcher/mods"
BundledMods.SEEN_FILE = "pocket-access-bundled-mods.txt"
BundledMods.MODS = {
  { folder = "pc_clock", id = "pocket_pc_clock", on = true },
  { folder = "crystal_randomizer", id = "crystal_randomizer", on = false },
}

-- developer files the game never loads
local SKIP = { tests = true }
local KEEP = { baseroms = true }

local function readManifest(fs, folder)
  local raw = fs.read(folder .. "/manifest.json")
  if not raw then return nil end
  local ok, data = pcall(require("src.link.Json").decode, raw)
  if ok and type(data) == "table" and type(data.id) == "string" then return data end
  return nil
end

local function readSeen(fs)
  local seen = {}
  local raw = fs.getInfo(BundledMods.SEEN_FILE, "file") and fs.read(BundledMods.SEEN_FILE)
  for id in tostring(raw or ""):gmatch("[^\r\n]+") do seen[id] = true end
  return seen
end

local function writeSeen(fs, seen)
  local ids = {}
  for id in pairs(seen) do ids[#ids + 1] = id end
  table.sort(ids)
  fs.write(BundledMods.SEEN_FILE, table.concat(ids, "\n") .. "\n")
end

-- Only the save folder's copy counts: the game folder is mounted under the same names.
local function installedById(fs)
  local found = {}
  local saveDir = (fs.getSaveDirectory() or ""):gsub("\\", "/")
  for _, name in ipairs(fs.getDirectoryItems("mods") or {}) do
    local folder = "mods/" .. name
    local realDir = (fs.getRealDirectory(folder) or ""):gsub("\\", "/")
    if realDir == saveDir then
      local manifest = readManifest(fs, folder)
      if manifest then found[manifest.id] = { folder = folder, version = manifest.version } end
    end
  end
  return found
end

local function clear(fs, folder)
  for _, name in ipairs(fs.getDirectoryItems(folder) or {}) do
    local path = folder .. "/" .. name
    if not KEEP[name] then
      local info = fs.getInfo(path)
      if info and info.type == "directory" then clear(fs, path) end
      fs.remove(path)
    end
  end
end

local function copy(fs, from, to)
  assert(fs.createDirectory(to), "could not create " .. to)
  for _, name in ipairs(fs.getDirectoryItems(from) or {}) do
    local source, target = from .. "/" .. name, to .. "/" .. name
    local info = fs.getInfo(source)
    if info and info.type == "directory" then
      if not SKIP[name] then copy(fs, source, target) end
    elseif info then
      local data = assert(fs.read(source))
      assert(fs.write(target, data), "could not write " .. target)
    end
  end
end

local function setOff(fs, id)
  local SaveData = require("src.core.SaveData")
  local options = SaveData.loadOptions(fs)
  SaveData.setModEnabled(options, id, false)
  SaveData.saveOptions(options, fs)
end

-- Returns a list of what was done, for the log.
function BundledMods.install(fs)
  fs = fs or love.filesystem
  local Semver = require("src.mods.Semver")
  local seen = readSeen(fs)
  local installed = installedById(fs)
  local done = {}
  for _, mod in ipairs(BundledMods.MODS) do
    local sourceFolder = BundledMods.SOURCE .. "/" .. mod.folder
    local bundled = readManifest(fs, sourceFolder)
    local have = installed[mod.id]
    if not bundled or bundled.id ~= mod.id then
      done[#done + 1] = mod.id .. ": not in this package"
    elseif have then
      if Semver.compare(have.version, bundled.version) == -1 then
        clear(fs, have.folder)
        copy(fs, sourceFolder, have.folder)
        done[#done + 1] = ("%s: updated %s to %s"):format(mod.id, tostring(have.version), bundled.version)
      end
      seen[mod.id] = true
    elseif not seen[mod.id] then
      fs.createDirectory("mods")
      local target = "mods/" .. mod.folder
      if fs.getInfo(target) then target = "mods/" .. mod.id end
      copy(fs, sourceFolder, target)
      if not mod.on then setOff(fs, mod.id) end
      seen[mod.id] = true
      done[#done + 1] = ("%s: installed %s%s"):format(mod.id, bundled.version, mod.on and "" or ", off")
    end
  end
  writeSeen(fs, seen)
  return done
end

return BundledMods
