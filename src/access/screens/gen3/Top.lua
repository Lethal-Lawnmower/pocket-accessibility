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

-- The message pages and yes/no already open when a hideBelow == false
-- layer was first seen on top, per layer record (weak: a closed layer
-- goes with its record).
local layerSeen = setmetatable({}, { __mode = "k" })

-- Screens Hud's update_top_menu drives by name rather than through a
-- layer's handleInput (src/ui/game3/hud.lua).
local SINGLETON_MENUS = {
  "src.ui.game3.save_menu", "src.ui.game3.option_menu", "src.ui.game3.trainer_card",
  "src.ui.game3.pc_menu", "src.ui.game3.shop_menu", "src.ui.game3.bag_menu",
  "src.ui.game3.region_map", "src.ui.game3.summary_menu", "src.ui.game3.party_menu",
  "src.ui.game3.pokedex", "src.ui.game3.start_menu",
}

-- Whether the top layer takes the frame's input (Hud.update_top_menu: a
-- skin's or the module's handleInput, or one of the named singletons).
local function ownsInput(layer)
  local mod = layer.mod
  if type(mod) ~= "table" then return false end
  if type(mod.handleInput) == "function" then return true end
  local Screens = loaded("src.ui.game3.screens")
  local skin = Screens and call(Screens.skin, layer.id)
  if type(skin) == "table" and type(skin.handleInput) == "function" then return true end
  for _, path in ipairs(SINGLETON_MENUS) do
    if loaded(path) == mod then return true end
  end
  return false
end

-- Hoenn's boot screens are objects in `boot.custom`
-- (src/ui/game3/boot_modules.lua), one at a time; a layer over them (OPTION,
-- Mystery Gift from the main menu) is the screen while it is open.
local function customBootTop(game, boot, layer)
  if layer then return proxy(layer, kindOf(layer.id), { layer = layer, mod = layer.mod, game = game }) end
  local c = boot.custom
  local fields = { boot = boot, game = game }
  if c.intro then return proxy(c.intro, "hoenn_intro", fields) end
  if c.title then return proxy(c.title, "hoenn_title", fields) end
  if c.menu then return proxy(c.menu, "hoenn_main_menu", fields) end
  if c.newGame then return proxy(c.newGame, "hoenn_birch", fields) end
  if c.combo then return proxy(c.combo, "hoenn_combo", fields) end
  return nil
end

local function bootTop(game, layer)
  if layer and layer.id == "naming" then
    return proxy(layer, "naming", { layer = layer, mod = layer.mod, game = game })
  end
  local boot = game.boot
  if type(boot) ~= "table" then return nil end
  if type(boot.custom) == "table" then return customBootTop(game, boot, layer) end
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

-- Layers that only drive the screen under them and draw nothing: Teachy
-- TV's Poké Dude demos push one over the bag or TM case they play back
-- (src/ui/game3/teachy_tv.lua TmDemo, BagDemo).  The screen is the layer
-- under it, so its own presenter reads the demo as it plays.
local DRIVER_LAYERS = { teachy_pokedude_tm_case = true, teachy_pokedude_bag = true }

local function screenLayer(Stack, layer)
  if not (layer and DRIVER_LAYERS[layer.id]) then return layer end
  local layers = type(Stack._layers) == "table" and Stack._layers or {}
  for i = #layers - 1, 1, -1 do
    if not DRIVER_LAYERS[layers[i].id] then return layers[i] end
  end
  return layer
end

-- Layers that only paint what the message and yes/no modules show: the
-- cross-generation Union Room battle (src/ui/g3u/Gen3Presenter.lua) draws
-- the battle interface with its text in Message and Choice.  Its text is
-- read as dialogue and questions; its command and move menus are not read.
local PAINT_LAYERS = { g3u_battle = true }

-- The ACCESSIBILITY page in Gen 3's OPTION screen wraps OptionMenu.show
-- once that module has loaded (src/access/Settings.lua); the game loads it
-- with its HUD, long before the player can open OPTION.
local optionsWrapped = false

function Top.resolve(game)
  if type(game) ~= "table" or game.phase == "arena" then return nil end
  if not optionsWrapped then
    local Settings = loaded("src.access.Settings")
    optionsWrapped = Settings ~= nil and Settings.installGen3 ~= nil and Settings.installGen3() == true
  end
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
  if Stack then layer = screenLayer(Stack, layer) end
  if game.phase == "boot" then return bootTop(game, layer) end
  if game.phase ~= "field" then return nil end

  local message = messageProxy(game)
  local choice = choiceProxy(game)
  if layer and PAINT_LAYERS[layer.id] then layer = nil end
  if layer then
    local top = proxy(layer, kindOf(layer.id), { layer = layer, mod = layer.mod, game = game })
    -- A layer that leaves what is under it visible (hideBelow false, such
    -- as a script's floor list) can have the field's message and yes/no
    -- drawn with it; never under the PC or box storage, which hide both.
    local covered = Stack and (call(Stack.has, "pc_menu") or call(Stack.has, "box_storage"))
    if layer.hideBelow == false and not covered then
      -- These layers usually open over a message that stays on screen
      -- (the elevator's "Which floor?", the prize corner's greeting), and
      -- Hud.update gives the input to the top layer whenever it takes
      -- input (update_top_menu).  So the layer is the screen and that
      -- older message is said first if it never was; a message or yes/no
      -- that opened after the layer (a confirmation its script shows) is
      -- the screen until it closes.  A layer that takes no input leaves
      -- the message and yes/no in charge.
      local seen = layerSeen[layer]
      if not seen then
        seen = { pages = message and message.key or false, choice = choice and choice.key or false }
        layerSeen[layer] = seen
      end
      if not ownsInput(layer) then
        if choice then return choice, message end
        if message then return message end
        return top
      end
      if choice and choice.key ~= seen.choice then return choice, message end
      if message and message.key ~= seen.pages then return message end
      return top, message
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

-- For presenter modules: proxy(key, kind, fields) and edge(kind, on), the
-- per-opening token for a screen that is only a flag on a singleton.
Top._proxy = proxy
Top._edge = edge
Top.edge = edge

return Top
