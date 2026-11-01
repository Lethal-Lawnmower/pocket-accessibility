-- What is on screen in a Gen 3 game (FireRed, LeafGreen; decision 29).
--
-- Gen 3 has no StateStack: boot, quest log, battle and the field each own
-- their screens, menus sit on src/ui/game3/stack.lua as layers
-- { id, mod, hideBelow, ... } whose `mod` is a module singleton, dialogue is
-- the module src/ui/game3/message.lua and yes/no is src/ui/game3/choice.lua.
-- Top.resolve(game) follows the game's own order (Game3:fixedUpdate,
-- Hud.update, ui_pass.lua) and returns the screen as a proxy table:
--   { gen3 = <kind>, key = <object>, game = <game>, layer = ..., mod = ... }
-- One proxy per opening: the key is an object that exists for exactly one
-- opening (a stack layer record is new on each push, Message._pages on each
-- message, Choice.done on each question, boot sub-states on each entry), so
-- ScreenReader's per-screen memo and its "entering" flag work as in Gen 1
-- and 2 even though the modules are singletons.  Presenters match on
-- `gen3` and must keep their memory in the memo, never on the module.
--
-- The second return value is a dialogue page under the top (the question
-- under a yes/no box) that ScreenReader says first if it was never spoken.
-- Top.ambient(game) lists passive overlays (no input) polled every frame.

local Top = {}

local proxies = setmetatable({}, { __mode = "k" })

local function proxy(key, kind, fields)
  local p = proxies[key]
  if not p or p.gen3 ~= kind then
    p = { gen3 = kind, key = key }
    proxies[key] = p
  end
  if fields then
    for name, value in pairs(fields) do p[name] = value end
  end
  return p
end

-- Edge tokens for screens that are only a flag on a singleton (Help): a new
-- token each time the flag turns on, so each opening has its own memo.
local tokens = {}
local function edge(kind, on)
  if not on then
    tokens[kind] = nil
    return nil
  end
  tokens[kind] = tokens[kind] or {}
  return tokens[kind]
end

local function loaded(path)
  return package.loaded[path]
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

-- Mod screens push ids "modui:<n>"; they share one kind.
local function kindOf(id)
  id = tostring(id or "")
  if id:find("^modui") then return "modui" end
  return id
end

local function messageProxy(game)
  local Message = loaded("src.ui.game3.message")
  if not (Message and Message.open and type(Message._pages) == "table") then return nil end
  return proxy(Message._pages, "message", { mod = Message, game = game })
end

local function choiceProxy(game)
  local Choice = loaded("src.ui.game3.choice")
  if not (Choice and Choice.active and Choice.done) then return nil end
  return proxy(Choice.done, "choice", { mod = Choice, game = game })
end

local function bootTop(game, layer)
  if layer and layer.id == "naming" then
    return proxy(layer, "naming", { layer = layer, mod = layer.mod, game = game })
  end
  local boot = game.boot
  if type(boot) ~= "table" then return nil end
  local phase = boot.phase
  if phase == "intro" and boot.introMovie then
    return proxy(boot.introMovie, "intro", { boot = boot, game = game })
  end
  if (phase == "title" or phase == "title_cry" or phase == "title_restart") and boot.title then
    return proxy(boot.title, "title", { boot = boot, game = game })
  end
  if phase == "menu" then
    if boot.saveError then return proxy(boot.saveError, "save_error", { boot = boot, game = game }) end
    return proxy(boot, "main_menu", { boot = boot, game = game })
  end
  if phase == "mystery_gift" and boot.gift then
    return proxy(boot.gift, "mystery_gift", { boot = boot, game = game })
  end
  if boot.newGame then
    return proxy(boot.newGame, "new_game", { boot = boot, game = game })
  end
  return nil
end

function Top.resolve(game)
  if type(game) ~= "table" or game.phase == "arena" then return nil end
  local Help = loaded("src.ui.game3.help_system")
  local helpToken = edge("help", Help ~= nil and Help.open == true)
  if helpToken then return proxy(helpToken, "help", { mod = Help, game = game }) end
  if game.phase == "quest_log" then
    local playback = game.questPlayback
    if playback then return proxy(playback, "quest_log", { playback = playback, game = game }) end
    return nil
  end
  local Stack = loaded("src.ui.game3.stack")
  local layer = Stack and call(Stack.top)
  if game.phase == "boot" then return bootTop(game, layer) end
  if game.phase ~= "field" then return nil end

  local message = messageProxy(game)
  local choice = choiceProxy(game)
  if layer then
    local top = proxy(layer, kindOf(layer.id), { layer = layer, mod = layer.mod, game = game })
    -- A layer that leaves what is under it visible (hideBelow false, such
    -- as a script's floor list) can have the field's message and yes/no
    -- over it; never under the PC or box storage, which hide both.
    local covered = Stack and (call(Stack.has, "pc_menu") or call(Stack.has, "box_storage"))
    if layer.hideBelow == false and not covered then
      if choice then return choice, message end
      if message then return message end
    end
    return top
  end
  local Battle = loaded("src.core.game3.battle")
  if Battle and call(Battle.isActive) then
    local state = rawget(Battle, "_st")
    if state then return proxy(state, "battle", { mod = Battle, game = game }) end
  end
  if choice then return choice, message end
  if message then return message end
  return nil
end

-- Passive overlays that take no input and never become the top (the map
-- name popup and similar).  Each is { kind, key }; presenters for these
-- kinds speak once per key.  Filled in by the overlay presenters' owners.
local ambientSources = {}

-- `source(game)` returns a proxy or nil.
function Top.addAmbient(source)
  ambientSources[#ambientSources + 1] = source
end

function Top.ambient(game)
  local list = {}
  for _, source in ipairs(ambientSources) do
    local ok, p = pcall(source, game, proxy)
    if ok and p then list[#list + 1] = p end
  end
  return list
end

Top._proxy = proxy
Top._edge = edge

return Top
