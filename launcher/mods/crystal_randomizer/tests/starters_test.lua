-- luajit launcher/mods/crystal_randomizer/tests/starters_test.lua   (from the repository root)
--
-- Runs on a small synthetic dataset shaped like Crystal's extracted tables.
-- With CRYSTAL_RANDOMIZER_CACHE set to an imported cache's data/generated
-- folder (for example %APPDATA%/LOVE/<identity>/crystal/data/generated), it
-- also runs against the real Crystal pokemon, scripts and text tables.
local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Starters = dofile("launcher/mods/crystal_randomizer/modules/starters.lua")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

-- ------------------------------------------------------------ synthetic data
local function mon(id, index, types, evolutions, groups)
  return { id = id, name = id, index = index, types = types, baseStats = {},
    evolutions = evolutions or {}, eggGroups = groups or { "EGG_GROUND", "EGG_GROUND" } }
end

local function syntheticPokemon()
  local P = {}
  local function add(m) P[m.id] = m end
  add(mon("BULBASAUR", 1, { "GRASS", "POISON" }, { { into = "IVYSAUR" } }))
  add(mon("IVYSAUR", 2, { "GRASS", "POISON" }))
  add(mon("PIDGEY", 16, { "NORMAL", "FLYING" }, { { into = "PIDGEOTTO" } }))
  add(mon("PIDGEOTTO", 17, { "NORMAL", "FLYING" }))
  add(mon("ABRA", 63, { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }))
  add(mon("EEVEE", 133, { "NORMAL", "NORMAL" }))
  add(mon("MEWTWO", 150, { "PSYCHIC_TYPE", "PSYCHIC_TYPE" }, {}, { "EGG_NONE", "EGG_NONE" }))
  add(mon("CHIKORITA", 152, { "GRASS", "GRASS" }))
  add(mon("CYNDAQUIL", 155, { "FIRE", "FIRE" }))
  add(mon("TOTODILE", 158, { "WATER", "WATER" }))
  add(mon("TOGEPI", 175, { "NORMAL", "NORMAL" }))
  add(mon("SUDOWOODO", 185, { "ROCK", "ROCK" }))
  add(mon("TYROGUE", 236, { "FIGHTING", "FIGHTING" }))
  P.growthRates = {} -- non-species rows exist in the real table too
  return P
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
    ["received"] = "{PLAYER} received\n{STRBUF}!{DONE}",
    ["eevee"] = "Take this EEVEE.{DONE}",
    ["tyrogue"] = "TYROGUE is a\nfighting-type.{DONE}",
    ["prize"] = "Here you go!{DONE}",
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

local function setup(seed, options)
  local data = { pokemon = syntheticPokemon() }
  local text, scripts = syntheticWorld()
  local ctx = Fake.new({ seed = seed, options = options })
  local mod = fakeMod(data)
  Starters.install(mod, ctx)
  ctx.setActive(seed ~= nil, seed, options)
  return ctx, mod, { text = text }, scripts, data
end

local byIndex = {}
for id, def in pairs(syntheticPokemon()) do if def.index then byIndex[def.index] = id end end

-- ------------------------------------------------------------ vanilla
do
  local ctx, mod, vm, scripts = setup(nil, {})
  ok(mod.wrapped["script.command"] ~= nil, "installs a script.command hook")
  for _, key in ipairs({ "elm155", "bill", "tree", "egg" }) do
    for i, cmd in ipairs(scripts[key]) do
      ok(run(mod, vm, scripts[key], i) == cmd, "vanilla save runs the cart row: " .. key .. " " .. i)
    end
  end
  eq(ctx.shared.starters, nil, "vanilla save publishes no starters")
end

-- ------------------------------------------------------------ answers NO
do
  local ctx, mod, vm, scripts = setup("seed-no", { starters = false, gifts = false })
  for i, cmd in ipairs(scripts.elm155) do
    ok(run(mod, vm, scripts.elm155, i) == cmd, "answered no: cart row " .. i)
  end
  eq(ctx.shared.starters, nil, "answered no: no starters published")
end

-- ------------------------------------------------------------ starters
local function startersFor(seed)
  local ctx = setup(seed, { starters = true })
  return ctx.shared.starters
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
    ok(new ~= "MEWTWO", "no legendary starter")
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
  eq(run(mod, vm, list, 8), list[8], "vanilla save after a randomized one gives CYNDAQUIL")
  -- and to another randomized save picks that save's starters
  ctx.setActive(true, "gamma", { starters = true })
  local gamma = startersFor("gamma")
  eq(ctx.shared.starters.CYNDAQUIL, gamma.CYNDAQUIL, "switching saves uses the new seed")
  eq(run(mod, vm, list, 8).species, data.pokemon[gamma.CYNDAQUIL].index, "and gives its starter")
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
end

-- ------------------------------------------------------------ real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local pokemon = dofile(cache .. "/pokemon.lua")
  local scripts = dofile(cache .. "/scripts.lua")
  local text = dofile(cache .. "/text.lua")
  local species = Starters.species(pokemon)
  ok(#species.all == 251, "real data: 251 species (" .. #species.all .. ")")
  -- find Elm's three ball scripts by their givepoke rows
  local elm = {}
  for key, list in pairs(scripts) do
    local plan = type(list) == "table" and Starters.planFor(list, species.byIndex)
    if plan then
      for index, kind in pairs(plan) do
        if kind == "starter" then elm[species.byIndex[index]] = list end
      end
    end
  end
  for _, id in ipairs(Starters.STARTERS) do ok(elm[id] ~= nil, "real data: Elm's ball for " .. id) end
  for n = 1, 25 do
    local ctx = Fake.new({ seed = "real" .. n, options = { starters = true, gifts = true } })
    local mod = fakeMod({ pokemon = pokemon })
    Starters.install(mod, ctx)
    ctx.setActive(true)
    local s = ctx.shared.starters
    local seen = {}
    for _, id in ipairs(Starters.STARTERS) do
      ok(pokemon[s[id]] and not seen[s[id]], "real data: distinct valid starter " .. tostring(s[id]))
      seen[s[id]] = true
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
      ok(heard and heard:find(newDef.name, 1, true) and (s[id] == id or not heard:find(id, 1, true)),
        "real data: Elm's question names " .. newDef.name .. ": " .. tostring(heard))
      if n == 1 then print("  e.g. " .. tostring(heard):gsub("[\n\v]", " ")) end
    end
  end
  print("real Crystal data checked: " .. cache)
end

print(string.format("starters_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
