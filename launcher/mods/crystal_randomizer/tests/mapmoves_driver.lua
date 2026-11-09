-- A game run for the mapmoves module, on Crystal, with no core: the driver
-- rewrites four doors the way `maps` does (Cherrygrove's Pokémon Center door
-- swapped with a Route 30 house door, Route 31's Dark Cave door swapped with
-- Route 32's Union Cave door), stubs ctx.shared.maps with that placement,
-- installs modules/mapmoves.lua with a fake ctx, and then, through the
-- engine's own World methods:
--   1. takes the Route 30 door into the center; blacks out: must land on that
--      door; Teleport: the same;
--   2. upstairs to the shared POKECENTER_2F and back down, then out: must come
--      out at the Route 30 door;
--   3. takes the Route 31 door into Union Cave, with lastOutdoor elsewhere;
--      uses an ESCAPE ROPE: must come out at the Route 31 door;
--   4. flies to Cherrygrove: its spawn, as vanilla;
--   5. switches the save to vanilla (warps restored): World methods put back,
--      and a blackout after Cherrygrove's own center lands on its spawn.
-- Run silently and isolated, with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_VERSION=crystal
--   POKEPORT_GAME=crystal POKEPORT_IDENTITY=pocket-access-maps-moves
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=launcher/mods/crystal_randomizer/tests/mapmoves_driver.lua
--   "C:\Program Files\LOVE\lovec.exe" .
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local World = require("src.world.gen2.World")
  local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
  local Moves = dofile("launcher/mods/crystal_randomizer/modules/mapmoves.lua")
  local passed, failed = 0, 0
  local function check(cond, ...)
    if cond then passed = passed + 1 else failed = failed + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end
  local function finish()
    U.log("SUMMARY", passed, "passed", failed, "failed")
    love.event.quit()
  end

  if not L.settle(2000, true) then U.log("FAIL", "never reached the free world") finish() return end
  U.log("RESULT", "start", L.where())
  local maps = game.data.gen2Maps
  local ORIGINAL = {}
  for _, name in ipairs(Moves.WRAPPED) do ORIGINAL[name] = World[name] end

  local function doorInto(mapId, wanted)
    for i, w in ipairs(maps[mapId].warps) do
      if wanted(maps[w.destMap], w.destMap) then return i, w end
    end
  end
  local cgCenter = doorInto("CHERRYGROVE_CITY", function(d) return Moves.isCenter(d) end)
  local r30House = doorInto("ROUTE_30", function(d) return d and d.environment == "INDOOR" and not Moves.isCenter(d) end)
  local r31Cave = doorInto("ROUTE_31", function(_, id) return id == "DARK_CAVE_VIOLET_ENTRANCE" end)
  local r32Cave = doorInto("ROUTE_32", function(_, id) return id == "UNION_CAVE_1F" end)
  if not (cgCenter and r30House and r31Cave and r32Cave) then
    U.log("FAIL", "doors not found", cgCenter, r30House, r31Cave, r32Cave) finish() return
  end

  -- `maps`' rewrite for a swap of doors A and B; returns undo
  local undos = {}
  local function swap(am, ai, bm, bi)
    local function set(t, k, v) undos[#undos + 1] = { t, k, t[k] }; t[k] = v end
    local wa, wb = maps[am].warps[ai], maps[bm].warps[bi]
    local da, db = { wa.destMap, wa.destWarp }, { wb.destMap, wb.destWarp }
    local function exitsOf(destMap, map, index)
      local list = {}
      for _, e in ipairs(maps[destMap].warps) do
        if e.destMap == map and e.destWarp == index then list[#list + 1] = e end
      end
      return list
    end
    local exitsA, exitsB = exitsOf(da[1], am, ai), exitsOf(db[1], bm, bi)
    set(wa, "destMap", db[1]); set(wa, "destWarp", db[2])
    set(wb, "destMap", da[1]); set(wb, "destWarp", da[2])
    for _, e in ipairs(exitsB) do set(e, "destMap", am); set(e, "destWarp", ai) end
    for _, e in ipairs(exitsA) do set(e, "destMap", bm); set(e, "destWarp", bi) end
  end
  local function restore()
    for i = #undos, 1, -1 do local u = undos[i]; u[1][u[2]] = u[3] end
    undos = {}
  end
  swap("CHERRYGROVE_CITY", cgCenter, "ROUTE_30", r30House)
  swap("ROUTE_31", r31Cave, "ROUTE_32", r32Cave)
  local placement = {
    ["CHERRYGROVE_CITY:" .. cgCenter] = "ROUTE_30:" .. r30House,
    ["ROUTE_30:" .. r30House] = "CHERRYGROVE_CITY:" .. cgCenter,
    ["ROUTE_31:" .. r31Cave] = "ROUTE_32:" .. r32Cave,
    ["ROUTE_32:" .. r32Cave] = "ROUTE_31:" .. r31Cave,
  }
  local ctx = Fake.new({ seed = "mapmoves-drive", options = { maps = "full" } })
  Moves.install({ game = game }, ctx)
  ctx.shared.maps = { placement = placement, report = {} }
  ctx.setActive(true)
  for _, line in ipairs(ctx.lines) do U.log("MODLOG", line) end
  check(Moves.isAttached(World), "attached while a placement is active")

  local mon = L.giveParty("ABRA", 40, { "TELEPORT", "DIG", "FLY", "TACKLE" })
  local world = game.world
  -- On the door, or the one step out of it the engine takes on arrival at a
  -- door tile (walking out of the vanilla center lands the same way).
  local function at(mapId, warpIndex)
    local w = maps[mapId].warps[warpIndex]
    local id, x, y = L.pos()
    return id == mapId and x == w.x and (y == w.y or y == w.y + 1)
  end
  -- stand on a door tile and take it, through World:takeWarp
  local function take(mapId, warpIndex)
    local w = maps[mapId].warps[warpIndex]
    L.teleport(mapId, w.x, w.y, "up")
    world = game.world
    world:takeWarp(world.map.def.warps[warpIndex])
    L.settle(600, true)
    world = game.world
  end
  local function takeHere(warpIndex)
    world:takeWarp(world.map.def.warps[warpIndex])
    L.settle(600, true)
    world = game.world
  end

  -- 1. center through the Route 30 door; blackout and Teleport
  take("ROUTE_30", r30House)
  U.log("RESULT", "through ROUTE_30 door", r30House, "->", L.where(), "blackoutMap", game.save.blackoutMap)
  check(world.map.id == "CHERRYGROVE_POKECENTER_1F", "the Route 30 door leads into the center")
  check(game.save.blackoutMap == "ROUTE_30", "blackout map is the route")
  local hp = world:healPoint()
  U.log("RESULT", "healPoint", hp and hp.map, hp and hp.x, hp and hp.y)
  for _, m in ipairs(game.save.party) do m.hp = 0 end
  world:whiteOut()
  L.settle(1500, true)
  world = game.world
  U.log("RESULT", "after blackout", L.where())
  check(at("ROUTE_30", r30House), "blackout lands on the Route 30 door into the center")
  check((game.save.party[1].hp or 0) > 0, "the party was healed")
  L.teleport("ROUTE_29", 10, 10, "down")
  world = game.world
  world:runTeleport({ text = "Return to the last\nPOKéMON CENTER.", mon = mon })
  L.settle(1500, true)
  world = game.world
  U.log("RESULT", "after Teleport", L.where())
  check(at("ROUTE_30", r30House), "Teleport lands on the Route 30 door into the center")

  -- 2. upstairs and out
  take("ROUTE_30", r30House)
  local stairs = doorInto("CHERRYGROVE_POKECENTER_1F", function(_, id) return id == "POKECENTER_2F" end)
  local function stairsCell()
    local w = maps.CHERRYGROVE_POKECENTER_1F.warps[stairs]
    return w
  end
  takeHere(stairs)
  U.log("RESULT", "upstairs", L.where())
  check(world.map.id == "POKECENTER_2F", "up to the shared 2F")
  takeHere(1)
  U.log("RESULT", "downstairs", L.where())
  check(world.map.id == "CHERRYGROVE_POKECENTER_1F", "the 2F stairs lead back into this center")
  local s = stairsCell()
  L.teleport("CHERRYGROVE_POKECENTER_1F", maps.CHERRYGROVE_POKECENTER_1F.warps[1].x,
    maps.CHERRYGROVE_POKECENTER_1F.warps[1].y, "down")
  world = game.world
  takeHere(1)
  U.log("RESULT", "out of the center", L.where(), "(stairs at", s.x, s.y, ")")
  check(at("ROUTE_30", r30House), "the center lets out at the Route 30 door")

  -- 3. Escape Rope out of Union Cave, entered from Route 31
  take("ROUTE_31", r31Cave)
  U.log("RESULT", "through ROUTE_31 door", r31Cave, "->", L.where())
  check(world.map.id == "UNION_CAVE_1F", "the Route 31 door leads into Union Cave")
  world.lastOutdoor = { id = "NEW_BARK_TOWN", x = 13, y = 6 }
  local ropeMap, ropeWarp = world:escapeRopeTarget()
  U.log("RESULT", "rope target", ropeMap, ropeWarp and ropeWarp.x, ropeWarp and ropeWarp.y)
  local used = world:useEscapeRope("ESCAPE_ROPE")
  U.log("RESULT", "useEscapeRope", used)
  for _ = 1, 600 do
    if world.queuedFieldMove == nil and world.map and world.map.id ~= "UNION_CAVE_1F" and L.free() then break end
    if game.stack:top() then L.tap("a", 8) else U.wait(1) end
  end
  L.settle(600, true)
  world = game.world
  U.log("RESULT", "after rope", L.where())
  check(at("ROUTE_31", r31Cave), "the rope leads out the Route 31 door")

  -- 4. Fly reaches the town
  world:flyTo("SPAWN_CHERRYGROVE", mon)
  L.settle(1500, true)
  world = game.world
  U.log("RESULT", "after Fly", L.where())
  local id, x, y = L.pos()
  check(id == "CHERRYGROVE_CITY" and x == 29 and y == 4, "Fly lands on Cherrygrove's spawn")

  -- 5. back to vanilla
  restore()
  ctx.shared.maps = nil
  ctx.setActive(false)
  local back = true
  for _, name in ipairs(Moves.WRAPPED) do back = back and World[name] == ORIGINAL[name] end
  check(back and not Moves.isAttached(), "vanilla save: every World method put back")
  take("CHERRYGROVE_CITY", cgCenter)
  check(world.map.id == "CHERRYGROVE_POKECENTER_1F", "vanilla: Cherrygrove's door is its center again")
  for _, m in ipairs(game.save.party) do m.hp = 0 end
  world:whiteOut()
  L.settle(1500, true)
  world = game.world
  U.log("RESULT", "vanilla blackout", L.where())
  id, x, y = L.pos()
  check(id == "CHERRYGROVE_CITY" and x == 29 and y == 4, "vanilla: blackout lands on Cherrygrove's spawn")
  finish()
end
