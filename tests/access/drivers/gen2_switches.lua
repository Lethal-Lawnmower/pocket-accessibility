-- Gen 2 auto-walk through switches (src/access/nav/SwitchWalk.lua): in Goldenrod
-- Underground's switch room, one auto-walk to the warehouse, with A in battles
-- from the harness.  GATE_SAVE=1 continues the disposable profile's save, which
-- must be in the room during the story: without it the harness teleports in with
-- no story flags, where every switch reads as blocked, so that run only shows the
-- refusal.  Harness setup gives a party.  Silent; read the RESULT lines.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U, AutoWalk = L.U, L.AutoWalk
  local SwitchWalk = require("src.access.nav.SwitchWalk")
  if os.getenv("GATE_SAVE") == "1" then
    U.wait(300)
    game:continueGame(require("src.core.SaveData").load(os.getenv("POKEPORT_VERSION") or "crystal"))
    L.settle(1000, false, 10)
  else
    L.settle(2000, true)
    -- the way in: the room's warp from the Underground, as the data lists it
    local entry
    for _, warp in ipairs(game.data.gen2Maps.GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES.warps) do
      if warp.destMap == "GOLDENROD_UNDERGROUND" then entry = entry or warp end
    end
    L.teleport("GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES", entry.x, entry.y + 1, "down")
  end
  L.strongParty()
  game.speedOverride = 4
  U.log("RESULT", "at", L.where())
  local list = {}
  for _, sign in ipairs(L.nav():switchSigns(L.nav():worldForCommand())) do
    list[#list + 1] = sign.label .. "@" .. sign.x .. "," .. sign.y
  end
  U.log("RESULT", "switches", table.concat(list, " ; "))
  local target = L.find(function(i) return tostring(i.label):find("Warehouse", 1, true) end, "warps")
  if not target then U.log("FAIL", "no warehouse warp listed") U.log("DONE") return end
  L.select(target, "warps")
  L.heard()
  AutoWalk.start(L.nav(), game, L.adapter())
  U.log("RESULT", "start", L.heard(), "trying", tostring(SwitchWalk.active()))
  local flips, order, kept = 0, {}, nil
  local function flags()
    local events = game.world.events
    local on = {}
    for i, id in ipairs({ 723, 724, 725, 726 }) do
      if events:get(id) then on[#on + 1] = i == 4 and "E" or tostring(i) end
    end
    return table.concat(on, "+")
  end
  U.log("RESULT", "switches on at start", flags())
  for frame = 1, 60000 do
    if not SwitchWalk.active() and not AutoWalk.active() then break end
    local state = SwitchWalk._state()
    kept = state or kept
    if state and state.flips ~= flips then
      flips = state.flips
      order[#order + 1] = state.sign.label
      U.log("RESULT", "flip", flips, state.sign.label, "now on", flags(), "player", L.where())
    end
    if not L.battleStep() then
      if frame % 15 == 0 and not (state and state.phase == "flipping")
         and (game.stack:top() ~= nil or not game.world:acceptsMenuInput()) then
        L.tap("a", 1)
      else
        U.wait(1)
      end
    end
  end
  if SwitchWalk.active() or AutoWalk.active() then
    SwitchWalk.stop() AutoWalk.stop()
    U.log("FAIL", "still walking at the limit")
  end
  -- what it learned: each switch tried from each state
  if kept then
    local ids, n = {}, 0
    for state in pairs(kept.tried) do n = n + 1 ids[state] = n end
    local lines = {}
    for state, edges in pairs(kept.tried) do
      for label, to in pairs(edges) do
        lines[#lines + 1] = ids[state] .. " " .. label .. " -> " .. (to == "blocked" and "blocked" or tostring(ids[to]))
      end
    end
    table.sort(lines)
    U.log("RESULT", "graph", table.concat(lines, " ; "))
  end
  local spoken = L.heard()
  U.log("RESULT", "ended", L.where(), "flips", flips, table.concat(order, ", "), spoken:sub(-90))
  if not L.where():find("WAREHOUSE", 1, true) then U.log("FAIL", "did not reach the warehouse") end
  U.log("DONE")
end
