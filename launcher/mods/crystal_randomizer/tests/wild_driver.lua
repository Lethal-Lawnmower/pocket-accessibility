-- In-game check for modules/wild.lua on Crystal: installs the module with a
-- stand-in ctx (the randomizer's core is not needed), then drives the real
-- World encounter paths -- a grass step on ROUTE_29, the three rods on
-- ROUTE_30, a headbutt tree and a ROCK SMASH rock -- first on a vanilla save,
-- then randomized (version 2 options: per route, about as strong, catch 'em
-- all, levels at 150%), then vanilla again, and logs what each path produced.
-- Only the first randomized grass encounter is allowed to open a battle.
-- Run silently with a disposable identity, for example:
--   POKEPORT_IDENTITY=pocket-access-rand-wild-run POKEPORT_ACCESS_SILENT=1
--   POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/wild_driver.lua
--   lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Rng = dofile("launcher/mods/crystal_randomizer/rng.lua")
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")
  local Mon = require("src.battle.gen2.Mon")
  local FieldMoves = require("src.world.gen2.FieldMoves")
  local Permissions = require("src.world.gen2.Permissions")

  local function finish(ok, why)
    U.log(ok and "DONE" or ("FAIL " .. tostring(why)))
    love.event.quit(ok and 0 or 1)
  end

  for _ = 1, 600 do
    if game.world and game.world.map then break end
    U.wait(1)
  end
  local world = game.world
  if not (world and world.map) then return finish(false, "the world did not start") end
  U.wait(30)
  U.log("MAP", world.map.id)

  -- A bus the hook can live on when no mod loader installed one.
  if not Runtime.hooks.chains then Runtime.install(Runtime.events, Hooks.new(), nil) end

  -- The stand-in ctx, the same fields the core provides.
  local state = { active = false, seed = nil, options = {} }
  local listeners = {}
  local ctx = { shared = {} }
  function ctx.active() return state.active end
  function ctx.seed() return state.active and state.seed or nil end
  function ctx.option(key) if state.active then return state.options[key] end end
  function ctx.rng(stream, ...) return Rng.stream(state.seed, stream, ...) end
  function ctx.onSave(fn) listeners[#listeners + 1] = fn end
  function ctx.log(fmt, ...) U.log("MODLOG", select("#", ...) > 0 and fmt:format(...) or fmt) end
  local function setSave(active, seed, options)
    state.active, state.seed, state.options = active, seed, options or {}
    for _, fn in ipairs(listeners) do fn(active) end
  end

  local Wild = dofile("launcher/mods/crystal_randomizer/modules/wild.lua")
  local mod = { game = game, hooks = { wrap = function(_, name, fn, priority)
    return Runtime.hooks:wrap(name, fn, priority, "wild_driver") end } }
  Wild.install(mod, ctx)

  local save = game.save
  save.party = { Mon.new(game.data, "TYPHLOSION", 50) }
  save.repelSteps = 0

  -- Battles are recorded; only `allowBattle` lets one open.
  local started, allowBattle = {}, false
  local realStart = world.startBattle
  world.startBattle = function(self, opts)
    started[#started + 1] = opts
    if allowBattle then
      allowBattle = false
      return realStart(self, opts)
    end
  end

  local function findCell(map, want)
    local env = map.def and map.def.environment
    for y = 0, map.heightCells - 1 do
      for x = 0, map.widthCells - 1 do
        local c = map:cellCollision(x, y)
        if want == "grass" and FieldMoves.canEncounterWildMon(env, c, false)
            and not Permissions.isWater(c) then return x, y end
        if want == "bank" and c and not Permissions.isWater(c) then
          for facing, d in pairs({ up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }) do
            local n = map:cellCollision(x + d[1], y + d[2])
            if n and Permissions.isWater(n) then return x, y, facing end
          end
        end
      end
    end
  end

  local function grassSpecies(n)
    local out = {}
    world.noWildEncounters = false
    for _ = 1, n do
      world.wildCooldown = 0
      local before = #started
      world:tryWildEncounter()
      if #started > before then out[#out + 1] = started[#started].wild.species end
    end
    return out
  end

  local function fishSpecies(n)
    local out = {}
    for _, rod in ipairs({ "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }) do
      local seen = {}
      for _ = 1, n do
        local outcome, wild = world:rollFishing(rod)
        if outcome == "battle" and wild then seen[wild.species] = true end
      end
      local list = {}
      for s in pairs(seen) do list[#list + 1] = s end
      table.sort(list)
      out[rod] = table.concat(list, ",")
    end
    return out
  end

  local function treeAndRock()
    world.treemonRandom = function() return 0 end
    world.rockmonRandom = function() return 0 end
    local before = #started
    world:tryHeadbutt(0, 0)
    local tree = #started > before and started[#started].wild.species or "none"
    local rockIndex = world:rockMonEncounter()
    world.treemonRandom, world.rockmonRandom = nil, nil
    return tree, rockIndex
  end

  local function survey(label)
    world:setMap("ROUTE_29", 0, 0, "down")
    U.wait(5)
    local gx, gy = findCell(world.map, "grass")
    if not gx then return finish(false, "no grass cell on ROUTE_29") end
    world:setMap("ROUTE_29", gx, gy, "down")
    U.wait(5)
    local grass = grassSpecies(400)
    U.log(label, "ROUTE_29 grass at", gx, gy, "tod", tostring(world.tod), ":", table.concat(grass, ","))
    -- The pokedex/route query reads the same tables.
    local tables = world.encounters.grass.ROUTE_29.slots
    local dayList = {}
    for _, slot in ipairs(tables.DAY) do dayList[#dayList + 1] = slot.species .. ":" .. slot.level end
    U.log(label, "ROUTE_29 DAY table", table.concat(dayList, ","))

    world:setMap("ROUTE_30", 0, 0, "down")
    U.wait(5)
    local bx, by, facing = findCell(world.map, "bank")
    if bx then
      world:setMap("ROUTE_30", bx, by, facing)
      U.wait(5)
      world.player.facing = facing
      local rods = fishSpecies(300)
      U.log(label, "ROUTE_30 fishing at", bx, by, facing, "OLD", rods.OLD_ROD, "GOOD", rods.GOOD_ROD,
        "SUPER", rods.SUPER_ROD)
    else
      U.log(label, "ROUTE_30 fishing: no bank cell found")
    end

    world:setMap("ROUTE_42", 0, 0, "down") -- a tree set map
    U.wait(5)
    local treeSet = world.encounters.trees and world.encounters.trees.ROUTE_42
    local tree = treeAndRock()
    world:setMap("ROUTE_40", 0, 0, "down") -- a rock map
    U.wait(5)
    local _, rockIndex = treeAndRock()
    U.log(label, "headbutt ROUTE_42 (" .. tostring(treeSet) .. ") first row:", tree,
      "| rock smash ROUTE_40 species index:", tostring(rockIndex))
    world.tempWildMon = nil
    return grass
  end

  -- Version 2 options: per route, about as strong, catch 'em all, levels at 150%.
  local OPTIONS = { wild = true, wild_mode = "route", wild_similar = true, wild_catch_all = true, wild_level = 150 }
  local vanillaDay = {}
  for _, slot in ipairs(world.encounters.grass.ROUTE_29.slots.DAY) do
    vanillaDay[#vanillaDay + 1] = { species = slot.species, level = slot.level }
  end
  local vanillaGrass = {}
  for _, tod in ipairs({ "MORN", "DAY", "NITE" }) do
    for _, slot in ipairs(world.encounters.grass.ROUTE_29.slots[tod]) do vanillaGrass[slot.species] = true end
  end
  survey("VANILLA")
  setSave(true, "driver-seed", OPTIONS)
  local randomized = survey("RANDOM")
  -- No-reuse and levels, read from the table the game itself rolls.
  local tableOk = true
  for i, slot in ipairs(world.encounters.grass.ROUTE_29.slots.DAY) do
    local want = math.max(2, math.min(100, math.floor(vanillaDay[i].level * 1.5 + 0.5)))
    if vanillaGrass[slot.species] or slot.level ~= want then tableOk = false end
  end
  local rolledOk = #randomized > 0
  for _, species in ipairs(randomized) do if vanillaGrass[species] then rolledOk = false end end
  U.log("CHECK ROUTE_29 DAY table no-reuse and 150% levels:", tostring(tableOk),
    "| rolled grass avoids vanilla ROUTE_29 species:", tostring(rolledOk))
  setSave(false)
  survey("RESTORED")
  local restoredOk = true
  for i, slot in ipairs(world.encounters.grass.ROUTE_29.slots.DAY) do
    if slot.species ~= vanillaDay[i].species or slot.level ~= vanillaDay[i].level then restoredOk = false end
  end
  U.log("CHECK restored ROUTE_29 DAY equals vanilla:", tostring(restoredOk))
  setSave(true, "driver-seed", OPTIONS)
  -- One real battle from the randomized grass.
  world:setMap("ROUTE_29", 0, 0, "down")
  U.wait(5)
  local gx, gy = findCell(world.map, "grass")
  world:setMap("ROUTE_29", gx, gy, "down")
  U.wait(5)
  allowBattle = true
  local got
  for _ = 1, 400 do
    world.wildCooldown = 0
    local before = #started
    world:tryWildEncounter()
    if #started > before then got = started[#started] break end
  end
  for _ = 1, 120 do U.wait(1) end
  local top = game.stack:top()
  local battle = top and top.battle
  local enemy = battle and (battle.enemy or battle.enemyMon)
  U.log("BATTLE wild", got and got.wild.species, "level", got and got.wild.level,
    "top screen phase", tostring(top and top.phase),
    "enemy", tostring(type(enemy) == "table" and (enemy.species or (enemy.mon and enemy.mon.species))))
  setSave(false)
  finish(tableOk and rolledOk and restoredOk, "a CHECK line failed")
end
