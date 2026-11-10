-- The launcher's backends on Android (docs/access/android.md, "Save editor" and
-- "Mods").  Android has no second program to talk to over stdin, so a launcher
-- screen opens a socket on this device only and starts the game's activity with
-- its port, a one-time token and which backend it wants: the save editor's
-- (launcher/SaveBackend/service.lua) or the Mods screen's
-- (launcher/ModBackend/modservice.lua).  This runs during main.lua's first line,
-- before anything of the game has started, and blocks there.  That also keeps SDL
-- from pausing it behind the launcher's screen, because SDL only pauses a program
-- when it pumps events.  It exits when the socket closes.

local AndroidSaveBackend = {}

local SERVICES = {
  save = { path = ";launcher/SaveBackend/?.lua;tools/save-editor/?.lua;tools/save-editor/panels/?.lua",
           module = "service" },
  mods = { path = ";launcher/ModBackend/?.lua", module = "modservice" },
}

-- The backend for `kind` ("save" or "mods"), its module path set up: the service
-- module (with answer(line)) and the JSON codec.  iOS uses this too
-- (src/access/IosLauncher.lua, serveBackend), with a different channel.
function AndroidSaveBackend.prepare(kind)
  local service = SERVICES[kind or "save"] or SERVICES.save
  love.filesystem.setRequirePath(love.filesystem.getRequirePath() .. service.path)
  return require(service.module), require("src.link.Json")
end

function AndroidSaveBackend.serve(port, token, kind)
  local socket = require("socket")
  local Service, Json = AndroidSaveBackend.prepare(kind)

  local client = assert(socket.connect("127.0.0.1", tonumber(port)))
  client:settimeout(nil)
  assert(client:send(tostring(token) .. "\n"))
  while true do
    local line = client:receive("*l")
    if not line then break end
    if line ~= "" then
      local ok, response = pcall(Service.answer, line)
      if not ok then response = { ok = false, error = tostring(response) } end
      if not client:send(Json.encode(response) .. "\n") then break end
    end
  end
  client:close()
  -- _exit, not os.exit: exit's cleanup raced Android's render thread and aborted the
  -- process on a destroyed mutex (seen on the emulator), which Android reports as a crash.
  -- Nothing is left to flush: every save or options write was finished when answered.
  local ffi = require("ffi")
  ffi.cdef("void _exit(int status);")
  ffi.C._exit(0)
end

return AndroidSaveBackend
