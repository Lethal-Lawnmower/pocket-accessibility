-- Scripted run for the ACCESSIBILITY options page (decision 26): open the
-- game's OPTIONS, open the page, set AUTO-WALK SPEED and DIALOGUE SPEECH with
-- the game's own keys, then auto-walk and check the logic speed while
-- walking and after, and talk to Mom with dialogue all at once.  Run
-- silently (POKEPORT_ACCESS_SILENT=1); read the RESULT lines and the trace.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Speech = require("src.access.Speech")
  local AutoWalk = require("src.access.nav.AutoWalk")
  if not U.newGame(game) then U.log("FAIL", "never reached the overworld") return end
  game.speedOverride = nil
  -- start from the defaults; the identity keeps options between runs
  game.save.options.accessAutoWalkSpeed, game.save.options.accessDialogue = nil, nil

  local said = {}
  local say = Speech.say
  Speech.say = function(text, opts) said[#said + 1] = tostring(text) return say(text, opts) end
  local function heard() local s = table.concat(said, " | ") said = {} return s end
  local function nav() return package.loaded["src.access.nav"].coordinator() end

  -- OPTIONS as the start menu opens it
  local OptionsMenu = require("src.ui.OptionsMenu")
  game.stack:push(OptionsMenu.new(game))
  U.wait(10)
  U.log("RESULT", "options opened =>", heard())
  U.tap(game, "a") U.wait(10)
  U.log("RESULT", "accessibility page =>", heard())
  U.tap(game, "left") U.wait(6) -- GAME SPEED wraps to the fastest level
  U.log("RESULT", "speed left =>", heard(), "stored", tostring(game.save.options.accessAutoWalkSpeed))
  U.tap(game, "down") U.wait(6)
  U.tap(game, "right") U.wait(6)
  U.log("RESULT", "dialogue =>", heard(), "stored", tostring(game.save.options.accessDialogue))
  U.tap(game, "b") U.wait(6)
  U.tap(game, "b") U.wait(10)
  U.log("RESULT", "closed =>", heard(), "top is map", tostring(game.stack:top() == game.overworld))

  -- auto-walk downstairs (Red's room has one warp)
  local snap = nav():captureWorld("all")
  local target
  for _, item in ipairs(snap.browse or {}) do
    if item.type == "warp" then target = item break end
  end
  nav().browseFilter, nav().browseSelectionId = "all", target and target.id
  AutoWalk.start(nav(), game)
  local seen = {}
  for _ = 1, 600 do
    if not AutoWalk.active() then break end
    if AutoWalk.walking() then seen[game:logicSpeed()] = true end
    U.wait(1)
  end
  local speeds = {}
  for s in pairs(seen) do speeds[#speeds + 1] = s end
  table.sort(speeds)
  for _ = 1, 120 do if not game.overworld.transitioning then break end U.wait(1) end
  U.wait(30)
  U.log("RESULT", "walk =>", heard(), "logic speeds while walking", table.concat(speeds, ","),
    "after", game:logicSpeed(), "override", tostring(game.speedOverride),
    "map", tostring(game.overworld.map.def and game.overworld.map.def.id))

  -- talk to Mom with ALL AT ONCE (SETTINGS_MOM_SPEED=game walks at the game speed)
  if os.getenv("SETTINGS_MOM_SPEED") == "game" then game.save.options.accessAutoWalkSpeed = nil end
  local p0 = game.overworld.player
  U.log("START", p0.cellX .. "," .. p0.cellY, tostring(p0.facing))
  snap = nav():captureWorld("all")
  for _, item in ipairs(snap.browse or {}) do
    U.log("ITEM", tostring(item.label))
    if tostring(item.label):find("Mom", 1, true) then target = item end
  end
  nav().browseFilter, nav().browseSelectionId = "all", target.id
  AutoWalk.start(nav(), game)
  do
    local w = AutoWalk._state()
    local s = {}
    for i, st in ipairs(w and w.steps or {}) do s[#s + 1] = st.fromX .. "," .. st.fromY .. ">" .. st.direction end
    U.log("STEPS", table.concat(s, " "))
  end
  for f = 1, 600 do
    if not AutoWalk.active() then break end
    if f <= 12 then
      local w = AutoWalk._state()
      U.log("F", f, p0.cellX .. "," .. p0.cellY, tostring(p0.facing), "moving", tostring(p0.moving), "held", tostring(w and w.held), "speed", game:logicSpeed(), "map", tostring(game.overworld.map.def.id), "trans", tostring(game.overworld.transitioning))
    end
    U.wait(1)
  end
  local arrival = heard()
  U.log("RESULT", "to", tostring(target.label), "=>", arrival)
  local face = arrival:match("Face (%a+) and interact")
  if face then U.tap(game, face) U.wait(10) end
  heard()
  U.tap(game, "a") U.wait(40)
  U.log("RESULT", "mom first frame =>", heard())
  for _ = 1, 30 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a") U.wait(10)
  end
  U.log("RESULT", "mom after presses =>", heard())
  Speech.say = say
  U.log("DONE")
end
