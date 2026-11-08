-- Crystal randomizer: where the HMs are found.
--
-- The pool is the seven HMs and nothing else (CONTRACT.md "keyitems"; why the
-- story key items are not in it is at the end of this comment).  Each HM's
-- vanilla source is a location; the seven HMs are dealt out again among those
-- seven locations, so every save still holds each HM exactly once:
--
--   SPROUT_TOWER_3F       HM05 FLASH      the Elder, after his battle
--   ILEX_FOREST           HM01 CUT        the charcoal master, after the FARFETCH'D
--   DANCE_THEATER         HM03 SURF       the gentleman, after the five KIMONO GIRLS
--   OLIVINE_CAFE          HM04 STRENGTH   the sailor
--   CIANWOOD_CITY         HM02 FLY        CHUCK's wife, after his badge
--   TEAM_ROCKET_BASE_B2F  HM06 WHIRLPOOL  LANCE, at the end of the hideout
--   ICE_PATH_1F           HM07 WATERFALL  an item ball
--
-- Only placements that keep the game beatable are used.  M.EVENTS and
-- M.SITES below are a logic model of Johto: what each story step and each
-- location needs (badges, story events, and the HMs together with the badge
-- that lets them be used outside battle).  Every permutation of the seven HMs
-- over the seven locations is checked against it once (5040 of them) and a
-- save's seed picks one of the beatable ones.  A beatable placement is one
-- where, starting with nothing, the player can reach every location, every
-- badge and the Elite Four.
--
-- The model is deliberately strict.  Where a step's true needs were not
-- certain, it needs everything a vanilla player necessarily holds at that
-- point of the vanilla story (the vanilla game proves that set is enough),
-- and only routes the vanilla story itself uses are modelled.  Strictness
-- only removes placements; it can never let one through that strands the
-- player.  The sources, per step, are next to each entry: pret/pokecrystal's
-- map scripts (maps/*.asm) and the cart's own decoded scripts and maps.
--
-- How the game is changed, per save (ctx.onSave): nothing in the scripts is
-- rewritten.  A `script.command` hook (src/script/gen2/Vm.lua runList) passes
-- a copy of each giving row (`verbosegiveitem`) carrying the placed HM, so
-- the VM's own "<PLAYER> received HM03." names it and puts it in the bag.
-- The NPC lines around the gift that name the vanilla HM ("That's SURF.",
-- "Take this FLASH HM.") are passed as copies pointing at new text keys whose
-- text names the placed HM, its move and the badge it needs.  The Ice Path
-- ball is the one table changed: its `itemball.item`, which the world reads
-- when the ball is picked up and the navigation reads to name it (as the
-- items module does), is set and put back exactly on every save switch.
--
-- Before anything is changed, the locations are found in the game data by
-- map and vanilla item (not by script address, so either Crystal revision
-- works), and every line to be rewritten is found by its words.  If any of
-- that does not match, or an HM no longer teaches its field move, the module
-- changes nothing for that save and says so in the log.
--
-- Not in the pool, and why (each needs its own audit before it can be added):
--   * SQUIRTBOTTLE: the flower shop hands it over only while SUDOWOODO has
--     not been fought (GoldenrodFlowerShop.asm: `checkevent
--     EVENT_FOUGHT_SUDOWOODO / iftrue .Lalala` before the gift).  With the
--     bottle found elsewhere, a player who waters SUDOWOODO first loses the
--     flower shop's item for good.
--   * BASEMENT KEY, CARD KEY, CLEAR BELL, SECRETPOTION, MACHINE PART, LOST
--     ITEM, PASS, S.S.TICKET, MYSTERY EGG, GS BALL, RED SCALE, BLUE CARD: each
--     is handed over inside a story chain whose next script takes it back or
--     checks for it, and holding one early could open a door out of order.
--   * BICYCLE: a plain `giveitem` with the shop's own "borrowed" lines.
--   * The rods, ITEMFINDER and COIN CASE: not progression; their offers and
--     explanations are about the item itself and are not rewritten yet.
--   * Kanto has no location in the pool, so it is not modelled.

local M = {
  id = "keyitems",
  questions = {
    { key = "keyitems", kind = "yesno", text = "Shuffle where\nHMs are found?",
      recommended = false, everything = false },
  },
}

-- ---------------------------------------------------------------- field moves

-- The move each HM teaches and the badge that allows it outside battle
-- (pokecrystal engine/events/overworld.asm: CutFunction ENGINE_HIVEBADGE,
-- FlashFunction ZEPHYR, SurfFunction FOG, FlyFunction STORM, StrengthFunction
-- PLAIN, WhirlpoolFunction GLACIER, WaterfallFunction RISING).  `use` is the
-- line the rewritten explanation says about the move.
M.FIELD_MOVES = {
  HM_CUT = { move = "CUT", badge = "HIVE", badgeName = "HIVEBADGE",
    use = "It cuts down\nsmall trees." },
  HM_FLY = { move = "FLY", badge = "STORM", badgeName = "STORMBADGE",
    use = "It flies you to\ntowns you have\vvisited." },
  HM_SURF = { move = "SURF", badge = "FOG", badgeName = "FOGBADGE",
    use = "It lets POKéMON\nswim across water." },
  HM_STRENGTH = { move = "STRENGTH", badge = "PLAIN", badgeName = "PLAINBADGE",
    use = "It lets POKéMON\nmove boulders." },
  HM_FLASH = { move = "FLASH", badge = "ZEPHYR", badgeName = "ZEPHYRBADGE",
    use = "It lights up even\nthe darkest caves." },
  HM_WHIRLPOOL = { move = "WHIRLPOOL", badge = "GLACIER", badgeName = "GLACIERBADGE",
    use = "It gets POKéMON\npast whirlpools." },
  HM_WATERFALL = { move = "WATERFALL", badge = "RISING", badgeName = "RISINGBADGE",
    use = "It lets POKéMON\nclimb waterfalls." },
}

-- ---------------------------------------------------------------- the logic model

-- A need is a story step's id, "item:HM_X" (the player holds that HM) or
-- "use:HM_X" (holds it and has the badge for it).
local ALL_USES = { "use:HM_CUT", "use:HM_FLY", "use:HM_SURF", "use:HM_STRENGTH",
  "use:HM_FLASH", "use:HM_WHIRLPOOL", "use:HM_WATERFALL" }

local function concat(...)
  local out = {}
  for i = 1, select("#", ...) do
    for _, v in ipairs((select(i, ...))) do out[#out + 1] = v end
  end
  return out
end

-- Story steps, in vanilla order.  `why` names the source.
M.EVENTS = {
  { id = "ZEPHYR", needs = {},
    why = "VioletGym: Falkner; Violet is reached from New Bark with no HM" },
  { id = "AZALEA", needs = { "ZEPHYR" },
    why = "Route 32, Union Cave, Route 33: walked in vanilla before any HM" },
  { id = "HIVE", needs = { "AZALEA" },
    why = "SlowpokeWellB1F then AzaleaGym: no HM" },
  { id = "GOLDENROD", needs = { "HIVE", "use:HM_CUT" },
    why = "IlexForest: the CUT tree on the way to Route 34 (the only route modelled)" },
  { id = "PLAIN", needs = { "GOLDENROD" }, why = "GoldenrodGym: Whitney" },
  { id = "ECRUTEAK", needs = { "GOLDENROD", "PLAIN" },
    why = "Route 35, National Park, Route 36: SUDOWOODO needs the SQUIRTBOTTLE, "
      .. "which GoldenrodFlowerShop gives after FLORIA and the PLAINBADGE (not shuffled)" },
  { id = "FOG", needs = { "ECRUTEAK" }, why = "BurnedTower1F/B1F, then EcruteakGym: no HM" },
  { id = "OLIVINE", needs = { "ECRUTEAK" }, why = "Routes 38 and 39: walked" },
  { id = "CIANWOOD", needs = { "OLIVINE", "use:HM_SURF" }, why = "Routes 40 and 41: water" },
  { id = "STORM", needs = { "CIANWOOD", "use:HM_STRENGTH" },
    why = "CianwoodGym: STRENGTH boulders in front of Chuck" },
  { id = "MINERAL", needs = { "CIANWOOD" },
    why = "OlivineLighthouse6F, CianwoodPharmacy's SECRETPOTION (not shuffled), OlivineGym" },
  { id = "MAHOGANY", needs = { "ECRUTEAK", "STORM", "MINERAL", "use:HM_SURF",
      "use:HM_STRENGTH", "use:HM_CUT" },
    why = "Route 42 and Mt. Mortar; strict: everything a vanilla player holds by then" },
  { id = "HIDEOUT", needs = { "MAHOGANY", "use:HM_SURF" },
    why = "LakeOfRage: the red GYARADOS is on the water; Lance, then TeamRocketBaseB1F-B3F" },
  { id = "GLACIER", needs = { "HIDEOUT" },
    why = "MahoganyGym: the mart's Rocket blocks it until the hideout is cleared" },
  { id = "RADIO", needs = { "GLACIER", "GOLDENROD" },
    why = "MahoganyGymActivateRockets: the takeover starts at seven badges, which the "
      .. "model already holds here; BASEMENT KEY and CARD KEY are not shuffled" },
  { id = "ICE_PATH", needs = { "HIDEOUT", "RADIO", "use:HM_STRENGTH", "use:HM_SURF",
      "use:HM_CUT" },
    why = "MahoganyTown: the RAGECANDYBAR man blocks Route 44 until the hideout is "
      .. "cleared; IcePathB1F has STRENGTH boulders" },
  { id = "BLACKTHORN", needs = { "ICE_PATH" }, why = "through the Ice Path" },
  { id = "RISING", needs = { "BLACKTHORN", "RADIO", "use:HM_CUT", "use:HM_SURF",
      "use:HM_STRENGTH", "use:HM_WHIRLPOOL", "use:HM_FLY", "use:HM_FLASH", "item:HM_WATERFALL" },
    why = "BlackthornCity: Clair is out until the Radio Tower is cleared; "
      .. "BlackthornGym1F boulders; DragonsDen water; strict: every other HM" },
  { id = "LEAGUE",
    needs = concat({ "ZEPHYR", "HIVE", "PLAIN", "FOG", "STORM", "MINERAL", "GLACIER",
      "RISING" }, ALL_USES),
    why = "Route 27 water, Tohjo Falls, VictoryRoadGate's eight-badge check, "
      .. "Victory Road; strict: every HM usable.  The goal." },
}

M.GOAL = "LEAGUE"

-- The locations, in the fixed order placements are listed in.  `kind` is
-- "script" (a person's `verbosegiveitem`) or "ball".  `texts` are the lines
-- around the gift that name the vanilla HM: `find` is a phrase of the cart's
-- text, `replace` the line said instead when another HM is placed here
-- (%MOVE% is the placed HM's move), or "explain" for a generated
-- explanation of the placed HM.
M.SITES = {
  { id = "SPROUT_TOWER_3F", map = "SPROUT_TOWER_3F", item = "HM_FLASH", kind = "script",
    needs = {},
    why = "SproutTower3F SageLiScript: after his battle, no other condition",
    texts = {
      { find = "Take this FLASH",
        replace = "You and your POKé-\nMON should have\fno problem using\nthis move.\f"
          .. "Take this HM,\n%MOVE%.{DONE}" },
      { find = "FLASH illuminates", replace = "explain" },
    } },
  { id = "ILEX_FOREST", map = "ILEX_FOREST", item = "HM_CUT", kind = "script",
    needs = { "HIVE" },
    why = "IlexForest: after the FARFETCH'D is herded, which needs the Slowpoke Well "
      .. "cleared; strict: the HIVEBADGE",
    texts = { { find = "That's the CUT HM.", replace = "explain" } } },
  { id = "DANCE_THEATER", map = "DANCE_THEATER", item = "HM_SURF", kind = "script",
    needs = { "ECRUTEAK" },
    why = "DanceTheater DanceTheaterSurfGuy: after the five KIMONO GIRLS, who are always there",
    texts = { { find = "That's SURF.", replace = "explain" } } },
  { id = "OLIVINE_CAFE", map = "OLIVINE_CAFE", item = "HM_STRENGTH", kind = "script",
    needs = { "OLIVINE" },
    why = "OlivineCafe OlivineCafeStrengthSailorScript: no condition",
    texts = {
      { find = "and teach them",
        replace = "Hah! Your POKéMON\nsure look like\vlightweights!\f"
          .. "Here, use this\nand teach them\v%MOVE%!{DONE}" },
    } },
  { id = "CIANWOOD_CITY", map = "CIANWOOD_CITY", item = "HM_FLY", kind = "script",
    needs = { "STORM" },
    why = "CianwoodCity CianwoodCityChucksWife: after EVENT_BEAT_CHUCK",
    texts = {
      { find = "Teach FLY to your", replace = "explain" },
      { find = "to FLY…", replace = "You crossed the\nsea to get here?\fThat must have\nbeen hard.{DONE}" },
      { find = "FLY without this",
        replace = "If you beat the\nGYM LEADER here,\vcome see me.\f"
          .. "I'll have a nice\ngift for you.{DONE}" },
    } },
  { id = "TEAM_ROCKET_BASE_B2F", map = "TEAM_ROCKET_BASE_B2F", item = "HM_WHIRLPOOL",
    kind = "script", needs = { "HIDEOUT" },
    why = "TeamRocketBaseB2F: LANCE after the last ELECTRODE, every time",
    texts = { { find = "That's WHIRLPOOL.", replace = "explain" } } },
  { id = "ICE_PATH_1F", map = "ICE_PATH_1F", item = "HM_WATERFALL", kind = "ball",
    needs = { "ICE_PATH" },
    why = "IcePath1F IcePath1FHMWaterfall: an item ball", texts = {} },
}

-- ---------------------------------------------------------------- reachability

-- Everything reachable from nothing with `placement` (site id -> item id):
-- returns done (step and site ids -> true) and have (item ids -> true).
function M.sweep(placement)
  local done, have = {}, {}
  local function met(need)
    local kind, id = need:match("^(%a+):(.+)$")
    if kind == "item" then return have[id] == true end
    if kind == "use" then
      local field = M.FIELD_MOVES[id]
      return have[id] == true and field ~= nil and done[field.badge] == true
    end
    return done[need] == true
  end
  local function all(needs)
    for _, need in ipairs(needs) do if not met(need) then return false end end
    return true
  end
  local changed = true
  while changed do
    changed = false
    for _, ev in ipairs(M.EVENTS) do
      if not done[ev.id] and all(ev.needs) then done[ev.id] = true; changed = true end
    end
    for _, site in ipairs(M.SITES) do
      if not done[site.id] and all(site.needs) then
        done[site.id] = true
        changed = true
        local item = placement[site.id]
        if item then have[item] = true end
      end
    end
  end
  return done, have
end

-- True when every location, every step and the goal are reachable.
function M.beatable(placement)
  local done = M.sweep(placement)
  for _, ev in ipairs(M.EVENTS) do if not done[ev.id] then return false end end
  for _, site in ipairs(M.SITES) do if not done[site.id] then return false end end
  return done[M.GOAL] == true
end

function M.vanillaPlacement()
  local out = {}
  for _, site in ipairs(M.SITES) do out[site.id] = site.item end
  return out
end

-- Every permutation of the pool over the sites, in a fixed order, calling
-- fn(placement) for each.  The pool is the sites' vanilla items in site order.
function M.eachPlacement(fn)
  local items, used, current = {}, {}, {}
  for i, site in ipairs(M.SITES) do items[i] = site.item end
  local n = #items
  local function go(depth)
    if depth > n then
      local placement = {}
      for i, site in ipairs(M.SITES) do placement[site.id] = items[current[i]] end
      fn(placement)
      return
    end
    for i = 1, n do
      if not used[i] then
        used[i], current[depth] = true, i
        go(depth + 1)
        used[i] = false
      end
    end
  end
  go(1)
end

local validCache
-- The beatable placements, in permutation order (computed once).
function M.validPlacements()
  if validCache then return validCache end
  local out = {}
  M.eachPlacement(function(p) if M.beatable(p) then out[#out + 1] = p end end)
  validCache = out
  return out
end

-- This seed's placement: one of the beatable ones, chosen by the seed alone.
function M.choose(ctx)
  local valid = M.validPlacements()
  if #valid == 0 then return nil end
  local index = ctx.rng("keyitems", "placement"):int(1, #valid)
  local chosen = {}
  for k, v in pairs(valid[index]) do chosen[k] = v end
  return chosen, index
end

-- ---------------------------------------------------------------- finding the sites

local GIVE_OPS = { verbosegiveitem = true, giveitem = true }

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local function rowItem(cmd)
  return cmd.item or (type(cmd.args) == "table" and cmd.args[1]) or nil
end

-- Every script key a map's events start, and every key those lists jump,
-- call or branch to, sorted.
function M.mapScriptKeys(scripts, map)
  local queue, seen = {}, {}
  local function add(key)
    if type(key) == "string" and type(scripts[key]) == "table" and not seen[key] then
      seen[key] = true
      queue[#queue + 1] = key
    end
  end
  for _, o in ipairs(map.objects or {}) do
    if type(o) == "table" then
      add(o.scriptKey)
      if type(o.trainer) == "table" then add(o.trainer.scriptKey) end
    end
  end
  for _, field in ipairs({ "bgEvents", "coordEvents", "sceneScripts", "callbacks" }) do
    for _, e in ipairs(map[field] or {}) do
      if type(e) == "table" then add(e.scriptKey) end
    end
  end
  local i = 1
  while queue[i] do
    for _, cmd in ipairs(scripts[queue[i]]) do
      if type(cmd) == "table" then
        for _, k in ipairs(sortedKeys(cmd)) do
          if k ~= "text" then add(cmd[k]) end
        end
      end
    end
    i = i + 1
  end
  table.sort(queue)
  return queue
end

-- Finds every site in `data` (data.gen2Maps, gen2Scripts, gen2Text, items).
-- Returns a table { [site id] = { give = { list, index } | ball = itemball,
-- texts = { [text key] = spec } }, itemIndex = { [item id] = index },
-- itemByIndex } or nil and the reason.
function M.discover(data)
  if type(data) ~= "table" then return nil, "no game data" end
  local maps, scripts, text, items =
    data.gen2Maps, data.gen2Scripts, data.gen2Text, data.items
  if type(maps) ~= "table" or type(scripts) ~= "table" or type(text) ~= "table"
      or type(items) ~= "table" then
    return nil, "the game data has no maps, scripts, text or items"
  end
  local found = { sites = {}, itemIndex = {}, itemByIndex = {} }
  for _, site in ipairs(M.SITES) do
    local def = items[site.item]
    local field = M.FIELD_MOVES[site.item]
    if type(def) ~= "table" or type(def.index) ~= "number" then
      return nil, site.item .. " is not in the item data"
    end
    if def.pocket ~= "TM_HM" then return nil, site.item .. " is not in the TM pocket" end
    if def.teaches ~= nil and def.teaches ~= field.move then
      return nil, site.item .. " teaches " .. tostring(def.teaches) .. ", not " .. field.move
    end
    found.itemIndex[site.item] = def.index
    found.itemByIndex[def.index] = site.item
  end
  local claimedText = {}
  for _, site in ipairs(M.SITES) do
    local map = maps[site.map]
    if type(map) ~= "table" then return nil, "no map " .. site.map end
    local index = found.itemIndex[site.item]
    local entry = { texts = {} }
    local keys = M.mapScriptKeys(scripts, map)
    if site.kind == "ball" then
      local balls = {}
      for _, o in ipairs(map.objects or {}) do
        if type(o) == "table" and type(o.itemball) == "table" and o.itemball.item == index then
          balls[#balls + 1] = o.itemball
        end
      end
      if #balls ~= 1 then
        return nil, ("%s: %d balls hold %s, not one"):format(site.map, #balls, site.item)
      end
      entry.ball = balls[1]
    else
      local rows = {}
      for _, key in ipairs(keys) do
        for i, cmd in ipairs(scripts[key]) do
          if type(cmd) == "table" and GIVE_OPS[cmd.op] and rowItem(cmd) == index then
            rows[#rows + 1] = { list = scripts[key], index = i, key = key }
          end
        end
      end
      if #rows ~= 1 then
        return nil, ("%s: %d rows give %s, not one"):format(site.map, #rows, site.item)
      end
      entry.give = rows[1]
    end
    for _, spec in ipairs(site.texts) do
      local hits = 0
      for _, key in ipairs(keys) do
        for _, cmd in ipairs(scripts[key]) do
          local tkey = type(cmd) == "table" and cmd.text
          local body = tkey and text[tkey]
          if type(body) == "string" and body:find(spec.find, 1, true) then
            if claimedText[tkey] and claimedText[tkey] ~= spec then
              return nil, "text " .. tostring(tkey) .. " matches two lines"
            end
            claimedText[tkey] = spec
            if not entry.texts[tkey] then hits = hits + 1 end
            entry.texts[tkey] = spec
          end
        end
      end
      if hits == 0 then
        return nil, ("%s: no line says %q"):format(site.map, spec.find)
      end
    end
    found.sites[site.id] = entry
  end
  if not M.beatable(M.vanillaPlacement()) then
    return nil, "the logic model does not find the vanilla game beatable"
  end
  return found
end

-- ---------------------------------------------------------------- text

local function moveName(data, item)
  local move = M.FIELD_MOVES[item].move
  local def = type(data.moves) == "table" and data.moves[move] or nil
  return (type(def) == "table" and type(def.name) == "string") and def.name or move
end

local function itemName(data, item)
  local def = data.items[item]
  return (type(def) == "table" and def.tmLabel or def.name) or item
end

-- What a rewritten line says when `item` is placed at a site.
function M.lineFor(spec, data, item)
  local move = moveName(data, item)
  if spec.replace == "explain" then
    local field = M.FIELD_MOVES[item]
    return ("That's %s,\n%s.\f%s\fTo use it out of\nbattle, you need\vthe %s.{DONE}")
      :format(itemName(data, item), move, field.use, field.badgeName)
  end
  return (spec.replace:gsub("%%MOVE%%", function() return move end))
end

-- The widest line of a text body, in characters (for the tests).
function M.widestLine(body)
  local widest = 0
  local plain = body:gsub("{DONE}", "")
  for line in (plain .. "\n"):gmatch("([^\n\v\f]*)[\n\v\f]") do
    local _, count = line:gsub("[^\128-\191]", "")
    if count > widest then widest = count end
  end
  return widest
end

local TEXT_PREFIX = "crystal_randomizer:keyitems:"

-- The plan for one placement: give rows to rewrite, text keys to point
-- elsewhere and the bodies of those keys, and the ball's new item.
function M.plan(found, data, placement)
  local plan = { give = {}, text = {}, bodies = {}, ball = nil }
  for _, site in ipairs(M.SITES) do
    local item = placement[site.id]
    local entry = found.sites[site.id]
    if item and item ~= site.item then
      local index = found.itemIndex[item]
      if entry.give then
        plan.give[entry.give.list] = plan.give[entry.give.list] or {}
        plan.give[entry.give.list][entry.give.index] = index
      end
      if entry.ball then plan.ball = { target = entry.ball, item = index } end
      for tkey, spec in pairs(entry.texts) do
        local newKey = TEXT_PREFIX .. tostring(tkey) .. ":" .. item
        plan.text[tkey] = newKey
        plan.bodies[newKey] = M.lineFor(spec, data, item)
      end
    end
  end
  return plan
end

-- The row to run instead of `cmd` (at `list`[`index`]), or nil for the cart's.
function M.rewriteRow(plan, list, index, cmd, textTable)
  local byIndex = list and plan.give[list]
  local item = byIndex and byIndex[index]
  if item and GIVE_OPS[cmd.op] then
    local row = {}
    for k, v in pairs(cmd) do row[k] = v end
    row.item = item
    if type(cmd.args) == "table" then
      local args = {}
      for k, v in pairs(cmd.args) do args[k] = v end
      args[1] = item
      row.args = args
    end
    return row
  end
  local newKey = cmd.text and plan.text[cmd.text]
  if newKey then
    if textTable then textTable[newKey] = plan.bodies[newKey] end
    local row = {}
    for k, v in pairs(cmd) do row[k] = v end
    row.text = newKey
    return row
  end
  return nil
end

-- ---------------------------------------------------------------- install

function M.install(mod, ctx)
  local state = { plan = nil }
  local changed = {}

  local function restore()
    for i = #changed, 1, -1 do
      local row = changed[i]
      row.target[row.field] = row.vanilla
    end
    changed = {}
  end

  local function set(target, field, value)
    if target[field] == value then return end
    changed[#changed + 1] = { target = target, field = field, vanilla = target[field] }
    target[field] = value
  end

  local function gameData()
    local ok, game = pcall(function() return mod.game end)
    local data = ok and type(game) == "table" and game.data or nil
    return type(data) == "table" and data or nil
  end

  local function apply()
    local data = gameData()
    if not data then
      ctx.log("keyitems: no game data yet; HMs stay where they are")
      return
    end
    local found, why = M.discover(data)
    if not found then
      ctx.log("keyitems: not shuffled, %s", tostring(why))
      return
    end
    local placement, index = M.choose(ctx)
    if not placement or not M.beatable(placement) then
      ctx.log("keyitems: no beatable placement; HMs stay where they are")
      return
    end
    local plan = M.plan(found, data, placement)
    if plan.ball then set(plan.ball.target, "item", plan.ball.item) end
    state.plan = plan
    local copy, parts = {}, {}
    for _, site in ipairs(M.SITES) do
      copy[site.id] = placement[site.id]
      parts[#parts + 1] = site.id .. "=" .. placement[site.id]
    end
    ctx.shared.keyitems = copy
    ctx.log("keyitems: placement %d of %d: %s", index, #M.validPlacements(),
      table.concat(parts, " "))
  end

  ctx.onSave(function(active)
    restore()
    state.plan = nil
    if active and ctx.option("keyitems") then apply() end
  end)

  local function hook(nextFn, sctx, name, args, cmd)
    local plan = state.plan
    if not plan or not ctx.active() or type(cmd) ~= "table" then
      return nextFn(sctx, name, args, cmd)
    end
    local vm = type(sctx) == "table" and sctx.vm or nil
    local row = vm and M.rewriteRow(plan, vm.cmdList, vm.cmdIndex, cmd, vm.text)
    return nextFn(sctx, name, args, row or cmd)
  end

  if mod and mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("script.command", hook)
  else
    ctx.log("keyitems: no mod.hooks; HMs stay where they are")
  end
end

return M
