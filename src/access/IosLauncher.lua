-- The game side of our native iOS launcher (launcher/ios/native/, docs/access/ios.md,
-- "Startup architecture").  On iOS LÖVE never ends the program: a quit starts the Lua
-- state again, and main.lua runs from the top.  PackagedBuild.install calls waitForGame
-- there, which shows the launcher (Swift, PocketLauncherBridge) and returns once the
-- player has chosen a game and the launcher has set POKEPORT_GAME and the import
-- variables; main.lua then reads them as on Android.  A game that quits or refuses to
-- start therefore comes back to the launcher.
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
    local wait = ffi.C.sel_registerName("waitForGame")
    local exit = ffi.C.sel_registerName("takeExitRequest")
    return {
      wait = function() return tonumber(send(class, wait)) end,
      takeExit = function() return tonumber(send(class, exit)) end,
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
  print("[access] ios launcher: " .. (chosen == 1 and ("game " .. tostring(os.getenv("POKEPORT_GAME")))
    or "not shown"))
  return chosen == 1
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
end

return IosLauncher
