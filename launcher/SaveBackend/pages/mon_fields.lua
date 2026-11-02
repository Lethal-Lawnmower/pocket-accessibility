-- The fields for one Pokémon, shared by the Party and Boxes pages: the sections,
-- rows and tools of upstream's InspectorBody.lua, described for the native window
-- instead of drawn.  Every write goes through upstream's Ops, so limits, undo and
-- legality stay upstream's.  Field ids match the ids Legality.highlights reports,
-- so a saved-value problem lands on the right control.
--
-- This module is not a page: main.lua only loads the ids in its page order.
local Ops = require("Ops")
local Gen = require("Gen")
local P = require("Properties")
local MonOps = require("MonOps")
local Limits = require("ValueLimits")
local Named = require("NamedChoices")
local Legality = require("Legality")
local BoxSort = require("BoxSort")

local M = {}

-- ------------------------------------------------------------------ plain names

-- Words that stay capitals when a name written in capitals is made readable.
local KEEP_CAPITALS = { HP = true, PP = true, TM = true, HM = true, PC = true, OT = true }

-- ROM names are often all capitals, which some speech settings spell out.  Names
-- that already have lower case letters are left alone.
local function plainName(name)
  name = tostring(name or "")
  if name:find("%l") then return name end
  return (name:gsub("%a[%w']*", function(word)
    if KEEP_CAPITALS[word] or word:find("%d") then return word end
    return word:sub(1, 1) .. word:sub(2):lower()
  end))
end
M.plainName = plainName

local function speciesLabel(S, mon)
  local def = S.data.pokemon[mon.species or mon.speciesId]
  return plainName((def and def.name) or mon.name or mon.species or "Unknown species")
end

local function isEgg(mon)
  return mon.egg == true or mon.isEgg == true or mon.egg == 1 or mon.isEgg == 1
end

-- "Level 12 Charmander", with a nickname in front of the species when it has one.
function M.describe(S, mon)
  local species = speciesLabel(S, mon)
  if isEgg(mon) then return "Egg of " .. species end
  local nickname = mon.nickname
  local name = species
  if type(nickname) == "string" and nickname ~= "" and nickname:lower() ~= species:lower() then
    name = nickname .. " (" .. species .. ")"
  end
  return "Level " .. tostring(mon.level or "unknown") .. " " .. name
end

local function isShiny(S, mon)
  local g = Gen.ofState(S)
  if g == 3 then
    if mon.isShiny ~= nil then return mon.isShiny == true end
    local ok, shiny = pcall(require("src.core.game3.pokemon").isShiny, mon)
    return ok and shiny == true
  elseif g == 2 then
    return require("src.pokemon.Stats").isShiny(mon.dvs) == true
  end
  return false
end
M.isShiny = isShiny

-- ----------------------------------------------------------------- long options

-- Built once for a catalog: a dropdown of 400 names on every answer would
-- otherwise re-sort for each row walked.
local catalogOwner, catalogLists

local function byLabel(a, b)
  local la, lb = a.label:lower(), b.label:lower()
  return la ~= lb and la < lb or (la == lb and tostring(a.value) < tostring(b.value))
end

-- Options plus a lookup from whatever a Pokémon stores (a native number, a name
-- key, the record itself) back to the option's value.
local function catalogOptions(records, ids, numberField, usable)
  local options, keyOf = {}, {}
  for _, id in ipairs(ids) do
    local def = records[id]
    local label = plainName(type(def) == "table" and def.name or id)
    if usable and not usable(id) then label = label .. " (no data)" end
    options[#options + 1] = { value = id, label = label }
    keyOf[id] = id
    if type(def) == "table" then
      keyOf[def] = id
      if def[numberField] ~= nil then keyOf[def[numberField]] = id end
      if def.id ~= nil and keyOf[def.id] == nil then keyOf[def.id] = id end
    end
  end
  table.sort(options, byLabel)
  return options, keyOf
end

local function catalogs(S)
  if catalogOwner == S.cat and catalogLists then return catalogLists end
  local lists = {}
  lists.species, lists.speciesKey = catalogOptions(S.data.pokemon, S.cat.species, "speciesId",
    function(id) return Ops.speciesUsable(S, id) end)
  lists.moves, lists.moveKey = catalogOptions(S.data.moves or {}, S.cat.moves or {}, "moveId",
    function(id) return Ops.moveUsable(S, id) end)
  if Gen.ofState(S) >= 2 then
    local holdable = {}
    for _, id in ipairs(Ops.itemSearch(S, "")) do
      if Ops.itemHoldable(S, id) then holdable[#holdable + 1] = id end
    end
    lists.items, lists.itemKey = catalogOptions(S.data.items, holdable, "itemId")
    table.insert(lists.items, 1, { value = "", label = "None" })
  end
  table.insert(lists.moves, 1, { value = "", label = "None" })
  catalogOwner, catalogLists = S.cat, lists
  return lists
end

function M.speciesOptions(S)
  return catalogs(S).species
end

-- A saved value outside the normal list still has to show, never a blank box.
local function withCurrent(options, value, label)
  for _, option in ipairs(options) do
    if option.value == value then return options end
  end
  local out = { { value = value, label = label } }
  for _, option in ipairs(options) do out[#out + 1] = option end
  return out
end

local function pairsToOptions(rows)
  local options = {}
  for i, row in ipairs(rows) do
    -- upstream's separator dot is read aloud as a word by some speech settings
    options[i] = { value = row[1], label = (plainName(row[2]):gsub(" · ", ", ")) }
  end
  return options
end

local function speciesKeyOf(S, mon)
  local stored = mon.species or mon.speciesId
  local lists = catalogs(S)
  local key = lists.speciesKey[stored] or lists.speciesKey[S.data.pokemon[stored]]
  return key or tostring(stored)
end

local function heldItemId(mon)
  local held = mon.heldItem or mon.item
  if held == 0 or held == "NONE" then return nil end
  return held
end

-- ------------------------------------------------------------------ small facts

local NATURE_STATS = { "Attack", "Defense", "Speed", "Sp. Atk", "Sp. Def" }
local STATUSES = {
  { "healthy", "Healthy" }, { "SLP", "Asleep" }, { "PSN", "Poisoned" }, { "BRN", "Burned" },
  { "FRZ", "Frozen" }, { "PAR", "Paralyzed" }, { "TOX", "Badly poisoned" },
}
local NUMBER_STATUS = { [0] = "healthy", [8] = "PSN", [16] = "BRN", [32] = "FRZ", [64] = "PAR", [128] = "TOX" }
local STAT_NAMES = {
  hp = "HP", atk = "Attack", def = "Defense", spa = "Sp. Atk", spd = "Sp. Def", spe = "Speed",
  attack = "Attack", defense = "Defense", speed = "Speed", special = "Special",
}
local G3_STATS = { "hp", "atk", "def", "spa", "spd", "spe" }
local OLD_STATS = { "hp", "attack", "defense", "speed", "special" }

local function savedStatus(mon)
  local status = mon.status or "healthy"
  if type(status) == "number" then
    status = NUMBER_STATUS[status] or (status >= 1 and status <= 7 and "SLP") or status
  end
  return status
end

function M.statusName(mon)
  local status = savedStatus(mon)
  for _, row in ipairs(STATUSES) do
    if row[1] == status then return row[2] end
  end
  return tostring(status)
end

local function typeName(S, t)
  if t == nil then return nil end
  if Gen.ofState(S) == 3 then
    if type(t) == "number" then
      for name, id in pairs(require("src.core.game3.battle.types").ID) do
        if id == t then t = name; break end
      end
    end
    t = tostring(t):gsub("^TYPE_", "")
    if t == "MYSTERY" then return "Unknown type" end
  else
    local ok, name = pcall(require("src.battle.TypeChart").displayName, t, S.data)
    if ok and name then t = name end
  end
  return plainName(t)
end

local function speciesTypes(S, mon, def)
  local types = {}
  if Gen.ofState(S) == 3 then
    types = require("src.core.game3.pokemon").types(mon.species) or {}
  else
    types = (def and def.types) or mon.types or {}
  end
  local out = {}
  for i, t in ipairs(types) do
    if i == 1 or t ~= types[1] then out[#out + 1] = typeName(S, t) end
  end
  return table.concat(out, ", ")
end

local function natureOf(mon)
  return mon.nature or (tonumber(mon.personality) or 0) % 25
end

local function natureName(id)
  local name = require("src.core.game3.summary_data").NATURES[id]
  return name and plainName(name) or tostring(id)
end

-- src/pokemon.c:1365, the same table upstream's inspector reads out.
local function natureEffect(id)
  id = tonumber(id) or 0
  local up, down = math.floor(id / 5) + 1, id % 5 + 1
  if up == down or not NATURE_STATS[up] then return "No stat change" end
  return "Raises " .. NATURE_STATS[up] .. ", lowers " .. NATURE_STATS[down]
end

local function genderOf(S, mon, def)
  local g = Gen.ofState(S)
  if g == 3 then
    return mon.gender or require("src.core.game3.pokemon").gender(mon.species, tonumber(mon.personality) or 0)
  elseif g == 2 then
    local ok, gender = pcall(require("src.core.gen2.Breeding").gender, def, mon.dvs)
    return ok and gender or nil
  end
end

local GENDER_NAMES = { M = "Male", F = "Female", male = "Male", female = "Female", U = "Genderless" }

-- ----------------------------------------------------------------- field builders

-- One builder per section; `C` carries what they all read.
local function context(S, mon)
  local report = Legality.mon(S, mon)
  return {
    S = S, mon = mon, g = Gen.ofState(S), report = report,
    issues = Legality.highlights(report, mon),
    def = S.data.pokemon[mon.species or mon.speciesId],
    fields = {},
  }
end

local function add(C, field)
  field.issue = field.issue or C.issues.fields[field.id]
  C.fields[#C.fields + 1] = field
end

local function info(C, id, label, value, help)
  add(C, { id = id, label = label, kind = "info", value = value, help = help })
end

local function number(C, id, label, value, help)
  local limits = Limits.mon(C.S, C.mon, id)
  add(C, { id = id, label = label, kind = "number", value = tonumber(value) or 0,
    lo = limits.lo, hi = limits.hi, help = help })
end

local function choice(C, id, label, value, options, help)
  add(C, { id = id, label = label, kind = "choice", value = value, options = options, help = help })
end

local function mainFields(C)
  local S, mon, g, def = C.S, C.mon, C.g, C.def
  local lists = catalogs(S)
  local speciesKey = speciesKeyOf(S, mon)
  choice(C, "species", "Species", speciesKey,
    withCurrent(lists.species, speciesKey, plainName(speciesLabel(S, mon))),
    "Keeps level and moves, and recalculates stats.")
  local dex = BoxSort.dexNumber(S, mon)
  if dex then info(C, "dex", "Pokédex number", dex) end
  local types = speciesTypes(S, mon, def)
  if types ~= "" then info(C, "types", "Types", types) end
  add(C, { id = "nickname", label = "Nickname", kind = "text", value = mon.nickname or "",
    help = "Up to " .. Ops.NICKNAME_MAX .. " characters. Empty uses the species name." })
  number(C, "level", "Level", mon.level, "Changes level and recalculates stats. Moves stay the same.")
  number(C, "experience", "Experience", Gen.exp(mon), "Total experience. Level updates to match.")
  number(C, "current-hp", "Current HP", mon.hp or 0, "The limit follows level and stats.")
  if g >= 2 then
    number(C, "friendship", "Friendship", mon.friendship or mon.happiness or 0,
      isEgg(mon) and "Egg hatch countdown. Lower means closer to hatching." or nil)
  end
  local statuses = {}
  for _, row in ipairs(STATUSES) do
    if g >= 2 or row[1] ~= "TOX" then statuses[#statuses + 1] = { value = row[1], label = row[2] } end
  end
  local status = savedStatus(mon)
  choice(C, "status", "Status", status, withCurrent(statuses, status, "Saved status " .. tostring(status)))

  if g == 3 then
    local Pokemon = require("src.core.game3.pokemon")
    local nature = natureOf(mon)
    local natures = {}
    for id = 0, 24 do natures[#natures + 1] = { value = id, label = natureName(id) } end
    choice(C, "nature", "Nature", nature, natures, "Changes the personality value.")
    info(C, "nature-effect", "Nature effect", natureEffect(nature))

    local slot = mon.abilityNum or (tonumber(mon.personality) or 0) % 2
    local abilities = {}
    for i, id in ipairs(Pokemon.abilities(mon.species)) do
      if id and id ~= 0 then abilities[#abilities + 1] = { value = i - 1, label = plainName(Pokemon.abilityName(id)) } end
    end
    choice(C, "ability", "Ability", slot, withCurrent(abilities, slot, "Saved ability slot " .. tostring(slot + 1)))

    local gender = genderOf(S, mon, def)
    local ratio = (Pokemon.speciesMeta(mon.species) or {}).genderRatio or 255
    if ratio == 255 or ratio == 0 or ratio == 254 then
      info(C, "gender", "Gender", ratio == 255 and "Genderless" or ratio == 0 and "Male" or "Female",
        "This species has a fixed gender.")
    else
      choice(C, "gender", "Gender", gender, { { value = "M", label = "Male" }, { value = "F", label = "Female" } },
        "Changes the personality value.")
    end
    add(C, { id = "shiny", label = "Shiny", kind = "check", value = isShiny(S, mon),
      help = "Changes the personality value." })
  elseif g == 2 then
    local gender = genderOf(S, mon, def)
    info(C, "gender", "Gender", GENDER_NAMES[gender or ""] or "Genderless", "Follows the DVs.")
    info(C, "shiny", "Shiny", isShiny(S, mon) and "Yes" or "No", "Follows the DVs.")
  end

  if g >= 2 then
    local held = heldItemId(mon)
    local heldKey = held == nil and "" or lists.itemKey[held] or lists.itemKey[S.data.items[held]] or tostring(held)
    local heldDef = held ~= nil and S.data.items[held]
    choice(C, "heldItem", "Held item", heldKey,
      withCurrent(lists.items, heldKey, plainName(heldDef and heldDef.name or heldKey)))
  end

  local letter = Ops.unownForm(S, mon)
  if letter ~= nil then
    choice(C, "form", "Unown form", letter, pairsToOptions(Ops.unownFormOptions(S)),
      g == 3 and "Keeps nature and shininess. Changes the personality value."
        or "Rewrites the middle bits of the DVs. Only I and V can be shiny.")
  end
  if g == 2 then
    local value = mon.pokerus or 0
    local rows = pairsToOptions(Named.property(S, P.find(S, "pokerus")))
    choice(C, "pokerus", "Pokérus", value, withCurrent(rows, value, "Saved value " .. tostring(value)))
  end
end

local function calculatedStats(C)
  local mon, stats = C.mon, C.mon.stats or {}
  local function value(...)
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      if v ~= nil then return tostring(v) end
    end
    return "unknown"
  end
  local parts = {
    "HP " .. value(stats.hp, mon.maxHp),
    "Attack " .. value(stats.attack, mon.attack),
    "Defense " .. value(stats.defense, mon.defense),
    "Speed " .. value(stats.speed, mon.speed),
  }
  if C.g == 1 then
    parts[#parts + 1] = "Special " .. value(stats.special)
  else
    parts[#parts + 1] = "Sp. Atk " .. value(stats.specialAttack, stats.spAtk, mon.spAtk)
    parts[#parts + 1] = "Sp. Def " .. value(stats.specialDefense, stats.spDef, mon.spDef)
  end
  return table.concat(parts, ", ")
end

local function statsFields(C)
  local mon = C.mon
  add(C, { id = "calculated", label = "Calculated stats", kind = "info", value = calculatedStats(C) })
  if C.g == 3 then
    local total = Limits.evTotal(mon)
    info(C, "ev-total", "EVs used", total .. " of 510, " .. math.max(0, 510 - total) .. " free",
      "All six stats share 510. Lower one to free up another.")
    for _, key in ipairs(G3_STATS) do
      number(C, "iv-" .. key, STAT_NAMES[key] .. " IV", mon.ivs and mon.ivs[key] or 0,
        "Natural stat strength. Higher is stronger.")
    end
    for _, key in ipairs(G3_STATS) do
      number(C, "ev-" .. key, STAT_NAMES[key] .. " EV", mon.evs and mon.evs[key] or 0,
        "Training points. The limit shrinks as the shared 510 is spent.")
    end
    return
  end
  local dvHelp = C.g == 2 and "Natural stat strength. Also sets HP, gender and shininess."
    or "Natural stat strength. Also sets HP."
  add(C, { id = "dv-hp", label = "HP DV", kind = "info", value = tostring(mon.dvs and mon.dvs.hp or 0),
    help = "Follows the other DVs." })
  for _, key in ipairs(OLD_STATS) do
    if key ~= "hp" then number(C, "dv-" .. key, STAT_NAMES[key] .. " DV", mon.dvs and mon.dvs[key] or 0, dvHelp) end
  end
  for _, key in ipairs(OLD_STATS) do
    number(C, "se-" .. key, STAT_NAMES[key] .. " stat experience", mon.statExp and mon.statExp[key] or 0,
      "Stat training. Each stat has its own limit.")
  end
end

local function moveFacts(C, slot)
  local S, mon = C.S, C.mon
  local stored = mon.moves and mon.moves[slot]
  local id = type(stored) == "table" and (stored.moveId or stored.id) or stored
  if id == nil or id == 0 then return nil end
  if type(stored) == "table" and stored.id ~= nil then id = stored.id end
  local def = S.data.moves and S.data.moves[id]
  local base = MonOps.getBasePp(S.data, mon, slot)
  return {
    id = id, def = def, base = base,
    pp = tonumber(type(stored) == "table" and stored.pp or (mon.pp and mon.pp[slot])) or 0,
    ups = MonOps.getPpUps(mon, slot),
  }
end

local function movesFields(C)
  local S = C.S
  local lists = catalogs(S)
  for slot = 1, 4 do
    local facts = moveFacts(C, slot)
    local key, help = "", "No move in this slot."
    if facts then
      key = lists.moveKey[facts.id] or lists.moveKey[facts.def] or tostring(facts.id)
      local kind = facts.def and typeName(S, facts.def.type)
      help = (kind and (kind .. ", ") or "") .. "base PP " .. tostring(facts.base or "unknown") .. "."
    end
    local label = facts and facts.def and plainName(facts.def.name) or ("Saved move " .. tostring(key))
    choice(C, "move" .. slot, "Move " .. slot, key, withCurrent(lists.moves, key, label), help)
    if facts then
      number(C, "pp-" .. slot, "Move " .. slot .. " PP", facts.pp, "Uses left for this move. PP Ups raise the limit.")
      number(C, "ppup-" .. slot, "Move " .. slot .. " PP Ups", facts.ups, "Raises this move's PP limit.")
    end
  end
end

-- One row of upstream's property schema: a checkbox, a named choice or a number.
local function property(C, d, label)
  local S, mon = C.S, C.mon
  label = label or d.label:gsub(" %(.-%)", "")
  local value = P.get(mon, d)
  -- Legality names range problems by the property's label, not its key.
  local issue = C.issues.fields[d.key] or C.issues.fields[d.label]
  if d.toggle then
    add(C, { id = d.key, label = label, kind = "check", value = value == true or value == 1, issue = issue })
  elseif d.text then
    add(C, { id = d.key, label = label, kind = "text", value = tostring(value or ""),
      help = "Up to " .. tostring(d.max) .. " characters.", issue = issue })
  else
    local rows = Named.property(S, d)
    if rows then
      choice(C, d.key, label, value, withCurrent(pairsToOptions(rows), value, "Saved value " .. tostring(value)))
    else
      number(C, d.key, label, value)
    end
    C.fields[#C.fields].issue = issue
  end
end

local function originFields(C)
  local S, mon = C.S, C.mon
  for _, d in ipairs(P.identity(S)) do property(C, d) end
  if C.g == 2 and Gen.hasCaughtData(S.save, S.version) then
    local value = mon.caughtByGender or ""
    choice(C, "caughtBy", "Caught by", value,
      withCurrent({ { value = "boy", label = "Boy" }, { value = "girl", label = "Girl" } }, value, "Not set"))
  end
end

local function extrasFields(C)
  if C.g ~= 3 then
    info(C, "no-extras", "Extras", "This generation has no contest conditions or ribbons.")
    return
  end
  local contestIssue, ribbonIssue = C.issues.fields.contest, C.issues.fields.ribbons
  if contestIssue then info(C, "contest", "Contest conditions", contestIssue) end
  for _, d in ipairs(P.contest) do
    property(C, d, plainName(d.child) .. " condition")
  end
  info(C, "ribbon-note", "Ribbons", ribbonIssue or "Setting a ribbon does not establish award or event eligibility.")
  for _, d in ipairs(P.ribbons) do
    property(C, d, (d.label:gsub(" %(.-%)", "")))
  end
end

local CHECK_WORDS = { error = "Error", warning = "Warning", pass = "Pass" }

local function checksFields(C)
  local report = C.report
  info(C, "check-result", "Result", report.errors > 0 and (report.errors .. " property errors")
    or "Values pass. Origin still needs checking.")
  for i, check in ipairs(report.checks) do
    info(C, "check-" .. i, "Check " .. i, (CHECK_WORDS[check.kind] or plainName(check.kind)) .. ": " .. check.message)
  end
end

local SECTIONS = {
  { id = "main", label = "Main", build = mainFields },
  { id = "stats", label = "Stats", build = statsFields },
  { id = "moves", label = "Moves", build = movesFields },
  { id = "origin", label = "Origin", build = originFields },
  { id = "extras", label = "Extras", build = extrasFields, g3Only = true },
  { id = "checks", label = "Checks", build = checksFields },
}

local function sectionOf(S, state)
  for _, section in ipairs(SECTIONS) do
    if section.id == state.section and (not section.g3Only or Gen.ofState(S) == 3) then return section end
  end
  return SECTIONS[1]
end

-- ------------------------------------------------------------------- the page api

-- The Section picker.  A section holding a saved-value problem says how many.
function M.sectionPicker(S, state, mon)
  local issues = mon and Legality.highlights(Legality.mon(S, mon), mon)
  local options = {}
  for _, section in ipairs(SECTIONS) do
    if not section.g3Only or Gen.ofState(S) == 3 then
      local errors = issues and issues.sections[section.id] or 0
      options[#options + 1] = { value = section.id,
        label = section.label .. (errors > 0 and (", " .. errors .. (errors == 1 and " problem" or " problems")) or "") }
    end
  end
  return { id = "section", label = "Section", value = sectionOf(S, state).id, options = options, below = true }
end

function M.pickSection(state, value)
  state.section = value
end

function M.fields(S, state, mon)
  if not mon then return {} end
  local C = context(S, mon)
  local section = sectionOf(S, state)
  if C.report.errors > 0 and section.id ~= "checks" then
    info(C, "errors", "Problems", C.report.errors .. (C.report.errors == 1 and " saved value error" or " saved value errors")
      .. ". The Checks section lists them.")
  end
  section.build(C)
  return C.fields
end

local function recommendAction(S, mon)
  local state = Ops.recommendState(S, mon)
  local label = ({ egg = "Recommended moveset, not for eggs", none = "No recommended moveset" })[state]
    or "Recommended moveset"
  return { id = "recommend", label = label, enabled = state == "ready",
    confirm = "Fetch a recommended moveset from the game's online service and replace this Pokémon's moves?" }
end

-- Tools for the section on show, then Full heal, which upstream offers on all of them.
function M.actions(S, state, mon)
  if not mon then return {} end
  local section, g = sectionOf(S, state).id, Gen.ofState(S)
  local list = {}
  if section == "main" then
    list = {
      { id = "max", label = "Max out" },
      { id = "fix", label = "Fix errors" },
      { id = "randomize", label = "Randomize",
        confirm = "Replace " .. M.describe(S, mon) .. " with a random wild Pokémon from this game?" },
      { id = "clone", label = "Clone to a box" },
    }
  elseif section == "stats" and g == 3 then
    list = { { id = "maxIvs", label = "Max all IVs" }, { id = "clearEvs", label = "Clear EVs" } }
  elseif section == "stats" then
    list = { { id = "maxDvs", label = "Max all DVs" }, { id = "maxStatExp", label = "Max stat training" } }
  elseif section == "moves" then
    list = {
      { id = "maxPp", label = "Max all PP" },
      recommendAction(S, mon),
      { id = "resetMoves", label = "Reset to learnset" },
    }
  elseif section == "checks" then
    list = { { id = "fix", label = "Fix errors" } }
  end
  list[#list + 1] = { id = "heal", label = "Full heal" }
  return list
end

-- A typed number outside the limits refuses in words; the box shows the real value again.
local function inLimits(S, mon, id, label, value)
  local limits = Limits.mon(S, mon, id)
  local n = tonumber(value)
  if not Legality.integer(n, limits.lo, limits.hi) then
    Ops.say(S, ("%s must be a whole number from %d to %d"):format(label, limits.lo, limits.hi))
    return nil
  end
  return n
end

local NUMBER_SETTERS = {
  level = { "Level", function(S, mon, n) return Ops.setLevel(S, mon, n) end },
  experience = { "Experience", function(S, mon, n) return Ops.setExperience(S, mon, n) end },
  ["current-hp"] = { "Current HP", function(S, mon, n) return Ops.setCurrentHp(S, mon, n) end },
  friendship = { "Friendship", function(S, mon, n) return Ops.setHappiness(S, mon, n) end },
}

local CHOICE_SETTERS = {
  species = Ops.setSpecies,
  nature = Ops.setNature,
  ability = Ops.setAbility,
  gender = Ops.setMonGender,
  shiny = Ops.setShiny,
  form = Ops.setUnownForm,
  pokerus = Ops.setPokerus,
}

local function setMonNumberField(S, mon, id, value)
  local slotKind, slot = id:match("^(pp)%-(%d)$")
  if not slotKind then slotKind, slot = id:match("^(ppup)%-(%d)$") end
  if slotKind then
    slot = tonumber(slot)
    local label = "Move " .. slot .. (slotKind == "pp" and " PP" or " PP Ups")
    local n = inLimits(S, mon, id, label, value)
    if not n then return true end
    if slotKind == "pp" then Ops.setPp(S, mon, slot, n) else Ops.setPpUps(S, mon, slot, n) end
    return true
  end
  local kind, key = id:match("^(%a%a)%-(%a+)$")
  if not kind then return false end
  local label = STAT_NAMES[key]
  if not label then return false end
  local isGen3 = Gen.ofState(S) == 3
  if ((kind == "iv" or kind == "ev") and isGen3) or ((kind == "dv" or kind == "se") and not isGen3) then
    local n = inLimits(S, mon, id, label .. " " .. kind:upper(), value)
    if not n then return true end
    if kind == "iv" then Ops.setIv(S, mon, key, n)
    elseif kind == "ev" then Ops.setEv(S, mon, key, n)
    elseif kind == "dv" then Ops.setDv(S, mon, key, n)
    else Ops.setStatExp(S, mon, key, n) end
    return true
  end
  return false
end

-- Fields that exist only in some generations; a request for one elsewhere refuses
-- rather than writing a value that game's save has no place for.
local LOWEST_GENERATION = { friendship = 2, heldItem = 2, form = 2, pokerus = 2,
  nature = 3, ability = 3, gender = 3, shiny = 3 }

-- Applies one field to one Pokémon.
function M.set(S, mon, id, value)
  if not mon then return Ops.say(S, "Select a Pokémon first") end
  if Gen.ofState(S) < (LOWEST_GENERATION[id] or 1) then
    return Ops.say(S, "That field is not available in this game")
  end
  local numberSetter = NUMBER_SETTERS[id]
  if numberSetter then
    local n = inLimits(S, mon, id, numberSetter[1], value)
    if n then numberSetter[2](S, mon, n) end
    return
  end
  if CHOICE_SETTERS[id] then
    return CHOICE_SETTERS[id](S, mon, value)
  end
  if id == "nickname" then
    if tostring(value or "") == (mon.nickname or "") then return end
    return Ops.setNickname(S, mon, value)
  elseif id == "status" then
    return Ops.setMonStatus(S, mon, value ~= "healthy" and value or nil)
  elseif id == "heldItem" then
    if value == "" and not heldItemId(mon) then return end
    return Ops.setHeldItem(S, mon, value ~= "" and value or nil)
  elseif id == "caughtBy" then
    if value == "" then return end
    return Ops.setCaughtByGender(S, mon, value)
  end
  local moveSlot = id:match("^move(%d)$")
  if moveSlot then
    moveSlot = tonumber(moveSlot)
    if value == "" then return Ops.clearMove(S, mon, moveSlot) end
    return Ops.setMove(S, mon, moveSlot, value)
  end
  if setMonNumberField(S, mon, id, value) then return end
  local d = P.find(S, id)
  if d then
    if type(value) == "number" and not d.choices then
      local limits = Limits.mon(S, mon, id)
      if not Legality.integer(value, limits.lo, limits.hi) then
        return Ops.say(S, ("%s must be a whole number from %d to %d"):format(d.label, limits.lo, limits.hi))
      end
    end
    return Ops.setMonProperty(S, mon, id, value)
  end
  return Ops.say(S, "That field is not available in this game")
end

-- Upstream's panel polls the fetch every frame.  The backend has no frames, so
-- the one press waits here, bounded by the fetch's own limit, with the window
-- still responsive because the client awaits the answer.
local function fetchRecommendedMoves(S, mon)
  local Recommend = require("src.recommend.Recommend")
  local status = Ops.recommendMoves(S, mon)
  if status ~= "pending" then return status end
  local deadline = love.timer.getTime() + Recommend.FETCH_SECONDS + 5
  while S.recommendJob and love.timer.getTime() < deadline do
    love.timer.sleep(0.1)
    Ops.pollRecommendedMoves(S)
  end
  if S.recommendJob then
    Recommend.cancel(S.recommendJob.job)
    S.recommendJob = nil
    Ops.say(S, "Recommended moveset unavailable (timed out)", "warn")
  end
end

local TOOLS = {
  max = Ops.maxMon, fix = Ops.fixMonErrors, randomize = Ops.randomizeMon, clone = Ops.cloneMonToBox,
  maxIvs = Ops.maxIvs, clearEvs = Ops.clearEvs, maxDvs = Ops.maxDvs, maxStatExp = Ops.maxStatExp,
  maxPp = Ops.maxAllPpUps, resetMoves = Ops.resetMoves, heal = Ops.healMon,
  recommend = fetchRecommendedMoves,
}

-- Runs a section tool.  Answers false when `id` is not one, so the page can try its own.
function M.action(S, mon, id)
  local tool = TOOLS[id]
  if not tool then return false end
  if not mon then
    Ops.say(S, "Select a Pokémon first")
    return true
  end
  -- These write stat tables only one era's saves have; the buttons are only offered there.
  local isGen3 = Gen.ofState(S) == 3
  if ((id == "maxIvs" or id == "clearEvs") and not isGen3) or ((id == "maxDvs" or id == "maxStatExp") and isGen3) then
    Ops.say(S, "That tool is not available in this game")
    return true
  end
  tool(S, mon)
  return true
end

return M
