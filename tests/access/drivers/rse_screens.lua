-- Hoenn screens (Emerald, Ruby, Sapphire): starts a new game directly, gives
-- a party and items through upstream's own Party.giveMon and Bag.add, opens
-- the start menu by START, and every entry by key press, then the screens
-- field scripts open.  Asserts nothing; logs SCREEN, SAID, BAD.  RSE_ONLY
-- (a comma list of section names) limits a run.
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/rse_screens.lua
--   POKEPORT_VERSION=emerald POKEPORT_GAME=emerald POKEPORT_IDENTITY=<disposable>
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
  local Bag = require("src.core.game3.bag")
  local C = require("src.core.game3.constants")
  local Stack = require("src.ui.game3.stack")
  local session = L.session()
  local consts = C.active(session)
  local function item(...)
    for _, name in ipairs({ ... }) do
      local ok, id = pcall(function() return consts:require("items", name) end)
      if ok then return id end
    end
    error("no item " .. tostring((...)))
  end

  section("setup", function() end)
  do
    session.party = {}
    local _, _, lead = Party.giveMon(session, consts:require("species", "SPECIES_MUDKIP"), 12)
    Party.giveMon(session, consts:require("species", "SPECIES_ZIGZAGOON"), 5, "ZIGGY")
    local _, _, third = Party.giveMon(session, consts:require("species", "SPECIES_RALTS"), 7)
    if third then third.item = item("ITEM_POTION") end
    Bag.add(session.bag, item("ITEM_POTION"), 3)
    Bag.add(session.bag, item("ITEM_ANTIDOTE"), 1)
    Bag.add(session.bag, item("ITEM_POKE_BALL"), 5)
    Bag.add(session.bag, item("ITEM_TM06", "ITEM_TM06_TOXIC"), 1)
    Bag.add(session.bag, item("ITEM_HM01", "ITEM_HM01_CUT"), 1)
    Bag.add(session.bag, item("ITEM_CHERI_BERRY"), 2)
    Bag.add(session.bag, item("ITEM_MACH_BIKE"), 1)
    session.money = 5000
    L.flag(session, "FLAG_SYS_POKEMON_GET")
    L.flag(session, "FLAG_SYS_POKEDEX_GET")
    L.flag(session, "FLAG_SYS_POKENAV_GET")
    L.flag(session, "FLAG_SYS_B_DASH")
    L.log("PARTY", #session.party)
  end

  local function startMenu()
    L.closeAll()
    tap("start", 25)
    return L.top() == "start"
  end

  local function startTo(id)
    if not startMenu() then L.log("NOSTART", tostring(L.top())) return false end
    local StartMenu = require("src.ui.game3.start_menu")
    for _ = 1, 12 do
      local entry = StartMenu.ENTRIES[StartMenu.cursor]
      if entry and entry.id == id then return true end
      tap("down", 12)
    end
    L.log("NOENTRY", id)
    return false
  end

  section("start", function()
    startMenu()
    taps({ "down", "down", "down" }, 14)
    tap("b", 25)
  end)

  section("bag", function()
    if not startTo("bag") then return end
    tap("a", 60)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "up" }, 15)
    tap("a", 25)                        -- action menu on the first item
    taps({ "right", "down", "left" }, 15)
    tap("b", 25)
    for _ = 1, 4 do
      tap("right", 40)                  -- next pockets
      tap("down", 15)
    end
    tap("b", 60)
    L.closeAll()
  end)

  section("party", function()
    if not startTo("pokemon") then return end
    tap("a", 60)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up" }, 15)
    tap("a", 25)                        -- action menu
    taps({ "down", "down", "up", "up" }, 15)
    tap("a", 60)                        -- SUMMARY
    L.log("TOP", tostring(L.top()))
    taps({ "right", "right", "right" }, 40)
    tap("a", 40)                        -- move detail
    taps({ "down", "down" }, 15)
    tap("b", 40)
    tap("left", 30)
    tap("down", 40)                     -- next Pokémon
    tap("b", 60)
    tap("b", 40)
    L.closeAll()
  end)

  section("pokedex", function()
    if not startTo("pokedex") then return end
    tap("a", 90)
    L.log("TOP", tostring(L.top()))
    wait(60)
    local Dex = require("src.ui.game3.rse.pokedex")
    local view = Dex.active()
    tap("start", 30)                    -- the list's menu
    taps({ "down", "down", "up", "up" }, 15)
    tap("b", 30)
    -- down to the first seen row (Hoenn lists every earlier number)
    for _ = 1, 40 do
      local it = view.list.items[view.selected]
      if it and it.seen then break end
      tap("down", 25)
    end
    tap("a", 90)                        -- entry
    wait(60)
    taps({ "right", "right", "left", "left" }, 20)
    tap("a", 120)                       -- AREA (Ruby: next text page)
    wait(40)
    tap("right", 120)                   -- CRY
    wait(40)
    tap("b", 120)                       -- back to the entry
    wait(30)
    tap("b", 90)                        -- list
    wait(30)
    tap("select", 120)                  -- search
    wait(40)
    taps({ "right", "left" }, 20)
    tap("a", 30)                        -- search rows
    taps({ "down", "down" }, 20)
    tap("a", 30)                        -- a parameter box
    taps({ "down", "down", "up" }, 20)
    tap("b", 30)
    tap("b", 30)
    tap("b", 90)
    wait(40)
    tap("b", 90)
    L.closeAll()
  end)

  section("trainer", function()
    if not startTo("trainer") then return end
    tap("a", 60)
    L.log("TOP", tostring(L.top()))
    tap("a", 60)
    tap("a", 60)
    tap("b", 60)
    L.closeAll()
  end)

  section("save", function()
    if not startTo("save") then return end
    tap("a", 60)
    L.log("TOP", tostring(L.top()))
    tap("down", 15)
    tap("up", 15)
    tap("b", 60)
    L.closeAll()
  end)

  section("option", function()
    if not startTo("option") then return end
    tap("a", 60)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "right", "left", "up" }, 15)
    tap("a", 25)
    taps({ "down", "right", "left" }, 15)
    tap("b", 25)
    tap("b", 60)
    L.closeAll()
  end)

  section("shop", function()
    require("src.ui.game3.shop_menu").show({ session = session,
      items = { item("ITEM_POTION"), item("ITEM_ANTIDOTE"), item("ITEM_POKE_BALL") } })
    wait(40)
    L.log("TOP", tostring(L.top()))
    taps({ "down", "up" }, 15)
    tap("a", 70)                        -- BUY
    taps({ "down", "up" }, 15)
    tap("a", 30)                        -- quantity
    tap("up", 15)
    tap("a", 30)                        -- confirm
    tap("down", 15)
    tap("up", 15)
    tap("a", 40)                        -- YES
    tap("a", 30)
    tap("b", 70)                        -- back to the root
    tap("down", 15)                     -- SELL
    tap("a", 90)
    tap("a", 30)                        -- sell the first row
    tap("up", 15)
    tap("a", 25)
    tap("a", 40)
    tap("a", 30)
    tap("b", 70)                        -- close the bag
    tap("b", 40)
    L.closeAll()
  end)

  section("pc", function()
    require("src.ui.game3.hud").openPc(game, session)
    wait(40)
    L.log("TOP", tostring(L.top()))
    L.talk(4)
    wait(20)
    taps({ "down", "up" }, 15)
    tap("down", 15)
    tap("a", 30)                        -- player's PC
    L.log("PCMODE", tostring(require("src.ui.game3.pc_menu").mode))
    taps({ "down", "up" }, 15)
    tap("a", 30)                        -- ITEM STORAGE
    taps({ "down", "up" }, 15)
    tap("down", 15)
    tap("a", 90)                        -- DEPOSIT: the bag at the item PC
    tap("a", 30)                        -- deposit the first row
    tap("up", 15)
    tap("a", 30)
    tap("a", 40)
    tap("b", 70)
    wait(30)
    tap("up", 15)
    tap("a", 60)                        -- WITHDRAW: item storage
    L.log("TOP", tostring(L.top()))
    tap("down", 15)
    tap("up", 15)
    tap("a", 30)
    tap("up", 15)
    tap("a", 30)
    tap("a", 30)
    tap("b", 40)
    wait(30)
    tap("b", 30)
    tap("b", 30)
    wait(30)
    tap("up", 15)
    tap("a", 30)                        -- someone's PC
    L.log("PCMODE", tostring(require("src.ui.game3.pc_menu").mode))
    taps({ "down", "up" }, 15)
    tap("down", 15)
    tap("a", 90)                        -- DEPOSIT or WITHDRAW
    L.log("TOP", tostring(L.top()))
    taps({ "down", "down", "up" }, 20)
    tap("a", 30)                        -- action menu
    tap("down", 20)
    tap("b", 30)
    tap("b", 90)
    wait(30)
    L.closeAll()
  end)

  section("starter", function()
    local Choose = require("src.ui.game3.rse.starter_choose")
    local chosen
    Choose.open({ onDone = function(result) chosen = result end })
    wait(80)
    L.log("TOP", tostring(L.top()))
    taps({ "left", "right", "right" }, 30)
    tap("a", 120)
    tap("down", 20)
    tap("a", 60)                        -- NO
    wait(30)
    tap("a", 120)
    tap("a", 60)                        -- YES
    L.log("CHOSEN", tostring(chosen))
    wait(40)
    L.closeAll()
  end)

  section("clock", function()
    local Clock = require("src.ui.game3.rse.wall_clock")
    Clock.open({ mode = "set", session = session, onDone = function() end })
    wait(80)
    L.log("TOP", tostring(L.top()))
    taps({ "right", "right", "left" }, 10)
    tap("a", 60)
    tap("down", 20)
    tap("a", 60)                        -- NO
    wait(30)
    tap("a", 60)
    tap("a", 60)                        -- YES
    wait(60)
    Clock.open({ mode = "view", session = session, onDone = function() end })
    wait(80)
    tap("a", 90)
    L.closeAll()
  end)

  section("map", function()
    local Map = require("src.ui.game3.rse.region_map")
    Map.show({ session = session, mode = "wall" })
    wait(90)
    L.log("TOP", tostring(L.top()))
    taps({ "up", "up", "up", "right", "right" }, 18)
    tap("b", 70)
    L.closeAll()
    Map.show({ session = session, mode = "fly" })
    wait(90)
    taps({ "up", "up", "up", "right", "right" }, 18)
    tap("b", 70)
    L.closeAll()
  end)

  section("pokenav", function()
    if not startTo("pokenav") then return end
    tap("a", 90)
    L.log("TOP", tostring(L.top()))
    wait(100)
    taps({ "down", "down", "down", "up" }, 20)
    tap("b", 60)
    L.closeAll()
  end)

  L.log("DONE", "rse_screens")
  love.event.quit()
end
