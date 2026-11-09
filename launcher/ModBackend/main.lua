-- The mod backend: upstream's mod index and manifest code running with no window,
-- answering the launcher's Mods window one JSON line at a time on stdin and stdout.
-- The feed, its cache, compatibility warnings, manifest checks and enable-state are
-- all upstream's (src/mods/ModIndex, Manifest, ModTargets; src/core/SaveData).
-- Downloading and unpacking are the launcher's own (ModInstaller.cs), because
-- upstream's installer is in its proprietary launcher code, which we may not use.
-- Lines not starting with RESPONSE_PREFIX are logging and the launcher ignores them.
local RESPONSE_PREFIX = "@@PA "

local gameDir = (os.getenv("POCKET_GAME_DIR") or ""):gsub("\\", "/")

local Json, Service

local function setUpPaths()
  local ffi = require("ffi")
  ffi.cdef("int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  -- the game's scripts read through love.filesystem, like its code
  assert(ffi.load("love").PHYSFS_mount(gameDir, "/", 1) ~= 0, "could not mount the game folder")
  package.path = gameDir .. "/?.lua;" .. gameDir .. "/?/init.lua;" .. package.path
  Json = require("src.link.Json")
  package.path = love.filesystem.getSource():gsub("\\", "/") .. "/?.lua;" .. package.path
  Service = require("modservice")
end

function love.run()
  setUpPaths()
  print = function(...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i]) end
    io.stderr:write(table.concat(parts, "\t"), "\n")
  end
  io.stdout:setvbuf("no")
  io.stdout:write(RESPONSE_PREFIX, Json.encode({ ready = true }), "\n")
  for line in io.stdin:lines() do
    if line ~= "" then
      local ok, response = pcall(Service.answer, line)
      if not ok then response = { ok = false, error = tostring(response) } end
      io.stdout:write(RESPONSE_PREFIX, Json.encode(response), "\n")
    end
  end
  return function() return 0 end
end
