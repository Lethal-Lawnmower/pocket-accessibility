-- Wires the reused navigation coordinator (Navigation.lua, gen2/Navigation.lua)
-- and the Pokemon Access command keys (CommandRouter.lua) into the running
-- game, replacing what the old fork did by editing src/core/Game.lua and
-- src/core/Game2.lua.
--
-- Red, Blue and Yellow (Gen 1), Gold, Silver and Crystal (Gen 2) and
-- FireRed (Gen 3): the running generation's world adapter (WorldAdapter.lua)
-- finds the game and answers "is the player on the map".  The coordinator is
-- created once a game with a world is up and re-created when a different
-- game, save (FireRed: session) or mod event bus appears.  Keys reach the
-- router before upstream's love.keypressed; a key the router consumes never
-- reaches the game.

local Speech = require("src.access.Speech")
local AutoWalk = require("src.access.nav.AutoWalk")
local Chase = require("src.access.nav.Chase")
local WalkSpeed = require("src.access.nav.WalkSpeed")
local WorldAdapter = require("src.access.nav.WorldAdapter")

local Nav = {}

local coordinator, router = nil, nil
local boundGame, boundSave, boundEvents, boundAdapter = nil, nil, nil, nil

-- The old coordinator speaks through an object with isAvailable / output /
-- stop; this adapter hands that to the Prism speech module.
local speechAdapter = {
  isAvailable = function() return Speech.available() end,
  output = function(_, text, opts)
    return Speech.say(text, { interrupt = opts and opts.interrupt or false })
  end,
  stop = function() return Speech.stop() end,
}

-- The running generation's adapter and game, or nil.
local function current()
  local adapter = WorldAdapter.current()
  if not adapter then return nil end
  local game = adapter.game()
  if not game then return nil end
  return adapter, game
end

local function modifierState()
  local keyboard = love and love.keyboard
  local function down(key)
    return keyboard and keyboard.isDown and keyboard.isDown(key) or false
  end
  return {
    leftShift = down("lshift"), rightShift = down("rshift"),
    control = down("lctrl") or down("rctrl"),
    alt = down("lalt") or down("ralt"),
    gui = down("lgui") or down("rgui"),
  }
end

local function build(game, adapter)
  local CommandRouter = require("src.access.nav.CommandRouter")
  local Runtime = package.loaded["src.mods.Runtime"]
  -- decision 22: the camera ("sonar") is off unless the player opts in.
  -- The options table is per generation (Gen 3 keeps it in game.options).
  local options = adapter.options and adapter.options(game)
    or (type(game.save) == "table" and game.save.options) or nil
  local cameraEnabled = type(options) == "table" and options.accessibilityCamera == true
  coordinator = adapter.newCoordinator(game, {
    speech = speechAdapter,
    cameraEnabled = cameraEnabled,
    events = Runtime and Runtime.events,
    enabled = true,
  })
  router = CommandRouter.new({
    modifierState = modifierState,
    cameraEnabled = cameraEnabled,
    rawKeyOwner = function(state)
      return type(state) == "table" and (type(state.onKeyPressed) == "function"
        or state.accessibilityOwnsRawKeys == true)
    end,
    navigationAllowed = function(state, actionId)
      if adapter.generation >= 2 then
        -- Gold's and FireRed's map is not a stack state: the world free of
        -- scripts, text and menus is the map; Shift+E also works on Gen 2's
        -- Unown puzzle screen
        return coordinator:commandAllowed(actionId)
      end
      -- Gen 1's map is its own top stack state; a menu, battle or dialogue
      -- above it keeps the keys.
      return state ~= nil and state.isOverworld == true
        and coordinator:worldForCommand() ~= nil
    end,
    onAction = function(actionId) return coordinator:handleCommand(actionId) end,
    onStatus = function(actionId) return coordinator:handleCommandStatus(actionId) end,
  })
  -- a trainer walks over on the open map before any screen opens, so the
  -- engagement pauses auto-walk until the battle is over
  if Runtime and Runtime.events and type(Runtime.events.on) == "function" then
    pcall(Runtime.events.on, Runtime.events, "world.trainer_engaged", function()
      AutoWalk.pause(true)
    end)
    -- steer tile by tile inside the game's step (fast AUTO-WALK SPEED)
    pcall(Runtime.events.on, Runtime.events, "world.stepped", function(payload)
      if type(payload) == "table" then AutoWalk.stepped(payload.x, payload.y) end
    end)
  end
end

-- What a coordinator is bound to besides the game: the save table in Gen 1
-- and Gen 2, the session in FireRed (Game3:saveGame replaces game.save on
-- every save, which re-created navigation and lost the object list and any
-- walk each time the player saved).
local function identityOf(adapter, game)
  if adapter.identity then return adapter.identity(game) end
  return game.save
end

-- Creates or re-creates the coordinator when the game, save or mod event
-- bus changes.  Cheap when nothing changed: a few comparisons.
local function ensure()
  local adapter, game = current()
  if not game then return nil end
  local Runtime = package.loaded["src.mods.Runtime"]
  local events = Runtime and Runtime.events
  local identity = identityOf(adapter, game)
  if coordinator and boundGame == game and boundSave == identity
     and boundEvents == events and boundAdapter == adapter then
    return coordinator, adapter, game
  end
  if coordinator then pcall(coordinator.shutdown, coordinator) end
  Chase.stop()
  AutoWalk.stop()
  local ok, err = pcall(build, game, adapter)
  if not ok then
    require("src.core.Logger").error("[access] navigation unavailable: %s", tostring(err))
    coordinator, router = nil, nil
  end
  boundGame, boundSave, boundEvents, boundAdapter = game, identity, events, adapter
  return coordinator, adapter, game
end

function Nav.update()
  local nav, adapter, game = ensure()
  if not nav then return end
  nav:updateNavigation()
  AutoWalk.update(adapter.top(game))
  Chase.update()
  WalkSpeed.update(game, AutoWalk.walking(), AutoWalk.turning())
end

-- Returns true when the key was an accessibility command (consumed).
function Nav.keypressed(key, _, isRepeat)
  local nav, adapter, game = ensure()
  if not nav or not router then return false end
  -- any key stops a chase on the open map (its text stays the player's)
  if Chase.active() and adapter.onMap(game) then
    Chase.stop("Auto walk stopped")
    return true
  end
  -- any key stops auto-walk while it walks (not while paused for a battle)
  if AutoWalk.walking() then
    AutoWalk.stop("Auto walk stopped")
    return true
  end
  local ok, consumed = pcall(router.keypressed, router, key, adapter.top(game), isRepeat)
  return ok and consumed == true
end

function Nav.keyreleased(key)
  if router then pcall(router.keyreleased, router, key) end
end

-- ------------------------------------------------------------ controller
-- Owner's scheme (decision 23): hold the left trigger as the navigation
-- modifier; with it held, D-pad up and down change the object category and
-- left and right move through that category.  Left stick click starts
-- auto-walk to the selected object; right stick click starts guided
-- navigation (the P command).  On the map, the left trigger is kept from
-- upstream, where it would otherwise lower the game speed (the left
-- shoulder still does that).

local TRIGGER_ON, TRIGGER_OFF = 0.4, 0.2 -- as src/core/GamepadMap.lua
local modifierHeld = false
local consumedButtons = {}

local DPAD_ACTIONS = {
  dpup = "previous_item_filter", dpdown = "next_item_filter",
  dpleft = "previous_map_item", dpright = "next_map_item",
}

-- Returns true when the axis event is ours (consumed).
function Nav.gamepadaxis(_, axis, value)
  if axis ~= "triggerleft" then return false end
  if value >= TRIGGER_ON then modifierHeld = true
  elseif value <= TRIGGER_OFF then modifierHeld = false end
  local nav, adapter, game = ensure()
  return nav ~= nil and adapter.onMap(game)
end

-- Returns true when the button press is ours (consumed).
function Nav.gamepadpressed(_, button)
  local nav, adapter, game = ensure()
  if not nav then return false end
  if Chase.active() and adapter.onMap(game) then
    Chase.stop("Auto walk stopped")
    consumedButtons[button] = true
    return true
  end
  if AutoWalk.walking() and button ~= "leftstick" then
    AutoWalk.stop("Auto walk stopped")
    consumedButtons[button] = true
    return true
  end
  if not adapter.onMap(game) then return false end
  if button == "leftstick" then
    AutoWalk.start(coordinator, game, adapter)
  elseif button == "rightstick" then
    coordinator:handleCommand("describe_route_to_selected_item")
  elseif modifierHeld and DPAD_ACTIONS[button] then
    coordinator:handleCommand(DPAD_ACTIONS[button])
    -- keep upstream's pad polling from treating the held D-pad as movement
    if game.input and game.input.padEventSeen then game.input:padEventSeen(button) end
  else
    return false
  end
  consumedButtons[button] = true
  return true
end

function Nav.gamepadreleased(_, button)
  if consumedButtons[button] then
    consumedButtons[button] = nil
    return true
  end
  return false
end

function Nav.coordinator() return coordinator end

-- For scripted drivers: the adapter and game the layer is bound to.
function Nav.bound() return boundAdapter, boundGame end

function Nav._resetForTests()
  coordinator, router = nil, nil
  boundGame, boundSave, boundEvents, boundAdapter = nil, nil, nil, nil
end

return Nav
