-- The game side of our native iOS launcher (launcher/ios/native/, docs/access/ios.md,
-- "Startup architecture").  On iOS LÖVE never ends the program: a quit starts the Lua
-- state again, and main.lua runs from the top.  PackagedBuild.install calls waitForGame
-- there, which shows the launcher (Swift, PocketLauncherBridge) and returns once the
-- player has chosen a game and the launcher has set POKEPORT_GAME and the import
-- variables; main.lua then reads them as on Android.  A game that quits or refuses to
-- start therefore comes back to the launcher.
--
-- The save editor and the Mods screen (docs/access/ios.md, "Save editor and mods") use the
-- same backends as Android (launcher/SaveBackend, launcher/ModBackend), without a socket:
-- waitForGame answers 2 and leaves the launcher's screen up, and serveBackend then takes
-- each request from the bridge (takeRequest runs the main run loop, so the screen keeps
-- working, until a request comes or the screen closes) and hands back the answer
-- (putResponse).  When the screen closes the program quits, so LÖVE starts a clean Lua
-- state: nothing the editor loaded stays for the next game.
--
-- The bridge is reached through LuaJIT's FFI and the Objective-C runtime (objc_getClass,
-- sel_registerName, objc_msgSend cast to the exact signature), the same route upstream's
-- liblove patch uses from C++, so no symbol of ours has to be exported.  Everywhere but
-- iOS, and when the bridge is missing, every function here does nothing.

local IosLauncher = {
  CLASS = "PocketLauncherBridge",
  -- how many updates between checks for the game screen's "close the game" action
  POLL_EVERY = 10,
}

local bridge -- nil: not looked up yet; false: not available
local updates = 0
local backendKind -- "save" or "mods" after waitForGame answered 2

local function isIos()
  local ok, name = pcall(function() return love.system.getOS() end)
  return ok and name == "iOS"
end

local function lookUp()
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi then return nil, "no FFI" end
  pcall(ffi.cdef, [[
    void *objc_getClass(const char *name);
    void *sel_registerName(const char *name);
  ]])
  -- declared only to take its address; it is always called through the cast below
  pcall(ffi.cdef, "void objc_msgSend(void);")
  local ok, result = pcall(function()
    local class = ffi.C.objc_getClass(IosLauncher.CLASS)
    if class == nil then return nil end
    -- +[PocketLauncherBridge waitForGame] and takeExitRequest: no arguments, an NSInteger back
    local send = ffi.cast("intptr_t (*)(void *, void *)", ffi.C.objc_msgSend)
    -- +takeRequest: a C string (the bridge keeps it until the next call), NULL once closed
    local sendTake = ffi.cast("const char *(*)(void *, void *)", ffi.C.objc_msgSend)
    -- +putResponse: a C string the bridge copies
    local sendPut = ffi.cast("void (*)(void *, void *, const char *)", ffi.C.objc_msgSend)
    local wait = ffi.C.sel_registerName("waitForGame")
    local exit = ffi.C.sel_registerName("takeExitRequest")
    local take = ffi.C.sel_registerName("takeRequest")
    local put = ffi.C.sel_registerName("putResponse:")
    return {
      wait = function() return tonumber(send(class, wait)) end,
      takeExit = function() return tonumber(send(class, exit)) end,
      takeRequest = function()
        local text = sendTake(class, take)
        if text == nil then return nil end
        return ffi.string(text)
      end,
      putResponse = function(text) sendPut(class, put, text) end,
    }
  end)
  if not ok then return nil, tostring(result) end
  if not result then return nil, "class " .. IosLauncher.CLASS .. " not found" end
  return result
end

local function get()
  if bridge == nil then
    bridge = false
    if isIos() then
      local found, why = lookUp()
      if found then
        bridge = found
      else
        print("[access] ios launcher unavailable: " .. tostring(why))
      end
    end
  end
  return bridge or nil
end

-- True when the launcher ran and a game was chosen (the environment is set).
function IosLauncher.waitForGame()
  local b = get()
  if not b then return false end
  print("[access] ios launcher: waiting for a game")
  local ok, chosen = pcall(b.wait)
  if not ok then
    print("[access] ios launcher failed: " .. tostring(chosen))
    return false
  end
  if chosen == 2 then
    backendKind = os.getenv("POCKET_BACKEND") or "save"
    print("[access] ios launcher: " .. backendKind .. " backend")
    return false
  end
  print("[access] ios launcher: " .. (chosen == 1 and ("game " .. tostring(os.getenv("POKEPORT_GAME")))
    or "not shown"))
  return chosen == 1
end

-- "save" or "mods" when the launcher opened a screen that needs a backend; nil otherwise.
function IosLauncher.backendRequested()
  return backendKind
end

-- Answers the open screen's requests until it closes, then quits so that LÖVE starts a
-- clean Lua state and the launcher again.  `prepare` is for tests.  Returns the number
-- of requests answered.
function IosLauncher.serveBackend(prepare)
  local b = get()
  if not (b and backendKind) then return 0 end
  prepare = prepare or require("src.access.AndroidSaveBackend").prepare
  local okPrepare, Service, Json = pcall(prepare, backendKind)
  local answered = 0
  while true do
    local okTake, line = pcall(b.takeRequest)
    if not okTake or not line then break end
    local response
    if okPrepare then
      local ok, result = pcall(Service.answer, line)
      response = ok and result or { ok = false, error = tostring(result) }
    else
      -- the screen still gets an answer, so it can say what went wrong
      response = { ok = false, error = "The backend did not start: " .. tostring(Service) }
    end
    local okEncode, text = pcall(function()
      return (Json or require("src.link.Json")).encode(response)
    end)
    if not okEncode then text = '{"ok":false,"error":"The answer could not be encoded."}' end
    pcall(b.putResponse, text)
    answered = answered + 1
  end
  print("[access] ios launcher: " .. backendKind .. " backend closed after " .. answered .. " requests")
  backendKind = nil
  love.event.quit()
  return answered
end

function IosLauncher.active()
  return get() ~= nil
end

-- Every update while a game runs: the game screen's VoiceOver action asks to close the
-- game, which goes through love.event.quit exactly like a window close elsewhere
-- (main.lua's love.quit; nothing is saved), and LÖVE then brings the launcher back.
function IosLauncher.update()
  local b = get()
  if not b then return end
  updates = updates + 1
  if updates < IosLauncher.POLL_EVERY then return end
  updates = 0
  local ok, requested = pcall(b.takeExit)
  if ok and requested == 1 then
    print("[access] ios launcher: closing the game")
    love.event.quit()
  end
end

function IosLauncher._setBridgeForTests(fake)
  bridge = fake
  updates = 0
  backendKind = nil
end

return IosLauncher
