-- The mods that come with the package (src/access/BundledMods.lua, decision 61):
-- copied into the save folder once, the randomizer written as off, a newer bundled
-- version replacing an older copy (keeping baseroms), a removed mod not put back, and
-- a copy already there left as it is.  A fake filesystem with a game folder and a
-- save folder mounted together, the way LÖVE mounts them.
-- Run: luajit tests/access/bundled_mods_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

local BundledMods = require("src.access.BundledMods")
local SaveData = require("src.core.SaveData")

local function manifest(id, version)
  return ('{"id":"%s","name":"%s","version":"%s","api":2,"entry":"main.lua"}'):format(id, id, version)
end

-- files: path -> contents, for each mount; save writes go to `save`
local function newFs(game)
  local fs = { game = game, save = {} }
  local function dirs(files, path)
    local items = {}
    local prefix = path == "" and "" or path .. "/"
    for file in pairs(files) do
      if file:sub(1, #prefix) == prefix then
        local rest = file:sub(#prefix + 1)
        local first = rest:match("^[^/]+")
        if first then items[first] = true end
      end
    end
    return items
  end
  local function isDir(files, path)
    for file in pairs(files) do
      if file:sub(1, #path + 1) == path .. "/" then return true end
    end
    return files[path .. "/"] ~= nil
  end
  function fs.getSaveDirectory() return "SAVE" end
  function fs.getRealDirectory(path)
    if fs.save[path] or isDir(fs.save, path) then return "SAVE" end
    if fs.game[path] or isDir(fs.game, path) then return "GAME" end
    return nil
  end
  function fs.getDirectoryItems(path)
    local merged = dirs(fs.save, path)
    for name in pairs(dirs(fs.game, path)) do merged[name] = true end
    local list = {}
    for name in pairs(merged) do
      if name ~= "" then list[#list + 1] = name end
    end
    table.sort(list)
    return list
  end
  function fs.getInfo(path, kind)
    local file = fs.save[path] or fs.game[path]
    local found = (file and file ~= true) and "file"
      or ((isDir(fs.save, path) or isDir(fs.game, path)) and "directory") or nil
    if not found or (kind and kind ~= found) then return nil end
    return { type = found }
  end
  function fs.read(path)
    local file = fs.save[path] or fs.game[path]
    if type(file) == "string" then return file end
    return nil
  end
  function fs.write(path, data)
    fs.save[path] = data
    return true
  end
  function fs.createDirectory(path)
    fs.save[path .. "/"] = fs.save[path .. "/"] or true
    return true
  end
  function fs.remove(path)
    fs.save[path] = nil
    fs.save[path .. "/"] = nil
    return true
  end
  return fs
end

local function game(clockVersion, randomizerVersion)
  return {
    ["launcher/mods/pc_clock/manifest.json"] = manifest("pocket_pc_clock", clockVersion),
    ["launcher/mods/pc_clock/main.lua"] = "-- clock " .. clockVersion,
    ["launcher/mods/crystal_randomizer/manifest.json"] = manifest("crystal_randomizer", randomizerVersion),
    ["launcher/mods/crystal_randomizer/main.lua"] = "-- randomizer",
    ["launcher/mods/crystal_randomizer/modules/wild.lua"] = "-- wild",
    ["launcher/mods/crystal_randomizer/tests/wild_test.lua"] = "-- test",
  }
end

local function enabled(fs, id)
  local options = SaveData.loadOptions(fs)
  local flag = SaveData.modEnabled(options, id, "crystal")
  if flag == nil then return true end
  return flag
end

-- a fresh save folder
local fs = newFs(game("1.0.0", "0.1.0"))
local done = BundledMods.install(fs)
eq(#done, 2, "both mods copied on first start")
check(fs.save["mods/pc_clock/manifest.json"] ~= nil, "clock copied into the save folder")
check(fs.save["mods/crystal_randomizer/modules/wild.lua"] ~= nil, "randomizer modules copied")
check(fs.save["mods/crystal_randomizer/tests/wild_test.lua"] == nil, "developer tests are not copied")
eq(enabled(fs, "pocket_pc_clock"), true, "the clock starts on")
eq(enabled(fs, "crystal_randomizer"), false, "the randomizer starts off")

-- the next start does nothing
eq(#BundledMods.install(fs), 0, "a second start changes nothing")

-- the player turns the randomizer on; the next start keeps that
local options = SaveData.loadOptions(fs)
SaveData.setModEnabled(options, "crystal_randomizer", true)
SaveData.saveOptions(options, fs)
BundledMods.install(fs)
eq(enabled(fs, "crystal_randomizer"), true, "a player's choice is kept")

-- a newer package replaces the older copy and keeps baseroms
fs.save["mods/pc_clock/baseroms/receipt.json"] = "{}"
fs.save["mods/pc_clock/old.lua"] = "-- gone in 1.1.0"
fs.game = game("1.1.0", "0.1.0")
done = BundledMods.install(fs)
eq(#done, 1, "one mod updated")
eq(fs.save["mods/pc_clock/main.lua"], "-- clock 1.1.0", "the clock's files are the new version's")
check(fs.save["mods/pc_clock/old.lua"] == nil, "files the new version no longer has are gone")
eq(fs.save["mods/pc_clock/baseroms/receipt.json"], "{}", "baseroms are kept")
eq(enabled(fs, "crystal_randomizer"), true, "an update does not touch on or off")

-- an older package does not downgrade
fs.game = game("1.0.0", "0.1.0")
eq(#BundledMods.install(fs), 0, "an older bundled version is not installed over a newer one")

-- a removed mod stays removed
for path in pairs(fs.save) do
  if path:find("^mods/crystal_randomizer") then fs.save[path] = nil end
end
eq(#BundledMods.install(fs), 0, "a removed mod is not put back")
check(fs.save["mods/crystal_randomizer/manifest.json"] == nil, "the randomizer stays removed")

-- a save folder that already has a copy, in another folder name, keeps it
fs = newFs(game("1.0.0", "0.1.0"))
fs.save["mods/my_clock/manifest.json"] = manifest("pocket_pc_clock", "1.0.0")
done = BundledMods.install(fs)
eq(#done, 1, "only the missing mod is copied")
check(fs.save["mods/pc_clock/manifest.json"] == nil, "the existing clock is not copied a second time")

T.finish()
