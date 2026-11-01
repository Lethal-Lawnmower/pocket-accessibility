-- Per-generation access to the running game for the navigation wiring
-- (init.lua), auto-walk (AutoWalk.lua) and AUTO-WALK SPEED (WalkSpeed.lua).
--
-- The coordinator itself is generation-specific by subclass (Navigation.lua
-- for Gen 1, gen2/Navigation.lua for Gold, Silver and Crystal).  Everything
-- outside the coordinator that touches the game asks one of the two adapters
-- below the same few questions, so auto-walk's state machine and the key and
-- controller wiring stay shared:
--
--   game()            the running game object, or nil
--   world(game)       the live overworld (Gen 1 `overworld`, Gen 2 `world`)
--   top(game)         what auto-walk treats as the top screen: the stack's
--                     top state; on Gen 2 with an empty stack, the world
--                     itself when the player is free to walk, or BUSY while a
--                     script, text, menu or battle holds it
--   onMap(game)       the player is on the map with no screen over it
--   transitioning(w)  the game is moving the player on its own (door and
--                     stair fades, spinner and ice slides, currents, forced
--                     steps): auto-walk lets go and waits
--   isBattle(state)   a battle screen (both generations mark `isBattle`)
--   afterSteer(game)  called after auto-walk changes the held direction
--                     inside the game's own step (see AutoWalk.stepped)
--   newCoordinator(game, opts)
--
-- Reading only: nothing here changes game state except Gen 2's afterSteer,
-- which re-reads the held direction into the world exactly as the game's
-- own next tick would (World:pollInput), listed in docs/access/architecture.md.

local WorldAdapter = {}

-- Gen 2's "the world is busy" top; never equal to any world or state.
WorldAdapter.BUSY = setmetatable({}, { __tostring = function() return "busy world" end })

local function generation()
  local GameVersion = package.loaded["src.core.GameVersion"]
  if not (GameVersion and GameVersion.generation) then return 1 end
  local ok, value = pcall(GameVersion.generation)
  return ok and value or 1
end

-- ------------------------------------------------------------------ Gen 1

local Gen1 = { generation = 1 }

function Gen1.game()
  local Game = package.loaded["src.core.Game"]
  if type(Game) ~= "table" or type(Game.save) ~= "table" or type(Game.data) ~= "table" then
    return nil
  end
  return Game
end

function Gen1.world(game) return game and game.overworld or nil end

function Gen1.top(game)
  return game and game.stack and game.stack:top() or nil
end

function Gen1.onMap(game)
  return game ~= nil and game.stack ~= nil and game.overworld ~= nil
    and game.stack:top() == game.overworld
end

function Gen1.transitioning(world)
  local player = world and world.player
  return (world and (world.spinnerSliding or world.transitioning))
    or (player and player.spinning) or false
end

function Gen1.isBattle(state)
  return type(state) == "table" and state.isBattle == true
end

function Gen1.afterSteer() end

function Gen1.newCoordinator(game, opts)
  return require("src.access.nav.Navigation").new(game, opts)
end

-- ------------------------------------------------------------------ Gen 2
-- Game2 keeps its instance in a main.lua local.  The mod loader binds the
-- Gen 1 Game facade (src/mods/Gen2Compat.lua) to it before game.ready; the
-- facade's `.overworld` is the live World, whose `game` field is the Game2
-- instance itself.  Read through package.loaded so nothing is loaded here.

local Gen2 = { generation = 2 }

local cachedGame = setmetatable({}, { __mode = "v" })

function Gen2.game()
  local Compat = package.loaded["src.mods.Gen2Compat"]
  local game
  if Compat and type(Compat.resolve) == "function" then
    local ok, facade = pcall(Compat.resolve, "src.core.Game")
    if ok and type(facade) == "table" then
      local okWorld, world = pcall(function() return facade.overworld end)
      game = okWorld and type(world) == "table" and world.game or nil
    end
  end
  game = game or cachedGame.game
  if type(game) ~= "table" or type(game.save) ~= "table" or type(game.data) ~= "table"
     or type(game.stack) ~= "table" then
    return nil
  end
  cachedGame.game = game
  return game
end

function Gen2.world(game)
  local world = game and game.world
  if type(world) == "table" and world.map and world.player then return world end
  return nil
end

-- The world holds the player for a script, a text box, a menu, a field-move
-- animation or a battle.  This is World:busy re-derived without its
-- `moveState` arm (scripted movement such as a whirlpool's bounce, which may
-- still be described) and without `mapSetup` (a door or stair fade, which is
-- a transition), so the two can be told apart.  The old fork split World:busy
-- upstream (busyBesidesMovement); this reads the same fields instead.
function Gen2.scriptHeld(world)
  if type(world) ~= "table" then return true end
  if world.battleActive then return true end
  local ok, running = pcall(world.scriptRunning, world)
  if not ok or running then return true end
  return world.pendingTrainerBattle ~= nil or world.textbox ~= nil
    or world.choicebox ~= nil or world.fishing ~= nil or world.headbutt ~= nil
    or world.fieldMove ~= nil or world.flyAnim ~= nil or world.skyfall ~= nil
end

function Gen2.top(game)
  if not game then return nil end
  local top = game.stack and game.stack:top() or nil
  if top then return top end
  local world = Gen2.world(game)
  if not world or game.phase ~= "play" then return nil end
  if Gen2.scriptHeld(world) or world.moveState ~= nil then return WorldAdapter.BUSY end
  return world
end

function Gen2.onMap(game)
  local world = Gen2.world(game)
  return world ~= nil and Gen2.top(game) == world
end

local Permissions
local function permissions()
  Permissions = Permissions or require("src.world.gen2.Permissions")
  return Permissions
end

-- The game moves the player without input: a warp's fade and load
-- (mapSetup), a spin, an ice slide (the latched direction on ice, as
-- World:acceptsMenuInput reads it), a current or waterfall, or the forced
-- step off a door the player arrived on.
function Gen2.transitioning(world)
  if type(world) ~= "table" then return false end
  if world.mapSetup ~= nil then return true end
  local player, map = world.player, world.map
  if not (player and map) then return false end
  if player.spinFrames then return true end
  local ok, coll = pcall(map.cellCollision, map, player.cellX, player.cellY)
  if not ok then return false end
  local P = permissions()
  if world.turningDirection and P.isIce(coll) then return true end
  if not player.moving and (P.currentDirection(coll) or P.doorForcedDirection(coll)) then
    return true
  end
  return false
end

Gen2.isBattle = Gen1.isBattle

-- Game2's tick reads the held direction into world.heldDir BEFORE the world
-- steps (Game2.lua stepBody: pollInput, then world:step), and a landing
-- starts the next step in the same tick with that latched direction.  A
-- direction chosen inside world.stepped would otherwise take effect one tile
-- late.  Re-reading the input here gives the value the next tick would read.
function Gen2.afterSteer(game)
  local world = Gen2.world(game)
  if world and type(world.pollInput) == "function" and game.input then
    pcall(world.pollInput, world, game.input)
  end
end

function Gen2.newCoordinator(game, opts)
  return require("src.access.nav.gen2.Navigation").new(game, opts)
end

WorldAdapter.gen1 = Gen1
WorldAdapter.gen2 = Gen2

-- The adapter for the running game's generation, or nil (Gen 3 and the
-- launcher have no navigation).
function WorldAdapter.current()
  local gen = generation()
  if gen == 1 then return Gen1 end
  if gen == 2 then return Gen2 end
  return nil
end

return WorldAdapter
