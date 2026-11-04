-- The NPCs and Objects categories on real maps of each generation (decision
-- 35): logs both lists where people, Pokemon and item balls share a room.
-- Silent and isolated, with POKEPORT_VERSION naming the game:
--   POKEPORT_DRIVER=tests/access/drivers/isolated.lua
--   ISOLATED_DRIVER=tests/access/drivers/npc_category.lua
return function(game)
  local version = os.getenv("POKEPORT_VERSION") or "red"
  local isGen3 = version == "firered" or version == "leafgreen"
  local L = dofile(isGen3 and "tests/access/drivers/gen3_nav_lib.lua"
    or "tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  local isGen1 = version == "red" or version == "blue" or version == "yellow"
  local started
  if isGen3 then started = L.boot()
  elseif isGen1 then started = U.newGame(game)
  else started = L.settle(2000, true) end
  if not started then U.log("FAIL", "never reached the free world") return end
  U.wait(30)
  local rooms = {
    firered = { { "FR_MT_MOON_1F", 14, 22 }, { "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", 7, 8 }, { "FR_VIRIDIAN_CITY_MART", 3, 6 } },
    red = { { "MT_MOON_1F", 14, 35 }, { "OAKS_LAB", 5, 10 } },
    blue = { { "MT_MOON_1F", 14, 35 }, { "OAKS_LAB", 5, 10 } },
    yellow = { { "MT_MOON_1F", 14, 35 }, { "OAKS_LAB", 5, 10 } },
    crystal = { { "UNION_CAVE_1F", 5, 19 }, { "CHERRYGROVE_POKECENTER_1F", 4, 6 } },
    gold = { { "UNION_CAVE_1F", 5, 19 }, { "CHERRYGROVE_POKECENTER_1F", 4, 6 } },
    silver = { { "UNION_CAVE_1F", 5, 19 }, { "CHERRYGROVE_POKECENTER_1F", 4, 6 } },
  }
  for _, room in ipairs(rooms[version] or {}) do
    if isGen1 then U.teleport(game, room[1], room[2], room[3], "up") else L.teleport(room[1], room[2], room[3]) end
    U.wait(60)
    U.log("RESULT", "room", room[1], isGen1 and "" or L.where())
    for _, filter in ipairs({ "npcs", "objects" }) do
      U.log("RESULT", "category", filter)
      for _, item in ipairs(L.browse(filter)) do U.log("ITEM", filter, tostring(item.label), tostring(item.type)) end
    end
    if isGen3 then
      local misc, all = L.browse("misc"), L.browse("all")
      for _, item in ipairs(misc) do U.log("ITEM", "misc", tostring(item.label), tostring(item.type)) end
      local leaked = 0
      for _, item in ipairs(all) do if item.browseType == "misc" then leaked = leaked + 1 end end
      U.log("RESULT", "misc", #misc, "in all", leaked)
      if misc[1] then
        local said = L.walkTo(misc[1], { filter = "misc", answer = "a", limit = 4000 })
        U.log("RESULT", "walked to", tostring(misc[1].label), L.where(), tostring(said))
      end
    end
  end
  U.log("RESULT", "npc_category done")
end
