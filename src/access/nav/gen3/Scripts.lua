-- What a FireRed script does, read from the extracted bundle without running
-- it (decision 29).  Object and sign script keys are ROM addresses
-- ("g3:081a89b7"): they are never spoken, so signs, item balls and doors are
-- named from the commands their scripts run instead.
--
-- Shapes recognised (checked against the whole FireRed cache, 2026-11-01):
--   item ball        setorcopyvar 0x8000 <item>, then callstd 1 (finditem)
--   card key door    a flag check, then a branch that plays the fanfare and
--                    sets metatiles (Silph Co.; 80 bg events)
--   secret switch    a yes/no (callstd 5) that toggles a flag and sets
--                    metatiles (Pokemon Mansion)
--   quiz machine     a yes/no that can start a trainer battle and sets
--                    metatiles (Cinnabar Gym)
--   trash can        special SetVermilionTrashCans (Vermilion Gym)
--   floor panel      special GetElevatorFloor (the elevators)
--   braille          special BrailleCursorToggle (Tanoby chambers)
--   fossil display   special OpenMuseumFossilPic (Pewter Museum)
-- Anything else is "Signpost N", as in Gen 1 and Gen 2.

local Scripts = {}

local function loaded(path) return package.loaded[path] end

local injected = nil

-- Tests hand in a scripts table; the game reads Space.bundle.scripts.
function Scripts.setSource(source) injected = source end

local function scriptTable()
  if injected then return injected end
  local Space = loaded("src.core.game3.scripting.space")
  local bundle = Space and Space.bundle
  return type(bundle) == "table" and type(bundle.scripts) == "table" and bundle.scripts or nil
end

function Scripts.get(key)
  local scripts = scriptTable()
  if type(key) ~= "string" or not scripts then return nil end
  local list = rawget(scripts, key)
  if type(list) ~= "table" and type(scripts[key]) == "table" then list = scripts[key] end
  return type(list) == "table" and list or nil
end

local specialNames = nil
local function specialName(id)
  if specialNames == nil then
    specialNames = false
    local ok, Constants = pcall(require, "src.core.game3.constants")
    if ok and Constants and Constants.of then
      local okOf, set = pcall(Constants.of, "firered")
      local specials = okOf and set and set.specials
      if type(specials) == "table" and type(specials.byId) == "table" then
        specialNames = specials.byId
      end
    end
  end
  if not specialNames then return nil end
  local value = specialNames[id]
  if type(value) == "table" then value = value[1] end
  return value
end
Scripts.specialName = specialName

-- Test hook: a fixed id -> name table.
function Scripts.setSpecialNames(names) specialNames = names end

local BRANCH = { ["goto"] = true, goto_if = true, call = true, call_if = true }

-- Every command reachable from a script, a few branches deep (the shapes
-- above are all within three).
function Scripts.reach(key, maxDepth)
  maxDepth = maxDepth or 4
  local summary = { ops = {}, specials = {}, stds = {}, flagsChecked = {}, flagsSet = {} }
  local seen = {}
  local function walk(k, depth)
    if depth > maxDepth or type(k) ~= "string" or seen[k] then return end
    seen[k] = true
    local list = Scripts.get(k)
    if not list then return end
    for _, cmd in ipairs(list) do
      if type(cmd) == "table" and type(cmd.op) == "string" then
        summary.ops[cmd.op] = (summary.ops[cmd.op] or 0) + 1
        if cmd.op == "special" or cmd.op == "specialvar" then
          local name = specialName(tonumber(cmd.id or cmd[1] or cmd[2]))
          if name then summary.specials[name] = true end
        elseif cmd.op == "callstd" then
          summary.stds[tonumber(cmd.std or cmd[1]) or -1] = true
        elseif cmd.op == "checkflag" then
          summary.flagsChecked[#summary.flagsChecked + 1] = tonumber(cmd.flag or cmd[1])
        elseif cmd.op == "setflag" or cmd.op == "clearflag" then
          summary.flagsSet[tonumber(cmd.flag or cmd[1]) or -1] = true
        end
        if BRANCH[cmd.op] then walk(cmd.target or cmd[2] or cmd[1], depth + 1) end
      end
    end
  end
  walk(key, 0)
  return summary
end

-- Specials that name the object, in order of precedence.
local SPECIAL_ROLES = {
  { "SetVermilionTrashCans", "Trash Can" },
  { "GetElevatorFloor", "Floor Panel" },
  { "BrailleCursorToggle", "Braille" },
  { "OpenMuseumFossilPic", "Fossil Display" },
  { "BedroomPC", "PC" }, { "AnimatePcTurnOn", "PC" },
  { "ShowBattleRecords", "Battle Records" }, { "ShowPokemonJumpRecords", "Records" },
  { "ShowBerryCrushRankings", "Records" }, { "ShowDodrioBerryPickingRecords", "Records" },
  { "GetHeracrossSizeRecordInfo", "Size Record" }, { "GetMagikarpSizeRecordInfo", "Size Record" },
  { "AnimateTeleporterHousing", "Teleporter" },
}

-- The role a sign's script names, or nil.  Returns role, kind.
function Scripts.signRole(key)
  if not Scripts.get(key) then return nil end
  local s = Scripts.reach(key)
  for _, row in ipairs(SPECIAL_ROLES) do
    if s.specials[row[1]] then return row[2], (row[2]:lower():gsub(" ", "_")) end
  end
  if s.ops.setmetatile then
    local yesNo = s.stds[5] == true
    if yesNo and s.ops.trainerbattle then return "Quiz Machine", "quiz_machine" end
    if yesNo and (s.ops.setflag or s.ops.clearflag) then return "Secret Switch", "secret_switch" end
    if s.ops.playfanfare and not yesNo then return "Card Key Door", "card_key_door" end
  end
  return nil
end

-- The flag a card key door's script checks before it unlocks: the second
-- flag it checks (the first is the door's own "already open" flag).  In
-- FireRed that is the Card Key ball's pickup flag, not the bag, so a key
-- in the bag from anywhere else does not open the door.
function Scripts.cardKeyFlag(key)
  local role, kind = Scripts.signRole(key)
  if kind ~= "card_key_door" then return nil end
  return Scripts.reach(key).flagsChecked[2]
end

-- The item an item ball holds (numeric FireRed item id), or nil.
function Scripts.itemBallItem(key)
  local list = Scripts.get(key)
  if not list then return nil end
  local item, finds = nil, false
  for _, cmd in ipairs(list) do
    if type(cmd) == "table" then
      if cmd.op == "setorcopyvar" and tonumber(cmd[1]) == 0x8000 then
        item = tonumber(cmd[2])
      elseif cmd.op == "callstd" and tonumber(cmd.std or cmd[1]) == 1 then
        finds = true
      end
    end
  end
  if finds and item and item > 0 then return item end
  return nil
end

-- Words kept in capitals: abbreviations a screen reader would otherwise
-- read as words.
local KEEP_CAPS = { PP = true, HP = true, TM = true, HM = true, PC = true }

-- "KING'S ROCK" as "King's Rock", "POKé BALL" as "Poké Ball", "TM05" as
-- "TM 05": the game's own name in
-- title case, word by word.
function Scripts.titleCase(name)
  if type(name) ~= "string" then return nil end
  name = name:gsub("^(%u%u)(%d+)$", "%1 %2")
  local words = {}
  for word in name:gmatch("%S+") do
    local letters = word:gsub("[^%a]", "")
    if KEEP_CAPS[letters] then
      words[#words + 1] = word
    else
      local first, rest = word:match("^([^%a]*%a)(.*)$")
      if first then
        words[#words + 1] = first:upper() .. rest:lower():gsub("\195\137", "\195\169")
      else
        words[#words + 1] = word
      end
    end
  end
  return table.concat(words, " ")
end

-- "Card Key", "TM 28", "Potion": the item's own name in title case.
function Scripts.itemLabel(itemId)
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  local name = ok and ItemsData and ItemsData.displayName and ItemsData.displayName(itemId) or nil
  if type(name) ~= "string" or name == "" or name == tostring(itemId) then return nil end
  return Scripts.titleCase(name)
end

return Scripts
