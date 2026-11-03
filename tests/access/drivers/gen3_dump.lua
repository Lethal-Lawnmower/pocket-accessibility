-- Prints FireRed floors as text, for reading a puzzle or a refusal: GEN3_DUMP_MAPS is a
-- comma-separated list of map ids (without FR_), GEN3_DUMP_FLAGS flags to set first
-- (decimal).  Each floor as its load script would draw it, with the game's flags.
--   # wall   . floor   ~ water   W warp   H hole   P pressure switch   B boulder
--   o other object   S sign   < > ^ v ledge or forced move   % other behaviour
-- Then its warps, signs and objects.  Silent; harness setup only.
return function(game)
  local L = dofile("tests/access/drivers/gen3_nav_lib.lua").new(game)
  local U = L.U
  if not L.boot() then return end
  for flag in (os.getenv("GEN3_DUMP_FLAGS") or ""):gmatch("%d+") do L.setFlag(tonumber(flag)) end
  L.giveParty(9, 90, { "SURF", "STRENGTH", "CUT" }, { "SURF", "STRENGTH", "CUT", "WATERFALL", "FLASH" })
  local nav = L.nav()
  local Scripts = require("src.access.nav.gen3.Scripts")
  local Terrain = require("src.access.nav.gen3.TerrainSemantics")
  for name in (os.getenv("GEN3_DUMP_MAPS") or ""):gmatch("[^,]+") do
    local id = "FR_" .. name
    local world = nav:regionalStaticWorld(id, { x = 0, y = 0 })
    if not world then
      U.log("DUMP", id, "no view")
    else
      local map, def = world.map, game.data.maps[id]
      local marks = {}
      for _, event in ipairs(def.bgEvents or {}) do
        if type(event.x) == "number" then marks[event.y * 1000 + event.x] = "S" end
      end
      for _, actor in ipairs(world.npcs) do
        marks[actor.cellY * 1000 + actor.cellX] = Terrain.isBoulder(actor) and "B" or "o"
      end
      U.log("DUMP", id, map.widthCells .. "x" .. map.heightCells)
      for y = 0, map.heightCells - 1 do
        local row = {}
        for x = 0, map.widthCells - 1 do
          local ch = "#"
          local beh = map:behavior(x, y)
          if map:warpAt(x, y) then ch = "W"
          elseif beh == 0x66 then ch = "H"
          elseif beh == 0x20 then ch = "P"
          elseif map:isWater(x, y) then ch = "~"
          elseif map:ledgeFacings(x, y) then ch = "%"
          elseif map:walkableColl(x, y) and not map:overrideBlocked(x, y) then ch = "."
          end
          if marks[y * 1000 + x] and (ch == "." or ch == "#" or ch == "P") then ch = marks[y * 1000 + x] end
          row[#row + 1] = ch
        end
        U.log("ROW", string.format("%3d", y), table.concat(row))
      end
      for index, warp in ipairs(def.warps or {}) do
        local active = map:warpAt(warp.x, warp.y)
        local dest, dx, dy = map:warpDestination(warp)
        U.log("WARP", index, warp.x .. "," .. warp.y, tostring(map:warpKind(warp.x, warp.y)),
          active and "active" or "off", tostring(dest), tostring(dx) .. "," .. tostring(dy))
      end
      for _, event in ipairs(def.bgEvents or {}) do
        U.log("SIGN", tostring(event.type), tostring(event.x) .. "," .. tostring(event.y), tostring(event.scriptKey),
          tostring((Scripts.signRole(event.scriptKey))), tostring(Scripts.signWords(event.scriptKey)))
      end
      for _, actor in ipairs(world.npcs) do
        U.log("OBJECT", actor.cellX .. "," .. actor.cellY, "gfx", tostring(actor.graphicsId), "elev",
          tostring(actor.currentElevation), tostring(actor.def and actor.def.scriptKey))
      end
    end
    U.wait(1)
  end
  U.log("DONE")
end
