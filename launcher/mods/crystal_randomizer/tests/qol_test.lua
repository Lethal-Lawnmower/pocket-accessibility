-- luajit launcher/mods/crystal_randomizer/tests/qol_test.lua   (from the repository root)
--
-- The quality-of-life module: its questions fit Oak's box, the experience
-- multiplier and catch-rate floor go through the engine's real hook chain
-- (src/mods/Hooks.lua) and the real catch maths (src/battle/gen2/Catching.lua),
-- blind trainers hide every map trainer's sight from the engine's own
-- Trainers.sees, and every option is per save, deterministic and restored
-- exactly.  With CRYSTAL_RANDOMIZER_CACHE set to an imported Crystal cache's
-- data/generated folder, it also runs on the real maps, species and scripts.
package.path = "./?.lua;./?/init.lua;" .. package.path

local Fake = dofile("launcher/mods/crystal_randomizer/tests/fake_ctx.lua")
local Qol = dofile("launcher/mods/crystal_randomizer/modules/qol.lua")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")
local Catching = require("src.battle.gen2.Catching")
local Trainers = require("src.world.gen2.Trainers")

local failures, checks = 0, 0
local function ok(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function eq(a, b, msg) ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

-- A live hook bus, the one the engine's call sites ask through Runtime.
local hooks = Hooks.new()
Runtime.install(Runtime.events, hooks, Runtime.errors)

-- Installs the module the way main.lua does and switches to the given save.
local function setup(data, seed, options)
  local ctx = Fake.new({ seed = seed or "unused", options = options or {} })
  local mod = { game = { data = data }, hooks = { wrap = function(_, name, fn)
    return hooks:wrap(name, fn, 0, "crystal_randomizer_test")
  end } }
  Qol.install(mod, ctx)
  ctx.setActive(seed ~= nil, seed, options)
  return ctx
end
local function reset()
  hooks:removeOwner("crystal_randomizer_test")
end
local function chainLength(name)
  local chain = hooks.chains[name]
  return chain and #chain or 0
end

-- exp.gain exactly as src/battle/gen2/Battle.lua calls it.
local function award(base)
  return Runtime.call("exp.gain", function(c) return c.vanilla end, { vanilla = base })
end

-- ------------------------------------------------------------ Oak's questions
do
  local keys = {}
  for _, q in ipairs(Qol.questions) do
    keys[q.key] = true
    local lines = 0
    for line in (q.text .. "\n"):gmatch("(.-)\n") do
      lines = lines + 1
      -- é is two bytes in UTF-8 and one tile on screen
      local width = #line:gsub("\195\169", "e")
      ok(width <= 18, q.key .. " line fits 18: " .. line)
    end
    eq(lines, 2, q.key .. " is one box of two lines")
    ok(not q.text:find("[\v\f]"), q.key .. " needs no scroll")
    if q.kind == "choice" then
      local values = {}
      for _, option in ipairs(q.options) do
        ok(#option.label <= 12, q.key .. " label fits 12: " .. option.label)
        eq(option.label, option.label:upper(), q.key .. " label is upper case")
        values[option.value] = true
      end
      ok(values[q.recommended], q.key .. " recommended is one of its options")
      ok(values[q.everything], q.key .. " everything is one of its options")
    else
      eq(type(q.recommended), "boolean", q.key .. " recommended is set")
      eq(type(q.everything), "boolean", q.key .. " everything is set")
    end
  end
  ok(keys.qol_exp and keys.qol_catch and keys.qol_blind, "the three questions exist")
  local q = Qol.questions[1]
  for _, option in ipairs(q.options) do
    ok(Qol.EXP_RATES[option.value] ~= nil, "every experience answer has a rate: " .. option.value)
  end
end

-- ------------------------------------------------------------ experience
do
  setup({}, nil, {})
  eq(award(100), 100, "vanilla save: experience unchanged")
  reset()
  local cases = { ["1"] = { 100, 1, 7 }, ["1.5"] = { 150, 1, 10 }, ["2"] = { 200, 2, 14 }, ["3"] = { 300, 3, 21 } }
  for value, want in pairs(cases) do
    setup({}, "s", { qol_exp = value })
    eq(award(100), want[1], "x" .. value .. " of 100")
    eq(award(1), want[2], "x" .. value .. " of 1 (never below 1)")
    eq(award(7), want[3], "x" .. value .. " of 7 (rounded down)")
    reset()
  end
  local ctx = setup({}, "s", { qol_exp = "3" })
  eq(award(50), 150, "x3 save")
  ctx.setActive(false)
  eq(award(50), 50, "switched to a vanilla save: unchanged")
  ctx.setActive(true, "t", { qol_exp = "1.5" })
  eq(award(50), 75, "switched to a x1.5 save")
  ctx.setActive(true, "t", { qol_exp = "bogus" })
  eq(award(50), 50, "an unknown answer is x1")
  ctx.setActive(true, "t", {})
  eq(award(50), 50, "no answer is x1")
  reset()
end

-- ------------------------------------------------------------ catch rate
do
  local function throw(catchRate, hp)
    local opts = { catchRate = catchRate, maxHp = 100, hp = hp, ball = "POKE_BALL",
      random = function() return 255 end }
    local _, rate = Catching.attempt(opts)
    return rate, opts
  end
  local function vanillaRate(catchRate, hp)
    return (Catching.rate({ catchRate = catchRate, maxHp = 100, hp = hp, ball = "POKE_BALL" }))
  end

  setup({}, nil, {})
  eq(chainLength("catch.rate"), 0, "vanilla save: no catch.rate wrap, so Catching.chance still previews")
  eq(throw(3, 1), vanillaRate(3, 1), "vanilla save: SUICUNE's rate unchanged")
  reset()

  local ctx = setup({}, "s", { qol_catch = true })
  eq(chainLength("catch.rate"), 1, "floor save: one catch.rate wrap")
  local rate, opts = throw(3, 1)
  eq(rate, vanillaRate(Qol.CATCH_FLOOR, 1), "rate 3 is thrown at as the floor (red HP)")
  eq(opts.catchRate, 3, "the catch site's own options are not changed")
  eq(throw(3, 100), vanillaRate(Qol.CATCH_FLOOR, 100), "rate 3 at full HP")
  eq(throw(255, 50), vanillaRate(255, 50), "a rate above the floor is unchanged")
  eq(throw(Qol.CATCH_FLOOR, 50), vanillaRate(Qol.CATCH_FLOOR, 50), "a rate at the floor is unchanged")
  local ultra = { catchRate = 3, maxHp = 100, hp = 1, ball = "ULTRA_BALL", random = function() return 255 end }
  local _, ultraRate = Catching.attempt(ultra)
  eq(ultraRate, (Catching.rate({ catchRate = Qol.CATCH_FLOOR, maxHp = 100, hp = 1, ball = "ULTRA_BALL" })),
    "the ball's multiplier applies on top of the floor")
  ok(ultraRate > rate, "an ULTRA BALL still beats a POKé BALL")
  eq(Qol.flooredOptions({}, 100).catchRate, 100, "a missing rate (read as 45) gets the floor")

  ctx.setActive(false)
  eq(chainLength("catch.rate"), 0, "switched to a vanilla save: the wrap is removed")
  eq(throw(3, 1), vanillaRate(3, 1), "and the rate is vanilla again")
  ctx.setActive(true, "s", { qol_catch = true })
  ctx.setActive(true, "s", { qol_catch = true })
  eq(chainLength("catch.rate"), 1, "the same save reported twice wraps once")
  ctx.setActive(true, "u", { qol_catch = false })
  eq(chainLength("catch.rate"), 0, "a save that answered no: no wrap")
  reset()
end

-- ------------------------------------------------------------ blind trainers
local function syntheticMaps()
  local function trainer(index, sight, class, member)
    return { index = index, sprite = "SPRITE_YOUNGSTER", type = 2, sight = sight,
      trainer = { class = class or 1, member = member or index, event = 1000 + index } }
  end
  return {
    ROUTE_30 = { objects = { trainer(1, 3), trainer(2, 1), { index = 3, sprite = "SPRITE_FISHER", sight = 2 },
      { index = 4, sprite = "SPRITE_POKE_BALL", itemball = { item = 18, quantity = 1 } } } },
    DANCE_THEATER = { objects = { trainer(1, 0) } },
    RADIO_TOWER_5F = { objects = { trainer(1, 1, 60, 1) } },
  }
end
local function sights(maps)
  local out = {}
  for mapId, map in pairs(maps) do
    for i, o in ipairs(map.objects or {}) do out[mapId .. "#" .. i] = o.sight end
  end
  return out
end
local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end
-- The engine's own eyesight test on an object, the player `d` cells below it.
local function sees(object, d)
  local npc = { def = object, cellX = 5, cellY = 5, facing = "down" }
  return Trainers.sees(npc, { cellX = 5, cellY = 5 + d }, npc.def.sight) ~= nil
end

do
  local data = { gen2Maps = syntheticMaps() }
  local vanilla = sights(data.gen2Maps)
  local joey = data.gen2Maps.ROUTE_30.objects[1]
  ok(sees(joey, 2), "vanilla: the trainer sees the player 2 cells away")

  local ctx = setup(data, nil, {})
  ok(same(vanilla, sights(data.gen2Maps)), "vanilla save: every sight kept")
  ctx.setActive(true, "s", { qol_blind = false })
  ok(same(vanilla, sights(data.gen2Maps)), "answered no: every sight kept")

  ctx.setActive(true, "s", { qol_blind = true })
  local blind = sights(data.gen2Maps)
  eq(blind["ROUTE_30#1"], 0, "a seeing trainer is blind")
  eq(blind["ROUTE_30#2"], 0, "a one-cell trainer is blind")
  eq(blind["RADIO_TOWER_5F#1"], 0, "a Rocket executive map trainer is blind too (talking still battles)")
  eq(blind["ROUTE_30#3"], 2, "a non-trainer object keeps its sight byte")
  eq(blind["DANCE_THEATER#1"], 0, "a trainer that never looked still never looks")
  eq(data.gen2Maps.ROUTE_30.objects[4].itemball.item, 18, "item balls untouched")
  ok(not sees(joey, 1) and not sees(joey, 2), "blind: the engine's eyesight test sees nothing")
  ok(joey.trainer.class == 1 and joey.trainer.event == 1001, "the trainer struct (talk battle) is untouched")

  local data2 = { gen2Maps = syntheticMaps() }
  setup(data2, "other", { qol_blind = true })
  ok(same(blind, sights(data2.gen2Maps)), "deterministic: any blind save gives the same sights")

  ctx.setActive(true, "s", { qol_blind = true })
  ok(same(blind, sights(data.gen2Maps)), "the same save reported twice changes nothing more")
  ctx.setActive(false)
  ok(same(vanilla, sights(data.gen2Maps)), "switched to a vanilla save: exact vanilla sights")
  ok(sees(joey, 2), "and the trainer sees again")
  ctx.setActive(true, "s", { qol_blind = true })
  ctx.setActive(true, "u", { qol_blind = false })
  ok(same(vanilla, sights(data.gen2Maps)), "switched to a save that answered no: exact vanilla sights")
  reset()
end

-- ------------------------------------------------------------ all three together
do
  local data = { gen2Maps = syntheticMaps() }
  local vanilla = sights(data.gen2Maps)
  local ctx = setup(data, "all", { qol_exp = "2", qol_catch = true, qol_blind = true })
  eq(award(40), 80, "together: x2")
  eq(chainLength("catch.rate"), 1, "together: catch floor wrapped")
  eq(data.gen2Maps.ROUTE_30.objects[1].sight, 0, "together: blind")
  ctx.setActive(false)
  eq(award(40), 40, "vanilla after: experience")
  eq(chainLength("catch.rate"), 0, "vanilla after: catch")
  ok(same(vanilla, sights(data.gen2Maps)), "vanilla after: sights")
  ctx.setActive(true, "all", { qol_exp = "2", qol_catch = true, qol_blind = true })
  eq(award(40), 80, "back to the save: x2 again")
  eq(data.gen2Maps.ROUTE_30.objects[1].sight, 0, "back to the save: blind again")
  reset()
end

-- ------------------------------------------------------------ real Crystal data
local cache = os.getenv("CRYSTAL_RANDOMIZER_CACHE")
if cache and cache ~= "" then
  local data = { gen2Maps = dofile(cache .. "/maps.lua"), pokemon = dofile(cache .. "/pokemon.lua"),
    gen2Trainers = dofile(cache .. "/trainers.lua"), gen2Scripts = dofile(cache .. "/scripts.lua") }
  local classById = {}
  for id, class in pairs(data.gen2Trainers.classes) do
    if type(class) == "table" and class.index then classById[class.index] = id end
  end
  local story = { RIVAL1 = true, RIVAL2 = true, FALKNER = true, BUGSY = true, WHITNEY = true, MORTY = true,
    CHUCK = true, JASMINE = true, PRYCE = true, CLAIR = true, WILL = true, KOGA = true, BRUNO = true,
    KAREN = true, CHAMPION = true, BROCK = true, MISTY = true, LT_SURGE = true, ERIKA = true, JANINE = true,
    SABRINA = true, BLAINE = true, BLUE = true, RED = true }

  -- Story battles are scripts (`loadtrainer` + `startbattle`), which never read sight.
  local scripted = {}
  for _, rows in pairs(data.gen2Scripts) do
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
      if type(row) == "table" and row.op == "loadtrainer" and classById[row.class] then
        scripted[classById[row.class]] = true
      end
    end
  end
  for id in pairs(story) do ok(scripted[id], "real data: " .. id .. " battles from a script") end
  ok(scripted.EXECUTIVEM and scripted.EXECUTIVEF, "real data: Team Rocket's executives have scripted battles")

  local vanilla = sights(data.gen2Maps)
  local seeing = Qol.seeingTrainers(data.gen2Maps)
  local rockets, storyTouched = 0, 0
  for _, row in ipairs(seeing) do
    local class = classById[row.object.trainer.class]
    if story[class] then storyTouched = storyTouched + 1 end
    if class and (class:find("GRUNT") or class:find("EXECUTIVE")) then rockets = rockets + 1 end
  end
  print(string.format("  real data: %d seeing map trainers, %d of them Team Rocket", #seeing, rockets))
  ok(#seeing > 250, "real data: the map trainers are found")
  eq(storyTouched, 0, "real data: no rival, gym leader, Elite Four or champion is a map trainer")

  local ctx = setup(data, "real", { qol_exp = "1.5", qol_catch = true, qol_blind = true })
  local blind = sights(data.gen2Maps)
  local changed, wrong = 0, 0
  for key, value in pairs(vanilla) do
    if blind[key] ~= value then
      changed = changed + 1
      if blind[key] ~= 0 then wrong = wrong + 1 end
    end
  end
  eq(changed, #seeing, "real data: exactly the seeing trainers changed")
  eq(wrong, 0, "real data: each to sight 0")
  local stillSees = 0
  for _, row in ipairs(seeing) do if sees(row.object, 1) then stillSees = stillSees + 1 end end
  eq(stillSees, 0, "real data: none passes the engine's eyesight test")

  local data2 = { gen2Maps = dofile(cache .. "/maps.lua") }
  setup(data2, "other", { qol_blind = true })
  ok(same(blind, sights(data2.gen2Maps)), "real data: deterministic")

  -- every species thrown at no lower than the floor, and no higher than it was
  local below, raised, lowered = 0, 0, 0
  for id, def in pairs(data.pokemon) do
    if type(def) == "table" and type(def.catchRate) == "number" then
      local opts = { catchRate = def.catchRate, maxHp = 100, hp = 50, ball = "POKE_BALL",
        random = function() return 255 end }
      local _, rate = Catching.attempt(opts)
      local want = Catching.rate({ catchRate = math.max(def.catchRate, Qol.CATCH_FLOOR), maxHp = 100,
        hp = 50, ball = "POKE_BALL" })
      if rate ~= want then lowered = lowered + 1; print("  catch mismatch " .. id) end
      if def.catchRate < Qol.CATCH_FLOOR then below = below + 1 end
      if rate > Catching.rate({ catchRate = def.catchRate, maxHp = 100, hp = 50, ball = "POKE_BALL" }) then
        raised = raised + 1
      end
    end
  end
  print(string.format("  real data: %d species below the floor of %d, %d thrown at more easily",
    below, Qol.CATCH_FLOOR, raised))
  eq(lowered, 0, "real data: every species thrown at max(rate, floor)")
  ok(raised > 100 and raised <= below, "real data: the species below the floor got easier")

  ctx.setActive(false)
  ok(same(vanilla, sights(data.gen2Maps)), "real data: exact vanilla sights restored")
  eq(chainLength("catch.rate"), 0, "real data: catch wrap removed")
  eq(award(10), 10, "real data: experience vanilla")
  reset()
  print("real Crystal data checked: " .. cache)
end

print(string.format("qol_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
