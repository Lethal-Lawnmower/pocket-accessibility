-- Guided navigation to every warp and connection of every Gen 3 map, entered at its first
-- warp with the harness party, badges and Flash. Logs each refusal (REFUSED) with what the
-- journey planner says for the same goals. SWEEP_MAPS limits it, SWEEP_FROM resumes it.
-- Silent and isolated: ISOLATED_DRIVER=tests/access/drivers/gen3_guided_sweep.lua
return function(game)
  local version = os.getenv("POKEPORT_VERSION")
  local isHoenn = version == "emerald" or version == "ruby" or version == "sapphire"
  local L = dofile(isHoenn and "tests/access/drivers/rse_nav_lib.lua" or "tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then U.log("FAIL", "boot") return end
  if isHoenn then
    pcall(L.giveParty)
  else
    -- the Kanto harness takes its party spelt out (no default): without one every water
    -- edge was refused for want of Surf
    pcall(L.giveParty, 9, 90, { "SURF", "STRENGTH", "CUT" }, { "SURF", "STRENGTH", "CUT", "WATERFALL", "ROCK_SMASH", "FLASH" })
  end
  local GameData = require("src.access.nav.gen3.GameData")
  local flash = GameData.flag("FLAG_SYS_USE_FLASH")
  local ids = L.mapIds and L.mapIds() or {}
  if #ids == 0 then
    -- FireRed and LeafGreen: every map of the cartridge, by id
    local prefix = GameData.mapPrefix()
    for id in pairs(game.data.maps) do
      if type(id) == "string" and id:sub(1, #prefix) == prefix then ids[#ids + 1] = id end
    end
    table.sort(ids)
  end
  local only = os.getenv("SWEEP_MAPS")
  local counts = { said = 0, refused = 0, bare = 0 }
  for _, mapId in ipairs(ids) do
    local def = game.data.maps[mapId]
    local warp = def and def.warps and def.warps[1]
    if warp and not mapId:find("BATTLE_FRONTIER", 1, true) and not mapId:find("TRAINER_HILL", 1, true) and not mapId:find("EVER_GRANDE_CITY_[A-Z]*S_ROOM") and not mapId:find("BATTLE_TENT", 1, true) and not mapId:find("HALL_OF_FAME", 1, true) and not mapId:find("CONTEST", 1, true) and (not os.getenv("SWEEP_FROM") or mapId > os.getenv("SWEEP_FROM")) and (not only or only:find(mapId, 1, true)) then
      local okT = pcall(L.teleport, mapId, warp.x, warp.y)
      U.wait(20)
      -- a script on arrival (a tent's greeting) holds a dialog: close it
      for _ = 1, 40 do
        local nav0 = L.nav()
        local okW, w = pcall(nav0.worldForCommand, nav0)
        if okW and w then break end
        L.tap("b", 4)
      end
      if okT and L.where():find(mapId, 1, true) then
        pcall(function() package.loaded["src.core.game3.field_view"].setFlashLevel(0) end)
        if flash then L.setFlag(flash) end
        local nav = L.nav()
        local okC, snap = pcall(nav.captureWorld, nav, "all")
        if not (okC and snap) then U.log("NOCAPTURE", mapId) end
        for _, item in ipairs(okC and snap and snap.browse or {}) do
          if item.type == "warp" or item.type == "connection" then
            nav.browseFilter, nav.browseSelectionId = "all", item.id
            L.heard()
            pcall(nav.describeRouteToSelected, nav)
            U.wait(25)
            local said = L.heard()
            if nav.activeNavigation then pcall(nav.stopNavigation, nav, false) end
            pcall(nav.cancelPendingRoute, nav, false)
            counts.said = counts.said + 1
            local first = said:match("^[^|]*") or ""
            if first:find("Cannot reach", 1, true) or first:find("No path", 1, true) or first:find("No route", 1, true) then
              counts.refused = counts.refused + 1
              local _, goals = nav:selectedRouteGoals()
              local okJ, leg, why = pcall(nav.regionalNextLeg, nav,
                { targetMapId = mapId, targetGoals = goals or {} })
              local journey = okJ and (leg and "journey ok" or tostring(why)) or "journey error"
              if first:find("Cannot reach yet", 1, true) then counts.bare = counts.bare + 1 end
              U.log("REFUSED", mapId, tostring(item.label), tostring(item.description), "=>", said, "||", journey)
            end
            U.wait(2)
            L.heard()
          end
        end
      end
    end
  end
  U.log("RESULT", "guided sweep", "asked", counts.said, "refused", counts.refused, "bare", counts.bare)
end
