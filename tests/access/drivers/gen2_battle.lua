-- Gen 2 battle speech, scripted (decision 27).  Plays real battles on the
-- imported cartridge data and logs every screen change, battle phase and
-- utterance, so the trace shows what the Gen 2 battle presenter says:
--
--   wild    a shiny wild SENTRET: one turn (a status move), the PKMN list
--           opened and cancelled, a move reordered with SELECT, POKé BALLs
--           thrown through the PACK until it is caught, the nickname NO,
--           then a second wild battle that is run from;
--   trainer YOUNGSTER JOEY with two mons: RATTATA one point short of level
--           20 knocks out the first, grows (stats box), learns FOCUS ENERGY
--           over TAIL WHIP (NO, NO, then YES), the SHIFT prompt is taken,
--           a voluntary switch back, the win, and RATTATA's evolution;
--   faint   a level 2 lead against a strong wild mon: "Use next POKéMON?",
--           then a trainer whose ace forces "Choose a POKéMON.";
--   fast    (only when asked for) a wild battle at POKEPORT_BATTLE_FAST
--           logic steps per frame (default 8) with BATTLE SCENE off.
--
-- POKEPORT_BATTLE_SCENES=wild,trainer,faint,fast picks scenes (default: the
-- first three); POKEPORT_BATTLE_WHOLE=1 runs with DIALOGUE SPEECH set to ALL
-- AT ONCE.  Every line the box shows is logged as SHOWN, so the trace can be
-- checked against the spoken lines.
-- Run silently with a disposable identity:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=pocket-access-battle-crystal
--   POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/gen2_battle.lua lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Mon = require("src.battle.gen2.Mon")
  local BattleState = require("src.ui.gen2.BattleState")

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(mt)
  end
  local function top() return game.stack:top() end
  local function isBattle(state) return state ~= nil and getmetatable(state) == BattleState end

  -- The driver runs once per logic step, so it sees every line the box
  -- shows ("SHOWN"), even when several steps pass between two rendered
  -- frames and the screen reader polls only once (fast-forward check).
  local lastTop, lastPhase, lastShown, lastTyper
  local function watch()
    local t = top()
    local name = className(t)
    if name ~= lastTop then U.log("SCREEN", name) lastTop = name end
    local phase = isBattle(t) and t.phase or nil
    if phase ~= lastPhase then
      if phase then U.log("PHASE", phase) end
      lastPhase = phase
    end
    if isBattle(t) then
      local shown = t.message
      if shown ~= lastShown or (shown and t.typedText == nil and lastTyper ~= nil) then
        if shown then U.log("SHOWN", (tostring(shown):gsub("[\n\v\f]", " / "))) end
        lastShown = shown
      end
      lastTyper = t.typedText
    end
  end
  local function wait(n) for _ = 1, n or 1 do U.wait(1) watch() end end

  -- Rendered frames, counted by the screen reader's own once-per-frame poll.
  -- Under fast-forward the driver runs many logic steps per frame; a person
  -- cannot press twice within one frame, so `tap` then waits for two polls
  -- first, or the driver would dismiss lines no person could have missed.
  local ScreenReader = require("src.access.screens.ScreenReader")
  local polls, srUpdate = 0, ScreenReader.update
  ScreenReader.update = function(...) polls = polls + 1 return srUpdate(...) end
  local function humanPace()
    if not game.driverSpeed or game.driverSpeed <= 1 then return end
    local start = polls
    for _ = 1, 2000 do
      if polls >= start + 2 then return end
      wait(1)
    end
  end

  local function tap(button, frames)
    humanPace()
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 8)
  end

  local function build(species, level, opts)
    local mon = Mon.new(game.data, species, level, opts)
    assert(mon, "no species " .. species)
    return mon
  end
  local function nearLevel(mon, level)
    local def = game.data.pokemon[mon.species]
    local growth = Mon.growthFor(game.data, def.growthRate)
    mon.experience = Mon.experienceForLevel(growth, level) - 1
  end
  local function moveSlot(mon, id)
    for i, move in ipairs(mon.moves or {}) do if move.id == id then return i end end
    return 1
  end

  -- cursor helpers on the battle screen
  local function pickMenu(s, index)
    for _ = 1, 6 do
      if s.menuIndex == index then break end
      local col, row = (s.menuIndex - 1) % 2, math.floor((s.menuIndex - 1) / 2)
      local wantCol, wantRow = (index - 1) % 2, math.floor((index - 1) / 2)
      if col < wantCol then tap("right") elseif col > wantCol then tap("left")
      elseif row < wantRow then tap("down") else tap("up") end
    end
    tap("a", 12)
  end
  local function pickMove(s, index)
    for _ = 1, 4 do
      if s.moveIndex == index then break end
      tap("down")
    end
    tap("a", 12)
  end
  local function answer(s, field, yes)
    local want = yes and 1 or 2
    if s[field] ~= want then tap("down") end
    tap("a", 12)
  end
  local function pickParty(menu, index)
    for _ = 1, 8 do
      if menu.index == index then break end
      tap(menu.index < index and "down" or "up")
    end
    tap("a", 12)
    if top() == menu and menu.submenu then tap("a", 12) end -- SWITCH
  end
  local function pickBall(pack, id)
    for _ = 1, 4 do
      if pack:pocket().id == "BALL" then break end
      tap("right", 10)
    end
    for _ = 1, 10 do
      local row = pack.rows and pack.rows[pack.index]
      if row and row.id == id then break end
      tap("down")
    end
    tap("a", 12)
    if top() == pack and pack.submenu then tap("a", 12) end -- USE
  end

  local function onStack(state)
    for _, s in ipairs(game.stack.states or {}) do if s == state then return true end end
    return false
  end
  local Gen2Battle = require("src.access.screens.gen2.Battle")

  -- Plays until the battle screen is gone.  `on[phase](s)` decides at the
  -- battle's choice points; `on[className](top, battle)` on screens above it.
  -- Lines that hold for A are pressed through.  Text boxes after the battle
  -- (an evolved mon's move prompt, the whiteout) are pressed through too,
  -- answering NO, then YES to "Stop learning?".
  local function play(name, on, limit)
    U.log("SCENE", name)
    local seen, healthLogged = nil, false
    on["src.render.TextBox"] = on["src.render.TextBox"] or function() tap("a", 12) end
    on["ChoiceBox"] = on["ChoiceBox"] or function(box)
      local states = game.stack.states
      local below = states[#states - 1]
      local page = below and below.pages and below.pages[#below.pages]
      local question = type(page) == "table" and table.concat(page, " ") or ""
      local want = question:find("Stop learning", 1, true) and 1 or 2
      if box.index ~= want then tap(box.index < want and "down" or "up", 12) else tap("a", 12) end
    end
    for _ = 1, limit or 30000 do
      local t = top()
      if seen and not onStack(seen) and (t == nil or not on[className(t)]) then
        wait(90)
        U.log("SCENE-END", name, "outcome", tostring(seen.battle and seen.battle.outcome))
        return true
      end
      if isBattle(t) then
        seen = t
        if t.phase == "menu" and not healthLogged then
          healthLogged = true
          U.log("HEALTH", Gen2Battle.health(t, "player"), "|", Gen2Battle.health(t, "enemy"))
        end
        local handler = on[t.phase]
        -- a line holding for A (a question before its YES/NO box included),
        -- or the stats box
        if (t.messageTimer or 0) > 0 or t.phase == "stats-box" then
          tap("a", 10)
        elseif handler then
          handler(t)
        else
          wait(1)
        end
      elseif seen and t ~= nil then
        local handler = on[className(t)]
        if handler then handler(t, seen) else wait(1) end
      else
        wait(1)
      end
    end
    U.log("FAIL", "scene did not finish", name, "top", className(top()),
      "phase", tostring(isBattle(top()) and top().phase))
    return false
  end

  local function closeDex(t) tap("a", 20) end
  local function evolution(t) tap("a", 30) end

  local scenes = os.getenv("POKEPORT_BATTLE_SCENES") or "wild,trainer,faint"
  local function wants(scene) return scenes:find(scene, 1, true) ~= nil end

  wait(60)
  assert(game.world and game.world.map, "the world did not start")
  game.save.player = game.save.player or {}
  U.log("MAP", game.world.map.id, "player", tostring(game.save.player.name))
  game.save.pokedex = game.save.pokedex or { seen = {}, caught = {} }
  -- the #DEX, so a new catch shows its entry (CheckReceivedDex)
  game.save.pokedexReceived = true
  -- POKEPORT_BATTLE_WHOLE=1: DIALOGUE SPEECH set to ALL AT ONCE for this run
  -- (decision 26), restored at the end
  local dialogue = game.options and game.options.accessDialogue
  if os.getenv("POKEPORT_BATTLE_WHOLE") == "1" and game.options then
    game.options.accessDialogue = "whole"
    U.log("DIALOGUE", "whole")
  end

  if wants("wild") then
    local lead = build("CYNDAQUIL", 10)
    game.save.party = { lead, build("TOTODILE", 8) }
    game.save.inventory = { POKE_BALL = 30 }
    local wild = build("SENTRET", 5, { shiny = true })
    game.world:startBattle({ wild = wild })
    local turn, opened, swapped = 0, false, false
    play("wild-catch", {
      menu = function(s)
        if not opened then
          opened = true
          return pickMenu(s, 2) -- PKMN, then cancel
        end
        if turn == 0 then return pickMenu(s, 1) end
        return pickMenu(s, 3) -- PACK
      end,
      moves = function(s)
        if not swapped then
          swapped = true
          tap("select") tap("down") tap("select") -- swap moves 1 and 2
          tap("up") tap("select") tap("select")   -- mark and unmark
        end
        turn = turn + 1
        return pickMove(s, moveSlot(s.battle.player, "LEER"))
      end,
      ["ask-nickname"] = function(s) return answer(s, "nicknameIndex", false) end,
      ["gen2.PartyMenu"] = function(t) tap("b", 20) end,
      ["gen2.PackMenu"] = function(t) pickBall(t, "POKE_BALL") end,
      ["gen2.PokedexMenu"] = closeDex,
    })

    wait(60)
    game.world:startBattle({ wild = build("PIDGEY", 3) })
    play("wild-run", {
      menu = function(s) return pickMenu(s, 4) end,
    })
  end

  if wants("trainer") then
    local lead = build("RATTATA", 19)
    nearLevel(lead, 20)
    local second = build("CYNDAQUIL", 12)
    game.save.party = { lead, second }
    local foes = { build("SENTRET", 3), build("PIDGEY", 4) }
    game.world:startBattle({ trainer = { class = "YOUNGSTER", classId = "YOUNGSTER",
      className = "YOUNGSTER", name = "YOUNGSTER JOEY", party = foes,
      winText = "Wow, {PLAYER}!\fYou're strong." } })
    local forgetAsks, switchedBack = 0, false
    play("trainer", {
      menu = function(s)
        if s.battle.player == second and not switchedBack then
          switchedBack = true
          return pickMenu(s, 2) -- PKMN: switch back to RATTATA
        end
        return pickMenu(s, 1)
      end,
      moves = function(s) return pickMove(s, 1) end,
      ["ask-forget"] = function(s)
        forgetAsks = forgetAsks + 1
        return answer(s, "forgetChoice", forgetAsks > 1)
      end,
      ["stop-learning"] = function(s) return answer(s, "forgetChoice", false) end,
      ["choose-forget"] = function(s)
        local slot = moveSlot(game.save.party[1], "TAIL_WHIP")
        for _ = 1, 4 do
          if s.forgetIndex == slot then break end
          tap("down")
        end
        tap("a", 12)
      end,
      ["ask-shift"] = function(s) return answer(s, "shiftIndex", true) end,
      ["gen2.PartyMenu"] = function(t, battle)
        local want = battle.battle.player == lead and 2 or 1
        pickParty(t, want)
      end,
      ["gen2.EvolutionAnim"] = evolution,
    })
  end

  if wants("faint") then
    game.save.party = { build("SENTRET", 2), build("TOTODILE", 40) }
    game.world:startBattle({ wild = build("GEODUDE", 25) })
    play("faint-wild", {
      menu = function(s) return pickMenu(s, 1) end,
      moves = function(s) return pickMove(s, moveSlot(s.battle.player, "WATER_GUN")) end,
      ["ask-next-mon"] = function(s) return answer(s, "nextMonIndex", true) end,
      ["gen2.PartyMenu"] = function(t) pickParty(t, 2) end,
    })
    wait(60)
    game.save.party = { build("SENTRET", 2), build("CYNDAQUIL", 40) }
    for _, mon in ipairs(game.save.party) do mon.hp = mon.maxHp end
    game.world:startBattle({ trainer = { class = "YOUNGSTER", classId = "YOUNGSTER",
      className = "YOUNGSTER", name = "YOUNGSTER JOEY", party = { build("ONIX", 25) },
      winText = "Aww." } })
    play("faint-trainer", {
      menu = function(s) return pickMenu(s, 1) end,
      moves = function(s) return pickMove(s, 1) end,
      ["gen2.PartyMenu"] = function(t) pickParty(t, 2) end,
      ["gen2.EvolutionAnim"] = evolution,
    })
  end

  -- Fast-forward: N logic steps per rendered frame (the screen reader polls
  -- once per frame), BATTLE SCENE off so move lines advance as soon as they
  -- are typed.  Compare the SHOWN lines with the spoken ones.
  if wants("fast") then
    local speed = tonumber(os.getenv("POKEPORT_BATTLE_FAST")) or 8
    local scene = game.options and game.options.battleScene
    if game.options then game.options.battleScene = false end
    game.save.party = { build("CYNDAQUIL", 20) }
    game.world:startBattle({ wild = build("GEODUDE", 12) })
    game.driverSpeed = speed
    U.log("SPEED", speed)
    play("fast", {
      menu = function(s) return pickMenu(s, 1) end,
      moves = function(s) return pickMove(s, moveSlot(s.battle.player, "EMBER")) end,
    }, 60000)
    game.driverSpeed = nil
    if game.options then game.options.battleScene = scene end
  end

  wait(30)
  if game.options then game.options.accessDialogue = dialogue end
  ScreenReader.update = srUpdate
  U.log("DONE")
end
