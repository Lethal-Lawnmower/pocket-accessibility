-- What changes when the game runs from a packaged folder (docs/access/launcher.md,
-- "Packaged release").  Upstream's launcher is proprietary (License Term 2) and is
-- left out of the package, so every route that would open it has to end somewhere
-- else.  The packaging script writes MARKER into the game folder; a source checkout
-- has no marker and nothing here does anything.
--
-- main.lua calls install() first, then asks this module at three places
-- (docs/access/architecture.md, hook list).  The stand-ins below keep upstream's
-- requires working without editing the upstream files that hold them.

local PackagedBuild = {
  active = false,
  MARKER = "pocket-access-package.txt",
  -- Our launcher reads this exit code as "the game refused to start", and the
  -- reason from this file in the save folder.
  EXIT_REFUSED = 40,
  REFUSAL_FILE = "pocket-access-start-refused.txt",
}

-- main.lua's RELAUNCH_MARKER: makes the next start ignore POKEPORT_GAME.
local RELAUNCH_MARKER = "relaunch_to_launcher.txt"

local function noop() end

-- Every method main.lua may call on whatever it holds as `Importer`.
local IMPORTER_METHODS = {
  "update", "draw", "keypressed", "textinput", "filedropped", "focus",
  "gamepadpressed", "gamepadreleased", "gamepadaxis",
  "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat",
  "touchpressed", "touchmoved", "touchreleased",
  "mousepressed", "mousereleased", "mousemoved",
  "autoUpdateAll", "ignoreReturningPointer", "savesChanged",
}

function PackagedBuild.fillImporterMethods(target)
  for _, name in ipairs(IMPORTER_METHODS) do
    if target[name] == nil then target[name] = noop end
  end
  return target
end

-- src/mods/LauncherMods.lua is on the Term 2 list.  The game itself reads it for
-- launcher translations (the game's mod loader replaces them on boot), issue
-- reports and account sync.  Our launcher handles mods through ModBackend.
local function launcherModsStandIn()
  return {
    translationStrings = noop,
    list = function() return {} end,
    modOptions = function() return {} end,
    setModOptions = function() return false end,
    setEnabled = function() return false end,
    installFromIndex = function() return nil, "not available in this build" end,
  }
end

-- Nothing is left that could restart into a launcher: closing the program returns
-- the player to our launcher, which is waiting on this process.
local function replaceRestart()
  local HostShell = require("src.core.HostShell")
  HostShell.restart = function()
    love.filesystem.remove(RELAUNCH_MARKER)
    love.event.quit()
  end
end

-- On a computer the games start the way the owner set them up for streaming
-- (decisions 62 and 63): borderless (desktop fullscreen), battles filling the screen
-- over the map, the layout that uses the whole window, and the richest Gen 1 colours.
-- These are upstream's own options; only their defaults change, so a player's saved
-- choice wins and every one of them is still in the options menu.  Speed, frame
-- rate, zoom, sound and accessibility settings stay upstream's (or ours).
-- Scripted runs (silent) keep upstream's defaults, so a test never covers the
-- screen and drivers see the layout they were written for.
PackagedBuild.DESKTOP_DEFAULTS = {
  -- Gen 1 and the options Gen 3 shares (src/core/SaveData.lua)
  shared = {
    videoMode = "borderless",
    battleFit = "fill", battleBg = "world", uiLayout = "dynamic",
    voidFill = "map", colors = "redpp",
  },
  -- Gen 2 keeps its own (src/core/gen2/Save.lua DEFAULT_OPTIONS); videoMode is shared
  gen2 = {
    battleFit = "fill", battleBg = "world", battleHud = "extended", uiLayout = "dynamic",
    voidFill = "trees",
  },
}

local GEN2_SAVE = "src.core.gen2.Save"

local function useDesktopDefaults()
  local SaveData = require("src.core.SaveData")
  local upstreamDefaults = SaveData.defaultOptions
  SaveData.defaultOptions = function(...)
    local options = upstreamDefaults(...)
    for key, value in pairs(PackagedBuild.DESKTOP_DEFAULTS.shared) do options[key] = value end
    return options
  end
  -- Gen 2's save module pulls in half the game, so it is changed when the game
  -- first loads it, not here.  The loader steps aside and lets require find the file.
  if package.loaded[GEN2_SAVE] == nil and package.preload[GEN2_SAVE] == nil then
    package.preload[GEN2_SAVE] = function(name)
      package.preload[name] = nil
      package.loaded[name] = nil
      local Save = require(name)
      if type(Save) == "table" and type(Save.DEFAULT_OPTIONS) == "table" then
        for key, value in pairs(PackagedBuild.DESKTOP_DEFAULTS.gen2) do Save.DEFAULT_OPTIONS[key] = value end
      end
      return Save
    end
  end
end

function PackagedBuild.install()
  if PackagedBuild.active or not love.filesystem.getInfo(PackagedBuild.MARKER, "file") then
    return PackagedBuild
  end
  PackagedBuild.active = true
  package.preload["src.import.RomImporter"] = function()
    return require("src.access.PackagedImporter")
  end
  package.preload["src.mods.LauncherMods"] = launcherModsStandIn
  -- its video lives in assets/launcher, which is left out
  package.preload["src.import.LauncherSplash"] = function()
    return { new = noop }
  end
  replaceRestart()
  -- upstream's updater would mount plain upstream over us.  It already stays off
  -- here (unfused, unstamped version); this holds even for a direct start.
  require("src.update.Boot").canUpdateInPlace = function() return false end
  -- a source run on the same save folder may have left one; it would turn the
  -- next Play into a start without a game
  love.filesystem.remove(RELAUNCH_MARKER)
  if not require("src.core.VideoMode").fixedDisplay() and os.getenv("POKEPORT_ACCESS_SILENT") ~= "1" then
    useDesktopDefaults()
  end
  -- the mods that come with the package; a failure here must never stop the game
  local copied, result = pcall(require("src.access.BundledMods").install)
  if not copied then
    print("[access] bundled mods: " .. tostring(result))
  elseif #result > 0 then
    print("[access] bundled mods: " .. table.concat(result, "; "))
  end
  -- Android's save editor and Mods screen run their backend in this program; it never returns
  local editorPort = os.getenv("POCKET_EDITOR_PORT")
  if editorPort then
    require("src.access.AndroidSaveBackend").serve(editorPort, os.getenv("POCKET_EDITOR_TOKEN"),
      os.getenv("POCKET_BACKEND"))
  end
  return PackagedBuild
end

-- Ends the program instead of opening a launcher.  Returns an inert stand-in, so
-- the rest of the frame finds what it expects until the quit event is handled.
function PackagedBuild.refuse(reason)
  print("[access] start refused: " .. tostring(reason))
  pcall(love.filesystem.write, PackagedBuild.REFUSAL_FILE, tostring(reason))
  love.event.quit(PackagedBuild.EXIT_REFUSED)
  return PackagedBuild.fillImporterMethods({})
end

-- main.lua's makeLauncher: every route to upstream's launcher goes through it.
-- initialTab names the game when a chosen game's cache failed the full check.
function PackagedBuild.noLauncher(launcherOpts)
  local game = launcherOpts and launcherOpts.initialTab
  local GameVersion = require("src.core.GameVersion")
  if type(game) == "string" and GameVersion.VERSIONS[game] then
    return PackagedBuild.refuse("The imported data for this game did not pass the game's check. "
      .. "Choose Import ROM and pick your cartridge dump again.")
  end
  return PackagedBuild.refuse("The game program was started without a game it can open. "
    .. "Start it from Pocket Accessibility's launcher.")
end

-- main.lua's returnToLauncher: a Discord invite or an outside launch request wants
-- upstream's launcher and would drop the running game, unsaved, to get there.
function PackagedBuild.ignoresReturn(opts)
  if opts and (opts.invite or opts.request) then
    print("[access] ignored a request that needs upstream's launcher")
    return true
  end
  return false
end

return PackagedBuild
