-- Haptics (decision 68): a light tick for every step the player takes and a
-- firmer click when they walk into something, on phones and tablets that can
-- vibrate.  Subtle on purpose: the system's own short effects, never a buzz.
--
-- Two native routes, both reached through LuaJIT's FFI so no Java or Swift
-- symbol of ours is exported to the game:
--   Android: the activity's Vibrator over JNI (the route upstream's
--            src/core/Orientation.lua uses), playing VibrationEffect's
--            predefined TICK and HEAVY_CLICK (API 29); on API 26-28 short
--            low-amplitude one-shots instead.  LÖVE's love.system.vibrate is
--            not used: on Android it is a full-strength buzz.
--   iOS:     +[PocketHaptics play:] (launcher/ios/native/PocketHaptics.swift),
--            UIKit's impact feedback, through the Objective-C runtime the way
--            src/access/IosLauncher.lua reaches the launcher.  love.system.vibrate
--            there is the long system vibration.
-- Both follow the device's own setting: Android's "touch feedback" / vibration
-- intensity and iOS's System Haptics can silence them.
--
-- Where the events come from (runtime wrappers, architecture.md hook list):
--   steps: upstream's world.stepped event, which src/access/nav/init.lua already
--          subscribes to for auto-walk (unscripted steps only, in every generation);
--   bumps: the moment each game plays its own bump sound -- Gen 1 Sound.play
--          "Collision", Gen 2 World:bumpSound, Gen 3 Audio.playSe(SE_WALL_HIT) --
--          so the click lands with the sound and repeats as the sound does.
-- The wrappers are installed once each module has been loaded by the game
-- (Haptics.update), so nothing here loads a generation that is not running.

local Haptics = {
  -- shortest gap between two pulses of one kind: a fast auto-walk can take
  -- several steps in one frame, which would blur into a buzz
  MIN_GAP = { step = 0.05, bump = 0.12 },
}

-- VibrationEffect.EFFECT_* (API 29) and the one-shot stand-ins for API 26-28
-- (milliseconds, amplitude 1-255).
local ANDROID_EFFECTS = {
  step = { predefined = 2, ms = 8, amplitude = 50 },   -- EFFECT_TICK
  bump = { predefined = 5, ms = 18, amplitude = 140 }, -- EFFECT_HEAVY_CLICK
}
-- +[PocketHaptics play:]'s kinds
local IOS_KINDS = { step = 1, bump = 2 }

local backend -- nil: not looked up yet; false: none on this device
local lastPulse = {}
local wrapped = {}
local isEnabled = function() return true end

local function now()
  local timer = love and love.timer
  return timer and timer.getTime and timer.getTime() or os.clock()
end

local function osName()
  local ok, name = pcall(function() return love.system.getOS() end)
  return ok and name or nil
end

-- ---------------------------------------------------------------- Android

-- Slot numbers in JNINativeInterface (jni.h).
local JNI = {
  FIND_CLASS = 6, EXCEPTION_CLEAR = 17, NEW_GLOBAL_REF = 21, DELETE_LOCAL_REF = 23,
  GET_OBJECT_CLASS = 31, GET_METHOD_ID = 33, CALL_OBJECT_METHOD_A = 36,
  CALL_BOOLEAN_METHOD_A = 39, CALL_VOID_METHOD_A = 63, GET_STATIC_METHOD_ID = 113,
  CALL_STATIC_OBJECT_METHOD_A = 116, NEW_STRING_UTF = 167, EXCEPTION_CHECK = 228,
}

local function androidBackend()
  local ffi = require("ffi")
  -- each separately: upstream's Orientation.lua may have declared the SDL ones
  pcall(ffi.cdef, "typedef union { void *l; int32_t i; int64_t j; } pocket_jvalue;")
  pcall(ffi.cdef, "void *SDL_AndroidGetJNIEnv(void);")
  pcall(ffi.cdef, "void *SDL_AndroidGetActivity(void);")

  local env = ffi.C.SDL_AndroidGetJNIEnv()
  if env == nil then return nil, "no JNI environment" end
  local fns = ffi.cast("void***", env)[0]
  local function fn(slot, signature) return ffi.cast(signature, fns[slot]) end
  local findClass = fn(JNI.FIND_CLASS, "void *(*)(void *, const char *)")
  local exceptionClear = fn(JNI.EXCEPTION_CLEAR, "void (*)(void *)")
  local exceptionCheck = fn(JNI.EXCEPTION_CHECK, "uint8_t (*)(void *)")
  local newGlobalRef = fn(JNI.NEW_GLOBAL_REF, "void *(*)(void *, void *)")
  local deleteLocalRef = fn(JNI.DELETE_LOCAL_REF, "void (*)(void *, void *)")
  local getObjectClass = fn(JNI.GET_OBJECT_CLASS, "void *(*)(void *, void *)")
  local getMethodID = fn(JNI.GET_METHOD_ID, "void *(*)(void *, void *, const char *, const char *)")
  local getStaticMethodID = fn(JNI.GET_STATIC_METHOD_ID,
    "void *(*)(void *, void *, const char *, const char *)")
  local callObjectA = fn(JNI.CALL_OBJECT_METHOD_A, "void *(*)(void *, void *, void *, pocket_jvalue *)")
  local callBooleanA = fn(JNI.CALL_BOOLEAN_METHOD_A, "uint8_t (*)(void *, void *, void *, pocket_jvalue *)")
  local callVoidA = fn(JNI.CALL_VOID_METHOD_A, "void (*)(void *, void *, void *, pocket_jvalue *)")
  local callStaticObjectA = fn(JNI.CALL_STATIC_OBJECT_METHOD_A,
    "void *(*)(void *, void *, void *, pocket_jvalue *)")
  local newStringUTF = fn(JNI.NEW_STRING_UTF, "void *(*)(void *, const char *)")

  -- true when the last call threw (and forgets the exception)
  local function threw()
    if exceptionCheck(env) ~= 0 then exceptionClear(env) return true end
    return false
  end
  local locals = {}
  local function keep(ref) if ref ~= nil then locals[#locals + 1] = ref end return ref end
  local function cleanUp() for _, ref in ipairs(locals) do deleteLocalRef(env, ref) end end

  local result, why = (function()
    local activity = keep(ffi.C.SDL_AndroidGetActivity())
    if activity == nil then return nil, "no activity" end
    local contextClass = keep(getObjectClass(env, activity))
    local getSystemService = getMethodID(env, contextClass, "getSystemService",
      "(Ljava/lang/String;)Ljava/lang/Object;")
    if getSystemService == nil or threw() then return nil, "no getSystemService" end
    local args = ffi.new("pocket_jvalue[2]")
    args[0].l = keep(newStringUTF(env, "vibrator"))
    local vibrator = keep(callObjectA(env, activity, getSystemService, args))
    if vibrator == nil or threw() then return nil, "no vibrator service" end
    local vibratorClass = keep(getObjectClass(env, vibrator))
    local hasVibrator = getMethodID(env, vibratorClass, "hasVibrator", "()Z")
    if hasVibrator == nil or threw() then return nil, "no hasVibrator" end
    if callBooleanA(env, vibrator, hasVibrator, args) == 0 or threw() then
      return nil, "this device cannot vibrate"
    end
    local vibrate = getMethodID(env, vibratorClass, "vibrate", "(Landroid/os/VibrationEffect;)V")
    if vibrate == nil or threw() then return nil, "no vibrate(VibrationEffect)" end
    local effectClass = keep(findClass(env, "android/os/VibrationEffect"))
    if effectClass == nil or threw() then return nil, "no VibrationEffect" end
    local predefined = getStaticMethodID(env, effectClass, "createPredefined",
      "(I)Landroid/os/VibrationEffect;")
    if predefined == nil then threw() end -- API 26-28
    local oneShot = getStaticMethodID(env, effectClass, "createOneShot",
      "(JI)Landroid/os/VibrationEffect;")
    if oneShot == nil then threw() end

    local effects = {}
    for kind, spec in pairs(ANDROID_EFFECTS) do
      local effect
      if predefined ~= nil then
        args[0].i = spec.predefined
        effect = callStaticObjectA(env, effectClass, predefined, args)
        if threw() then effect = nil end
      end
      if effect == nil and oneShot ~= nil then
        args[0].j, args[1].i = spec.ms, spec.amplitude
        effect = callStaticObjectA(env, effectClass, oneShot, args)
        if threw() then effect = nil end
      end
      if effect ~= nil then
        effects[kind] = newGlobalRef(env, keep(effect))
      end
    end
    if next(effects) == nil then return nil, "no vibration effects" end
    local vibratorRef = newGlobalRef(env, vibrator)
    local callArgs = ffi.new("pocket_jvalue[1]")
    return {
      play = function(kind)
        local effect = effects[kind]
        if not effect then return false end
        callArgs[0].l = effect
        callVoidA(env, vibratorRef, vibrate, callArgs)
        return not threw()
      end,
    }
  end)()
  cleanUp()
  return result, why
end

-- ---------------------------------------------------------------- iOS

local function iosBackend()
  local ffi = require("ffi")
  pcall(ffi.cdef, [[
    void *objc_getClass(const char *name);
    void *sel_registerName(const char *name);
  ]])
  -- declared only to take its address; always called through the cast below
  pcall(ffi.cdef, "void objc_msgSend(void);")
  local class = ffi.C.objc_getClass("PocketHaptics")
  if class == nil then return nil, "class PocketHaptics not found" end
  local send = ffi.cast("void (*)(void *, void *, intptr_t)", ffi.C.objc_msgSend)
  local play = ffi.C.sel_registerName("play:")
  return {
    play = function(kind)
      local code = IOS_KINDS[kind]
      if not code then return false end
      send(class, play, code)
      return true
    end,
  }
end

-- ---------------------------------------------------------------- public

local function get()
  if backend == nil then
    backend = false
    local name = osName()
    local lookUp = (name == "Android" and androidBackend) or (name == "iOS" and iosBackend) or nil
    if lookUp then
      local ok, found, why = pcall(lookUp)
      if ok and found then
        backend = found
      else
        print("[access] haptics unavailable: " .. tostring(ok and why or found))
      end
    end
  end
  return backend or nil
end

-- True when this device can play our haptics (the HAPTICS option is shown).
function Haptics.available()
  return get() ~= nil
end

-- `enabled()` says whether the player has HAPTICS on (src/access/Settings.lua).
function Haptics.setEnabledCheck(enabled)
  isEnabled = enabled
end

-- Plays "step" or "bump".  Returns true when a pulse was sent.
function Haptics.pulse(kind)
  local gap = Haptics.MIN_GAP[kind]
  if not gap then return false end
  local okEnabled, enabled = pcall(isEnabled)
  if not (okEnabled and enabled) then return false end
  local b = get()
  if not b then return false end
  local t = now()
  if lastPulse[kind] and t - lastPulse[kind] < gap then return false end
  lastPulse[kind] = t
  local ok, sent = pcall(b.play, kind)
  return ok and sent == true
end

function Haptics.stepped()
  return Haptics.pulse("step")
end

function Haptics.bumped()
  return Haptics.pulse("bump")
end

-- The bump-sound wrappers, each installed once its module is loaded.
local BUMP_SOUNDS = {
  { -- Gen 1: OverworldController's blocked step (and the elevator's shake)
    module = "src.core.Sound", field = "play",
    isBump = function(_, name) return name == "Collision" end,
  },
  { -- Gen 2: World:bumpSound (a blocked step or map connection)
    module = "src.world.gen2.World", field = "bumpSound",
    isBump = function() return true end,
  },
  { -- Gen 3: the player's (and the bikes') wall hit
    module = "src.core.game3.audio", field = "playSe",
    isBump = function(id)
      if id == "SE_WALL_HIT" then return true end
      local SE = package.loaded["src.core.game3.se_ids"]
      return type(SE) == "table" and SE.SE_WALL_HIT ~= nil and id == SE.SE_WALL_HIT
    end,
  },
}

local function wrapLoaded()
  for _, hook in ipairs(BUMP_SOUNDS) do
    if not wrapped[hook.module] then
      local module = package.loaded[hook.module]
      if type(module) == "table" and type(rawget(module, hook.field)) == "function" then
        wrapped[hook.module] = true
        local original = module[hook.field]
        module[hook.field] = function(a, b, ...)
          if hook.isBump(a, b) then Haptics.bumped() end
          return original(a, b, ...)
        end
      end
    end
  end
end

-- From the access layer's after-update hook: installs the wrappers for any
-- game module loaded since.  Cheap once all are in.
function Haptics.update()
  if wrapped.done then return end
  if not (Haptics.available()) then wrapped.done = true return end
  wrapLoaded()
  local all = true
  for _, hook in ipairs(BUMP_SOUNDS) do all = all and wrapped[hook.module] == true end
  wrapped.done = all
end

function Haptics._setBackendForTests(fake)
  backend = fake or nil
  lastPulse = {}
end

function Haptics._resetWrappersForTests()
  wrapped = {}
end

return Haptics
