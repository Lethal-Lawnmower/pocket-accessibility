-- The Pokénav in Emerald, Ruby and Sapphire: opened by START, every sub-screen
-- reached by key press.  Trainers, contest stats and ribbons are set first with
-- upstream's own functions.  Asserts nothing; logs SCREEN, SAID, BAD.
-- RSE_ONLY (a comma list of section names) limits a run.
return function(game)
  local L = dofile("tests/access/drivers/rse_menus_lib.lua")(game)
  local tap, taps, wait, waitFor = L.tap, L.taps, L.wait, L.waitFor

  local only
  if os.getenv("RSE_ONLY") then
    only = {}
    for name in os.getenv("RSE_ONLY"):gmatch("[^,]+") do only[name] = true end
  end
  local function section(label, fn)
    if only and not only[label] then return end
    L.section(label, fn)
  end

  waitFor("boot", function() return game.phase == "boot" and game.boot end, 900)
  wait(60)
  local ok, err = pcall(function() game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 }) end)
  if not ok then L.log("FAIL", "new game: " .. tostring(err)) love.event.quit() return end
  wait(120)
  L.talk(40)
  wait(60)

  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants")
  local Stack = require("src.ui.game3.stack")
  local Ribbons = require("src.core.game3.rse.ribbons")
  local session = L.session()
  local consts = C.active(session)
  local isEmerald = os.getenv("POKEPORT_GAME") == "emerald"
  local navPath = isEmerald and "src.ui.game3.rse.pokenav.init" or "src.ui.game3.rs.pokenav.init"

  session.party = {}
  Party.giveMon(session, consts:require("species", "SPECIES_MUDKIP"), 12)
  Party.giveMon(session, consts:require("species", "SPECIES_ZIGZAGOON"), 5, "ZIGGY")
  Party.giveMon(session, consts:require("species", "SPECIES_RALTS"), 7)
  L.flag(session, "FLAG_SYS_POKEMON_GET")
  L.flag(session, "FLAG_SYS_POKEDEX_GET")
  L.flag(session, "FLAG_SYS_POKENAV_GET")
  session.party[1].contest = { cool = 40, beauty = 12, cute = 3, smart = 0, tough = 25, sheen = 60 }
  session.party[2].contest = { cool = 9, beauty = 90, cute = 70, smart = 5, tough = 1, sheen = 255 }
  local Storage = require("src.core.game3.storage")
  Storage.ensure(session)
  session.storage.boxes[1].mons = session.storage.boxes[1].mons or {}
  local boxed = {}
  for key, value in pairs(session.party[3]) do boxed[key] = value end
  boxed.contest = { cool = 200, beauty = 1, cute = 1, smart = 1, tough = 1, sheen = 0 }
  session.storage.boxes[1].mons[1] = boxed

  local function startTo(id)
    L.closeAll()
    tap("start", 25)
    if L.top() ~= "start" then L.log("NOSTART", tostring(L.top())) return false end
    local StartMenu = require("src.ui.game3.start_menu")
    for _ = 1, 12 do
      local entry = StartMenu.ENTRIES[StartMenu.cursor]
      if entry and entry.id == id then return true end
      tap("down", 12)
    end
    L.log("NOENTRY", id)
    return false
  end

  local function nav() return require(navPath).active() end
  local function open()
    if not startTo("pokenav") then return false end
    tap("a", 30)
    waitFor("pokenav", function()
      local s = nav()
      if not s then return false end
      if isEmerald then return s.phase == "menu" and s.screen and not s:busy(s.screenTask) end
      return s.phase == "active" and s.busy == 0
    end, 300)
    wait(10)
    return true
  end

  -- Upstream's own map load, as gen3_nav_lib.lua does: calls and the map's
  -- "you are here" need a real outdoor map, not the opening truck.
  local function teleport(pattern, x, y)
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local mapId
    for id in pairs(game.data.maps) do
      if tostring(id):find(pattern) then mapId = id break end
    end
    if not mapId then L.log("NOMAP", pattern) return false end
    L.closeAll()
    local done, why = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = "down" }) end)
    if not done then L.log("FAIL", "Map.load " .. tostring(mapId) .. ": " .. tostring(why)) return false end
    session.x, session.y, session.facing = x, y, "down"
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing, Player.moveDir, Player.moving = "down", "down", false
    wait(60)
    L.log("MAP", tostring(mapId) .. " " .. tostring(session.map))
    return true
  end

  section("outdoors", function() end)
  teleport("ROUTE_?118$", 12, 8)

  section("menus", function()
    if not open() then return end
    taps({ "down", "down", "up", "up" }, 20)
    L.log("STEP", "condition menu")
    tap("down", 20)
    tap("a", 60)
    taps({ "down", "down" }, 20)
    tap("up", 20)
    L.log("STEP", "search menu")
    tap("a", 60)
    taps({ "down", "down", "down", "down", "down" }, 20)
    tap("b", 60)
    L.log("STEP", "b from search row")
    tap("b", 60)
    L.closeAll()
  end)

  section("map", function()
    if not open() then return end
    tap("a", 90)
    taps({ "right", "right", "up", "up", "up" }, 20)
    taps({ "right", "right", "right", "right" }, 20)
    L.log("STEP", "zoom")
    tap("a", 60)
    taps({ "left", "left", "down" }, 25)
    L.log("STEP", "zoom out")
    tap("a", 60)
    tap("b", 80)
    L.closeAll()
  end)

  section("graph_party", function()
    if not open() then return end
    tap("down", 20)
    tap("a", 60)
    tap("a", 120)
    taps({ "down", "down", "down", "down" }, 50)
    tap("b", 80)
    tap("up", 20)
    tap("a", 120)
    tap("up", 50)
    L.log("STEP", "A on CANCEL")
    tap("a", 80)
    L.closeAll()
  end)

  section("graph_search", function()
    if not open() then return end
    tap("down", 20)
    tap("a", 60)
    tap("down", 20)
    tap("a", 60)
    L.log("STEP", "search COOL")
    tap("a", 90)
    taps({ "down", "down", "up", "up" }, 20)
    L.log("STEP", "graph of the boxed result")
    tap("a", 120)
    taps({ "down", "down", "up" }, 50)
    L.log("STEP", "markings")
    tap("a", 30)
    tap("a", 20)
    taps({ "down", "up" }, 20)
    tap("b", 30)
    tap("a", 30)
    tap("a", 20)
    taps({ "down", "down", "down", "down" }, 20)
    tap("a", 30)
    L.log("STEP", "back to the list")
    tap("b", 90)
    tap("down", 20)
    tap("b", 90)
    tap("b", 60)
    L.closeAll()
  end)

  section("no_ribbons", function()
    if isEmerald then L.flag(session, "FLAG_ADDED_MATCH_CALL_TO_POKENAV") end
    L.flag(session, "FLAG_SYS_RIBBON_GET")
    if not open() then return end
    taps({ "down", "down", "down" }, 20)
    tap("a", 30)
    tap("a", 30)
    tap("down", 20)
    tap("up", 20)
    L.closeAll()
  end)

  section("ribbons", function()
    L.flag(session, "FLAG_SYS_RIBBON_GET")
    if isEmerald then L.flag(session, "FLAG_ADDED_MATCH_CALL_TO_POKENAV") end
    Ribbons.set(session.party[1], "champion", 1)
    Ribbons.set(session.party[1], "cool", 2)
    Ribbons.set(session.party[2], "tough", 1)
    local gift = Ribbons.GIFT_FIELDS[1]
    session.giftRibbons = session.giftRibbons or {}
    session.giftRibbons[1] = 1
    Ribbons.set(session.party[2], gift, 1)
    if not open() then return end
    taps({ "down", "down", "down" }, 20)
    tap("a", 90)
    taps({ "down", "up" }, 20)
    L.log("STEP", "summary")
    tap("a", 90)
    tap("down", 50)
    tap("up", 50)
    L.log("STEP", "ribbon selected")
    tap("a", 40)
    taps({ "right", "right", "down", "left" }, 30)
    tap("b", 40)
    tap("down", 50)
    tap("a", 40)
    L.log("STEP", "gift ribbon row")
    tap("down", 30)
    tap("up", 30)
    tap("b", 40)
    tap("b", 60)
    tap("b", 60)
    L.closeAll()
  end)

  if isEmerald then
    local Rematch = require("src.core.game3.rse.rematch")
    local MatchCall = require("src.core.game3.rse.match_call")

    section("matchcall", function()
      L.flag(session, "FLAG_ADDED_MATCH_CALL_TO_POKENAV")
      L.flag(session, "FLAG_HAS_MATCH_CALL")
      L.flag(session, "FLAG_ENABLE_MOM_MATCH_CALL")
      for i = 0, 11 do
        if not MatchCall.hasRematchId(i) then Rematch.setFlag(session, Rematch.registeredFlagId(session, i), true) end
      end
      Rematch.set(session, 1, 1)
      if not open() then return end
      taps({ "down", "down" }, 20)
      tap("a", 90)
      local screen = nav().screen
      L.log("ENTRIES", #screen.entries)
      taps({ "down", "down", "up" }, 18)
      tap("right", 18)
      tap("left", 18)
      L.log("STEP", "options, no Check")
      tap("a", 25)
      taps({ "down", "up", "down" }, 15)
      L.log("STEP", "cancel the options")
      tap("a", 25)
      tap("down", 18)
      L.log("STEP", "options with Check")
      tap("a", 25)
      taps({ "down", "down", "up" }, 15)
      L.log("STEP", "check page")
      tap("a", 60)
      taps({ "down", "down", "up" }, 60)
      tap("b", 40)
      local function placeCall()
        tap("a", 25)
        tap("a", 25)
        for _ = 1, 60 do
          if screen.handler == "list" then break end
          tap("a", 40)
        end
        wait(30)
      end
      tap("up", 18)
      L.log("STEP", "call a trainer on this route")
      placeCall()
      tap("down", 18)
      L.log("STEP", "call a trainer elsewhere who wants a rematch")
      placeCall()
      taps({ "up", "up" }, 18)
      L.log("STEP", "call a special trainer")
      placeCall()
      tap("b", 80)
      L.closeAll()
      Rematch.set(session, MatchCall.entryRematchIdx(screen.entries[3]), 1)
      L.log("STEP", "reopen with a rematch on this route")
      if not open() then return end
      L.closeAll()
    end)

    section("callwindow", function()
      L.closeAll()
      wait(30)
      local Window = require("src.ui.game3.rse.pokenav.call_window")
      local trainer = Rematch.trainerIds(1)[1]
      L.log("STEP", "incoming call")
      MatchCall.startCall(session, game, { trainerId = trainer })
      wait(40)
      if not Window.isOpen() then
        L.log("STEP", "queued for a step; starting the window with the same message")
        Window.start({ session = session, message = function() return MatchCall.selectMessage(session, trainer) end })
      end
      wait(120)
      for _ = 1, 40 do
        if not Window.isOpen() then break end
        tap("a", 40)
      end
      L.log("TOP", tostring(L.top()))
    end)

    section("event_island", function()
      if not teleport("FARAWAY_ISLAND_ENTRANCE$", 8, 8) then return end
      if not open() then return end
      tap("a", 90)
      taps({ "right", "a" }, 30)
      tap("b", 80)
      L.closeAll()
      teleport("ROUTE_?118$", 12, 8)
    end)

    section("tutorial", function()
      L.closeAll()
      wait(30)
      local closed = false
      require(navPath).show({ session = session, tutorial = true, onClose = function() closed = true end })
      wait(120)
      tap("b", 20)
      tap("a", 20)
      taps({ "down", "down" }, 20)
      tap("a", 90)
      tap("a", 25)
      tap("a", 25)
      for _ = 1, 30 do
        local s = nav()
        if not s or s.screen.handler == "list" then break end
        tap("a", 40)
      end
      wait(30)
      tap("b", 80)
      tap("b", 80)
      L.log("CLOSED", tostring(closed))
      L.closeAll()
    end)
  else
    section("eyes", function()
      local Flags = require("src.core.game3.scripting.flags")
      local Space = require("src.core.game3.scripting.space")
      local Data = require("src.ui.game3.rs.pokenav.data")
      local detail = require("src.ui.game3.rs.pokenav.gfx").manifest("pokenav_detail")
      L.log("STEP", "no trainers registered")
      if not open() then return end
      taps({ "down", "down" }, 20)
      tap("a", 30)
      tap("b", 20)
      L.closeAll()
      for i = 0, 9 do
        Flags.setFlag(Space.store, nil, Data.TRAINER_FLAG_START + detail.rematches[i].opponentIDs[1], true)
      end
      Flags.setFlag(Space.store, nil, Data.TRAINER_FLAG_START + detail.leaders[0].opponentId, true)
      session.trainerRematches = session.trainerRematches or {}
      session.trainerRematches[1] = 1
      if not open() then return end
      taps({ "down", "down" }, 20)
      tap("a", 80)
      taps({ "down", "down", "up" }, 20)
      tap("right", 20)
      tap("left", 20)
      L.log("STEP", "trainer detail")
      tap("a", 40)
      taps({ "down", "up" }, 40)
      tap("b", 40)
      tap("down", 20)
      tap("b", 60)
      L.closeAll()
    end)

    section("nearby", function()
      session.trainerRematches = session.trainerRematches or {}
      session.trainerRematches[0] = 1
      if not open() then return end
      L.closeAll()
    end)

    section("tidal", function()
      local Flags = require("src.core.game3.scripting.flags")
      local Space = require("src.core.game3.scripting.space")
      local function var(name) return consts:require("vars", name) end
      Flags.setVar(Space.store, nil, var("VAR_PORTHOLE_STATE"), 3)
      if not teleport("SS_TIDAL_CORRIDOR$", 8, 3) then return end
      if not open() then return end
      tap("a", 90)
      tap("up", 20)
      tap("b", 80)
      L.closeAll()
      L.log("STEP", "under way: porthole state 2, step 70")
      Flags.setVar(Space.store, nil, var("VAR_PORTHOLE_STATE"), 2)
      Flags.setVar(Space.store, nil, var("VAR_CRUISE_STEP_COUNT"), 70)
      if not open() then return end
      tap("a", 90)
      tap("b", 80)
      L.closeAll()
    end)
  end

  L.log("DONE", "rse_screens_pokenav")
  love.event.quit()
end
