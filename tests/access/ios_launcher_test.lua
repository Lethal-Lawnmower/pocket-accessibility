-- src/access/IosLauncher.lua without an iPhone: off iOS it must do nothing at all
-- (Windows and Android keep their behaviour), and with a stand-in for the native
-- bridge it reports the choice and turns the game screen's close action into one
-- love.event.quit.  The real bridge (Swift, through the FFI) is covered only by the
-- simulator smoke test (launcher/ios/simulator_smoke.sh).
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq

local quits = 0
_G.love = {
  system = { getOS = function() return "Windows" end },
  event = { quit = function() quits = quits + 1 end },
}

local IosLauncher = require("src.access.IosLauncher")

-- ------------------------------------------------------------ off iOS
eq(IosLauncher.waitForGame(), false, "off iOS nothing waits")
eq(IosLauncher.active(), false, "and the launcher is not active")
for _ = 1, 50 do IosLauncher.update() end
eq(quits, 0, "and updates never quit")

-- ------------------------------------------------------------ a stand-in bridge
local waited, exitAnswers = 0, {}
IosLauncher._setBridgeForTests({
  wait = function() waited = waited + 1; return 1 end,
  takeExit = function()
    exitAnswers[#exitAnswers + 1] = true
    return #exitAnswers == 2 and 1 or 0
  end,
})
eq(IosLauncher.active(), true, "with the bridge the launcher is active")
eq(IosLauncher.waitForGame(), true, "a chosen game returns true")
eq(waited, 1, "the bridge was asked once")

for _ = 1, IosLauncher.POLL_EVERY - 1 do IosLauncher.update() end
eq(#exitAnswers, 0, "the close action is not asked every frame")
IosLauncher.update()
eq(#exitAnswers, 1, "but every few updates")
eq(quits, 0, "no close requested yet")
for _ = 1, IosLauncher.POLL_EVERY do IosLauncher.update() end
eq(quits, 1, "a close request quits the game once")
for _ = 1, IosLauncher.POLL_EVERY * 3 do IosLauncher.update() end
eq(quits, 1, "and only once")

IosLauncher._setBridgeForTests({
  wait = function() return 0 end,
  takeExit = function() error("bridge broke") end,
})
eq(IosLauncher.waitForGame(), false, "a launcher that could not show returns false")
for _ = 1, IosLauncher.POLL_EVERY do IosLauncher.update() end
eq(quits, 1, "a failing bridge never quits the game")

IosLauncher._setBridgeForTests({ wait = function() error("no window") end, takeExit = function() return 0 end })
eq(IosLauncher.waitForGame(), false, "an error in the launcher returns false instead of stopping the game")

-- ------------------------------------------------------------ iOS without the bridge class
IosLauncher._setBridgeForTests(nil)
love.system.getOS = function() return "iOS" end
local okFfi = pcall(require, "ffi")
if okFfi then
  -- LuaJIT on Windows has no Objective-C runtime: the lookup fails cleanly
  eq(IosLauncher.waitForGame(), false, "no Objective-C runtime: nothing waits")
  eq(IosLauncher.active(), false, "and nothing polls")
else
  check(true, "no FFI here; the iOS lookup is not exercised")
end

T.finish("ios launcher")
