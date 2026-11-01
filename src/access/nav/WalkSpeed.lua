-- Game speed while auto-walk walks (decision 26).
--
-- When the player picked a speed for auto-walk, it is applied through the
-- game's own runtime speed field (game.speedOverride, which upstream's skin
-- fast-forward also uses) only while auto-walk is actually walking.  A
-- battle or any other screen pauses the walk, and the player's own battle
-- and menu speeds apply again.  Link play and fixed-speed minigames still
-- win: Game:logicSpeed checks its lock before the override.
--
-- The previous value is restored on the way out, unless something else
-- changed the field in the meantime, in which case it is left alone.

local Settings = require("src.access.Settings")

local WalkSpeed = {}

local applied = nil -- { game, value, previous } while our speed is in force

local function restore()
  if not applied then return end
  local game = applied.game
  if game.speedOverride == applied.value then game.speedOverride = applied.previous end
  applied = nil
end

-- Called every frame after auto-walk updates.  `turning`: auto-walk is
-- turning to face a field-move obstacle, which must take one game tick, not
-- a fast frame's worth (a waterfall's bottom cell can be stepped onto), so
-- the game runs at 1X for it whatever the speed settings say.
function WalkSpeed.update(game, walking, turning)
  local want = walking and game and Settings.autoWalkSpeed(game) or nil
  if walking and turning and game then want = 1 end
  if not want then return restore() end
  if applied and applied.game ~= game then restore() end
  if not applied then
    applied = { game = game, value = want, previous = game.speedOverride }
  elseif game.speedOverride ~= applied.value then
    -- someone else took the field while we walked: hand it back to them
    applied = nil
    return
  end
  applied.value = want
  game.speedOverride = want
end

function WalkSpeed._resetForTests() applied = nil end

return WalkSpeed
