-- The running game object, for parts of the layer that cannot reach it
-- through a screen.  main.lua keeps its Game in a local, but every frame it
-- calls PlatformHooks.update(Game, dt) and looks the function up at call
-- time, so a runtime wrapper on that function sees the live game for every
-- generation (no upstream edit; listed in docs/access/architecture.md).
-- Gen 3 needs it most: it has no StateStack, so screen speech finds its
-- screens through the game (src/access/screens/gen3/Top.lua).

local CurrentGame = {}

-- Weak, so a game that main.lua drops (back to a launcher, a reboot) is
-- collected normally.
local ref = setmetatable({}, { __mode = "v" })
local installed = false

-- Scripted driver runs step the game directly and never call
-- PlatformHooks.update (main.lua love.update); tests/access/drivers/
-- isolated.lua hands the game over instead.  Gen 3's runtime also keeps
-- the game while the field runs, a fallback for any other path.
function CurrentGame.get()
  if ref.game then return ref.game end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and rawget(Runtime, "_game")
  if type(game) == "table" then return game end
  return nil
end

function CurrentGame.set(game)
  ref.game = game
end

function CurrentGame.install()
  if installed then return end
  local ok, PlatformHooks = pcall(require, "src.core.PlatformHooks")
  if not ok or type(PlatformHooks) ~= "table" or type(PlatformHooks.update) ~= "function" then return end
  installed = true
  local original = PlatformHooks.update
  PlatformHooks.update = function(game, dt, ...)
    ref.game = game
    return original(game, dt, ...)
  end
end

return CurrentGame
