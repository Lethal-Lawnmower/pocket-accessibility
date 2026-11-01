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
  if nav then nav:updateNavigation() end
end

-- Returns true when the key was an accessibility command (consumed).
function Nav.keypressed(key, _, isRepeat)
  if not ensure() or not router then return false end
  local game = gen1Game()
  local top = game and game.stack and game.stack:top() or nil
  local ok, consumed = pcall(router.keypressed, router, key, top, isRepeat)
  return ok and consumed == true
end

function Nav.keyreleased(key)
  if router then pcall(router.keyreleased, router, key) end
end

function Nav.coordinator() return coordinator end

function Nav._resetForTests()
  coordinator, router, boundSave, boundEvents = nil, nil, nil, nil
end

return Nav
