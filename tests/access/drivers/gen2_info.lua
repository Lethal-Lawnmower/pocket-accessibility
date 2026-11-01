-- Gen 2 information screens (decision 27): party list and submenu, summary
-- pages and move screen, a switch, TM teaching, a Potion, every Pokédex
-- view, the Pokégear (strip, map, phone call, radio), the fly map, the town
-- map, a house radio, an incoming call and the trainer card.  Logs every
-- screen change; speech shows as `say!:` lines with POKEPORT_ACCESS_TRACE=1.
--
-- The save is given what the screens need directly (a party with an egg,
-- a poisoned mon and mail, Pokédex marks, the Pokégear cards, phone
-- numbers, badges, Unown forms, flypoints), so run it only in a disposable
-- identity, silently:
--   POKEPORT_ACCESS_SILENT=1 POKEPORT_BACKGROUND=1 POKEPORT_ACCESS_TRACE=1
--   POKEPORT_TOUCH=0 POKEPORT_IDENTITY=pocket-access-info-crystal
--   POKEPORT_VERSION=crystal POKEPORT_GAME=crystal
--   POKEPORT_DRIVER=tests/access/drivers/gen2_info.lua lovec .
-- It asserts nothing about wording; it shows what the layer says.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")

  local function className(state)
    if state == nil then return "overworld" end
    local mt = getmetatable(state)
    for name, mod in pairs(package.loaded) do
      if mod == mt and type(name) == "string" then return (name:gsub("^src%.ui%.", "")) end
    end
    return tostring(state.name or state.id or mt)
  end

  local lastTop
  local function watch()
    local name = className(game.stack:top())
    if name ~= lastTop then
      U.log("SCREEN", name)
      lastTop = name
    end
  end
  local function wait(n) for _ = 1, n do U.wait(1) watch() end end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    wait(2)
    game.input.state[button] = false
    wait(frames or 8)
  end
  local function top() return game.stack:top() end
  local function topIs(name) return className(top()) == name end
  local function waitFor(name, limit)
    for _ = 1, limit or 300 do
      if topIs(name) then return true end
      wait(1)
    end
    U.log("FAIL", "never reached", name, "top", className(top()))
    return false
  end
  local function inWorld() return game.world and game.world.map and top() == nil end
  local function waitWorld(limit)
    for _ = 1, limit or 600 do
      if inWorld() then return true end
      wait(1)
    end
    U.log("FAIL", "world never came back; top", className(top()))
    return false
  end
  local function section(name) U.log("SECTION", name) end
  -- press B until `done()` holds; a screen may ignore a press while it
  -- waits on a sound (the summary's second swap sound, for one)
  local function backUntil(done, limit)
    for _ = 1, limit or 12 do
      if done() then return true end
      tap("b", 24)
    end
    if done() then return true end
    U.log("FAIL", "could not back out; top", className(top()))
    return false
  end
  -- mash A through dialogue (and the call script) until the VM is idle and
  -- `done()` holds; never presses A on a screen that is not a TextBox
  local function finishScript(done, limit)
    for _ = 1, limit or 1500 do
      local vm = game.world and game.world.vm
      local busy = vm and vm:running()
      if topIs("src.render.TextBox") or topIs("ChoiceBox") then
        tap("a", 12)
      elseif not busy and done() then
        return true
      else
        wait(1)
      end
    end
    U.log("FAIL", "script did not finish; top", className(top()))
    return false
  end

  -- with POKEPORT_DRIVER the world starts directly
  for _ = 1, 900 do
    if game.world and game.world.map and game.phase == "play" then break end
    wait(1)
  end
  if not (game.world and game.world.map) then U.log("FAIL", "no world") return end
  waitWorld(600)
  local world, save, data = game.world, game.save, game.data
  U.log("MAP", world.map.id, save.version)

  -- ------------------------------------------------------------ save setup
  local Mon = require("src.battle.gen2.Mon")
  local Phone = require("src.core.gen2.Phone")
  local Unown = require("src.core.gen2.Unown")
  local function mon(species, level, fields)
    local m = assert(Mon.new(data, species, level), "no species " .. species)
    for k, v in pairs(fields or {}) do m[k] = v end
    return m
  end
  local pika = mon("PIKACHU", 12, { nickname = "SPARKY",
    item = (data.items and data.items.BERRY) and "BERRY" or nil })
  pika.hp = math.max(1, (pika.maxHp or pika.stats.hp) - 10)
  local egg = mon("TOGEPI", 5, { isEgg = true, nickname = "EGG", eggSteps = 20 })
  local chiko = mon("CHIKORITA", 9, { status = "psn", item = "FLOWER_MAIL" })
  save.party = { pika, egg, chiko }
  save.inventory = save.inventory or {}
  save.inventory.POTION = 3

  save.pokedex = save.pokedex or {}
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.caught = save.pokedex.caught or {}
  for _, s in ipairs({ "CHIKORITA", "PIKACHU", "TOGEPI", "SENTRET", "PIDGEY", "UNOWN" }) do
    save.pokedex.seen[s] = true
  end
  for _, s in ipairs({ "CHIKORITA", "PIKACHU", "SENTRET" }) do save.pokedex.caught[s] = true end
  save.unownDex = { 1, 5 }
  save.engineFlags = save.engineFlags or {}
  save.engineFlags[Unown.ENGINE_UNOWN_DEX] = true

  save.pokegearFlags = { map = true, phone = true, radio = true }
  for name, goldId in pairs({ ENGINE_RADIO_CARD = 0, ENGINE_MAP_CARD = 1, ENGINE_PHONE_CARD = 2 }) do
    world:setEngineFlag(world:engineFlagId(name, goldId), true)
  end
  Phone.addContact(save, 1) -- MOM
  Phone.addContact(save, 4) -- PROF.ELM

  save.player = save.player or {}
  save.player.money = 3000
  save.player.badges = { true, true }
  save.player.kantoBadges = { BOULDER = true }
  save.visitedSpawns = { SPAWN_NEW_BARK = true, SPAWN_CHERRYGROVE = true, SPAWN_VIOLET = true }
  for flag = 64, 66 do save.engineFlags[flag] = true end
  wait(10)

  -- ------------------------------------------------------- party, summary
  section("party")
  game:openStartMenuItem("pokemon")
  if waitFor("gen2.PartyMenu") then
    wait(20)
    for _ = 1, 3 do tap("down") end
    for _ = 1, 3 do tap("up") end
    tap("a")            -- submenu on SPARKY
    tap("down") tap("up")
    tap("a", 40)        -- STATS
    if waitFor("gen2.SummaryMenu") then
      section("summary")
      wait(20)
      tap("right", 12) tap("right", 12) tap("right", 12)  -- pages, wrapping to the first
      tap("down", 20)   -- the egg
      tap("down", 20)   -- CHIKORITA
      tap("up", 12) tap("up", 12)
      tap("right", 12)  -- moves page
      tap("select", 12) -- move screen
      tap("down") tap("a") tap("up") tap("a", 40) -- reorder: move 2 onto 1
      tap("b", 24)      -- back to the page
      backUntil(function() return topIs("gen2.PartyMenu") end)
    end
    section("switch")
    tap("a") tap("down") tap("a", 12)  -- SWITCH
    tap("down") tap("a", 40)           -- with the egg
    backUntil(inWorld)
  end
  waitWorld()

  section("teach")
  -- a move from PIKACHU's own TM list, so one row is ABLE and CHIKORITA's is not
  local pikaDef = data.pokemon.PIKACHU or {}
  local teachMove = (pikaDef.tmhm or {})[1]
  U.log("TEACH", tostring(teachMove))
  Screens.push(game, "Gen2PartyMenu", { prompt = "teach", tmhm = { move = teachMove },
    onCancel = function() game.stack:pop() end, onChoose = function() end })
  if waitFor("gen2.PartyMenu") then
    wait(10)
    tap("down") tap("down")
    backUntil(inWorld)
  end
  waitWorld()

  section("potion")
  game:usePartyItem("POTION")
  if waitFor("gen2.PartyMenu") then
    wait(10)
    local menu = top()
    for _ = 1, 6 do
      if menu.party[menu.index] == pika then break end
      tap("down")
    end
    tap("a", 10)
    wait(150)
    tap("a", 40)
  end
  waitWorld()

  -- -------------------------------------------------------------- Pokédex
  section("pokedex")
  game:openStartMenuItem("pokedex")
  if waitFor("gen2.PokedexMenu") then
    wait(20)
    tap("down") tap("down") tap("up") tap("up")
    tap("a", 20)        -- entry (CHIKORITA leads the NEW order)
    tap("a", 12)        -- PAGE: page 2
    tap("right")        -- AREA
    tap("a", 20)        -- the nest map
    tap("b", 12)
    tap("right") tap("right") -- CRY, PRNT (not pressed: PRNT writes a file)
    tap("b", 12)        -- listing
    tap("select", 12)   -- OPTION
    tap("down") tap("down") tap("down")
    tap("a", 20)        -- UNOWN MODE
    tap("right") tap("left")
    tap("b", 12)        -- back to OPTION
    tap("up")
    tap("b", 12)        -- listing
    tap("start", 12)    -- SEARCH
    tap("right") tap("right") -- TYPE1 FLYING
    tap("down") tap("down")
    tap("a", 20)        -- BEGIN SEARCH!!
    tap("down")
    backUntil(inWorld)  -- close
  end
  waitWorld()

  -- ------------------------------------------------------------- Pokégear
  section("pokegear")
  game:openStartMenuItem("pokegear")
  if waitFor("gen2.Pokegear") then
    local gear = top()
    wait(30)
    tap("right", 15)    -- MAP on the strip
    tap("a", 15)        -- into the card
    tap("up") tap("up") tap("down")
    tap("right", 20)    -- PHONE
    tap("down")         -- PROF.ELM
    tap("a")            -- CALL / CANCEL
    tap("down") tap("up")
    tap("a", 30)        -- CALL
    section("pokegear call")
    finishScript(function() return topIs("gen2.Pokegear") end, 1500)
    if gear.call then tap("a", 20) end -- hang up
    section("pokegear radio")
    tap("right", 30)    -- RADIO
    for _ = 1, 8 do tap("up", 10) end -- 4.5
    wait(900)
    tap("down", 20)
    tap("b", 20)        -- strip
    backUntil(inWorld)  -- close
  end
  waitWorld()

  section("fly map")
  if world:openFlyMap(pika) then
    if waitFor("gen2.Pokegear") then
      wait(20)
      tap("up") tap("up") tap("down")
      backUntil(inWorld)
    end
  else
    U.log("FAIL", "fly map did not open")
  end
  waitWorld()

  section("town map")
  Screens.push(game, "Gen2Pokegear", { townMap = true, currentLandmark = game:currentLandmark() })
  if waitFor("gen2.Pokegear") then
    wait(20)
    tap("up") tap("up") tap("down")
    backUntil(inWorld)
  end
  waitWorld()

  section("house radio")
  Screens.push(game, "Gen2MapRadio", { channel = 1, onDone = function() end })
  if waitFor("gen2.MapRadio") then
    wait(800)
    tap("a", 30)
  end
  waitWorld()

  section("incoming call")
  Phone.queueSpecialCall(save, 5)
  local call = Phone.checkSpecialCall(save, {})
  if call and world:receivePhoneCall(call) then
    finishScript(inWorld, 2000)
  else
    U.log("FAIL", "incoming call did not start")
    Phone.clearSpecialCall(save)
  end
  waitWorld()

  section("trainer card")
  game:openStartMenuItem("status")
  if waitFor("gen2.TrainerCard") then
    wait(20)
    tap("right", 12) tap("right", 12) tap("right", 12)
    backUntil(inWorld)
  end
  waitWorld()
  U.log("DONE")
end
