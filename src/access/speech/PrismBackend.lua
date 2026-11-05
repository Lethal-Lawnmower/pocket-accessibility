-- Prism speech backend, loaded in-process through LuaJIT FFI.
--
-- Prism picks the best available output on its own (the running screen
-- reader first, then system voices).  This module only finds prism.dll,
-- opens one context, acquires that best backend and forwards text to it.
-- Prism is the only speech path (docs/access/decisions.md, decisions 3 and 9):
-- if it cannot load, open() reports why and the game runs silent.  There is
-- deliberately no fallback to another speech library.

local PrismBackend = {}
PrismBackend.__index = PrismBackend

local ffiLoaded, ffi = pcall(require, "ffi")
local bit = require("bit")

local declared = false

-- Only the calls we use, copied from Prism 0.17.3's include/prism.h.
-- Opaque handles stay opaque; the config struct must match field for field
-- because prism_config_init returns it by value.
local CDEF = [[
typedef struct PrismContext PrismContext;
typedef struct PrismBackend PrismBackend;
typedef struct PrismRegistry PrismRegistry;
typedef struct {
  uint8_t version;
  PrismRegistry *registry;
  void *availability_callback;
  void *availability_userdata;
  uint32_t availability_poll_interval_ms;
  uint32_t availability_debounce_samples;
  uint32_t availability_backoff_max_ms;
  bool availability_auto_power_manage;
} PrismConfig;
PrismConfig prism_config_init(void);
PrismContext *prism_init(PrismConfig *cfg);
void prism_shutdown(PrismContext *ctx);
PrismBackend *prism_registry_acquire_best(PrismContext *ctx);
void prism_backend_free(PrismBackend *backend);
const char *prism_backend_name(PrismBackend *backend);
uint64_t prism_backend_get_features(PrismBackend *backend);
int prism_backend_speak(PrismBackend *backend, const char *text, bool interrupt);
int prism_backend_output(PrismBackend *backend, const char *text, bool interrupt);
int prism_backend_stop(PrismBackend *backend);
const char *prism_error_string(int error);
]]

-- PrismBackendFeature bits used here (all below 2^31, so 32-bit bit ops work).
local SUPPORTS_SPEAK = 4    -- 1 << 2
local SUPPORTS_OUTPUT = 32  -- 1 << 5, speech plus braille
local SUPPORTS_STOP = 128   -- 1 << 7

local PRISM_OK = 0

local function libraryName(osName)
  if osName == "Windows" then return "prism.dll" end
  if osName == "OSX" then return "libprism.dylib" end
  return "libprism.so"
end

local function joinPath(dir, name)
  if type(dir) ~= "string" or dir == "" then return nil end
  return (dir:gsub("[\\/]+$", "")) .. "/" .. name
end

-- Where prism.dll may live, most specific first:
--   1. POKEPORT_PRISM_DLL, an explicit path (development and testing);
--   2. beside the executable (a packaged build);
--   3. the source folder, then its local-deps/prism/ (a source checkout).
-- local-deps/ is git-ignored, so the binary is never committed.
function PrismBackend.candidates(env, dirs, osName)
  local name = libraryName(osName)
  local list, seen = {}, {}
  local function add(path)
    if path and path ~= "" and not seen[path] then
      seen[path] = true
      list[#list + 1] = path
    end
  end
  add(env("POKEPORT_PRISM_DLL"))
  -- Android installs the library with the app, where the loader finds it by name alone
  if osName == "Android" then add(name) end
  for _, dir in ipairs(dirs) do add(joinPath(dir, name)) end
  for _, dir in ipairs(dirs) do add(joinPath(dir, "local-deps/prism/" .. name)) end
  return list
end

local function loveDirectories()
  local dirs = {}
  if love and love.filesystem then
    local okBase, base = pcall(love.filesystem.getSourceBaseDirectory)
    if okBase and base then dirs[#dirs + 1] = base end
    local okSource, source = pcall(love.filesystem.getSource)
    if okSource and source then dirs[#dirs + 1] = source end
  end
  return dirs
end

local function errorText(lib, code)
  local ok, text = pcall(function() return ffi.string(lib.prism_error_string(code)) end)
  return ok and text or ("Prism error " .. tostring(code))
end

-- Returns a backend object, or nil plus a message saying exactly what failed.
function PrismBackend.open(opts)
  opts = opts or {}
  if not ffiLoaded then return nil, "LuaJIT FFI is not available" end
  if not declared then
    ffi.cdef(CDEF)
    declared = true
  end

  local paths = PrismBackend.candidates(opts.env or os.getenv,
    opts.dirs or loveDirectories(), opts.os or (jit and jit.os) or "Windows")
  local lib, tried = nil, {}
  for _, path in ipairs(paths) do
    local ok, loaded = pcall(ffi.load, path)
    if ok then lib = loaded break end
    tried[#tried + 1] = path
  end
  if not lib then
    return nil, "prism library not found; tried: " .. table.concat(tried, ", ")
  end

  local config = ffi.new("PrismConfig[1]")
  config[0] = lib.prism_config_init()
  local context = lib.prism_init(config)
  if context == nil then return nil, "prism_init failed" end

  local handle = lib.prism_registry_acquire_best(context)
  if handle == nil then
    lib.prism_shutdown(context)
    return nil, "Prism found no usable speech output"
  end

  local self = setmetatable({
    lib = lib,
    context = context,
    handle = handle,
    features = tonumber(lib.prism_backend_get_features(handle)) or 0,
  }, PrismBackend)
  self.name = ffi.string(lib.prism_backend_name(handle))
  return self
end

function PrismBackend:supports(mask)
  return bit.band(self.features, mask) ~= 0
end

-- Output sends speech and braille together when the backend can, so braille
-- display users get the same text.  Returns true, or false plus Prism's error.
function PrismBackend:say(text, interrupt)
  if not self.handle then return false, "backend closed" end
  local code
  if self:supports(SUPPORTS_OUTPUT) then
    code = self.lib.prism_backend_output(self.handle, text, interrupt and true or false)
  elseif self:supports(SUPPORTS_SPEAK) then
    code = self.lib.prism_backend_speak(self.handle, text, interrupt and true or false)
  else
    return false, "backend " .. self.name .. " cannot speak"
  end
  if code ~= PRISM_OK then return false, errorText(self.lib, code) end
  return true
end

function PrismBackend:stop()
  if not (self.handle and self:supports(SUPPORTS_STOP)) then return false end
  return self.lib.prism_backend_stop(self.handle) == PRISM_OK
end

function PrismBackend:close()
  if self.handle then self.lib.prism_backend_free(self.handle) end
  if self.context then self.lib.prism_shutdown(self.context) end
  self.handle, self.context = nil, nil
end

return PrismBackend
