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
  -- a ledge hop is two cells on one input: mid-hop the player is on the ledge's own tile
  return (world and (world.spinnerSliding or world.transitioning))
    or (player and (player.spinning or player.ledgeHop)) or false
end

function Gen1.isBattle(state)
  return type(state) == "table" and state.isBattle == true
end

function Gen1.afterSteer() end

function Gen1.newCoordinator(game, opts)
  return require("src.access.nav.gen1.Navigation").new(game, opts)
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

-- What the layer binds a coordinator to: a new one is built when this
-- changes.  Gen 1 and Gen 2 keep one save table per loaded game.
function Gen1.identity(game) return game and game.save end
Gen2.identity = Gen1.identity

-- The options table the game persists (custom names, the camera option).
function Gen1.options(game)
  local save = game and game.save
  return type(save) == "table" and type(save.options) == "table" and save.options or nil
end
Gen2.options = Gen1.options

-- ------------------------------------------------------------ FireRed
-- Gen 3 has no world object and no StateStack (decision 29).  The field is
-- a set of module singletons in src/core/game3/ (player, collision, map,
-- objects, warp, field); nav/gen3/World.lua builds one stable facade over
-- them per game, which is what `world` and `top` hand out, so auto-walk's
-- `top == walk.overworld` holds as in Gen 1.  The "free on the map" test
-- below is the old project's Gen 3 FieldInput classifier
-- (purple-gen3-integration, src/accessibility/gen3/FieldInput.lua, commit
-- 244150e22, upstream v0.3.32), re-derived for v0.3.98 under decision 20:
-- the same gates Player.update checks before it polls the D-pad.
-- Every Gen 3 cartridge shares this adapter: the field modules are one code
-- path upstream, and what differs comes from the profile (nav/gen3/GameData.lua).

local Gen3 = { generation = 3 }

-- A battle in progress: the Gen 3 battle is a module, never a screen, so
-- auto-walk and the commands see this fixed marker as the top.
WorldAdapter.GEN3_BATTLE = setmetatable({ isBattle = true, accessibilityRole = "battle" },
  { __tostring = function() return "gen3 battle" end })

local function loaded(path) return package.loaded[path] end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

function Gen3.game()
  local CurrentGame = loaded("src.access.CurrentGame")
  local game = CurrentGame and call(CurrentGame.get) or nil
  if type(game) ~= "table" then
    local Runtime = loaded("src.core.game3.runtime")
    game = Runtime and rawget(Runtime, "_game") or nil
  end
  if type(game) ~= "table" or type(game.data) ~= "table" or type(game.input) ~= "table" then
    return nil
  end
  if game.generation ~= nil and game.generation ~= 3 then return nil end
  -- no session before a new game or Continue: nothing to navigate yet
  if type(game.session) ~= "table" then return nil end
  return game
end

local function fieldRunning(game)
  local Runtime = loaded("src.core.game3.runtime")
  local Field = loaded("src.core.game3.field")
  return game ~= nil and game.phase == "field" and Runtime ~= nil and Runtime.active == true
    and Field ~= nil and rawget(Field, "running") == true
end

function Gen3.world(game)
  if not fieldRunning(game) then return nil end
  return require("src.access.nav.gen3.World").facade(game)
end

-- The player is held by something other than a warp: a message, yes/no
-- box, menu, fade, help screen, script, lock, step event, ferry or the
-- fishing rod.  These pause auto-walk (it resumes when the map returns).
function Gen3.held(game)
  local Help = loaded("src.ui.game3.help_system")
  if Help and call(Help.isOpen) then return true end
  local Hud = loaded("src.ui.game3.hud")
  if Hud and call(Hud.busy) then return true end
  local Field = loaded("src.core.game3.field")
  if Field then
    if call(Field.isLocked) then return true end
    if rawget(Field, "_holdInput") == true then return true end
    if rawget(Field, "_fishing") ~= nil then return true end
  end
  local Fade = loaded("src.ui.game3.fade")
  if Fade and Fade.lockInput then return true end
  local Space = loaded("src.core.game3.scripting.space")
  local vm = Space and Space.vm
  if vm and type(vm.isRunning) == "function" and call(vm.isRunning, vm) then return true end
  if Space and Space._pendingOnFrame then return true end
  local StepEvents = loaded("src.core.game3.step_events")
  if StepEvents and call(StepEvents.busy) then return true end
  local Seagallop = loaded("src.ui.game3.seagallop")
  if Seagallop and call(Seagallop.isActive) then return true end
  local Player = loaded("src.core.game3.player")
  if Player and (Player.fishing or Player.action) then return true end
  return false
end

local function warpBusy()
  local Warp = loaded("src.core.game3.warp")
  return Warp ~= nil and call(Warp.isBusy) == true
end

local function battleActive()
  local Battle = loaded("src.core.game3.battle") or loaded("src.core.game3.battle.init")
  if Battle and call(Battle.isActive) then return true end
  local Transition = loaded("src.core.game3.battle_transition")
  return Transition ~= nil and call(Transition.isActive) == true
end
Gen3.battleActive = battleActive

function Gen3.top(game)
  if not game then return nil end
  if battleActive() then return WorldAdapter.GEN3_BATTLE end
  local world = Gen3.world(game)
  if not world then return WorldAdapter.BUSY end
  -- a warp (door, stairs, pad, hole, the walk off an arrival mat) moves the
  -- player on its own: it is a transition, not a screen, so a walk that
  -- reaches a door keeps going and sees the new map as its arrival
  if warpBusy() then return world end
  if Gen3.held(game) then return WorldAdapter.BUSY end
  return world
end

function Gen3.onMap(game)
  local world = Gen3.world(game)
  return world ~= nil and Gen3.top(game) == world and not warpBusy()
end

-- The game moves the player without input: a warp, forced movement (ice,
-- spinners, currents, walk and slide tiles), a waterfall ride or a
-- waterfall's push, a scripted step, a surf hop, a boulder push or a field
-- move's animation.
function Gen3.transitioning(_world)
  if warpBusy() then return true end
  local Forced = loaded("src.core.game3.forced_movement")
  if Forced and rawget(Forced, "forced") == true then return true end
  local Player = loaded("src.core.game3.player")
  if Player then
    if Player.spinning or Player._scriptedStep or Player.surfHopping
       or Player.boulderPush or (tonumber(Player.fieldMoveAnim) or 0) > 0 then
      return true
    end
  end
  local Field = loaded("src.core.game3.field")
  if Field then
    if rawget(Field, "_waterfall") then return true end
    if call(Field.callbackPending) then return true end
    if call(Field.forcedMovementPending) then return true end
  end
  return false
end

Gen3.isBattle = Gen1.isBattle

-- Player.update polls the D-pad after finishing a step in the same tick
-- (finishStep emits world.stepped first), so a direction changed inside the
-- event is read at once, as in Gen 1.
function Gen3.afterSteer() end

-- Game3:saveGame replaces game.save on every save; the session lives for a
-- whole play session (a new game or Continue makes a new one).
function Gen3.identity(game) return game and game.session end

-- Gen 3 persists its options in game.options (Game3:writeOptions), but that
-- is the root of the shared options.lua (Gen 1's save.options): FireRed's
-- own values live in the cartridge block named by the profile (`firered`),
-- where the ACCESSIBILITY page keeps them too (src/access/Settings.lua).
-- Read as a plain field, never created here; nil until a session has bound
-- its options.
function Gen3.options(game)
  local root = game and type(game.options) == "table" and game.options or nil
  if not root then return nil end
  local id = "firered"
  local Profile = package.loaded["src.core.game3.profile"]
  if Profile and type(Profile.active) == "function" then
    local ok, row = pcall(Profile.active)
    if ok and type(row) == "table" and type(row.optionsBlock) == "string" then id = row.optionsBlock end
  end
  local block = root[id]
  return type(block) == "table" and block or nil
end

function Gen3.newCoordinator(game, opts)
  return require("src.access.nav.gen3.Navigation").new(game, opts)
end

WorldAdapter.gen1 = Gen1
WorldAdapter.gen2 = Gen2
WorldAdapter.gen3 = Gen3

-- The adapter for the running game's generation, or nil (the launcher).
function WorldAdapter.current()
  local gen = generation()
  if gen == 1 then return Gen1 end
  if gen == 2 then return Gen2 end
  if gen == 3 then return Gen3 end
  return nil
end

return WorldAdapter
