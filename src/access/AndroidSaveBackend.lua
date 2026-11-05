-- The save backend on Android (docs/access/android.md, "Save editor").  Android has no
-- second program to talk to over stdin, so the launcher's editor screen opens a socket
-- on this device only and starts the game's activity with its port and a one-time token.
-- This runs during main.lua's first line, before anything of the game has started, and
-- blocks there.  That also keeps SDL from pausing it behind the editor screen, because
-- SDL only pauses a program when it pumps events.  It exits when the socket closes.

local AndroidSaveBackend = {}

function AndroidSaveBackend.serve(port, token)
  local socket = require("socket")
  love.filesystem.setRequirePath(love.filesystem.getRequirePath()
    .. ";launcher/SaveBackend/?.lua;tools/save-editor/?.lua;tools/save-editor/panels/?.lua")
  local Json = require("src.link.Json")
  local Service = require("service")

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
  os.exit(0)
end

return AndroidSaveBackend
