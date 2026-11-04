local S = require("tests.harness").suite("accessibility command router")
local CommandRouter = require("src.access.nav.CommandRouter")
local Input = require("src.core.Input")

local expectedPlain = {
  y = "read_player_position",
  j = "previous_map_item",
  k = "describe_route_to_selected_item",
  l = "next_map_item",
  t = "read_screen_text",
  m = "read_map_name",
  q = "read_game_time",
  e = "read_collision_tiles",
  d = "move_camera_left",
  g = "move_camera_right",
  r = "move_camera_up",
  v = "move_camera_down",
  f = "reset_camera_to_player",
  c = "toggle_camera_follow",
  h = "read_enemy_health",
}

local expectedShift = {
  y = "read_camera_position",
  j = "previous_item_filter",
  l = "next_item_filter",
  k = "auto_walk_to_selected_item",
  d = "move_camera_left_through_walls",
  g = "move_camera_right_through_walls",
  r = "move_camera_up_through_walls",
  v = "move_camera_down_through_walls",
  f = "describe_route_to_camera",
  c = "toggle_camera_follow",
  h = "read_player_health",
  e = "read_terrain",
}

S.same(CommandRouter.MAPPINGS.plain, expectedPlain,
  "public plain-key map is the executable Pokemon Access command set")
S.same(CommandRouter.MAPPINGS.shift, expectedShift,
  "public shifted map includes every source chord and Shift+C alias")

S.same(CommandRouter.GAMEPAD_DEFAULTS, {
  { action = "previous_item_filter", control = "leftshoulder" },
  { action = "next_item_filter", control = "rightshoulder" },
  { action = "previous_map_item", control = "axis:triggerleft:positive" },
  { action = "next_map_item", control = "axis:triggerright:positive" },
  { action = "describe_route_to_selected_item", control = "rightstick" },
}, "modern-controller navigation defaults are public and stable")

-- Lifecycle reconciliation is now owned by each current engine service
-- (Game, Game2, and Game3), not by CommandRouter.  Its protected-key contract
-- is covered when those services attach the router; keeping the historical
-- Input.driverOwned assertions here would test an upstream API that no longer
-- exists rather than this module.

local modifiers = {}
local calls = {}
local router = CommandRouter.new({
  modifierState = function() return modifiers end,
  onAction = function(action, metadata)
    calls[#calls + 1] = { action, metadata.chord }
    return true
  end,
})

local consumed = router:keypressed("d")
S.check(not consumed, "historical D passes through while command layer is off")
S.eq(#calls, 0, "disabled historical commands never dispatch")

local helpCalls = {}
local helpRouter = CommandRouter.new({
  modifierState = function() return modifiers end,
  onAction = function(id, metadata)
    helpCalls[#helpCalls + 1] = { id, metadata.chord, metadata.active }
    return true
  end,
})
local helpConsumed, helpAction = helpRouter:keypressed("f8")
S.check(helpConsumed and helpAction == "read_command_help",
  "F8 help is discoverable before command mode is enabled")
S.same(helpCalls[1], { "read_command_help", "f8", false },
  "F8 reports its chord and inactive-layer context")
helpRouter:keypressed("f8", nil, true)
S.eq(#helpCalls, 1, "held F8 help is one-shot")
helpRouter:keyreleased("f8")

local action
consumed, action = router:keypressed("f7")
S.check(consumed, "unmodified F7 is consumed as the command-layer toggle")
S.eq(action, "command_layer_enabled", "first toggle exposes stable enabled action")
S.check(router:isActive(), "first F7 enables the explicit command layer")
S.same(calls[1], { "command_layer_enabled", "f7" },
  "toggle reports status through the injected action callback")

consumed, action = router:keypressed("f7", nil, true)
S.check(consumed and action == "command_layer_enabled",
  "keyboard-repeat F7 is consumed without changing status")
S.eq(#calls, 1, "held F7 dispatches status only once")
router:keyreleased("f7")
consumed, action = router:keypressed("f7")
S.check(consumed and action == "command_layer_disabled",
  "released F7 may toggle the layer again")
S.check(not router:isActive(), "second edge disables the command layer")
S.eq(#calls, 2, "second toggle dispatches one disabled status")
router:keyreleased("f7")

-- Validate every chord independently rather than relying on the router's own
-- mapping table as test data.
local mappedCalls = {}
local mapped = CommandRouter.new({
  active = true,
  modifierState = function() return modifiers end,
  onAction = function(id, metadata)
    mappedCalls[#mappedCalls + 1] = { id = id, chord = metadata.chord }
    return true
  end,
})

modifiers = {}
for key, want in pairs(expectedPlain) do
  local before = #mappedCalls
  local wasConsumed, got = mapped:keypressed(key)
  S.check(wasConsumed, "plain " .. key .. " is consumed while layer is active")
  S.eq(got, want, "plain " .. key .. " dispatches its stable action")
  S.same(mappedCalls[before + 1], { id = want, chord = key },
    "plain " .. key .. " reports exact chord metadata")
  mapped:keyreleased(key)
end

modifiers = { leftShift = true }
for key, want in pairs(expectedShift) do
  local before = #mappedCalls
  local wasConsumed, got = mapped:keypressed(key)
  S.check(wasConsumed, "left Shift+" .. key .. " is consumed")
  S.eq(got, want, "left Shift+" .. key .. " dispatches its stable action")
  S.same(mappedCalls[before + 1], { id = want, chord = "shift+" .. key },
    "left Shift+" .. key .. " reports exact chord metadata")
  mapped:keyreleased(key)
end

modifiers = {}
local before = #mappedCalls
consumed, action = mapped:keypressed("y")
S.check(consumed and action == "read_player_position", "first Y edge dispatches")
consumed, action = mapped:keypressed("Y")
S.check(consumed and action == "read_player_position",
  "held/repeated Y remains consumed despite case variation")
S.eq(#mappedCalls, before + 1, "held command key is one-shot")
mapped:keyreleased("Y")
mapped:keypressed("y")
S.eq(#mappedCalls, before + 2, "release re-arms a command key")
mapped:keyreleased("y")

-- The latch is the exact chord, not merely the base key.  If a modifier set
-- changes while a key remains held, the newly formed exact chord gets one
-- edge and can return to the original chord once, matching Pokemon Access.
before = #mappedCalls
modifiers = {}
mapped:keypressed("y")
modifiers = { leftShift = true }
consumed, action = mapped:keypressed("y", nil, true)
S.check(consumed and action == "read_camera_position",
  "held Y may form the distinct left-Shift+Y chord once")
mapped:keypressed("y", nil, true)
modifiers = {}
consumed, action = mapped:keypressed("y", nil, true)
S.check(consumed and action == "read_player_position",
  "held Shift+Y may return to the distinct plain Y chord once")
S.eq(#mappedCalls, before + 3,
  "modifier-set changes dispatch each exact chord only once")
mapped:keyreleased("y")

local reservedBefore = #mappedCalls
for _, key in ipairs({ "w", "a", "s" }) do
  local wasConsumed, got = mapped:keypressed(key)
  S.check(wasConsumed and got == nil,
    "active compatibility mode reserves native " .. key:upper() .. " movement")
  mapped:keyreleased(key)
end
S.eq(#mappedCalls, reservedBefore,
  "reserved WAS keys do not dispatch invented accessibility actions")

local passCount = #mappedCalls
for _, key in ipairs({ "space", "rshift", "lshift", "f6" }) do
  S.check(not mapped:keypressed(key), key .. " is not owned by the command router")
end
S.eq(#mappedCalls, passCount, "unknown keys and global F6 dispatch no actions")

modifiers = { leftShift = true }
S.check(not mapped:keypressed("f7"), "Shift+F7 is not a toggle chord")
S.check(mapped:isActive(), "modified F7 leaves command mode unchanged")
mapped:keyreleased("f7")

for _, state in ipairs({
  { control = true }, { lctrl = true }, { alt = true }, { ralt = true },
  { gui = true }, { meta = true }, { rightShift = true }, { rshift = true },
  { leftShift = true, rightShift = true },
}) do
  modifiers = state
  S.check(not mapped:keypressed("y"),
    "Ctrl/Alt/GUI/right-Shift extras make a command pass through")
  mapped:keyreleased("y")
end
S.check(mapped:isActive(), "unsafe modifier sets cannot toggle or alter mode")

modifiers = { capsLock = true, numLock = true }
consumed, action = mapped:keypressed("t")
S.check(consumed and action == "read_screen_text",
  "lock-key state is ignored like the original exact-set dispatcher")
mapped:keyreleased("t")

modifiers = {}
local rawCalls = 0
local rawRouter = CommandRouter.new({
  active = true,
  modifierState = function() return modifiers end,
  onAction = function() rawCalls = rawCalls + 1 end,
})
for _, context in ipairs({
  true,
  { rawKeysOwned = true },
  { ownsRawKeys = true },
  { captureKeys = true },
  { rawKeyOwner = "BindingsMenu" },
}) do
  S.check(not rawRouter:keypressed("d", context),
    "raw-key owner has priority over native-conflicting D")
  S.check(not rawRouter:keypressed("f7", context),
    "raw-key owner also has priority over F7")
  S.check(not rawRouter:keypressed("f8", context),
    "raw-key owner also has priority over F8 help")
end
S.eq(rawCalls, 0, "raw-key contexts suppress actions and status callbacks")
S.check(rawRouter:isActive(), "raw-key F7 never changes layer state")
S.check(not rawRouter:keypressed("f6", { ownsRawKeys = true }),
  "F6 remains outside the router even in raw-key contexts")

local customRaw = true
local custom = CommandRouter.new({
  active = true,
  modifierState = function() return {} end,
  rawKeyOwner = function(context) return customRaw and context == "capture" end,
  onAction = function() return true end,
})
S.check(not custom:keypressed("m", "capture"),
  "integration can inject raw-key ownership arbitration")
customRaw = false
S.check(custom:keypressed("m", "capture"),
  "command resumes when injected raw ownership ends")

local unavailable = CommandRouter.new({
  active = true,
  modifierState = function() return {} end,
  onAction = function() return false, "not on a map" end,
})
local result, reason
consumed, action, result, reason = unavailable:keypressed("d")
S.check(consumed, "recognized D is consumed even when action is unavailable")
S.eq(action, "move_camera_left", "unavailable command retains stable action ID")
S.check(result == false and reason == "not on a map",
  "callback availability result is returned for integration diagnostics")

local exploding = CommandRouter.new({
  active = true,
  modifierState = function() return {} end,
  onAction = function() error("handler boom") end,
})
local ok
ok, consumed, action = pcall(function() return exploding:keypressed("d") end)
S.check(ok and consumed and action == "move_camera_left",
  "action callback exceptions cannot leak a recognized D into movement")
S.check(exploding.lastError and exploding.lastError:find("handler boom", 1, true),
  "callback exception is retained for diagnostics")

local statusCalls = {}
local statusRouter = CommandRouter.new({
  modifierState = function() return {} end,
  onAction = function(id) statusCalls[#statusCalls + 1] = "action:" .. id end,
  onStatus = function(id) statusCalls[#statusCalls + 1] = "status:" .. id end,
})
statusRouter:keypressed("f7")
S.same(statusCalls, { "status:command_layer_enabled" },
  "dedicated status callback takes precedence for toggles")

local failingModifiers = CommandRouter.new({
  active = true,
  modifierState = function() error("modifier boom") end,
  onAction = function() error("must not run") end,
})
S.check(not failingModifiers:keypressed("d"),
  "modifier-state failure safely passes keys through")
S.check(failingModifiers.lastError
    and failingModifiers.lastError:find("modifier boom", 1, true),
  "modifier-state failure is retained for diagnostics")

local failingContext = CommandRouter.new({
  active = true,
  rawKeyOwner = function() error("context boom") end,
  onAction = function() error("must not run") end,
})
S.check(not failingContext:keypressed("d"),
  "raw-owner arbitration failure safely passes keys through")
S.check(failingContext.lastError
    and failingContext.lastError:find("context boom", 1, true),
  "raw-owner failure is retained for diagnostics")

-- Extra controller inputs dispatch without the keyboard compatibility layer.
local padCalls = {}
local padRouter = CommandRouter.new({
  onAction = function(id, metadata)
    padCalls[#padCalls + 1] = { id, metadata.chord }
    return true
  end,
})
consumed, action = padRouter:gamepadpressed("leftshoulder")
S.check(consumed and action == "previous_item_filter",
  "left bumper selects the previous entity category")
padRouter:gamepadpressed("leftshoulder", nil, true)
S.eq(#padCalls, 1, "held bumper dispatches only once")
padRouter:gamepadreleased("leftshoulder")
padRouter:gamepadpressed("leftshoulder")
S.eq(#padCalls, 2, "released bumper re-arms its navigation action")
padRouter:gamepadreleased("leftshoulder")
padRouter:gamepadpressed("rightshoulder")
padRouter:resetGamepad()
padRouter:gamepadpressed("rightshoulder")
S.eq(#padCalls, 4,
  "focus or disconnect reset re-arms a controller command without release")
padRouter:gamepadreleased("rightshoulder")

padRouter:gamepadaxis("triggerleft", -1)
S.eq(#padCalls, 4, "resting left trigger does not move the entity cursor")
consumed, action = padRouter:gamepadaxis("triggerleft", 0.8)
S.check(consumed and action == "previous_map_item",
  "left trigger selects the previous entity")
padRouter:gamepadaxis("triggerleft", 0.9)
S.eq(#padCalls, 5, "held trigger dispatches only once")
padRouter:gamepadaxis("triggerleft", 0)
padRouter:gamepadaxis("triggerleft", 0.8)
S.eq(#padCalls, 6, "released trigger re-arms after crossing the deadzone")

local reboundCalls = {}
local rebound = CommandRouter.new({
  gamepadBindings = {
    describe_route_to_selected_item = { pad = "x" },
  },
  onAction = function(id) reboundCalls[#reboundCalls + 1] = id end,
})
S.check(not rebound:gamepadpressed("rightstick"),
  "rebinding removes the path command from its old button")
consumed, action = rebound:gamepadpressed("x")
S.check(consumed and action == "describe_route_to_selected_item",
  "a rebound face button dispatches pathfinding")
S.same(reboundCalls, { "describe_route_to_selected_item" },
  "rebound controller action dispatches exactly once")

local onMap, contextualCalls = false, {}
local contextual = CommandRouter.new({
  active = true,
  navigationAllowed = function() return onMap end,
  onAction = function(id)
    contextualCalls[#contextualCalls + 1] = id
    return true
  end,
})
S.check(not contextual:keypressed("k", { screenId = "Bag" }),
  "pathfinding key passes through when a menu owns focus")
S.check(not contextual:keypressed("j", { screenId = "Battle" }),
  "entity browse key passes through during battle")
S.check(not contextual:keypressed("w", { screenId = "Bag" }),
  "reserved movement letter is not stolen from a menu")
S.eq(contextual:blockedKeys({ screenId = "Bag" }), nil,
  "hotplug reconciliation does not suppress menu keyboard holds")
S.check(contextual:keypressed("t", { screenId = "Bag" }),
  "read-screen shortcut remains available in menus")
S.check(contextual:keypressed("h", { screenId = "Battle" }),
  "battle health shortcut remains available during battle")
S.check(not contextual:gamepadpressed("rightstick", { screenId = "Bag" }),
  "controller route button is not stolen from a menu")
S.check(not contextual:gamepadpressed("leftshoulder", { screenId = "Bag" }),
  "controller category button is not stolen from a menu")
S.check(not contextual:gamepadaxis("triggerleft", 0.8, { screenId = "Bag" }),
  "controller entity trigger passes through in a menu")
S.same(contextualCalls, { "read_screen_text", "read_enemy_health" },
  "off-map navigation never reaches the accessibility command handler")
onMap = true
S.check(contextual:blockedKeys().w == true,
  "command-mode movement reservation resumes only in free roam")
local mapPressed, mapAction = contextual:gamepadpressed("rightstick")
S.check(mapPressed and mapAction == "describe_route_to_selected_item",
  "controller route re-arms on returning to actionable world")
contextual:gamepadaxis("triggerleft", 0)
S.check(contextual:gamepadaxis("triggerleft", 0.8),
  "entity trigger dispatches again in free-roam world")
contextual:keypressed("k")
S.eq(contextualCalls[#contextualCalls], "describe_route_to_selected_item",
  "keyboard path command dispatches only in free-roam world")
local failedGate = CommandRouter.new({
  navigationAllowed = function() error("synthetic context failure") end,
  onAction = function() error("must not dispatch") end,
})
S.check(not failedGate:gamepadpressed("rightstick"),
  "context failures pass controller input through instead of stealing it")
S.check(failedGate.lastError
    and failedGate.lastError:find("synthetic context failure", 1, true),
  "navigation context failure remains diagnosable")

S.finish()
