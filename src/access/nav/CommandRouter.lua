-- Reused from the old Pocket Accessibility project (src/accessibility/CommandRouter.lua at
-- commit 71cdd419e) under decision 20; adapted for v0.3.98.

-- Context-safe keyboard router for the historical Pokemon Access commands.
--
-- The original emulator script watched global keyboard state, which is not
-- safe in a native game: D is Right movement and right Shift is Select.  This
-- router therefore keeps the historical chords behind an explicit F7 command
-- layer.  Raw-key/capture screens always win, unknown keys pass through, and
-- only left Shift may form an accessibility chord.
--
-- Integration intentionally depends on injected functions rather than love:
--
--   CommandRouter.new({
--     modifierState = function(context)
--       return {
--         leftShift = love.keyboard.isDown("lshift"),
--         rightShift = love.keyboard.isDown("rshift"),
--         control = love.keyboard.isDown("lctrl", "rctrl"),
--         alt = love.keyboard.isDown("lalt", "ralt"),
--         gui = love.keyboard.isDown("lgui", "rgui"),
--       }
--     end,
--     onAction = function(actionId, metadata) ... end,
--   })
--
-- keypressed returns consumed, actionId, callbackResult, callbackReason.
-- A recognized command is consumed even if its callback rejects the action or
-- raises.  Call keyreleased so keyboard-repeat events remain one-shot.

local CommandRouter = {}
CommandRouter.__index = CommandRouter

CommandRouter.ACTIONS = {
  READ_PLAYER_POSITION = "read_player_position",
  READ_CAMERA_POSITION = "read_camera_position",
  PREVIOUS_MAP_ITEM = "previous_map_item",
  NEXT_MAP_ITEM = "next_map_item",
  PREVIOUS_ITEM_FILTER = "previous_item_filter",
  NEXT_ITEM_FILTER = "next_item_filter",
  DESCRIBE_ROUTE_TO_ITEM = "describe_route_to_selected_item",
  AUTO_WALK_TO_ITEM = "auto_walk_to_selected_item",
  READ_SCREEN_TEXT = "read_screen_text",
  READ_MAP_NAME = "read_map_name",
  READ_GAME_TIME = "read_game_time",
  READ_COLLISION_TILES = "read_collision_tiles",
  READ_TERRAIN = "read_terrain",
  MOVE_CAMERA_LEFT = "move_camera_left",
  MOVE_CAMERA_RIGHT = "move_camera_right",
  MOVE_CAMERA_UP = "move_camera_up",
  MOVE_CAMERA_DOWN = "move_camera_down",
  RESET_CAMERA_TO_PLAYER = "reset_camera_to_player",
  MOVE_CAMERA_LEFT_THROUGH_WALLS = "move_camera_left_through_walls",
  MOVE_CAMERA_RIGHT_THROUGH_WALLS = "move_camera_right_through_walls",
  MOVE_CAMERA_UP_THROUGH_WALLS = "move_camera_up_through_walls",
  MOVE_CAMERA_DOWN_THROUGH_WALLS = "move_camera_down_through_walls",
  DESCRIBE_ROUTE_TO_CAMERA = "describe_route_to_camera",
  TOGGLE_CAMERA_FOLLOW = "toggle_camera_follow",
  READ_ENEMY_HEALTH = "read_enemy_health",
  READ_PLAYER_HEALTH = "read_player_health",
  READ_COMMAND_HELP = "read_command_help",
}

CommandRouter.STATUS = {
  ENABLED = "command_layer_enabled",
  DISABLED = "command_layer_disabled",
}

-- In compatibility mode the emulator-era command vocabulary owns D, so the
-- native WASD set cannot remain half active. Arrow keys are the unambiguous
-- movement controls; these otherwise-native letters are reserved consistently.
-- (no letter commands use them now: decision 46, so WASD keeps moving in command mode)
CommandRouter.RESERVED_WASD = {}

local A = CommandRouter.ACTIONS

-- These tables are public so help/binding screens can enumerate the exact
-- first-party command surface without maintaining a second key map.
CommandRouter.MAPPINGS = {
  plain = {
    j = A.PREVIOUS_MAP_ITEM,
    l = A.NEXT_MAP_ITEM,
    k = A.DESCRIBE_ROUTE_TO_ITEM,
  },
  shift = {
    j = A.PREVIOUS_ITEM_FILTER,
    l = A.NEXT_ITEM_FILTER,
    k = A.AUTO_WALK_TO_ITEM,
  },
}

-- Extra modern-controller controls have no Game Boy meaning, so they can
-- expose navigation directly without stealing A/B/Start/Select or requiring
-- the keyboard-only F7 compatibility layer.  Triggers are SDL gamepad axes;
-- their serialized names also serve as stable rebinding values.
CommandRouter.GAMEPAD_DEFAULTS = {
  { action = A.PREVIOUS_ITEM_FILTER, control = "leftshoulder" },
  { action = A.NEXT_ITEM_FILTER, control = "rightshoulder" },
  { action = A.PREVIOUS_MAP_ITEM, control = "axis:triggerleft:positive" },
  { action = A.NEXT_MAP_ITEM, control = "axis:triggerright:positive" },
  { action = A.DESCRIBE_ROUTE_TO_ITEM, control = "rightstick" },
}

-- Navigation commands should not steal input from a menu, dialogue, battle,
-- or a scripted transition. Screen text, health and help remain usable there.
-- The engine injects the actual world predicate because Gen I's top state
-- and Gen II's native world/stack have different shapes.
local NON_NAVIGATION = {
  [A.READ_SCREEN_TEXT] = true,
  [A.READ_GAME_TIME] = true,
  [A.READ_ENEMY_HEALTH] = true,
  [A.READ_PLAYER_HEALTH] = true,
  [A.READ_COMMAND_HELP] = true,
}

local AXIS_ON, AXIS_OFF = 0.5, 0.3

local function gamepadControl(overlay, record)
  local binding = type(overlay) == "table" and overlay[record.action] or nil
  if type(binding) == "table" and type(binding.pad) == "string"
     and binding.pad ~= "" then
    return binding.pad:lower()
  end
  return record.control
end

local function noModifiers()
  return {}
end

local function noAction()
  return true
end

local function flag(state, ...)
  for i = 1, select("#", ...) do
    if state[select(i, ...)] == true then return true end
  end
  return false
end

local function normalizeModifiers(state)
  state = type(state) == "table" and state or {}
  return {
    leftShift = flag(state, "leftShift", "left_shift", "lshift"),
    rightShift = flag(state, "rightShift", "right_shift", "rshift"),
    control = flag(state, "control", "ctrl", "leftControl", "rightControl",
                   "leftCtrl", "rightCtrl", "lctrl", "rctrl"),
    alt = flag(state, "alt", "leftAlt", "rightAlt", "lalt", "ralt"),
    gui = flag(state, "gui", "meta", "super", "command", "cmd",
               "leftGui", "rightGui", "lgui", "rgui"),
  }
end

local function defaultRawKeyOwner(context)
  if context == true then return true end
  if type(context) ~= "table" then return false end
  return context.rawKeysOwned == true
      or context.ownsRawKeys == true
      or context.captureKeys == true
      or (context.rawKeyOwner ~= nil and context.rawKeyOwner ~= false)
end

-- Camera ("sonar") actions: every action whose id names the camera.
function CommandRouter.isCameraAction(actionId)
  return type(actionId) == "string" and actionId:find("camera", 1, true) ~= nil
end

function CommandRouter.new(opts)
  opts = opts or {}
  assert(opts.modifierState == nil or type(opts.modifierState) == "function",
    "modifierState must be a function")
  assert(opts.onAction == nil or type(opts.onAction) == "function",
    "onAction must be a function")
  assert(opts.onStatus == nil or type(opts.onStatus) == "function",
    "onStatus must be a function")
  assert(opts.rawKeyOwner == nil or type(opts.rawKeyOwner) == "function",
    "rawKeyOwner must be a function")
  assert(opts.navigationAllowed == nil
      or type(opts.navigationAllowed) == "function",
    "navigationAllowed must be a function")

  local self = setmetatable({
    active = opts.active == true,
    modifierState = opts.modifierState or noModifiers,
    onAction = opts.onAction or noAction,
    onStatus = opts.onStatus,
    rawKeyOwner = opts.rawKeyOwner or defaultRawKeyOwner,
    navigationAllowed = opts.navigationAllowed,
    -- nil keeps the old behaviour (camera on); init.lua passes the option
    cameraEnabled = opts.cameraEnabled,
    heldChordByKey = {},
    heldGamepadButtons = {},
    heldGamepadAxes = {},
    lastDispatch = nil,
    lastError = nil,
  }, CommandRouter)
  self:applyGamepadBindings(opts.gamepadBindings)
  return self
end

function CommandRouter:_navigationAllowed(context, actionId)
  if not self.navigationAllowed then return true end
  local ok, allowed = pcall(self.navigationAllowed, context, actionId)
  if not ok then
    self.lastError = tostring(allowed)
    return false
  end
  return allowed == true
end

function CommandRouter:applyGamepadBindings(overlay)
  self.gamepadButtonMappings = {}
  self.gamepadAxisMappings = {}
  self.heldGamepadButtons = {}
  self.heldGamepadAxes = {}
  for _, record in ipairs(CommandRouter.GAMEPAD_DEFAULTS) do
    local control = gamepadControl(overlay, record)
    local axis, direction = control:match("^axis:([^:]+):([^:]+)$")
    if axis and (direction == "positive" or direction == "negative") then
      self.gamepadAxisMappings[axis .. ":" .. direction] = record.action
    else
      self.gamepadButtonMappings[control] = record.action
    end
  end
end

function CommandRouter:resetGamepad()
  self.heldGamepadButtons = {}
  self.heldGamepadAxes = {}
end

function CommandRouter:isActive()
  return self.active
end

-- External state restoration may set the mode without announcing it.  Normal
-- keyboard toggles always announce through a status/action callback.
function CommandRouter:setActive(active)
  self.active = active == true
  self.heldChordByKey = {}
  return self.active
end

function CommandRouter:_rawKeysOwned(context)
  local ok, owned = pcall(self.rawKeyOwner, context)
  if not ok then
    -- If context arbitration itself fails, passing the key through is safer
    -- than stealing input from a possible text/capture screen.
    self.lastError = tostring(owned)
    return true
  end
  return owned == true
end

function CommandRouter:_modifiers(context)
  local ok, state = pcall(self.modifierState, context)
  if not ok then
    self.lastError = tostring(state)
    return nil
  end
  return normalizeModifiers(state)
end

function CommandRouter:_dispatch(actionId, metadata, status)
  local callback = status and (self.onStatus or self.onAction) or self.onAction
  local ok, result, reason = pcall(callback, actionId, metadata)
  self.lastDispatch = {
    action = actionId,
    metadata = metadata,
    callbackOK = ok,
    result = ok and result or nil,
    reason = ok and reason or tostring(result),
  }
  if not ok then
    self.lastError = tostring(result)
    return nil, self.lastError
  end
  return result, reason
end

local function unsafeModifiers(modifiers)
  return modifiers.control or modifiers.alt or modifiers.gui
      or modifiers.rightShift
end

local function chordFor(key, shifted)
  return shifted and ("shift+" .. key) or key
end

-- context is an integration-owned value passed to modifierState/rawKeyOwner.
-- isRepeat is optional; repeat events are consumed but never re-dispatched.
function CommandRouter:keypressed(key, context, isRepeat)
  key = type(key) == "string" and key:lower() or ""
  if key == "" or self:_rawKeysOwned(context) then return false end

  local modifiers = self:_modifiers(context)
  if not modifiers or unsafeModifiers(modifiers) then return false end
  local shifted = modifiers.leftShift

  -- Discoverability is available before command mode is enabled, but still
  -- yields to raw-key/capture screens and unsafe modifier combinations.
  if key == "f8" then
    if shifted then return false end
    local chord = "f8"
    if self.heldChordByKey[key] == chord
        or (isRepeat == true and self.heldChordByKey[key] == nil) then
      self.heldChordByKey[key] = chord
      return true, CommandRouter.ACTIONS.READ_COMMAND_HELP
    end
    self.heldChordByKey[key] = chord
    local actionId = CommandRouter.ACTIONS.READ_COMMAND_HELP
    local result, reason = self:_dispatch(actionId, {
      key = key,
      chord = chord,
      active = self.active,
      status = false,
      global = true,
    }, false)
    return true, actionId, result, reason
  end

  if key == "f7" then
    if shifted then return false end
    local chord = "f7"
    if self.heldChordByKey[key] == chord
        or (isRepeat == true and self.heldChordByKey[key] == nil) then
      self.heldChordByKey[key] = chord
      return true, self.active and CommandRouter.STATUS.ENABLED
                               or CommandRouter.STATUS.DISABLED
    end

    self.active = not self.active
    self.heldChordByKey[key] = chord
    local actionId = self.active and CommandRouter.STATUS.ENABLED
                                 or CommandRouter.STATUS.DISABLED
    local result, reason = self:_dispatch(actionId, {
      key = key,
      chord = chord,
      active = self.active,
      status = true,
    }, true)
    return true, actionId, result, reason
  end

  if not self.active then return false end
  if CommandRouter.RESERVED_WASD[key] then
    return self:_navigationAllowed(context)
  end
  local actionId = CommandRouter.MAPPINGS[shifted and "shift" or "plain"][key]
  if not actionId then return false end
  -- v0.3.98 adaptation (decision 22): with the camera off, its keys are not
  -- commands at all and pass through to the game.
  if self.cameraEnabled == false and CommandRouter.isCameraAction(actionId) then
    return false
  end
  if not NON_NAVIGATION[actionId] and not self:_navigationAllowed(context, actionId) then
    return false
  end

  local chord = chordFor(key, shifted)
  if self.heldChordByKey[key] == chord
      or (isRepeat == true and self.heldChordByKey[key] == nil) then
    self.heldChordByKey[key] = chord
    return true, actionId
  end
  self.heldChordByKey[key] = chord
  local result, reason = self:_dispatch(actionId, {
    key = key,
    chord = chord,
    shifted = shifted,
    active = true,
    status = false,
  }, false)
  return true, actionId, result, reason
end

function CommandRouter:keyreleased(key)
  key = type(key) == "string" and key:lower() or ""
  self.heldChordByKey[key] = nil
end

-- Physical-key reconciliation after a focus/resume reset must not resurrect a
-- native binding for a key currently owned by command mode.  The input layer
-- accepts this set as an optional filter while retaining identical behavior
-- for every ordinary caller.
function CommandRouter:blockedKeys(context)
  if not self.active then return nil end
  if not self:_navigationAllowed(context) then return nil end
  local keys = {}
  for key in pairs(CommandRouter.RESERVED_WASD) do keys[key] = true end
  for key in pairs(CommandRouter.MAPPINGS.plain) do keys[key] = true end
  for key in pairs(CommandRouter.MAPPINGS.shift) do keys[key] = true end
  return keys
end

-- Controller navigation is always available: these controls do not overlap
-- the Game Boy surface, and requiring F7 would make a controller-only setup
-- impossible to discover. Game gives raw capture screens first refusal.
function CommandRouter:gamepadpressed(button, context, isRepeat)
  button = type(button) == "string" and button:lower() or ""
  local actionId = self.gamepadButtonMappings[button]
  if not actionId then return false end
  if not self:_navigationAllowed(context, actionId) then return false end
  if self.heldGamepadButtons[button]
      or (isRepeat == true and self.heldGamepadButtons[button] == nil) then
    self.heldGamepadButtons[button] = true
    return true, actionId
  end
  self.heldGamepadButtons[button] = true
  local result, reason = self:_dispatch(actionId, {
    pad = button,
    chord = "gamepad:" .. button,
    active = self.active,
    status = false,
  }, false)
  return true, actionId, result, reason
end

function CommandRouter:gamepadreleased(button)
  button = type(button) == "string" and button:lower() or ""
  self.heldGamepadButtons[button] = nil
end

function CommandRouter:gamepadaxis(axis, value, context)
  axis = type(axis) == "string" and axis:lower() or ""
  value = tonumber(value) or 0
  local positive = axis .. ":positive"
  local negative = axis .. ":negative"
  local direction, actionId
  if self.gamepadAxisMappings[positive] then
    direction, actionId = "positive", self.gamepadAxisMappings[positive]
  elseif self.gamepadAxisMappings[negative] then
    direction, actionId = "negative", self.gamepadAxisMappings[negative]
  else
    return false
  end

  local control = axis .. ":" .. direction
  local active, released
  if direction == "positive" then
    active, released = value > AXIS_ON, value < AXIS_OFF
  else
    active, released = value < -AXIS_ON, value > -AXIS_OFF
  end
  if released then self.heldGamepadAxes[control] = nil end
  if not self:_navigationAllowed(context, actionId) then return false end
  if not active or self.heldGamepadAxes[control] then return true, actionId end

  self.heldGamepadAxes[control] = true
  local result, reason = self:_dispatch(actionId, {
    axis = axis,
    value = value,
    chord = "gamepad:axis:" .. control,
    active = self.active,
    status = false,
  }, false)
  return true, actionId, result, reason
end

return CommandRouter
