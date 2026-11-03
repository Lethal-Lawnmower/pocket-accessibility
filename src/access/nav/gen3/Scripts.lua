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
  -- deep enough for Cinnabar Gym's quiz machines, which branch before they ask
  local s = Scripts.reach(key, 8)
  for _, row in ipairs(SPECIAL_ROLES) do
    if s.specials[row[1]] then return row[2], (row[2]:lower():gsub(" ", "_")) end
  end
  -- signs whose text is a script command, not a loaded word
  if s.ops.playslotmachine then return "Slot Machine", "slot_machine" end
  if s.ops.braillemessage then return "Braille", "braille" end
  if s.ops.checkmoney and s.ops.additem then return "Vending Machine", "vending_machine" end
  if s.ops.setmetatile then
    local yesNo = s.stds[5] == true
    if yesNo and s.ops.trainerbattle then return "Quiz Machine", "quiz_machine" end
    if yesNo and (s.ops.setflag or s.ops.clearflag) then return "Secret Switch", "secret_switch" end
    if s.ops.playfanfare and not yesNo then return "Card Key Door", "card_key_door" end
    -- pressed with no question, and something opens: the Game Corner's poster
    if not yesNo and s.ops.setflag and not s.ops.trainerbattle then return "Hidden Switch", "hidden_switch" end
  end
  return nil
end

-- The flag a card key door's script checks before it unlocks: the second
-- flag it checks (the first is the door's own "already open" flag).  In
-- FireRed that is the Card Key ball's pickup flag, not the bag, so a key
-- in the bag from anywhere else does not open the door.
-- What a plain sign says, for its name: the first text its script loads, first line
-- only (read from the script, never run).  Nil when it has none.
function Scripts.signWords(key)
  local list = Scripts.get(key)
  local RomText = package.loaded["src.core.game3.rom_text"] or require("src.core.game3.rom_text")
  for _, cmd in ipairs(type(list) == "table" and list or {}) do
    if type(cmd) == "table" and cmd.op == "loadword" and type(cmd.value) == "string" then
      local ok, text = pcall(RomText.plain, cmd.value)
      if ok and type(text) == "string" then
        local line = text:gsub("{[^}]*}", " "):gsub("%c.*$", ""):gsub("%s+", " ")
          :gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" then return line:sub(1, 48) end
      end
    end
  end
  return nil
end

function Scripts.cardKeyFlag(key)
  local role, kind = Scripts.signRole(key)
  if kind ~= "card_key_door" then return nil end
  return Scripts.reach(key).flagsChecked[2]
end

-- The door's own flag (the first flag its script checks: set once it is
-- opened).  The floor's load script closes every door whose flag is unset;
-- the layout itself draws them open.
function Scripts.cardKeyDoorOpenFlag(key)
  local _, kind = Scripts.signRole(key)
  if kind ~= "card_key_door" then return nil end
  return Scripts.reach(key).flagsChecked[1]
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

-- ------------------------------------------------------------ map numbers

-- Scripts name maps by group and number (setdynamicwarp, warphole); the
-- data names them "FR_" plus the constant without "MAP_".
local mapIds, injectedGroups = nil, nil
function Scripts.setMapGroups(byName) injectedGroups = byName mapIds = nil end

function Scripts.mapIdOf(group, num)
  group, num = tonumber(group), tonumber(num)
  if not (group and num) then return nil end
  if mapIds == nil then
    local byName = injectedGroups
    if not byName then
      local ok, Constants = pcall(require, "src.core.game3.constants")
      local okOf, set = false, nil
      if ok and Constants and Constants.of then okOf, set = pcall(Constants.of, "firered") end
      byName = okOf and set and set.map_groups and set.map_groups.byName or nil
    end
    mapIds = {}
    for name, row in pairs(type(byName) == "table" and byName or {}) do
      if type(name) == "string" and type(row) == "table" and row.group and row.num then
        mapIds[tonumber(row.group) * 1024 + tonumber(row.num)] = "FR_" .. name:gsub("^MAP_", "")
      end
    end
  end
  return mapIds and mapIds[group * 1024 + num] or nil
end

-- ------------------------------------------------------------ load scripts

-- What a map's load scripts do to its floor, read without running them:
-- the transition script, then the load script (pokefirered's order), with
-- flags and variables read from the save and the script's own setflag,
-- setvar and addvar kept on the side.  Understood: checkflag,
-- checktrainerflag (flag 0x500 + the trainer, Flags.trainerFlagId), compare,
-- goto/call (with conditions), return, end, setvar, addvar, subvar,
-- copyvar, setflag, clearflag, setmetatile (recorded), setmaplayoutindex
-- (recorded), and a few that do not change the floor.  Anything else on
-- the path taken (a special, a movement, a warp) makes the result
-- unreadable: nil and the op's name.
--   flag(id) -> bool, var(id) -> number   readers (the save)
-- Returns { cells = { [y*1024+x] = { x, y, mid, impassable } },
-- layoutIndex = n or nil, key = string } where key changes whenever the
-- result does.
local HARMLESS = { lockall = true, releaseall = true, lock = true, release = true,
  setworldmapflag = true, nop = true, nop1 = true,
  -- these touch the save's respawn, the weather and objects, never the floor
  setrespawn = true, setweather = true, doweather = true, setescapewarp = true,
  setobjectmovementtype = true, setobjectxyperm = true, setobjectxy = true,
  addobject = true, removeobject = true, showobjectat = true, hideobjectat = true }
-- pokefirered sCmpTable: the comparison result is 0 (less, or a flag
-- unset), 1 (equal, or set) or 2 (greater)
local CONDITION = {
  [0] = { [0] = true }, [1] = { [1] = true }, [2] = { [2] = true },
  [3] = { [0] = true, [1] = true }, [4] = { [1] = true, [2] = true },
  [5] = { [0] = true, [2] = true },
}

local function argOf(cmd, name, index)
  local value = cmd[name]
  if value == nil then value = cmd[index] end
  return value
end

function Scripts.loadState(def, flag, var)
  if type(def) ~= "table" then return nil, "no map" end
  local ms = type(def.mapScripts) == "table" and def.mapScripts or {}
  local flags, vars = {}, {}
  local function getFlag(id)
    if flags[id] ~= nil then return flags[id] end
    return flag and flag(id) == true or false
  end
  local function getVar(id)
    if vars[id] ~= nil then return vars[id] end
    -- temporary and special variables start every map at 0
    if (id >= 0x4000 and id <= 0x400F) or id >= 0x8000 then return 0 end
    return tonumber(var and var(id)) or 0
  end
  local cells, layoutIndex = {}, nil
  local steps = 0
  local function run(key)
    local result = 0
    local stack = {}
    local list, pc = Scripts.get(key), 1
    if not list then return nil, "missing script" end
    while true do
      steps = steps + 1
      if steps > 4000 then return nil, "too long" end
      local cmd = list[pc]
      pc = pc + 1
      if type(cmd) ~= "table" then
        if #stack == 0 then return true end
        local frame = table.remove(stack)
        list, pc = frame[1], frame[2]
      else
        local op = cmd.op
        if op == "end" then return true
        elseif op == "return" then
          if #stack == 0 then return true end
          local frame = table.remove(stack)
          list, pc = frame[1], frame[2]
        elseif op == "checkflag" then
          result = getFlag(tonumber(argOf(cmd, "flag", 1))) and 1 or 0
        elseif op == "checktrainerflag" then
          result = getFlag(0x500 + (tonumber(argOf(cmd, "trainer", 1)) or 0)) and 1 or 0
        elseif op == "compare_var_to_value" or op == "compare_var_to_var" then
          local a = getVar(tonumber(argOf(cmd, "var", 1)))
          local b = tonumber(argOf(cmd, "value", 2)) or 0
          if op == "compare_var_to_var" then b = getVar(b) end
          result = (a < b and 0) or (a == b and 1) or 2
        elseif op == "goto" or op == "call" or op == "goto_if" or op == "call_if" then
          local taken = true
          if op == "goto_if" or op == "call_if" then
            local cond = tonumber(argOf(cmd, "cond", 1))
            taken = CONDITION[cond] ~= nil and CONDITION[cond][result] == true
            if not CONDITION[cond] then return nil, op end
          end
          if taken then
            local target = cmd.target
            local nextList = Scripts.get(target)
            if not nextList then return nil, "missing script" end
            if op == "call" or op == "call_if" then stack[#stack + 1] = { list, pc } end
            list, pc = nextList, 1
          end
        elseif op == "setvar" then
          vars[tonumber(argOf(cmd, "var", 1))] = tonumber(argOf(cmd, "value", 2)) or 0
        elseif op == "addvar" or op == "subvar" then
          local id = tonumber(argOf(cmd, "var", 1))
          local delta = tonumber(argOf(cmd, "value", 2)) or 0
          vars[id] = getVar(id) + (op == "addvar" and delta or -delta)
        elseif op == "copyvar" then
          vars[tonumber(cmd[1])] = getVar(tonumber(cmd[2]))
        elseif op == "setflag" or op == "clearflag" then
          flags[tonumber(argOf(cmd, "flag", 1))] = op == "setflag"
        elseif op == "setmetatile" then
          local x, y = tonumber(cmd[1]), tonumber(cmd[2])
          if not (x and y) then return nil, op end
          cells[y * 1024 + x] = { x = x, y = y, mid = tonumber(cmd[3]) or 0,
            impassable = (tonumber(cmd[4]) or 0) ~= 0 }
        elseif op == "setmaplayoutindex" then
          layoutIndex = tonumber(cmd[1])
        elseif op == "special" or op == "specialvar" then
          local id = op == "specialvar" and cmd[2] or cmd.id or cmd[1]
          return nil, "special " .. tostring(specialName(tonumber(id)))
        elseif not HARMLESS[op] then
          return nil, tostring(op)
        end
      end
    end
  end
  for _, kind in ipairs({ "onTransition", "onLoad" }) do
    if type(ms[kind]) == "string" then
      local ok, why = run(ms[kind])
      if not ok then return nil, why end
    end
  end
  local parts = { tostring(layoutIndex) }
  local keys = {}
  for k in pairs(cells) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local c = cells[k]
    parts[#parts + 1] = k .. ":" .. c.mid .. (c.impassable and "i" or "")
  end
  return { cells = cells, layoutIndex = layoutIndex, key = table.concat(parts, ",") }
end

-- ------------------------------------------------------------ elevators

-- The floors an elevator's floor panel serves: every setdynamicwarp its
-- script reaches (the menu's choices), as { mapId, x, y }, in script
-- order; and the flag the panel checks before it works at all (the
-- Rocket Hideout's Lift Key), or nil.  The gate is a checkflag followed
-- at once by a branch taken when the flag is unset, into a branch that
-- reaches no floor.
function Scripts.elevatorPanel(key)
  local list = Scripts.get(key)
  if not list then return nil end
  local floors, seen, visited = {}, {}, {}
  local function walk(k, depth)
    if depth > 6 or visited[k] then return end
    visited[k] = true
    for _, cmd in ipairs(Scripts.get(k) or {}) do
      if type(cmd) == "table" then
        if cmd.op == "setdynamicwarp" then
          local mapId = Scripts.mapIdOf(cmd[1], cmd[2])
          local x, y = tonumber(cmd[4]), tonumber(cmd[5])
          if mapId and x and y and not seen[mapId] then
            seen[mapId] = true
            floors[#floors + 1] = { mapId = mapId, x = x, y = y }
          end
        elseif BRANCH[cmd.op] then
          walk(cmd.target, depth + 1)
        end
      end
    end
  end
  walk(key, 0)
  if #floors == 0 then return nil end
  local gate
  for i, cmd in ipairs(list) do
    if type(cmd) == "table" and cmd.op == "checkflag" then
      local nextCmd = list[i + 1]
      if type(nextCmd) == "table" and nextCmd.op == "goto_if" and tonumber(argOf(nextCmd, "cond", 1)) == 0 then
        local branch = Scripts.reach(nextCmd.target)
        if not branch.ops.setdynamicwarp then gate = tonumber(argOf(cmd, "flag", 1)) end
      end
      break
    end
  end
  return { floors = floors, gateFlag = gate }
end

-- The item whose receipt sets `flag`: a script that sets the flag and
-- gives or finds an item (setorcopyvar 0x8000 <item>, then callstd 0 or
-- 1).  The Lift Key for the Rocket Hideout elevator.  Cached per flag.
local gateItems = {}
function Scripts.itemSettingFlag(flag)
  flag = tonumber(flag)
  if not flag then return nil end
  if gateItems[flag] ~= nil then return gateItems[flag] or nil end
  gateItems[flag] = false
  local scripts = injected
  if not scripts then
    local Space = loaded("src.core.game3.scripting.space")
    scripts = Space and Space.bundle and Space.bundle.scripts
  end
  for _, list in pairs(type(scripts) == "table" and scripts or {}) do
    if type(list) == "table" then
      local sets, item, gives = false, nil, false
      for _, cmd in ipairs(list) do
        if type(cmd) == "table" then
          if cmd.op == "setflag" and tonumber(argOf(cmd, "flag", 1)) == flag then sets = true end
          if cmd.op == "setorcopyvar" and tonumber(cmd[1]) == 0x8000 then item = tonumber(cmd[2]) end
          if cmd.op == "callstd" then
            local std = tonumber(cmd.std or cmd[1])
            if std == 0 or std == 1 then gives = true end
          end
        end
      end
      if sets and gives and item and item > 0 then
        gateItems[flag] = item
        return item
      end
    end
  end
  return nil
end

function Scripts._resetCachesForTests()
  for k in pairs(gateItems) do gateItems[k] = nil end
  mapIds = nil
end

-- ------------------------------------------------------------ falling

-- Where a map's own frame script drops the player (warphole <group> <num>,
-- landing where they stood), when the floor cracks underfoot: its resume
-- script sets step callback 4 (thin ice cracks, cracked ice gives way;
-- Icefall Cave 1F).  Returns the map id or nil.
function Scripts.crackedIceDrop(def)
  local ms = type(def) == "table" and type(def.mapScripts) == "table" and def.mapScripts or nil
  if not ms then return nil end
  local cracks = false
  if type(ms.onResume) == "string" then
    for _, cmd in ipairs(Scripts.get(ms.onResume) or {}) do
      if type(cmd) == "table" and cmd.op == "setstepcallback" and tonumber(cmd[1]) == 4 then cracks = true end
    end
  end
  if not cracks then return nil end
  for _, row in ipairs(type(ms.onFrame) == "table" and ms.onFrame or {}) do
    for _, cmd in ipairs(Scripts.get(row.script) or {}) do
      if type(cmd) == "table" and cmd.op == "warphole" then
        return Scripts.mapIdOf(cmd[1], cmd[2])
      end
    end
  end
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
  local name
  if ok and type(ItemsData) == "table" and type(ItemsData.displayName) == "function" then
    -- the item pack may not be loaded (it raises then)
    local okName, value = pcall(ItemsData.displayName, itemId)
    name = okName and value or nil
  end
  if type(name) ~= "string" or name == "" or name == tostring(itemId) then return nil end
  return Scripts.titleCase(name)
end

return Scripts
