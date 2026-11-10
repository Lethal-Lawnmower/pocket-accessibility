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

-- ------------------------------------------------------------ the save editor's backend
-- waitForGame answers 2: the launcher's screen stays up and needs a backend
local requests = { '{"cmd":"open","version":"red","id":1}', '{"cmd":"save","id":2}' }
local responses = {}
local backendEnv = "save"
local realGetenv = os.getenv
os.getenv = function(name)
  if name == "POCKET_BACKEND" then return backendEnv end
  return realGetenv(name)
end
IosLauncher._setBridgeForTests({
  wait = function() return 2 end,
  takeExit = function() return 0 end,
  takeRequest = function() return table.remove(requests, 1) end,
  putResponse = function(text) responses[#responses + 1] = text end,
})
eq(IosLauncher.waitForGame(), false, "a backend is not a game")
eq(IosLauncher.backendRequested(), "save", "the save backend is asked for")
local quitsBefore = quits
local kinds = {}
local answered = IosLauncher.serveBackend(function(kind)
  kinds[#kinds + 1] = kind
  return { answer = function(line)
    if line:find('"save"') then error("disk full") end
    return { ok = true, echo = line }
  end }, { encode = function(value)
    return (value.ok and "ok:" or "error:") .. tostring(value.echo or value.error)
  end }
end)
eq(answered, 2, "both requests answered")
eq(kinds[1], "save", "with the save service")
eq(responses[1], 'ok:{"cmd":"open","version":"red","id":1}', "the answer goes back through the bridge")
check(responses[2]:find("^error:") and responses[2]:find("disk full"), "a failing answer still answers, with the error")
eq(quits, quitsBefore + 1, "closing the screen quits, so LÖVE starts clean")
eq(IosLauncher.backendRequested(), nil, "and the backend is done")

-- a backend that cannot start still answers each request with why
requests = { '{"cmd":"open","id":1}' }
responses = {}
backendEnv = "mods"
IosLauncher.waitForGame()
eq(IosLauncher.backendRequested(), "mods", "the mods backend is asked for")
IosLauncher.serveBackend(function() error("module 'modservice' not found") end)
check(responses[1] and responses[1]:find("did not start", 1, true), "the screen hears that the backend did not start")
os.getenv = realGetenv

-- serveBackend without a request for one does nothing
eq(IosLauncher.serveBackend(function() error("not called") end), 0, "no backend asked: nothing served")

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
