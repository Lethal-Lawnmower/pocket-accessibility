-- src/access/PackagedBuild.lua with a stand-in love: nothing happens without the
-- marker; with it, launcher routes end the program instead of opening a launcher.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq

local marker, removed, written, quitCode
love = {
  filesystem = {
    getInfo = function(path) return path == "pocket-access-package.txt" and marker and {} or nil end,
    remove = function(path) removed[path] = true end,
    write = function(path, text) written[path] = text; return true end,
  },
  event = { quit = function(code) quitCode = code or 0 end },
  system = { getOS = function() return osName end },
}
osName = "Windows"
local function upstreamDefaults() return { videoMode = "windowed", textSpeed = 3 } end
package.loaded["src.core.SaveData"] = { defaultOptions = upstreamDefaults }
package.loaded["src.core.HostShell"] = { restart = function() error("upstream restart ran") end }
package.loaded["src.update.Boot"] = { canUpdateInPlace = function() return true end }
package.loaded["src.core.GameVersion"] = { VERSIONS = { red = {} } }
local realPrint = print
print = function() end -- the module logs each refusal

local function fresh()
  removed, written, quitCode = {}, {}, nil
  package.loaded["src.access.PackagedBuild"] = nil
  package.preload["src.import.RomImporter"] = nil
  return require("src.access.PackagedBuild")
end

-- source checkout
marker = false
local Build = fresh().install()
check(not Build.active, "no marker: not active")
check(package.preload["src.import.RomImporter"] == nil, "no marker: no stand-ins")

-- packaged
marker = true
Build = fresh().install()
check(Build.active, "marker: active")
check(package.preload["src.import.RomImporter"] ~= nil, "RomImporter stand-in")
check(package.preload["src.mods.LauncherMods"]().translationStrings() == nil, "LauncherMods stand-in")
eq(package.preload["src.import.LauncherSplash"]().new(), nil, "no splash")
check(removed["relaunch_to_launcher.txt"], "a stale relaunch marker is removed")
check(not require("src.update.Boot").canUpdateInPlace(), "updater off")
local SaveData = require("src.core.SaveData")
if os.getenv("POKEPORT_ACCESS_SILENT") ~= "1" then
  eq(SaveData.defaultOptions().videoMode, "borderless", "a computer starts borderless by default")
  eq(SaveData.defaultOptions().textSpeed, 3, "the other defaults are upstream's")
end

-- Android keeps upstream's defaults (its display is fixed)
SaveData.defaultOptions = upstreamDefaults
osName = "Android"
fresh().install()
eq(SaveData.defaultOptions().videoMode, "windowed", "Android: video mode default untouched")
osName = "Windows"

removed = {}
require("src.core.HostShell").restart()
check(removed["relaunch_to_launcher.txt"], "restart removes the marker")
eq(quitCode, 0, "restart only quits")

quitCode = nil
local stub = Build.noLauncher({ initialTab = "red" })
eq(quitCode, 40, "failed cache: refused exit code")
check(written[Build.REFUSAL_FILE]:find("Import ROM", 1, true), "failed cache: says what to do")
check(type(stub.update) == "function" and type(stub.draw) == "function", "refusal stand-in has methods")

quitCode, written = nil, {}
Build.noLauncher(nil)
eq(quitCode, 40, "no game: refused exit code")
check(written[Build.REFUSAL_FILE]:find("launcher", 1, true), "no game: says what to do")

check(Build.ignoresReturn({ tab = "online", invite = "abc" }), "Discord invite ignored")
check(Build.ignoresReturn({ request = {} }), "launch request ignored")
check(not Build.ignoresReturn({ tab = "online" }), "arena exit ends the game")
check(not Build.ignoresReturn(nil), "game exit ends the game")

print = realPrint
T.finish()
