-- Wires the reused navigation coordinator (Navigation.lua) and the
-- Pokemon Access command keys (CommandRouter.lua) into the running game,
-- replacing what the old fork did by editing src/core/Game.lua.
--
-- Gen 1 only: the coordinator is created once a Gen 1 game is loaded
-- (src/core/Game.lua is the game object and module at once) and re-created
-- when a different save or mod event bus appears.  Keys reach the router
-- before upstream's love.keypressed; a key the router consumes never
-- reaches the game.

local Speech = require("src.access.Speech")
local AutoWalk = require("src.access.nav.AutoWalk")
local WalkSpeed = require("src.access.nav.WalkSpeed")

local Nav = {}

local coordinator, router = nil, nil
local boundSave, boundEvents = nil, nil

-- The old coordinator speaks through an object with isAvailable / output /
-- stop; this adapter hands that to the Prism speech module.
local speechAdapter = {
  isAvailable = function() return Speech.available() end,
  output = function(_, text, opts)
    return Speech.say(text, { interrupt = opts and opts.interrupt or false })
  end,
  stop = function() return Speech.stop() end,
}

local function gen1Game()
  local Game = package.loaded["src.core.Game"]
  if type(Game) ~= "table" or type(Game.save) ~= "table" or type(Game.data) ~= "table" then
    return nil
  end
  local GameVersion = package.loaded["src.core.GameVersion"]
  if GameVersion and GameVersion.generation and GameVersion.generation() ~= 1 then
    return nil
  end
  return Game
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

local function build(game)
  local Navigation = require("src.access.nav.Navigation")
  local CommandRouter = require("src.access.nav.CommandRouter")
  local Runtime = package.loaded["src.mods.Runtime"]
  -- decision 22: the camera ("sonar") is off unless the player opts in
  local cameraEnabled = game.save.options and game.save.options.accessibilityCamera == true
  coordinator = Navigation.new(game, {
    speech = speechAdapter,
    cameraEnabled = cameraEnabled,
    events = Runtime and Runtime.events,
    enabled = true,
  })
  router = CommandRouter.new({
    modifierState = modifierState,
    cameraEnabled = cameraEnabled,
    rawKeyOwner = function(state)
      return state ~= nil and (type(state.onKeyPressed) == "function"
        or state.accessibilityOwnsRawKeys == true)
    end,
    navigationAllowed = function(state)
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

-- Creates or re-creates the coordinator when the game, save or mod event
-- bus changes.  Cheap when nothing changed: two comparisons.
local function ensure()
  local game = gen1Game()
  if not game then return nil end
  local Runtime = package.loaded["src.mods.Runtime"]
  local events = Runtime and Runtime.events
  if coordinator and boundSave == game.save and boundEvents == events then
    return coordinator
  end
  if coordinator then pcall(coordinator.shutdown, coordinator) end
  local ok, err = pcall(build, game)
  if not ok then
    require("src.core.Logger").error("[access] navigation unavailable: %s", tostring(err))
    coordinator, router = nil, nil
  end
  boundSave, boundEvents = game.save, events
  return coordinator
end

function Nav.update()
  local nav = ensure()
  if not nav then return end
  nav:updateNavigation()
  local game = gen1Game()
  AutoWalk.update(game and game.stack and game.stack:top() or nil)
  WalkSpeed.update(game, AutoWalk.walking())
end

-- Returns true when the key was an accessibility command (consumed).
function Nav.keypressed(key, _, isRepeat)
  if not ensure() or not router then return false end
  -- any key stops auto-walk while it walks (not while paused for a battle)
  if AutoWalk.walking() then
    AutoWalk.stop("Auto walk stopped")
    return true
  end
  local game = gen1Game()
  local top = game and game.stack and game.stack:top() or nil
  local ok, consumed = pcall(router.keypressed, router, key, top, isRepeat)
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

local function onMap(game)
  return game and game.stack and game.overworld ~= nil
    and game.stack:top() == game.overworld
end

-- Returns true when the axis event is ours (consumed).
function Nav.gamepadaxis(_, axis, value)
  if axis ~= "triggerleft" then return false end
  if value >= TRIGGER_ON then modifierHeld = true
  elseif value <= TRIGGER_OFF then modifierHeld = false end
  local game = gen1Game()
  return ensure() ~= nil and onMap(game)
end

-- Returns true when the button press is ours (consumed).
function Nav.gamepadpressed(_, button)
  if not ensure() then return false end
  local game = gen1Game()
  if AutoWalk.walking() and button ~= "leftstick" then
    AutoWalk.stop("Auto walk stopped")
    consumedButtons[button] = true
    return true
  end
  if not onMap(game) then return false end
  if button == "leftstick" then
    AutoWalk.start(coordinator, game)
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

function Nav._resetForTests()
  coordinator, router, boundSave, boundEvents = nil, nil, nil, nil
end

return Nav
