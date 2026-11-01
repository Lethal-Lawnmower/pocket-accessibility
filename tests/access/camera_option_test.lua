-- Decision 22: with the camera off, its keys are not commands and pass
-- through to the game; with it on, they are routed as before.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq
local CommandRouter = require("src.access.nav.CommandRouter")

check(CommandRouter.isCameraAction("move_camera_left"), "camera actions are recognised")
check(not CommandRouter.isCameraAction("next_map_item"), "other actions are not")

local function router(cameraEnabled)
  local actions = {}
  local r = CommandRouter.new({ active = true, cameraEnabled = cameraEnabled,
    navigationAllowed = function() return true end,
    onAction = function(id) actions[#actions + 1] = id return true end })
  return r, actions
end

local off, offActions = router(false)
eq(off:keypressed("d", {}, false), false, "camera off: D passes through")
off:keyreleased("d")
eq(#offActions, 0, "camera off: no camera action")
eq(off:keypressed("l", {}, false), true, "camera off: L still browses")
eq(offActions[1], "next_map_item", "camera off: object list works")

local on, onActions = router(true)
eq(on:keypressed("d", {}, false), true, "camera on: D is a command")
eq(onActions[1], "move_camera_left", "camera on: D moves the camera")
T.finish()
