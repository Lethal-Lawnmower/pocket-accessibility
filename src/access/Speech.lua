-- The one place the accessibility layer speaks from.
--
-- Callers say what to announce and whether it replaces stale speech:
--   Speech.say("Pokemon Center", { interrupt = true })   -- new focus
--   Speech.say("It's super effective!")                   -- queued after
-- Focus changes should interrupt, so moving through a menu never builds a
-- backlog of old item names.  The backend is Prism (speech/PrismBackend.lua);
-- tests inject a fake through Speech.start({ backend = ... }).

local Logger = require("src.core.Logger")

local Speech = {}

local backend = nil
local status = "not started"
-- POKEPORT_ACCESS_TRACE=1 logs every utterance, so scripted runs can check
-- what would be spoken without anyone listening.
local trace = os.getenv("POKEPORT_ACCESS_TRACE") == "1"

-- Opens the backend once.  Returns true when speech is available; otherwise
-- false, and Speech.status() keeps the reason for diagnostics.
function Speech.start(opts)
  opts = opts or {}
  if backend then return true end
  if opts.backend then
    backend = opts.backend
  else
    local PrismBackend = require("src.access.speech.PrismBackend")
    local opened, err = PrismBackend.open(opts)
    if not opened then
      status = "unavailable: " .. tostring(err)
      Logger.error("[access] speech %s", status)
      return false
    end
    backend = opened
  end
  status = "ready: " .. tostring(backend.name)
  Logger.info("[access] speech %s", status)
  return true
end

function Speech.available()
  return backend ~= nil
end

function Speech.status()
  return status
end

-- Returns true when the text was handed to the backend.  Empty text is a
-- caller bug worth seeing in the log, not something to speak.
function Speech.say(text, opts)
  if not backend then return false end
  text = text ~= nil and tostring(text) or ""
  if text:match("^%s*$") then
    Logger.warn("[access] ignored empty speech")
    return false
  end
  local interrupt = opts and opts.interrupt or false
  if trace then Logger.info("[access] say%s: %s", interrupt and "!" or "", text) end
  local ok, err = backend:say(text, interrupt)
  if not ok then Logger.warn("[access] speech failed: %s", tostring(err)) end
  return ok
end

function Speech.stop()
  if not backend then return false end
  return backend:stop()
end

function Speech.shutdown()
  if backend then backend:close() end
  backend = nil
  status = "stopped"
end

return Speech
