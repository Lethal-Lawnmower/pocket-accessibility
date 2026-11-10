-- Accessibility speech layer: Speech routing, Access.install wiring, and
-- PrismBackend's library search order.  Uses a fake backend; real Prism
-- output is checked by running the game (docs/access/speech.md).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Speech = require("src.access.Speech")
local Access = require("src.access")
local PrismBackend = require("src.access.speech.PrismBackend")

local function fakeBackend()
  local fake = { name = "Fake", spoken = {}, stops = 0, closed = false }
  function fake:say(text, interrupt)
    self.spoken[#self.spoken + 1] = { text = text, interrupt = interrupt }
    return true
  end
  function fake:stop() self.stops = self.stops + 1 return true end
  function fake:close() self.closed = true end
  return fake
end

-- Speech before start is a silent no-op, not an error.
Speech.shutdown()
check(not Speech.available(), "no backend before start")
check(Speech.say("hello") == false, "say before start returns false")

-- Routing to the backend.
local fake = fakeBackend()
check(Speech.start({ backend = fake }), "start with injected backend")
eq(Speech.status(), "ready: Fake", "status names the backend")
check(Speech.say("Pokemon Center", { interrupt = true }), "say returns true")
eq(fake.spoken[1].text, "Pokemon Center", "text passed through")
eq(fake.spoken[1].interrupt, true, "interrupt flag passed through")
Speech.say("queued")
eq(fake.spoken[2].interrupt, false, "default does not interrupt")
Speech.say(42)
eq(fake.spoken[3].text, "42", "non-string text is converted")
check(Speech.say("   ") == false, "blank text is not spoken")
eq(#fake.spoken, 3, "blank text never reaches the backend")
check(Speech.stop(), "stop forwards to backend")
eq(fake.stops, 1, "backend stop called once")
Speech.shutdown()
check(fake.closed, "shutdown closes the backend")
check(not Speech.available(), "no backend after shutdown")

-- A failing backend reports false instead of raising.
local failing = fakeBackend()
function failing:say() return false, "boom" end
Speech.start({ backend = failing })
check(Speech.say("x") == false, "backend failure returns false")
Speech.shutdown()

-- A line Prism refuses as invalid UTF-8 is spoken again in plain ASCII.
local refusing = fakeBackend()
local realSay = refusing.say
function refusing:say(text, interrupt)
  if text:find("[\128-\255]") then return false, "Invalid UTF-8" end
  return realSay(self, text, interrupt)
end
Speech.start({ backend = refusing })
check(Speech.say("but good luck…", { interrupt = true }), "refused line still reports spoken")
eq(refusing.spoken[1].text, "but good luck...", "refused line is said in ASCII")
eq(refusing.spoken[1].interrupt, true, "the retry keeps the interrupt flag")
check(Speech.say("POKéMON\255"), "stray bytes are dropped on the retry")
eq(refusing.spoken[2].text, "POKeMON", "accents become plain letters")
check(Speech.say("…\255") == true, "punctuation-only text is still said")
check(Speech.say("\255") == false, "nothing left to say fails quietly")
Speech.shutdown()

-- Other failures are not retried.
local broken = fakeBackend()
local brokenCalls = 0
function broken:say() brokenCalls = brokenCalls + 1 return false, "boom" end
Speech.start({ backend = broken })
Speech.say("a…")
eq(brokenCalls, 1, "only an encoding refusal is retried")
Speech.shutdown()

-- Access.install announces readiness once and closes speech on a real quit.
local quitResult = nil
love.quit = function() return quitResult end
local installFake = fakeBackend()
Access._resetForTests()
check(Access.install({ speech = { backend = installFake } }), "install runs once")
check(Access.install({ speech = { backend = installFake } }) == false, "second install refused")
eq(installFake.spoken[1].text, "Pocket Accessibility ready.", "ready announcement")
eq(installFake.spoken[1].interrupt, true, "ready announcement interrupts")

quitResult = true
eq(love.quit(), true, "cancelled quit result passes through")
check(not installFake.closed, "cancelled quit keeps speech open")
quitResult = nil
eq(love.quit(), nil, "normal quit result passes through")
check(installFake.closed, "real quit closes speech")
Access._resetForTests()

-- Library search order: explicit path, beside the program, then local-deps.
local env = function(name)
  if name == "POKEPORT_PRISM_DLL" then return "C:/custom/prism.dll" end
end
local paths = PrismBackend.candidates(env, { "C:/game/", "C:/src" }, "Windows")
eq(paths[1], "C:/custom/prism.dll", "explicit path first")
eq(paths[2], "C:/game/prism.dll", "program folder second, trailing slash trimmed")
eq(paths[3], "C:/src/prism.dll", "source folder third")
eq(paths[4], "C:/game/local-deps/prism/prism.dll", "local-deps after direct folders")
eq(#PrismBackend.candidates(function() end, { "/a", "/a" }, "Linux"), 2,
  "duplicate folders are listed once")
eq(PrismBackend.candidates(function() end, { "/a" }, "Linux")[1], "/a/libprism.so",
  "Linux library name")
local iosPaths = PrismBackend.candidates(function() end, { "/app/love.app" }, "iOS")
eq(iosPaths[1], "@executable_path/Frameworks/libprism.dylib", "iOS: the app's Frameworks folder first")
eq(iosPaths[2], "/app/love.app/libprism.dylib", "iOS: then the usual folders")

-- A missing library is reported with every path tried.
local opened, err = PrismBackend.open({ env = function() end, dirs = { "Z:/nowhere" } })
check(opened == nil, "open fails without a library")
check(tostring(err):find("Z:/nowhere/prism.dll", 1, true) ~= nil,
  "failure message lists the paths tried")

T.finish()
