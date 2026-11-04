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
