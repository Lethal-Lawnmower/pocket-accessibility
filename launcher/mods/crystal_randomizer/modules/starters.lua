-- Crystal randomizer: starters, gift Pokemon and static encounters.
--
-- Nothing in the game's tables is changed.  Every species is swapped as the
-- script VM runs a command, through the `script.command` hook
-- (src/script/gen2/Vm.lua runList), which hands a hook the decoded cart row and
-- runs whatever row the hook passes down instead.  So a vanilla save, or a save
-- with these questions answered NO, runs every row exactly as the cart wrote it,
-- and loading another save needs nothing restored.  The only state is what is
-- worked out at `ctx.onSave` from the seed and the data as it stands then
-- (after the pokemon, stats and evolutions modules, which run first, have made
-- their changes for this save), and it is worked out again on every switch.
--
-- What is swapped, and where:
--   * A script list (one decoded cart script) that gives or fights a Pokemon:
--     `givepoke` (not the trainer-owned gift, KENYA the SPEAROW, whose mail and
--     nickname are the errand), `giveegg` and `loadwildmon`.  Lists that sell
--     a Pokemon for coins (`checkcoins` / `takecoins`, the Game Corner prize
--     counters) are left alone, because their menu names the prize before the
--     purchase; and the catching tutorial (`catchtutorial`) is left alone,
--     because it is a demonstration, not an encounter.
--   * In such a list, every row naming that species follows it: `pokepic`,
--     `cry`, `getmonname`, `checkpoke`, and every `writetext` whose text names
--     the species or its type ("CYNDAQUIL, the fire POKéMON?" in Elm's lab),
--     so what the player hears is what they get.  The type Elm names is the
--     given species' type as it stands for this save, so it stays right when
--     the pokemon module has shuffled types, even with the starters left alone.
--
-- Elm's three balls are the givepoke rows for CHIKORITA, CYNDAQUIL and TOTODILE;
-- those three become three different species and are published as
-- ctx.shared.starters, and the rival's side of each ball as
-- ctx.shared.starterRivalPairs (see publish below), for the trainers module.
-- Options for the three balls:
--   * starters_stages: every starter is the first stage of a three-stage line
--     in the evolution data of this save.
--   * starters_triangle: the three beat each other in a circle the way the
--     vanilla three do.  In vanilla the rival takes the ball strong against
--     the player's (player CHIKORITA, rival CYNDAQUIL; CYNDAQUIL, TOTODILE;
--     TOTODILE, CHIKORITA), so the species in each rival ball is strong against
--     the one in the player's ball, and not the other way round.
--
-- Every other gift and static encounter keeps its level and gets a species
-- chosen from a stream keyed by its vanilla species alone, so one gift reached
-- by two scripts (the Karate King's Tyrogue) is the same on both paths.  With
-- gifts_legendary, a legendary static (HO-OH, LUGIA, SUICUNE, CELEBI) becomes
-- another legendary, each a different one, and every other gift and static
-- becomes a species that is not legendary.
--
-- What counts as legendary comes from the data: both egg groups EGG_NONE and
-- genderless (the wild module's round-one rule; on the cart's data it is the
-- same twelve species as this module's round-one rule, no egg group, no
-- evolution and no pre-evolution, but it does not move when evolutions are
-- shuffled).  That shape covers the eleven legendaries, MEW and UNOWN; the pool
-- a legendary static is drawn from is the shape's species whose base stat
-- total is above the average species', which leaves UNOWN out.
--
-- Not reached by this module (there is no script row to rewrite):
--   * SHUCKIE (`special GiveShuckle`, src/script/gen2/Specials.lua), and the
--     Odd Egg (`special GiveOddEgg`, src/script/gen2/specials/crystal_story.lua).
--   * Raikou and Entei: they roam (src/core/gen2 Roamers), they are never a
--     `loadwildmon`.
--   * Overworld sprites keep their vanilla look, so a sprite the navigation
--     names by its sheet (SPRITE_BIG_SNORLAX reads "Snorlax") still says so.

local M = {
  id = "starters",
  questions = {
    { key = "starters", kind = "yesno", text = "Shuffle the\nstarter POKéMON?",
      recommended = true, everything = true },
    { key = "starters_stages", kind = "yesno", onlyIf = "starters",
      text = "Starters with\nthree stages?", recommended = true, everything = true },
    { key = "starters_triangle", kind = "yesno", onlyIf = "starters",
      text = "Keep a type\ntriangle among\vthe starters?", recommended = true, everything = true },
    { key = "gifts", kind = "yesno", text = "Shuffle gift and\nstatic POKéMON?",
      recommended = true, everything = true },
    { key = "gifts_legendary", kind = "yesno", onlyIf = "gifts",
      text = "Legendaries stay\nlegendary?", recommended = true, everything = true },
  },
}

-- The three balls in Elm's lab, in the order ctx.shared.starters lists them.
M.STARTERS = { "CHIKORITA", "CYNDAQUIL", "TOTODILE" }
-- The ball the vanilla rival takes when the player takes a given ball: the
-- cart's own pairing (his member ids RIVAL1_1_CHIKORITA and so on follow it).
M.RIVAL_BALL = { CHIKORITA = "CYNDAQUIL", CYNDAQUIL = "TOTODILE", TOTODILE = "CHIKORITA" }
local IS_STARTER = {}
for _, id in ipairs(M.STARTERS) do IS_STARTER[id] = true end

-- Ops that mean "this list is not a gift or an encounter" (see above).
local SKIP_LIST_OPS = { checkcoins = true, takecoins = true, catchtutorial = true }

local GENDER_UNKNOWN, NO_EGGS_RAW = 255, 255
local STAT_KEYS = { "hp", "attack", "defense", "speed", "specialAttack", "specialDefense" }

-- ---------------------------------------------------------------- species data

-- Genderless and unable to breed: the legendaries, MEW and UNOWN in the cart.
function M.isLegendaryShape(def)
  if type(def) ~= "table" or def.genderRatio ~= GENDER_UNKNOWN then return false end
  if type(def.eggGroupsRaw) == "number" then return def.eggGroupsRaw == NO_EGGS_RAW end
  local groups = def.eggGroups
  return type(groups) == "table" and groups[1] == "EGG_NONE" and groups[2] == "EGG_NONE"
end

local function baseStatTotal(def)
  local stats = def and def.baseStats
  if type(stats) ~= "table" then return 0 end
  local total = 0
  for _, key in ipairs(STAT_KEYS) do
    if type(stats[key]) == "number" then total = total + stats[key] end
  end
  return total
end

-- The number of stages on the longest line starting at `id` in the current
-- evolution data (1 for a species that does not evolve).  `seen` guards
-- against a loop a shuffle might make.
local function lineLength(pokemon, id, seen)
  seen = seen or {}
  if seen[id] then return 0 end
  seen[id] = true
  local best = 0
  local def = pokemon[id]
  for _, evo in ipairs(def and def.evolutions or {}) do
    if evo.into and type(pokemon[evo.into]) == "table" then
      best = math.max(best, lineLength(pokemon, evo.into, seen))
    end
  end
  seen[id] = nil
  return 1 + best
end
M.lineLength = lineLength

-- Everything the choices need from the data as it stands now.  Not cached:
-- the evolutions and types change per save, so install works it out again at
-- every save switch.  Lists are sorted by index, so the same seed picks the
-- same species whatever order `pairs` walks the table in.
function M.species(pokemon)
  local byIndex, all = {}, {}
  local evolvedInto = {}
  for id, def in pairs(pokemon or {}) do
    if type(def) == "table" and type(def.index) == "number" and def.baseStats then
      byIndex[def.index] = id
      all[#all + 1] = id
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.into then evolvedInto[evo.into] = true end
      end
    end
  end
  table.sort(all, function(a, b) return pokemon[a].index < pokemon[b].index end)
  local totalStats = 0
  for _, id in ipairs(all) do totalStats = totalStats + baseStatTotal(pokemon[id]) end
  local averageStats = #all > 0 and totalStats / #all or 0
  -- basic: first stages (nothing evolves into them) that are not legendary-
  -- shaped; starters and eggs come from here.  threeStage: those whose line
  -- has three stages.  ordinary: every species that is not legendary-shaped.
  -- legendary: legendary-shaped and stronger than the average species.
  local basic, threeStage, ordinary, legendary = {}, {}, {}, {}
  local isLegendary = {}
  for _, id in ipairs(all) do
    local def = pokemon[id]
    if M.isLegendaryShape(def) then
      if baseStatTotal(def) > averageStats then
        legendary[#legendary + 1] = id
        isLegendary[id] = true
      end
    else
      ordinary[#ordinary + 1] = id
      if not evolvedInto[id] then
        basic[#basic + 1] = id
        if lineLength(pokemon, id) == 3 then threeStage[#threeStage + 1] = id end
      end
    end
  end
  return { byIndex = byIndex, all = all, basic = basic, threeStage = threeStage,
    ordinary = ordinary, legendary = legendary, isLegendary = isLegendary }
end

-- ---------------------------------------------------------------- type strength

-- attacker type -> defender type -> multiplier (1 when the chart is silent).
function M.typeTable(typeChart)
  local out = {}
  for _, row in ipairs(type(typeChart) == "table" and typeChart.matchups or {}) do
    if row.attacker and row.defender and type(row.multiplier) == "number" then
      out[row.attacker] = out[row.attacker] or {}
      out[row.attacker][row.defender] = row.multiplier / 10
    end
  end
  return out
end

local function distinctTypes(def)
  local types = def and def.types or {}
  local out = {}
  if types[1] then out[1] = types[1] end
  if types[2] and types[2] ~= types[1] then out[#out + 1] = types[2] end
  return out
end

-- True when one of `a`'s types hits `b` super effectively, counting both of
-- `b`'s types.
function M.hitsHard(chart, a, b)
  for _, attack in ipairs(distinctTypes(a)) do
    local row = chart[attack] or {}
    local mult = 1
    for _, defend in ipairs(distinctTypes(b)) do
      local m = row[defend]
      if m then mult = mult * m end
    end
    if mult > 1 then return true end
  end
  return false
end

-- `a` is strong against `b`: it hits `b` hard and `b` does not hit it hard.
function M.strongAgainst(chart, a, b)
  return M.hitsHard(chart, a, b) and not M.hitsHard(chart, b, a)
end

-- ---------------------------------------------------------------- the choices

-- Three species from `order` (in that order of preference) where each rival
-- ball beats its player ball: CYNDAQUIL's beats CHIKORITA's, TOTODILE's beats
-- CYNDAQUIL's, CHIKORITA's beats TOTODILE's.  nil when no three do.
function M.findTriangle(order, pokemon, chart)
  local memo = {}
  local function strong(a, b)
    local key = a .. ">" .. b
    local v = memo[key]
    if v == nil then
      v = M.strongAgainst(chart, pokemon[a], pokemon[b])
      memo[key] = v
    end
    return v
  end
  for _, x in ipairs(order) do
    for _, y in ipairs(order) do
      if y ~= x and strong(y, x) then
        for _, z in ipairs(order) do
          if z ~= x and z ~= y and strong(z, y) and strong(x, z) then
            return { CHIKORITA = x, CYNDAQUIL = y, TOTODILE = z }
          end
        end
      end
    end
  end
  return nil
end

-- Version 2 of the triangle search (saves made from 2026-11-10).  findTriangle
-- takes the first triangle in a shuffled order, so on the cart's data, with
-- three stages, GEODUDE, LARVITAR and CHIKORITA each turned up in about a third
-- of all seeds (three times their share) and some species never did.  Here
-- every triangle is listed and each gets a weight, worked out from the data
-- alone, that evens out how often each species is in the chosen one as far as
-- the types allow (iterative proportional scaling: a species in too many
-- triangles has its triangles scaled down, one in too few up).  The seed then
-- draws one triangle by weight and turns it so any of its three may be in any
-- ball.  nil when there is no triangle.
M.TRIANGLE_ROUNDS = 200

function M.triangles(pool, pokemon, chart)
  local beatenBy = {}
  for _, a in ipairs(pool) do
    local list = {}
    for _, b in ipairs(pool) do
      if b ~= a and M.strongAgainst(chart, pokemon[b], pokemon[a]) then list[#list + 1] = b end
    end
    beatenBy[a] = list
  end
  local strong = {}
  for a, list in pairs(beatenBy) do
    for _, b in ipairs(list) do strong[b .. ">" .. a] = true end
  end
  -- x the CHIKORITA ball, y beats x, z beats y, x beats z; each cycle once,
  -- with its earliest species (in pool order) first
  local rank = {}
  for i, id in ipairs(pool) do rank[id] = i end
  local list = {}
  for _, x in ipairs(pool) do
    for _, y in ipairs(beatenBy[x]) do
      for _, z in ipairs(beatenBy[y]) do
        if z ~= x and strong[x .. ">" .. z] and rank[x] < rank[y] and rank[x] < rank[z] then
          list[#list + 1] = { x, y, z }
        end
      end
    end
  end
  return list
end

function M.triangleWeights(list)
  local weights = {}
  for i = 1, #list do weights[i] = 1 end
  for _ = 1, M.TRIANGLE_ROUNDS do
    local share, total = {}, 0
    for i, tri in ipairs(list) do
      for _, id in ipairs(tri) do share[id] = (share[id] or 0) + weights[i] end
      total = total + weights[i]
    end
    local count = 0
    for _ in pairs(share) do count = count + 1 end
    local target = 3 * total / count
    for i, tri in ipairs(list) do
      local factor = 1
      for _, id in ipairs(tri) do factor = factor * (target / share[id]) end
      weights[i] = weights[i] * factor ^ (1 / 3)
    end
  end
  return weights
end

-- Per pool table: M.species builds new pools at every save switch, so a
-- cached answer never outlives the types and evolutions it was made from.
local triangleCache = setmetatable({}, { __mode = "k" })

function M.fairTriangle(rng, pool, pokemon, chart)
  local cached = triangleCache[pool]
  if not cached then
    local list = M.triangles(pool, pokemon, chart)
    cached = { list = list, weights = M.triangleWeights(list) }
    triangleCache[pool] = cached
  end
  local list, weights = cached.list, cached.weights
  if #list == 0 then return nil end
  local total = 0
  for _, w in ipairs(weights) do total = total + w end
  local at, chosen = rng:next() * total, list[#list]
  for i, w in ipairs(weights) do
    at = at - w
    if at < 0 then chosen = list[i]; break end
  end
  -- turning the cycle keeps every rival ball strong against its player ball
  local turn = rng:int(0, 2)
  local balls = {}
  for i = 1, 3 do balls[i] = chosen[(i - 1 + turn) % 3 + 1] end
  return { CHIKORITA = balls[1], CYNDAQUIL = balls[2], TOTODILE = balls[3] }
end

-- { CHIKORITA = x, CYNDAQUIL = y, TOTODILE = z }, three different species,
-- and whether the type triangle was asked for and found.  `options` holds
-- `stages`, `triangle` and `fair` (version 2's triangle search); `chart` is M.typeTable's.
function M.chooseStarters(ctx, pokemon, options, chart, species)
  options = options or {}
  species = species or M.species(pokemon)
  local pool = options.stages and species.threeStage or species.basic
  if #pool < 3 then return nil end
  if options.triangle and chart and options.fair then
    local found = M.fairTriangle(ctx.rng("starters", "triangle", options.stages and "stages" or "any"),
      pool, pokemon, chart)
    if found then return found, true end
  elseif options.triangle and chart then
    local order = ctx.rng("starters", "triangle", options.stages and "stages" or "any"):shuffled(pool)
    local found = M.findTriangle(order, pokemon, chart)
    if found then return found, true end
  end
  -- Round one's stream, so a save with the new options off picks as before.
  local order = ctx.rng("starters"):shuffled(pool)
  local out = {}
  for i, vanilla in ipairs(M.STARTERS) do out[vanilla] = order[i] end
  return out, false
end

-- Each vanilla legendary in `species.legendary` to a different one: one
-- shuffle of the pool, and each member goes to the next (a single loop, so no
-- legendary stays itself while there are two or more).
function M.legendaryMap(ctx, species)
  local pool = species.legendary
  local order = ctx.rng("gifts", "legendary"):shuffled(pool)
  local map = {}
  for i, id in ipairs(order) do map[id] = order[i % #order + 1] end
  return map
end

-- The species given instead of `vanilla` by a gift (`kind` "gift") or an egg
-- (`kind` "egg", from the first-stage pool, since an egg hatches one).  With
-- `keepLegendary`, a legendary goes through `legendaryMap` and anything else
-- comes from the species that are not legendary.
function M.chooseGift(ctx, pokemon, vanilla, kind, species, keepLegendary, legendaryMap)
  species = species or M.species(pokemon)
  if kind == "egg" then return ctx.rng("gifts", kind, vanilla):pick(species.basic) end
  if keepLegendary then
    if species.isLegendary[vanilla] then
      return (legendaryMap or M.legendaryMap(ctx, species))[vanilla]
    end
    return ctx.rng("gifts", kind, vanilla):pick(species.ordinary)
  end
  return ctx.rng("gifts", kind, vanilla):pick(species.all)
end

-- ---------------------------------------------------------------- text

-- The word the cart's prose uses for a type: "fire", "psychic".
local function typeWord(typeId)
  return (tostring(typeId):gsub("_TYPE$", "")):lower()
end

function M.typePhrase(def)
  local types = def and def.types or {}
  local first, second = types[1], types[2]
  if not first then return nil end
  if second and second ~= first then
    return typeWord(first) .. "/" .. typeWord(second)
  end
  return typeWord(first)
end

-- The set of type words the prose can use, from the type chart and every
-- species' types.
function M.typeWords(data)
  local words = {}
  local chart = data and data.type_chart
  for id in pairs(chart and chart.types or {}) do words[typeWord(id)] = true end
  for _, def in pairs(data and data.pokemon or {}) do
    if type(def) == "table" and type(def.types) == "table" then
      for _, t in ipairs(def.types) do words[typeWord(t)] = true end
    end
  end
  return words
end

-- Every whole-word `from` in `body` (no capital letter touching either end, so
-- a name inside a longer name is not hit) becomes `to`.
local function replaceWord(body, from, to)
  if from == "" or from == to then return body end
  local out, pos = {}, 1
  while true do
    local s, e = body:find(from, pos, true)
    if not s then break end
    local before = s > 1 and body:sub(s - 1, s - 1) or ""
    local after = body:sub(e + 1, e + 1)
    if before:match("%u") or after:match("%u") then
      out[#out + 1] = body:sub(pos, e)
    else
      out[#out + 1] = body:sub(pos, s - 1) .. to
    end
    pos = e + 1
  end
  out[#out + 1] = body:sub(pos)
  return table.concat(out)
end

local function namesWord(body, name)
  return replaceWord(body, name, "\0") ~= body
end

-- A phrase "fire" or "grass/poison" made only of type words.
local function isTypePhrase(phrase, words)
  if phrase == "" then return false end
  for part in (phrase .. "/"):gmatch("([^/]*)/") do
    if not words[part] then return false end
  end
  return true
end

-- Every "<type> POKéMON" and "<type>-type" in `body` names `phrase` instead.
local function setTypePhrase(body, phrase, words)
  local function swap(suffix)
    return function(found)
      if isTypePhrase(found, words) then return phrase .. suffix end
      return found .. suffix
    end
  end
  body = body:gsub("([%l/]+) POKéMON", swap(" POKéMON"))
  body = body:gsub("([%l/]+)%-type", swap("-type"))
  return body
end

-- `body` with the vanilla species' name replaced by the new one's, and, in a
-- text that names it, its type ("the fire POKéMON", "a fighting-type") set to
-- the new one's current type.  `words` is M.typeWords; without it only the
-- old species' own type phrase is recognised.  The text box soft-wraps a line
-- that grows past the box (src/render/TextBox.lua paginate).
function M.rewriteText(body, fromDef, toDef, words)
  if type(body) ~= "string" or not fromDef or not toDef then return body end
  local fromName, toName = fromDef.name or fromDef.id, toDef.name or toDef.id
  if not namesWord(body, fromName) then return body end
  body = replaceWord(body, fromName, toName)
  local toType = M.typePhrase(toDef)
  if not toType then return body end
  if not words then
    words = {}
    local fromType = M.typePhrase(fromDef)
    if not fromType then return body end
    for part in (fromType .. "/"):gmatch("([^/]*)/") do words[part] = true end
  end
  return setTypePhrase(body, toType, words)
end

-- ---------------------------------------------------------------- the rows

local function speciesOf(cmd)
  local args = cmd.args
  return cmd.species or (args and args[1])
end

-- Which species a list gives or fights, and how: { [index] = "starter" |
-- "gift" | "egg" }, or false for a list with none.  Cached per list table
-- (a list's rows never change, and which vanilla species a row names does not
-- depend on the save).
local planCache = setmetatable({}, { __mode = "k" })

function M.planFor(list, byIndex)
  local cached = planCache[list]
  if cached ~= nil then return cached end
  local plan = false
  if type(list) == "table" then
    for _, cmd in ipairs(list) do
      if type(cmd) == "table" and SKIP_LIST_OPS[cmd.op] then
        planCache[list] = false
        return false
      end
    end
    for _, cmd in ipairs(list) do
      local op = type(cmd) == "table" and cmd.op
      local index, kind
      if op == "givepoke" then
        local trainer = cmd.trainer or (cmd.args and cmd.args[4]) or 0
        if trainer == 0 then index = speciesOf(cmd) end
      elseif op == "giveegg" then
        index, kind = speciesOf(cmd), "egg"
      elseif op == "loadwildmon" then
        index = speciesOf(cmd)
      end
      local id = index and byIndex[index]
      if id then
        plan = plan or {}
        plan[index] = kind or (IS_STARTER[id] and "starter") or "gift"
      end
    end
  end
  planCache[list] = plan
  return plan
end

local SPECIES_FIELD = {
  givepoke = "species", giveegg = "species", loadwildmon = "species",
  pokepic = "species", getmonname = "species", checkpoke = "species",
  cry = "id",
}

local function copyRow(cmd)
  local row = {}
  for k, v in pairs(cmd) do row[k] = v end
  return row
end

-- The row to run instead of `cmd`, or nil to run the cart's own.
-- `swap` maps a vanilla species index to the index given instead (changed
-- ones only); `given` lists every species the list gives, { from = index,
-- to = index }, sorted by `from`, changed or not, so a text's type follows the
-- given species even when only its type changed.
function M.rewriteRow(cmd, swap, pokemon, byIndex, text, textKeyPrefix, given, words)
  local op = cmd.op
  local field = SPECIES_FIELD[op]
  if field then
    local current = cmd[field]
    if current == nil and field == "species" then current = speciesOf(cmd) end
    local new = current and swap[current]
    if not new then return nil end
    local row = copyRow(cmd)
    row[field] = new
    if op == "giveegg" or op == "pokepic" or op == "checkpoke" then
      -- these read args[1] when the decoded field is missing; keep both agreeing
      if type(cmd.args) == "table" then
        local args = copyRow(cmd.args)
        args[1] = new
        row.args = args
      end
    end
    return row
  end
  if (op == "writetext" or op == "farwritetext") and cmd.text and text then
    local body = text[cmd.text]
    if type(body) ~= "string" then return nil end
    if not given then
      given = {}
      for from, to in pairs(swap) do given[#given + 1] = { from = from, to = to } end
      table.sort(given, function(a, b) return a.from < b.from end)
    end
    local rewritten, tag = body, {}
    for _, pair in ipairs(given) do
      local toDef = pokemon[byIndex[pair.to]]
      rewritten = M.rewriteText(rewritten, pokemon[byIndex[pair.from]], toDef, words)
      tag[#tag + 1] = pair.from .. ">" .. pair.to .. "=" .. tostring(M.typePhrase(toDef))
    end
    if rewritten == body then return nil end
    -- A key of our own, named by the cart's key and the swap, so the vanilla
    -- entry is never touched.  It is written each time it is used, so a save
    -- whose types differ never hears another save's text.
    local key = textKeyPrefix .. cmd.text .. ":" .. table.concat(tag, ",")
    text[key] = rewritten
    local row = copyRow(cmd)
    row.text = key
    return row
  end
  return nil
end

-- ---------------------------------------------------------------- install

function M.install(mod, ctx)
  -- Everything here is rebuilt from the seed and the current data at every
  -- save switch; nothing in the game's tables is written.
  local state = {}

  local function gameData()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    if type(data) == "table" and type(data.pokemon) == "table" then return data end
    return nil
  end

  local function reset()
    state = { data = nil, species = nil, starters = nil, gifts = {}, legendaryMap = nil,
      chart = nil, words = nil }
    ctx.shared.starters, ctx.shared.starterRivalPairs = nil, nil
  end

  -- The data-derived tables for this save, worked out once per switch (or on
  -- first use, when the game's data was not there yet at the switch).
  local function prepare()
    if state.data then return state.data end
    local data = gameData()
    if not data then return nil end
    state.data = data
    state.species = M.species(data.pokemon)
    state.chart = M.typeTable(data.type_chart)
    state.words = M.typeWords(data)
    return data
  end

  -- ctx.shared.starterRivalPairs: keyed by the ball the player takes,
  --   { player = species in that ball, rivalBall = the ball the vanilla rival
  --     then takes, rival = species in it, strong = true when that species is
  --     strong against the player's (it hits it super effectively and is not
  --     hit super effectively back), with this save's types }.
  local function publish(starters, triangle)
    local copy, pairs_ = {}, {}
    for k, v in pairs(starters) do copy[k] = v end
    for _, ball in ipairs(M.STARTERS) do
      local rivalBall = M.RIVAL_BALL[ball]
      local pokemon = state.data.pokemon
      pairs_[ball] = { player = starters[ball], rivalBall = rivalBall, rival = starters[rivalBall],
        strong = M.strongAgainst(state.chart, pokemon[starters[rivalBall]], pokemon[starters[ball]]) }
    end
    ctx.shared.starters, ctx.shared.starterRivalPairs = copy, pairs_
    ctx.log("starters: CHIKORITA>%s CYNDAQUIL>%s TOTODILE>%s%s%s",
      copy.CHIKORITA, copy.CYNDAQUIL, copy.TOTODILE,
      ctx.option("starters_stages") and ", three stages" or "",
      triangle and ", type triangle" or (ctx.option("starters_triangle") and ", no triangle found" or ""))
  end

  local function refreshStarters()
    if not (ctx.active() and ctx.option("starters")) then return end
    local data = prepare()
    if not data then return end
    local chosen, triangle = M.chooseStarters(ctx, data.pokemon,
      { stages = ctx.option("starters_stages") == true, triangle = ctx.option("starters_triangle") == true,
        fair = (ctx.version and ctx.version() or 1) >= 2 },
      state.chart, state.species)
    state.starters = chosen
    if chosen then publish(chosen, triangle) end
  end

  ctx.onSave(function()
    reset()
    if ctx.active() then refreshStarters() end
  end)

  -- The species id given instead of vanilla `id`, or nil to keep it.
  local function replacementFor(id, kind, pokemon)
    if kind == "starter" then
      if not ctx.option("starters") then return nil end
      if not state.starters then refreshStarters() end
      return state.starters and state.starters[id]
    end
    if not ctx.option("gifts") then return nil end
    local key = kind .. ":" .. id
    local chosen = state.gifts[key]
    if chosen == nil then
      local keep = ctx.option("gifts_legendary") == true
      if keep and not state.legendaryMap then state.legendaryMap = M.legendaryMap(ctx, state.species) end
      chosen = M.chooseGift(ctx, pokemon, id, kind, state.species, keep, state.legendaryMap) or false
      state.gifts[key] = chosen
    end
    return chosen or nil
  end

  local function hook(nextFn, sctx, name, args, cmd)
    if not ctx.active() or type(cmd) ~= "table" then
      return nextFn(sctx, name, args, cmd)
    end
    local vm = type(sctx) == "table" and sctx.vm or nil
    local data = prepare()
    if not (vm and data) then return nextFn(sctx, name, args, cmd) end
    local species = state.species
    local plan = M.planFor(vm.cmdList, species.byIndex)
    if not plan then return nextFn(sctx, name, args, cmd) end
    local swap, given = {}, {}
    for index, kind in pairs(plan) do
      local id = species.byIndex[index]
      local new = replacementFor(id, kind, data.pokemon)
      local def = new and data.pokemon[new]
      local to = index
      if def and def.index ~= index then
        swap[index] = def.index
        to = def.index
      end
      given[#given + 1] = { from = index, to = to }
    end
    table.sort(given, function(a, b) return a.from < b.from end)
    local row = M.rewriteRow(cmd, swap, data.pokemon, species.byIndex,
      vm.text, "crystal_randomizer:", given, state.words)
    return nextFn(sctx, name, args, row or cmd)
  end

  reset()
  if mod and mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("script.command", hook)
  else
    ctx.log("starters: no mod.hooks; nothing will be randomized")
  end
end

return M
