-- The save backend on Windows: upstream's save-editor logic (tools/save-editor) running
-- with no window, answering the launcher's native editor one JSON line at a time on
-- stdin and stdout.  service.lua does the answering.  Lines not starting with
-- RESPONSE_PREFIX are upstream's logging and the launcher ignores them.
local RESPONSE_PREFIX = "@@PA "

local gameDir = (os.getenv("POCKET_GAME_DIR") or ""):gsub("\\", "/")
local backendDir = love.filesystem.getSource():gsub("\\", "/")

local Service, Json

local function setUpPaths()
  local ffi = require("ffi")
  ffi.cdef("int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  -- the game's data and scripts read through love.filesystem, like its code
  assert(ffi.load("love").PHYSFS_mount(gameDir, "/", 1) ~= 0, "could not mount the game folder")
  package.path = backendDir .. "/?.lua;" .. gameDir .. "/?.lua;" .. gameDir .. "/?/init.lua;"
    .. gameDir .. "/tools/save-editor/?.lua;" .. gameDir .. "/tools/save-editor/panels/?.lua;" .. package.path
  Json = require("src.link.Json")
  Service = require("service")
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
