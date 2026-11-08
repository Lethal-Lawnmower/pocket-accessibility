-- luajit launcher/mods/crystal_randomizer/tests/starters_test.lua   (from the repository root)
--
-- Runs on a small synthetic dataset shaped like Crystal's extracted tables.
-- With CRYSTAL_RANDOMIZER_CACHE set to an imported cache's data/generated
-- folder (for example %APPDATA%/LOVE/<identity>/crystal/data/generated), it
-- also runs against the real Crystal pokemon, type chart, scripts and text.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Starters = dofile("launcher/mods/crystal_randomizer/modules/starters.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

-- UTF-8 characters, not bytes: "é" is one character on Oak's screen.
local function chars(s) return #(s:gsub("[\128-\191]", "")) end

-- ------------------------------------------------------------ synthetic data
local function stats(total)
  local each = math.floor(total / 6)
  return { hp = each, attack = each, defense = each, speed = each, specialAttack = each,
    specialDefense = total - 5 * each }
end

local function mon(id, index, types, evolutions, opts)
  opts = opts or {}
  return { id = id, name = opts.name or id, index = index, types = types, baseStats = stats(opts.bst or 400),
    evolutions = evolutions or {}, eggGroups = opts.groups or { "EGG_GROUND", "EGG_GROUND" },
    genderRatio = opts.gender or 127 }
end

local LEGEND = { groups = { "EGG_NONE", "EGG_NONE" }, gender = 255, bst = 600 }

local function syntheticPokemon()
  local P = {}
  local function add(m) P[m.id] = m end
  add(mon("BULBASAUR", 1, { "GRASS", "POISON" }, { { into = "IVYSAUR" } }, { bst = 318 }))
  add(mon("IVYSAUR", 2, { "GRASS", "POISON" }, { { into = "VENUSAUR" } }))
  add(mon("VENUSAUR", 3, { "GRASS", "POISON" }, {}, { bst = 525 }))
  add(mon("CHARMANDER", 4, { "FIRE", "FIRE" }, { { into = "CHARMELEON" } }, { bst = 309 }))
  add(mon("CHARMELEON", 5, { "FIRE", "FIRE" }, { { into = "CHARIZARD" } }))
  add(mon("CHARIZARD", 6, { "FIRE", "FLYING" }, {}, { bst = 534 }))
  add(mon("SQUIRTLE", 7, { "WATER", "WATER" }, { { into = "WARTORTLE" } }, { bst = 314 }))
  add(mon("WARTORTLE", 8, { "WATER", "WATER" }, { { into = "BLASTOISE" } }))
  add(mon("BLASTOISE", 9, { "WATER", "WATER" }, {}, { bst = 530 }))
  add(mon("PIDGEY", 16, { "NORMAL", "FLYING" }, { { into = "PIDGEOTTO" } }))
  add(mon("PIDGEOTTO", 17, { "NORMAL", "FLYING" }))
  add(mon("ABRA", 63, { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }))
  add(mon("GEODUDE", 74, { "ROCK", "GROUND" }, { { into = "GRAVELER" } }))
  add(mon("GRAVELER", 75, { "ROCK", "GROUND" }, { { into = "GOLEM" } }))
  add(mon("GOLEM", 76, { "ROCK", "GROUND" }))
  add(mon("EEVEE", 133, { "NORMAL", "NORMAL" }))
  add(mon("MEWTWO", 150, { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, {}, LEGEND))
  add(mon("CHIKORITA", 152, { "GRASS", "GRASS" }))
  add(mon("CYNDAQUIL", 155, { "FIRE", "FIRE" }))
  add(mon("TOTODILE", 158, { "WATER", "WATER" }))
  add(mon("TOGEPI", 175, { "NORMAL", "NORMAL" }))
  add(mon("SUDOWOODO", 185, { "ROCK", "ROCK" }))
  add(mon("UNOWN", 201, { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, {},
    { groups = { "EGG_NONE", "EGG_NONE" }, gender = 255, bst = 200 }))
  add(mon("TYROGUE", 236, { "FIGHTING", "FIGHTING" }))
  add(mon("SUICUNE", 245, { "WATER", "WATER" }, {}, LEGEND))
  add(mon("LUGIA", 249, { "PSYCHIC_TYPE", "FLYING" }, {}, LEGEND))
  add(mon("HO_OH", 250, { "FIRE", "FLYING" }, {}, { name = "HO-OH", groups = LEGEND.groups, gender = 255, bst = 680 }))
  add(mon("CELEBI", 251, { "PSYCHIC_TYPE", "GRASS" }, {}, LEGEND))
  P.growthRates = {} -- non-species rows exist in the real table too
  return P
end

local function syntheticChart()
  local rows = {}
  local function m(a, d, x) rows[#rows + 1] = { attacker = a, defender = d, multiplier = x } end
  m("FIRE", "GRASS", 20); m("GRASS", "FIRE", 5); m("WATER", "FIRE", 20); m("FIRE", "WATER", 5)
  m("GRASS", "WATER", 20); m("WATER", "GRASS", 5); m("WATER", "ROCK", 20); m("WATER", "GROUND", 20)
  m("GRASS", "ROCK", 20); m("GRASS", "GROUND", 20); m("FIRE", "ROCK", 5); m("ROCK", "FIRE", 20)
  m("ROCK", "FLYING", 20); m("GROUND", "FIRE", 20); m("POISON", "GRASS", 20); m("GRASS", "POISON", 5)
  m("FLYING", "GRASS", 20); m("GRASS", "FLYING", 5); m("FIGHTING", "NORMAL", 20); m("FIGHTING", "ROCK", 20)
  m("PSYCHIC_TYPE", "FIGHTING", 20); m("PSYCHIC_TYPE", "POISON", 20); m("FIGHTING", "PSYCHIC_TYPE", 5)
  m("FIRE", "FIRE", 5); m("WATER", "WATER", 5); m("GRASS", "GRASS", 5)
  local types = {}
  for _, id in ipairs({ "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "FIRE", "WATER", "GRASS",
      "PSYCHIC_TYPE" }) do types[id] = { id = id } end
  return { matchups = rows, types = types }
end

local function elmScript(index, textKey)
  return {
    { op = "checkevent", event = 26 },
    { op = "pokepic", species = index, args = { index }, object = index },
    { op = "cry", id = index },
    { op = "writetext", text = textKey },
    { op = "yesorno" },
    { op = "getmonname", species = index, buffer = 0 },
    { op = "writetext", text = "received" },
    { op = "givepoke", species = index, level = 5, item = 173, trainer = 0 },
  }
end

local function syntheticWorld()
  local text = {
    ["take155"] = "ELM: You'll take\nCYNDAQUIL, the\vfire POKéMON?{DONE}",
    ["take158"] = "ELM: Do you want\nTOTODILE, the\vwater POKéMON?{DONE}",
    ["take152"] = "ELM: So, you like\nCHIKORITA, the\vgrass POKéMON?{DONE}",
    ["great"] = "ELM: I think\nthat's a great\vPOKéMON too!{DONE}",
    ["received"] = "{PLAYER} received\n{STRBUF}!{DONE}",
    ["eevee"] = "Take this EEVEE.{DONE}",
    ["tyrogue"] = "TYROGUE is a\nfighting-type.{DONE}",
    ["prize"] = "Here you go!{DONE}",
    ["suicune"] = "SUICUNE!{DONE}",
  }
  local scripts = {
    elm155 = elmScript(155, "take155"),
    elm158 = elmScript(158, "take158"),
    elm152 = elmScript(152, "take152"),
    bill = { { op = "writetext", text = "eevee" },
      { op = "givepoke", species = 133, level = 20, item = 0, trainer = 0 } },
    kiyo = { { op = "writetext", text = "tyrogue" },
      { op = "givepoke", species = 236, level = 10, item = 0, trainer = 0 } },
    kiyo2 = { { op = "givepoke", species = 236, level = 10, item = 0, trainer = 0 } },
    tree = { { op = "loadwildmon", species = 185, level = 20 }, { op = "startbattle" } },
    egg = { { op = "giveegg", args = { 175, 5 } } },
    kenya = { { op = "givepoke", species = 16, level = 10, trainer = 1, name = "KENYA" } },
    prize = { { op = "checkcoins" }, { op = "getmonname", species = 63 },
      { op = "givepoke", species = 63, level = 5, trainer = 0 }, { op = "takecoins" } },
    tutorial = { { op = "loadwildmon", species = 16, level = 5 }, { op = "catchtutorial" } },
    hooh = { { op = "cry", id = 250 }, { op = "loadwildmon", species = 250, level = 60 }, { op = "startbattle" } },
    lugia = { { op = "loadwildmon", species = 249, level = 60 }, { op = "startbattle" } },
    suicune = { { op = "writetext", text = "suicune" }, { op = "loadwildmon", species = 245, level = 40 } },
    celebi = { { op = "loadwildmon", species = 251, level = 30 }, { op = "startbattle" } },
  }
  return text, scripts
end

-- A fake mod: a live `game` and a hooks table that records the wrap.
local function fakeMod(data)
  local mod = { game = { data = data }, wrapped = {} }
  mod.hooks = { wrap = function(self, name, fn) mod.wrapped[name] = fn end }
  return mod
end

-- Run one row of `list` through the installed hook the way Vm.runList does,
-- and return the row the VM would run.
local function run(mod, vm, list, i)
  vm.cmdList = list
  local cmd = list[i]
  local ran
  local hook = mod.wrapped["script.command"]
  hook(function(_, _, _, row) ran = row end, { vm = vm }, cmd.op, cmd.args or {}, cmd)
  return ran
end

-- Stand-ins for the modules that run before this one and change the data at
-- each switch: option "evo" gives ABRA a three-stage line (ABRA > TOGEPI >
-- SUDOWOODO) and cuts BULBASAUR's to two; option "types" makes CYNDAQUIL a
-- WATER type.  Both restore the vanilla tables when the option is off.
local function earlierModules(ctx, data)
  local P = data.pokemon
  local vanilla = { abra = P.ABRA.evolutions, togepi = P.TOGEPI.evolutions, ivysaur = P.IVYSAUR.evolutions,
    cyndaquil = P.CYNDAQUIL.types }
  ctx.onSave(function(active)
    if active and ctx.option("evo") then
      P.ABRA.evolutions = { { into = "TOGEPI" } }
      P.TOGEPI.evolutions = { { into = "SUDOWOODO" } }
      P.IVYSAUR.evolutions = {}
    else
      P.ABRA.evolutions, P.TOGEPI.evolutions, P.IVYSAUR.evolutions = vanilla.abra, vanilla.togepi, vanilla.ivysaur
    end
    P.CYNDAQUIL.types = (active and ctx.option("types")) and { "WATER", "WATER" } or vanilla.cyndaquil
  end)
end

local function setup(seed, options)
  local data = { pokemon = syntheticPokemon(), type_chart = syntheticChart() }
  local text, scripts = syntheticWorld()
  local ctx = Fake.new({ seed = seed, options = options })
  local mod = fakeMod(data)
  earlierModules(ctx, data)
  Starters.install(mod, ctx)
  ctx.setActive(seed ~= nil, seed, options)
  return ctx, mod, { text = text }, scripts, data
end

local byIndex = {}
for id, def in pairs(syntheticPokemon()) do if def.index then byIndex[def.index] = id end end

-- ------------------------------------------------------------ the questions
do
  local seenKeys = {}
  for _, q in ipairs(Starters.questions) do
    ok(type(q.recommended) == "boolean" and type(q.everything) == "boolean",
      "question " .. q.key .. " has recommended and everything values")
    ok(q.onlyIf == nil or seenKeys[q.onlyIf], "question " .. q.key .. " depends on an earlier key")
    seenKeys[q.key] = true
    for box in (q.text .. "\f"):gmatch("([^\f]*)\f") do
      for line in (box:gsub("\v", "\n") .. "\n"):gmatch("([^\n]*)\n") do
        ok(chars(line) <= 18, "question " .. q.key .. " line fits Oak's box: '" .. line .. "'")
      end
    end
  end
  for _, key in ipairs({ "starters", "starters_stages", "starters_triangle", "gifts", "gifts_legendary" }) do
    ok(seenKeys[key], "asks " .. key)
  end
end

-- ------------------------------------------------------------ vanilla
do
  local ctx, mod, vm, scripts = setup(nil, {})
  ok(mod.wrapped["script.command"] ~= nil, "installs a script.command hook")
  for _, key in ipairs({ "elm155", "bill", "tree", "egg", "hooh" }) do
    for i, cmd in ipairs(scripts[key]) do
      ok(run(mod, vm, scripts[key], i) == cmd, "vanilla save runs the cart row: " .. key .. " " .. i)
    end
  end
  eq(ctx.shared.starters, nil, "vanilla save publishes no starters")
  eq(ctx.shared.starterRivalPairs, nil, "vanilla save publishes no rival pairs")
end

-- ------------------------------------------------------------ answers NO
do
  local ctx, mod, vm, scripts = setup("seed-no", { starters = false, gifts = false })
  for i, cmd in ipairs(scripts.elm155) do
    ok(run(mod, vm, scripts.elm155, i) == cmd, "answered no: cart row " .. i)
  end
  eq(ctx.shared.starters, nil, "answered no: no starters published")
  eq(ctx.shared.starterRivalPairs, nil, "answered no: no rival pairs published")
end

-- ------------------------------------------------------------ starters
local function startersFor(seed, options)
  local ctx = setup(seed, options or { starters = true })
  return ctx.shared.starters, ctx.shared.starterRivalPairs
end

do
  local s = startersFor("alpha")
  ok(s ~= nil, "starters published")
  local seen = {}
  local P = syntheticPokemon()
  for _, vanilla in ipairs(Starters.STARTERS) do
    local new = s[vanilla]
    ok(P[new] ~= nil, "starter " .. vanilla .. " is a real species id: " .. tostring(new))
    ok(not seen[new], "starters are distinct: " .. tostring(new))
    seen[new] = true
    ok(new ~= "IVYSAUR" and new ~= "PIDGEOTTO", "starter is a first stage: " .. tostring(new))
    ok(not Starters.isLegendaryShape(P[new]), "no legendary starter")
  end
  local again = startersFor("alpha")
  for _, vanilla in ipairs(Starters.STARTERS) do
    eq(again[vanilla], s[vanilla], "same seed, same starter for " .. vanilla)
  end
  -- different seeds should not all agree
  local differs = false
  for n = 1, 20 do
    local other = startersFor("seed" .. n)
    for _, v in ipairs(Starters.STARTERS) do if other[v] ~= s[v] then differs = true end end
  end
  ok(differs, "other seeds give other starters")
  -- the new options off keep round one's pick: the stream "starters" over the
  -- first-stage pool
  local ctx = Fake.new({ seed = "alpha" })
  local order = ctx.rng("starters"):shuffled(Starters.species(P).basic)
  eq(s.CHIKORITA .. s.CYNDAQUIL .. s.TOTODILE, order[1] .. order[2] .. order[3],
    "with the new options off, round one's starters")
end

do
  local ctx, mod, vm, scripts, data = setup("beta", { starters = true })
  local new = ctx.shared.starters.CYNDAQUIL
  local newIndex = data.pokemon[new].index
  local list = scripts.elm155
  eq(run(mod, vm, list, 1), list[1], "checkevent untouched")
  local pic = run(mod, vm, list, 2)
  eq(pic.species, newIndex, "pokepic shows the new starter")
  eq(pic.args[1], newIndex, "pokepic args agree")
  eq(list[2].species, 155, "the cart's own row is not modified")
  eq(run(mod, vm, list, 3).id, newIndex, "cry is the new starter's")
  local textRow = run(mod, vm, list, 4)
  local body = vm.text[textRow.text]
  ok(textRow ~= list[4] or new == "CYNDAQUIL", "the question row is rewritten")
  ok(body:find(data.pokemon[new].name, 1, true) ~= nil, "Elm names the new starter: " .. body)
  ok(new == "CYNDAQUIL" or body:find("CYNDAQUIL", 1, true) == nil, "Elm no longer names CYNDAQUIL")
  ok(body:find(Starters.typePhrase(data.pokemon[new]) .. " POKéMON", 1, true) ~= nil,
    "Elm names the new starter's type: " .. body)
  eq(vm.text.take155, "ELM: You'll take\nCYNDAQUIL, the\vfire POKéMON?{DONE}", "vanilla text kept")
  eq(run(mod, vm, list, 6).species, newIndex, "getmonname (received ...) names it")
  eq(run(mod, vm, list, 7), list[7], "a text without the name is the cart's")
  local give = run(mod, vm, list, 8)
  eq(give.species, newIndex, "givepoke gives it")
  eq(give.level, 5, "level kept")
  eq(give.item, 173, "held item kept")
  -- gifts were not asked for
  eq(run(mod, vm, scripts.bill, 2), scripts.bill[2], "gifts unchanged when only starters asked")

  -- switching to a vanilla save restores everything at once
  ctx.setActive(false)
  eq(ctx.shared.starters, nil, "vanilla save after a randomized one clears starters")
  eq(ctx.shared.starterRivalPairs, nil, "vanilla save after a randomized one clears rival pairs")
  eq(run(mod, vm, list, 8), list[8], "vanilla save after a randomized one gives CYNDAQUIL")
  eq(run(mod, vm, list, 4), list[4], "vanilla save after a randomized one: Elm's own text")
  -- and to another randomized save picks that save's starters
  ctx.setActive(true, "gamma", { starters = true })
  local gamma = startersFor("gamma")
  eq(ctx.shared.starters.CYNDAQUIL, gamma.CYNDAQUIL, "switching saves uses the new seed")
  eq(run(mod, vm, list, 8).species, data.pokemon[gamma.CYNDAQUIL].index, "and gives its starter")
end

-- ------------------------------------------------------------ three stages
do
  local P = syntheticPokemon()
  eq(Starters.lineLength(P, "BULBASAUR"), 3, "BULBASAUR's line has three stages")
  eq(Starters.lineLength(P, "PIDGEY"), 2, "PIDGEY's line has two (synthetic)")
  local looped = syntheticPokemon()
  looped.GOLEM.evolutions = { { into = "GEODUDE" } }
  ok(Starters.lineLength(looped, "GEODUDE") <= 3, "an evolution loop ends")
  local vanillaThree = { BULBASAUR = true, CHARMANDER = true, SQUIRTLE = true, GEODUDE = true }
  local shuffledThree = { ABRA = true, CHARMANDER = true, SQUIRTLE = true, GEODUDE = true }
  for n = 1, 30 do
    local s = startersFor("stages" .. n, { starters = true, starters_stages = true })
    for _, v in ipairs(Starters.STARTERS) do
      ok(vanillaThree[s[v]], "three-stage starter, vanilla evolutions: " .. tostring(s[v]))
    end
    s = startersFor("stages" .. n, { starters = true, starters_stages = true, evo = true })
    for _, v in ipairs(Starters.STARTERS) do
      ok(shuffledThree[s[v]], "three-stage starter read from the shuffled evolutions: " .. tostring(s[v]))
    end
  end
  -- one install switching between a shuffled-evolution save and a vanilla-evolution one
  local ctx = setup("stages1", { starters = true, starters_stages = true, evo = true })
  local first = ctx.shared.starters.CHIKORITA .. ctx.shared.starters.CYNDAQUIL .. ctx.shared.starters.TOTODILE
  ctx.setActive(true, "stages1", { starters = true, starters_stages = true })
  for _, v in ipairs(Starters.STARTERS) do
    ok(vanillaThree[ctx.shared.starters[v]], "after a switch the evolutions are read again: "
      .. tostring(ctx.shared.starters[v]))
  end
  ctx.setActive(true, "stages1", { starters = true, starters_stages = true, evo = true })
  eq(ctx.shared.starters.CHIKORITA .. ctx.shared.starters.CYNDAQUIL .. ctx.shared.starters.TOTODILE, first,
    "and switching back gives the first save's starters again")
end

-- ------------------------------------------------------------ type triangle
local function checkTriangle(s, pairs_, data, label)
  local chart = Starters.typeTable(data.type_chart)
  local P = data.pokemon
  ok(pairs_ ~= nil, label .. ": rival pairs published")
  if not pairs_ then return end
  for _, ball in ipairs(Starters.STARTERS) do
    local pair = pairs_[ball]
    ok(type(pair) == "table", label .. ": a pair for " .. ball)
    if pair then
      eq(pair.rivalBall, Starters.RIVAL_BALL[ball], label .. ": vanilla rival ball for " .. ball)
      eq(pair.player, s[ball], label .. ": player species for " .. ball)
      eq(pair.rival, s[pair.rivalBall], label .. ": rival species for " .. ball)
      ok(pair.strong == true, label .. ": rival's " .. tostring(pair.rival) .. " is strong against "
        .. tostring(pair.player))
      ok(Starters.strongAgainst(chart, P[pair.rival], P[pair.player]), label .. ": checked by the chart")
      ok(not Starters.strongAgainst(chart, P[pair.player], P[pair.rival]), label .. ": and not the other way")
    end
  end
end

do
  eq(Starters.RIVAL_BALL.CHIKORITA, "CYNDAQUIL", "player CHIKORITA, rival CYNDAQUIL")
  eq(Starters.RIVAL_BALL.CYNDAQUIL, "TOTODILE", "player CYNDAQUIL, rival TOTODILE")
  eq(Starters.RIVAL_BALL.TOTODILE, "CHIKORITA", "player TOTODILE, rival CHIKORITA")
  -- the orientation is the vanilla one: on the vanilla three, each rival ball beats the player's
  local P = syntheticPokemon()
  local chart = Starters.typeTable(syntheticChart())
  for ball, rival in pairs(Starters.RIVAL_BALL) do
    ok(Starters.strongAgainst(chart, P[rival], P[ball]), "vanilla: " .. rival .. " beats " .. ball)
  end
  local distinctSets = {}
  for n = 1, 30 do
    for _, opts in ipairs({ { starters = true, starters_triangle = true },
        { starters = true, starters_triangle = true, starters_stages = true },
        -- shuffled evolutions and types (ABRA's three-stage line has no
        -- triangle with the others, so stages are off here)
        { starters = true, starters_triangle = true, evo = true, types = true } }) do
      local ctx, mod, vm, scripts, data = setup("tri" .. n, opts)
      local s = ctx.shared.starters
      checkTriangle(s, ctx.shared.starterRivalPairs, data, "triangle seed " .. n)
      distinctSets[s.CHIKORITA .. s.CYNDAQUIL .. s.TOTODILE] = true
      if opts.starters_stages then
        for _, v in ipairs(Starters.STARTERS) do
          eq(Starters.lineLength(data.pokemon, s[v]), 3, "triangle and three stages together: " .. s[v])
        end
      end
      -- Elm says the species and type of what is in each ball
      for vanilla, key in pairs({ CHIKORITA = "elm152", CYNDAQUIL = "elm155", TOTODILE = "elm158" }) do
        local def = data.pokemon[s[vanilla]]
        local row = run(mod, vm, scripts[key], 4)
        local body = vm.text[row.text]
        ok(body:find(def.name, 1, true) and body:find(Starters.typePhrase(def) .. " POKéMON", 1, true),
          "triangle: Elm names " .. def.name .. " and its type: " .. body)
      end
      -- same seed, same answers
      local again, againPairs = startersFor("tri" .. n, opts)
      for _, v in ipairs(Starters.STARTERS) do
        eq(again[v], s[v], "triangle: same seed, same starter")
        eq(againPairs[v].rival, ctx.shared.starterRivalPairs[v].rival, "triangle: same seed, same pairs")
      end
    end
  end
  local count = 0
  for _ in pairs(distinctSets) do count = count + 1 end
  ok(count > 3, "the triangle varies between seeds (" .. count .. " sets)")
  -- without the option, pairs are published but need not be strong
  local s, pairs_ = startersFor("plain", { starters = true })
  ok(pairs_ and pairs_.CHIKORITA.rival == s.CYNDAQUIL and type(pairs_.CHIKORITA.strong) == "boolean",
    "pairs are published without the triangle too")
  -- no triangle in the pool (the three-stage pool with ABRA's shuffled line:
  -- nothing beats ABRA and ABRA beats nothing): the round-one pick, logged
  do
    local c = setup("notri", { starters = true, starters_triangle = true, starters_stages = true, evo = true })
    local order = Fake.new({ seed = "notri" }).rng("starters"):shuffled({ "CHARMANDER", "SQUIRTLE", "ABRA",
      "GEODUDE" })
    ok(c.shared.starters ~= nil, "no triangle in the shuffled pool: starters still chosen")
    ok(c.lines[#c.lines]:find("no triangle found", 1, true) ~= nil, "and the log says so: " .. c.lines[#c.lines])
    ok(c.shared.starterRivalPairs ~= nil, "and pairs are still published")
    eq(c.shared.starters.CHIKORITA .. c.shared.starters.CYNDAQUIL .. c.shared.starters.TOTODILE,
      order[1] .. order[2] .. order[3], "the fallback is round one's pick from the three-stage pool")
  end
  local data = { pokemon = syntheticPokemon(), type_chart = { matchups = {} } }
  local ctx = Fake.new({ seed = "flat", options = { starters = true, starters_triangle = true } })
  local mod = fakeMod(data)
  Starters.install(mod, ctx)
  ctx.setActive(true)
  ok(ctx.shared.starters ~= nil, "no triangle possible: starters still chosen")
  ok(ctx.lines[#ctx.lines]:find("no triangle found", 1, true) ~= nil, "and the log says so")
end

-- ------------------------------------------------------------ types from this save
do
  -- the pokemon module made CYNDAQUIL a WATER type; starters left alone
  local ctx, mod, vm, scripts = setup("typed", { types = true })
  local row = run(mod, vm, scripts.elm155, 4)
  eq(vm.text[row.text], "ELM: You'll take\nCYNDAQUIL, the\vwater POKéMON?{DONE}",
    "Elm names the type CYNDAQUIL has in this save")
  eq(run(mod, vm, scripts.elm155, 8), scripts.elm155[8], "and still gives CYNDAQUIL")
  eq(run(mod, vm, scripts.elm158, 4), scripts.elm158[4], "a text whose type did not change is the cart's")
  eq(run(mod, vm, scripts.elm155, 7), scripts.elm155[7], "a text without the name is the cart's")
  ctx.setActive(false)
  eq(run(mod, vm, scripts.elm155, 4), scripts.elm155[4], "vanilla save: Elm's own text again")
end

-- ------------------------------------------------------------ gifts and statics
do
  local ctx, mod, vm, scripts, data = setup("delta", { gifts = true })
  eq(ctx.shared.starters, nil, "gifts only: starters not shuffled")
  eq(run(mod, vm, scripts.elm155, 8), scripts.elm155[8], "gifts only: Elm's ball is vanilla")
  local bill = run(mod, vm, scripts.bill, 2)
  ok(byIndex[bill.species] ~= nil, "Eevee gift is a valid species")
  eq(bill.level, 20, "gift level kept")
  if bill.species ~= 133 then
    local textRow = run(mod, vm, scripts.bill, 1)
    ok(vm.text[textRow.text]:find(byIndex[bill.species], 1, true) ~= nil, "Bill names the gift")
  end
  local a = run(mod, vm, scripts.kiyo, 2)
  local b = run(mod, vm, scripts.kiyo2, 1)
  eq(a.species, b.species, "one gift reached by two scripts is the same species")
  eq(run(mod, vm, scripts.tree, 1).level, 20, "static encounter level kept")
  ok(byIndex[run(mod, vm, scripts.tree, 1).species] ~= nil, "static encounter species valid")
  local egg = run(mod, vm, scripts.egg, 1)
  ok(byIndex[egg.species] ~= nil and egg.args[1] == egg.species, "egg species valid, args agree")
  eq(egg.args[2], 5, "egg level kept")
  eq(scripts.egg[1].args[1], 175, "egg cart row untouched")
  eq(run(mod, vm, scripts.kenya, 1), scripts.kenya[1], "trainer-owned gift (KENYA) untouched")
  eq(run(mod, vm, scripts.prize, 2), scripts.prize[2], "coin prize names untouched")
  eq(run(mod, vm, scripts.prize, 3), scripts.prize[3], "coin prize untouched")
  eq(run(mod, vm, scripts.tutorial, 1), scripts.tutorial[1], "catching tutorial untouched")
  -- determinism across installs
  local ctx2, mod2, vm2, scripts2 = setup("delta", { gifts = true })
  eq(run(mod2, vm2, scripts2.bill, 2).species, bill.species, "same seed, same gift")
  eq(run(mod2, vm2, scripts2.tree, 1).species, run(mod, vm, scripts.tree, 1).species, "same seed, same static")
  -- order independence: ask the tree first in a fresh install
  local ctx3, mod3, vm3, scripts3 = setup("delta", { gifts = true })
  local tree3 = run(mod3, vm3, scripts3.tree, 1).species
  eq(tree3, run(mod, vm, scripts.tree, 1).species, "result does not depend on asking order")
  -- round one's pick when the legendary option is off
  local P = syntheticPokemon()
  eq(byIndex[bill.species], Fake.new({ seed = "delta" }).rng("gifts", "gift", "EEVEE"):pick(Starters.species(P).all),
    "legendary option off: round one's gift")
end

-- ------------------------------------------------------------ legendaries for legendaries
do
  local species = Starters.species(syntheticPokemon())
  local names = table.concat(species.legendary, ",")
  eq(names, "MEWTWO,SUICUNE,LUGIA,HO_OH,CELEBI", "legendary pool from the data (UNOWN is too weak)")
  local opts = { gifts = true, gifts_legendary = true }
  local legendaryStatics = { hooh = 2, lugia = 1, suicune = 2, celebi = 1 }
  local ordinaryGifts = { { "bill", 2 }, { "kiyo", 2 }, { "tree", 1 } }
  local varied = {}
  for n = 1, 40 do
    local ctx, mod, vm, scripts, data = setup("leg" .. n, opts)
    local used = {}
    for key, i in pairs(legendaryStatics) do
      local row = run(mod, vm, scripts[key], i)
      local id = byIndex[row.species]
      ok(species.isLegendary[id], "legendary static " .. key .. " becomes a legendary: " .. tostring(id))
      ok(id ~= byIndex[scripts[key][i].species], "legendary static " .. key .. " becomes another one")
      ok(not used[id], "each legendary static becomes a different one: " .. tostring(id))
      used[id] = true
      eq(row.level, scripts[key][i].level, "legendary static level kept")
      varied[key .. id] = true
    end
    -- the cry before HO-OH's battle follows it
    eq(run(mod, vm, scripts.hooh, 1).id, run(mod, vm, scripts.hooh, 2).species, "HO-OH's cry follows")
    local text = run(mod, vm, scripts.suicune, 1)
    local id = byIndex[run(mod, vm, scripts.suicune, 2).species]
    ok(vm.text[text.text]:find(data.pokemon[id].name, 1, true), "the text before SUICUNE names its replacement")
    for _, g in ipairs(ordinaryGifts) do
      local row = run(mod, vm, scripts[g[1]], g[2])
      local def = data.pokemon[byIndex[row.species]]
      ok(not Starters.isLegendaryShape(def), "ordinary gift " .. g[1] .. " stays non-legendary: " .. def.id)
    end
    -- same seed, same statics, whatever order they are asked in
    local ctx2, mod2, vm2, scripts2 = setup("leg" .. n, opts)
    eq(run(mod2, vm2, scripts2.celebi, 1).species, run(mod, vm, scripts.celebi, 1).species,
      "legendaries: same seed, same CELEBI replacement")
    eq(run(mod2, vm2, scripts2.hooh, 2).species, run(mod, vm, scripts.hooh, 2).species,
      "legendaries: same seed, same HO-OH replacement")
    -- restore
    ctx.setActive(false)
    eq(run(mod, vm, scripts.hooh, 2), scripts.hooh[2], "vanilla save: HO-OH again")
  end
  local count = 0
  for _ in pairs(varied) do count = count + 1 end
  ok(count > 8, "legendary replacements vary between seeds (" .. count .. ")")
end

-- ------------------------------------------------------------ text rewriting
do
  local P = syntheticPokemon()
  eq(Starters.rewriteText("CYNDAQUIL, the\vfire POKéMON?", P.CYNDAQUIL, P.BULBASAUR),
    "BULBASAUR, the\vgrass/poison POKéMON?", "dual type phrase")
  eq(Starters.rewriteText("TYROGUE is a\nfighting-type.", P.TYROGUE, P.ABRA),
    "ABRA is a\npsychic-type.", "-type phrase, PSYCHIC_TYPE spelled psychic")
  eq(Starters.rewriteText("Take this EEVEEX", P.EEVEE, P.ABRA), "Take this EEVEEX",
    "a name inside a longer word is left alone")
  local words = Starters.typeWords({ pokemon = P, type_chart = syntheticChart() })
  eq(Starters.rewriteText("ELM: You'll take\nCYNDAQUIL, the\vwater POKéMON?", P.CYNDAQUIL, P.CHARIZARD, words),
    "ELM: You'll take\nCHARIZARD, the\vfire/flying POKéMON?", "any type phrase is set to the new type")
  eq(Starters.rewriteText("a great\vPOKéMON too!", P.CYNDAQUIL, P.CHARIZARD, words), "a great\vPOKéMON too!",
    "a text that does not name the species is left alone")
end

-- ------------------------------------------------------------ real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local pokemon = dofile(cache .. "/pokemon.lua")
  local scripts = dofile(cache .. "/scripts.lua")
  local text = dofile(cache .. "/text.lua")
  local typeChart = dofile(cache .. "/type_chart.lua")
  local data = { pokemon = pokemon, type_chart = typeChart }
  local species = Starters.species(pokemon)
  local chart = Starters.typeTable(typeChart)
  ok(#species.all == 251, "real data: 251 species (" .. #species.all .. ")")
  -- the two round-one rules agree on the cart's data
  local evolvedInto = {}
  for _, id in ipairs(species.all) do
    for _, evo in ipairs(pokemon[id].evolutions or {}) do evolvedInto[evo.into] = true end
  end
  for _, id in ipairs(species.all) do
    local def = pokemon[id]
    local loner = def.eggGroups[1] == "EGG_NONE" and #def.evolutions == 0 and not evolvedInto[id]
    eq(Starters.isLegendaryShape(def), loner, "real data: both round-one legendary rules agree on " .. id)
  end
  local legendary = table.concat(species.legendary, ",")
  eq(legendary, "ARTICUNO,ZAPDOS,MOLTRES,MEWTWO,MEW,RAIKOU,ENTEI,SUICUNE,LUGIA,HO_OH,CELEBI",
    "real data: the legendary pool")
  print("  three-stage first stages: " .. #species.threeStage .. " (" .. table.concat(species.threeStage, " ") .. ")")
  for _, id in ipairs(Starters.STARTERS) do
    ok(species.isLegendary[id] == nil, "real data: " .. id .. " is not legendary")
    eq(Starters.lineLength(pokemon, id), 3, "real data: " .. id .. "'s line has three stages")
    local rival = Starters.RIVAL_BALL[id]
    ok(Starters.strongAgainst(chart, pokemon[rival], pokemon[id]),
      "real data: the vanilla rival's " .. rival .. " is strong against the player's " .. id)
  end
  -- find Elm's three ball scripts, the legendary statics and every other gift
  local elm, legendLists, giftLists = {}, {}, {}
  for key, list in pairs(scripts) do
    local plan = type(list) == "table" and Starters.planFor(list, species.byIndex)
    if plan then
      for index, kind in pairs(plan) do
        local id = species.byIndex[index]
        if kind == "starter" then elm[id] = list
        elseif kind == "gift" and species.isLegendary[id] then legendLists[#legendLists + 1] = { list, id, key }
        elseif kind == "gift" then giftLists[#giftLists + 1] = { list, id, key } end
      end
    end
  end
  for _, id in ipairs(Starters.STARTERS) do ok(elm[id] ~= nil, "real data: Elm's ball for " .. id) end
  local legendNames = {}
  for _, l in ipairs(legendLists) do legendNames[l[2]] = true end
  for _, id in ipairs({ "HO_OH", "LUGIA", "SUICUNE", "CELEBI" }) do
    ok(legendNames[id], "real data: a static " .. id .. " is found")
  end
  local function giveRow(mod, list)
    local vm = { text = setmetatable({}, { __index = text }) }
    for i, cmd in ipairs(list) do
      if cmd.op == "givepoke" or cmd.op == "loadwildmon" then return run(mod, vm, list, i), cmd end
    end
  end
  local allOptions = { starters = true, starters_stages = true, starters_triangle = true, gifts = true,
    gifts_legendary = true }
  for n = 1, 25 do
    for _, opts in ipairs({ allOptions, { starters = true, starters_triangle = true },
        { starters = true, gifts = true } }) do
      local ctx = Fake.new({ seed = "real" .. n, options = opts })
      local mod = fakeMod(data)
      Starters.install(mod, ctx)
      ctx.setActive(true)
      local s = ctx.shared.starters
      local seen = {}
      if opts.starters_triangle then checkTriangle(s, ctx.shared.starterRivalPairs, data, "real triangle " .. n) end
      for _, id in ipairs(Starters.STARTERS) do
        ok(pokemon[s[id]] and not seen[s[id]], "real data: distinct valid starter " .. tostring(s[id]))
        seen[s[id]] = true
        if opts.starters_stages then
          eq(Starters.lineLength(pokemon, s[id]), 3, "real data: three-stage starter " .. s[id])
        end
        local list = elm[id]
        local vm = { text = setmetatable({}, { __index = text }) }
        local newDef = pokemon[s[id]]
        local heard
        for i, cmd in ipairs(list) do
          local row = run(mod, vm, list, i)
          if cmd.op == "givepoke" then eq(row.species, newDef.index, "real data: Elm gives " .. s[id]) end
          if cmd.op == "writetext" and text[cmd.text] and text[cmd.text]:find(id, 1, true) then
            heard = vm.text[row.text]
          end
        end
        ok(heard and heard:find(newDef.name, 1, true) and (s[id] == id or not heard:find(id, 1, true))
          and heard:find(Starters.typePhrase(newDef) .. " POKéMON", 1, true),
          "real data: Elm's question names " .. newDef.name .. " and its type: " .. tostring(heard))
        if n == 1 and opts == allOptions then print("  e.g. " .. tostring(heard):gsub("[\n\v]", " ")) end
      end
      if opts.gifts_legendary then
        local used = {}
        for _, l in ipairs(legendLists) do
          local row = giveRow(mod, l[1])
          local got = species.byIndex[row.species]
          ok(species.isLegendary[got] and got ~= l[2], "real data: " .. l[2] .. " becomes another legendary: " .. got)
          ok(used[l[2]] == nil or used[l[2]] == got, "real data: one vanilla legendary, one replacement")
          used[l[2]] = got
        end
        local back = {}
        for vanilla, got in pairs(used) do
          ok(not back[got], "real data: legendary statics become different legendaries")
          back[got] = vanilla
        end
        for _, l in ipairs(giftLists) do
          local row = giveRow(mod, l[1])
          local got = row and species.byIndex[row.species]
          ok(got and not Starters.isLegendaryShape(pokemon[got]),
            "real data: ordinary gift/static " .. l[2] .. " stays non-legendary: " .. tostring(got))
        end
        if n == 1 then
          local o = {}
          for vanilla, got in pairs(used) do o[#o + 1] = vanilla .. ">" .. got end
          table.sort(o)
          print("  legendaries: " .. table.concat(o, " "))
        end
      end
      -- restore: a vanilla save runs every row as the cart wrote it
      ctx.setActive(false)
      eq(ctx.shared.starterRivalPairs, nil, "real data: vanilla save clears the pairs")
      local row, cmd = giveRow(mod, elm.CYNDAQUIL)
      eq(row, cmd, "real data: vanilla save gives CYNDAQUIL")
    end
  end
  print("real Crystal data checked: " .. cache)
end

print(string.format("starters_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
