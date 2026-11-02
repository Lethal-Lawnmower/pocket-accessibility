-- The Items page: Bag, PC, Wallet, Badges and, on Ruby, Sapphire and Emerald,
-- Pokéblocks.  Same rows, limits and Ops calls as upstream's panels/Items.lua,
-- panels/ItemPicker.lua and panels/Pokeblocks.lua, with their picker popup replaced
-- by a dropdown and their click-twice arming by the form's `confirm`
-- (docs/access/save-editor.md).  The arming lives in upstream's panels, not in
-- Ops.bagDrop, Ops.pcDrop or PokeblockOps.clear, so one confirmed press does it.
local Ops = require("Ops")
local Gen = require("Gen")
local Legality = require("Legality")
local Pokeblocks = require("PokeblockOps")

local Page = {}

-- ---------------------------------------------------------------- plain words

-- Gen 3 keeps its bag under numeric keys ("13") while its item table may also be
-- reached by constant name, so the lookup tries both before giving up on a name.
local function itemDefinition(S, id)
  local items = S.data and S.data.items or {}
  if items[id] then return items[id] end
  local number = tonumber(id)
  if number and items[number] then return items[number] end
  if number then
    for _, def in pairs(items) do
      if type(def) == "table" and tonumber(def.itemId) == number then return def end
    end
  end
  return nil
end

-- Upstream's display name, with the stray spacing its list row also strips.
local function itemName(S, id)
  local def = itemDefinition(S, id)
  local name = tostring(def and def.name or id)
  return (name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function titleCase(words)
  return (words:lower():gsub("(%a)(%w*)", function(first, rest) return first:upper() .. rest end))
end

-- "BOULDERBADGE" and "ZEPHYRBADGE" read as "Boulder Badge" and "Zephyr Badge".
local function badgeName(id)
  local stem = tostring(id):gsub("_?BADGE$", "")
  return titleCase((stem:gsub("_", " "))) .. " Badge"
end

-- Ops words its status with internal ids ("POTION x5", "12/20 KEY_ITEM slots").
-- The status is read aloud, so it gets the display name instead.
local function plainStatus(S, id)
  local status = tostring(S.status or "")
  if id ~= nil then
    local raw = tostring(id)
    local first, last = status:find(raw, 1, true)
    if first then status = status:sub(1, first - 1) .. itemName(S, id) .. status:sub(last + 1) end
  end
  status = status:gsub("(%u[%u_]+) slots", function(pocket)
    return (pocket:gsub("_", " "):lower()) .. " slots"
  end)
  return (status:gsub("sorted by index", "sorted by item number"))
end

-- Runs one edit and rewrites whatever it had to say.  Upstream's toast reuses its
-- table when the same words come again, and the backend tells something new by that
-- table changing, so a second identical refusal would be silent; dropping the old
-- toast first makes every spoken result count as new.  If nothing was said, the old
-- one goes back and the status stays out of the answer.
local function perform(S, id, operation)
  local toastBefore = S.toast
  S.toast = nil
  local result = operation()
  if S.toast then
    S.status = plainStatus(S, id)
  else
    S.toast = toastBefore
  end
  return result
end

-- ---------------------------------------------------------------------- views

local function viewOptions(S)
  local options = {
    { value = "bag", label = "Bag" },
    { value = "pc", label = "PC" },
    { value = "wallet", label = "Wallet" },
    { value = "badges", label = "Badges" },
  }
  if Pokeblocks.has(S.save, S.version) then
    options[#options + 1] = { value = "pokeblocks", label = "Pokéblocks" }
  end
  return options
end

-- The view in `state`, or Bag if this save has no such view.
local function currentView(S, state)
  for _, option in ipairs(viewOptions(S)) do
    if option.value == state.view then return state.view end
  end
  state.view = "bag"
  return "bag"
end

-- --------------------------------------------------------------- Bag and PC

local function stackRowId(row)
  return tostring(row.id) .. "#" .. tostring(row.slot)
end

-- The selected stack.  Undo, Reload or a drop can take it away, and a stack that
-- split or merged can change slot, so this falls back to the same item, then to
-- whatever now sits at the same place in the list.
local function selectedStack(S, state, pc)
  local rows = Ops.stackRows(S, pc)
  local key = pc and "pc" or "bag"
  local wanted = state[key .. "Selected"]
  local index
  for i, row in ipairs(rows) do
    if stackRowId(row) == wanted then index = i; break end
  end
  if not index and wanted then
    local item = tostring(wanted):match("^(.*)#[^#]*$")
    for i, row in ipairs(rows) do
      if tostring(row.id) == item then index = i; break end
    end
  end
  if not index and #rows > 0 then
    index = math.max(1, math.min(state[key .. "Index"] or 1, #rows))
  end
  local row = index and rows[index] or nil
  state[key .. "Selected"] = row and stackRowId(row) or nil
  state[key .. "Index"] = index
  return row, rows
end

local function storeOf(S, pc)
  return pc and Ops.pcItems(S) or S.save.inventory or {}
end

-- The catalog names an item by constant, but Gen 3 stores and lists it under its
-- number, so a catalog id has to pass through here to meet a stack.
local function storeKey(S, id)
  if Gen.ofState(S) == 3 then return require("Game3Adapter").key(S.data, id) end
  return id
end

-- Every addable item, A to Z so that typing a letter in the dropdown finds it.
-- The catalog does not change while a save is open, so this is built once.
local function addableItems(S, state)
  if state.addable then return state.addable end
  local items = {}
  for _, id in ipairs(Ops.itemSearch(S, "")) do
    items[#items + 1] = { id = id, name = itemName(S, id) }
  end
  table.sort(items, function(a, b)
    local left, right = a.name:lower(), b.name:lower()
    if left ~= right then return left < right end
    return tostring(a.id) < tostring(b.id)
  end)
  state.addable = items
  return items
end

-- The dropdown's choice as the catalog's own id; JSON may have changed its type.
local function chosenItem(S, state)
  local items = addableItems(S, state)
  for _, item in ipairs(items) do
    if tostring(item.id) == tostring(state.addItem) then return item end
  end
  -- Sorted by name, Gen 1's list opens on its elevator floors ("10F"), which
  -- upstream lists as items; start on a real item so Add is never a surprise.
  local first = items[1]
  for _, item in ipairs(items) do
    if not tostring(item.name):match("^B?%d+F$") then
      first = item
      break
    end
  end
  state.addItem = first and first.id or nil
  return first
end

local function addOptions(S, state, pc)
  local options, store = {}, storeOf(S, pc)
  for _, item in ipairs(addableItems(S, state)) do
    -- how many this store already holds, so a second add is an informed one
    local have = Ops.itemQty(store, storeKey(S, item.id))
    local label = have > 0 and (item.name .. ", have " .. have) or item.name
    options[#options + 1] = { value = item.id, label = label }
  end
  return options
end

local function stackRowText(S, row, repeated)
  local text = itemName(S, row.id) .. ", " .. tostring(row.count)
  if repeated then text = text .. ", stack " .. row.slot end
  return text
end

local function stackList(S, rows, selected, pc)
  local copies = {}
  for _, row in ipairs(rows) do
    local key = tostring(row.id)
    copies[key] = (copies[key] or 0) + 1
  end
  local shown = {}
  for i, row in ipairs(rows) do
    shown[i] = { id = stackRowId(row), text = stackRowText(S, row, copies[tostring(row.id)] > 1) }
  end
  return {
    label = pc and "PC storage" or "Bag",
    rows = shown,
    selected = selected and stackRowId(selected) or nil,
    filter = true,
  }
end

-- Names the stack being edited, since a filter can hide the selection in the list.
local function countLabel(name, row, rows)
  if not row then return "Count" end
  for _, other in ipairs(rows) do
    if other ~= row and tostring(other.id) == tostring(row.id) then
      return "Count of " .. name .. ", stack " .. row.slot
    end
  end
  return "Count of " .. name
end

local function stackModel(S, state, pc)
  local row, rows = selectedStack(S, state, pc)
  local chosen = chosenItem(S, state)
  local name = row and itemName(S, row.id) or nil
  local count = row and (row.count or 0) or nil
  local max = row and Ops.itemMax(S, row.id, pc) or nil
  local issue
  if row and not Legality.integer(count, 1, max) then
    issue = "Saved stack must be a whole number from 1 to " .. max
  end
  local where = pc and "PC storage" or "the bag"
  return {
    pickers = { { id = "view", label = "View", value = pc and "pc" or "bag", options = viewOptions(S) } },
    summary = (pc and "PC storage: " or "Bag: ") .. #rows .. (#rows == 1 and " stack" or " stacks"),
    list = stackList(S, rows, row, pc),
    fields = {
      { id = "count", label = countLabel(name, row, rows), kind = "number",
        value = count, lo = row and 1 or nil, hi = max, enabled = row ~= nil, issue = issue,
        help = "Set the stack size. Max fills it; Drop removes it." },
      { id = "addItem", label = "Item to add", kind = "choice", value = chosen and chosen.id or nil,
        options = addOptions(S, state, pc), help = "Add puts one of this item in " .. where .. "." },
    },
    actions = {
      { id = "add", label = "Add to " .. (pc and "PC" or "Bag"), enabled = chosen ~= nil },
      { id = "decrease", label = "Decrease", enabled = row ~= nil },
      { id = "increase", label = "Increase", enabled = row ~= nil },
      { id = "max", label = "Max", enabled = row ~= nil },
      { id = "maxAll", label = "Max all", enabled = #rows > 0 },
      { id = "sortName", label = "Sort A-Z", enabled = #rows > 0 },
      { id = "sortNumber", label = "Sort by number", enabled = #rows > 0 },
      { id = "move", label = pc and "Move to Bag" or "Move to PC",
        enabled = row ~= nil and Ops.moveCount(S, not pc, row.id) > 0 },
      { id = "delete", label = "Drop", enabled = row ~= nil,
        confirm = row and ("Drop this stack of " .. count .. " " .. name .. " from " .. where .. "?") or nil },
    },
  }
end

-- Upstream's item editor takes a whole number from 1 to the limit and turns it into
-- a change of count; the limit check lives in its editor, so it is repeated here.
local function setStackCount(S, state, pc, value)
  local row = selectedStack(S, state, pc)
  if not row then return perform(S, nil, function() return Ops.say(S, "Select a stack first") end) end
  local max = Ops.itemMax(S, row.id, pc)
  local name = itemName(S, row.id)
  if not Legality.integer(value, 1, max) then
    return perform(S, nil, function()
      return Ops.say(S, name .. " count must be a whole number from 1 to " .. max .. ". Drop removes the stack.")
    end)
  end
  local count = row.count or 0
  if value == count then return true end
  local adjust = pc and Ops.pcAdjust or Ops.bagAdjust
  return perform(S, row.id, function() return adjust(S, row.id, value - count, row.slot) end)
end

-- After an add, the stack it landed in becomes the selection.  With split stacks
-- that is the item's last row: the game fills the earlier ones first.
local function selectLastStackOf(S, state, pc, id)
  local key = pc and "pc" or "bag"
  for _, row in ipairs(Ops.stackRows(S, pc)) do
    if tostring(row.id) == tostring(id) then state[key .. "Selected"] = stackRowId(row) end
  end
end

-- Upstream's PC sort only reorders the view when the save stores no order, and
-- then reports nothing, which sounds the same as a button that did not work.
local function sortStacks(S, pc, mode)
  local words = mode == "name" and "name" or "item number"
  if not pc then
    return perform(S, nil, function() return Ops.bagSort(S, mode) end)
  end
  return perform(S, nil, function()
    Ops.pcSort(S, mode)
    if not S.toast then Ops.say(S, "PC storage sorted by " .. words, "info") end
    return true
  end)
end

local function stackAction(S, state, pc, action)
  local row = selectedStack(S, state, pc)
  if action == "add" then
    local chosen = chosenItem(S, state)
    if not chosen then return Ops.say(S, "Pick an item first") end
    local add = pc and Ops.addToPc or Ops.addToBag
    local added = perform(S, chosen.id, function() return add(S, chosen.id) end)
    if added then
      local key = storeKey(S, chosen.id)
      selectLastStackOf(S, state, pc, key)
      -- A second add must not sound like the first, so the new total is in the words.
      local slots = tostring(S.status):match("%(.-slots%)$")
      S.status = "Added " .. chosen.name .. ", now " .. Ops.itemQty(storeOf(S, pc), key)
        .. (pc and " in PC storage" or " in the bag") .. (slots and (" " .. slots) or "")
    end
    return added
  elseif action == "maxAll" then
    local maxAll = pc and Ops.pcMaxAll or Ops.bagMaxAll
    return perform(S, nil, function() return maxAll(S) end)
  elseif action == "sortName" then
    return sortStacks(S, pc, "name")
  elseif action == "sortNumber" then
    return sortStacks(S, pc, "index")
  end
  if not row then return Ops.say(S, "Select a stack first") end
  local id, slot = row.id, row.slot
  return perform(S, id, function()
    if action == "decrease" then
      return (pc and Ops.pcAdjust or Ops.bagAdjust)(S, id, -1, slot)
    elseif action == "increase" then
      return (pc and Ops.pcAdjust or Ops.bagAdjust)(S, id, 1)
    elseif action == "max" then
      return (pc and Ops.pcMax or Ops.bagMax)(S, id)
    elseif action == "move" then
      return (pc and Ops.pcToBag or Ops.bagToPc)(S, id)
    elseif action == "delete" then
      return (pc and Ops.pcDrop or Ops.bagDrop)(S, id, slot)
    end
    error("items does not handle action " .. tostring(action), 0)
  end)
end

-- --------------------------------------------------------------------- Wallet

local function walletFields(S)
  local save, version = S.save, S.version
  local fields = {}
  local function number(id, label, value, hi, help)
    fields[#fields + 1] = { id = id, label = label, kind = "number", lo = 0, hi = hi, value = value, help = help }
  end
  number("money", "Money", Gen.money(save), 999999, "Your wallet.")
  number("coins", "Coins", Gen.coins(save), 9999, "Game Corner coins.")
  if Gen.hasBuenaPoints(save, version) then
    number("buenaPoints", "Buena points", Gen.buenaPoints(save, version), 30, "Blue Card points for Buena's prizes.")
  end
  if Gen.hasBerryPowder(save, version) then
    number("berryPowder", "Berry Powder", Gen.berryPowder(save, version), Gen.BERRY_POWDER_MAX,
      "Powder from Berry Crush, spent at the Berry Powder shop.")
  end
  if Gen.hasVolcanicAsh(save, version) then
    number("volcanicAsh", "Volcanic Ash", Gen.volcanicAsh(save, version), Gen.VOLCANIC_ASH_MAX,
      "Ash collected in the Soot Sack, spent at the Glass Workshop.")
  end
  if Gen.hasBattlePoints(save, version) then
    number("battlePoints", "Battle Points", Gen.battlePoints(save, version), Gen.BATTLE_POINTS_MAX,
      "Battle Frontier points, spent at the Exchange Service Corner.")
  end
  return fields
end

local WALLET_FIELD = {
  money = true, coins = true, buenaPoints = true, berryPowder = true, volcanicAsh = true, battlePoints = true,
}

-- Upstream's value editor holds the limit, and Ops only answers "Invalid trainer
-- value" for money and coins, so the limit is said here in words.
local function setWalletValue(S, field, value)
  for _, entry in ipairs(walletFields(S)) do
    if entry.id == field and not Legality.integer(value, entry.lo, entry.hi) then
      return Ops.say(S, entry.label .. " must be a whole number from " .. entry.lo .. " to " .. entry.hi)
    end
  end
  return Ops.setTrainerProperty(S, field, value)
end

-- --------------------------------------------------------------------- Badges

local function badgeModel(S, state)
  local ids = Ops.badgeIds(S)
  local rows, earned, selected = {}, 0, nil
  for i, id in ipairs(ids) do
    local has = Gen.hasBadge(S.save, id) and true or false
    if has then earned = earned + 1 end
    rows[i] = { id = tostring(id), text = badgeName(id), checked = has }
    if tostring(id) == state.badge then selected = tostring(id) end
  end
  selected = selected or (rows[1] and rows[1].id) or nil
  state.badge = selected
  return {
    pickers = { { id = "view", label = "View", value = "badges", options = viewOptions(S) } },
    summary = "Badges: " .. earned .. " of " .. #ids,
    -- The filter box stays on: the form applies its text to every list, and a
    -- hidden box would leave a list silently filtered with no way to clear it.
    list = { label = "Badges", rows = rows, selected = selected, checks = true, filter = true },
  }
end

local function toggleBadge(S, request)
  for _, id in ipairs(Ops.badgeIds(S)) do
    if tostring(id) == tostring(request.row) then
      local want = request.checked == true
      if (Gen.hasBadge(S.save, id) and true or false) == want then return true end
      Ops.toggleBadge(S, id)
      S.status = badgeName(id) .. (want and " earned" or " removed")
      return true
    end
  end
  return Ops.say(S, "That badge is not in this game")
end

-- ----------------------------------------------------------------- Pokéblocks

local FLAVOR_FIELDS = { "spicy", "dry", "sweet", "bitter", "sour", "feel" }
local IS_FLAVOR_FIELD = {}
for _, field in ipairs(FLAVOR_FIELDS) do IS_FLAVOR_FIELD[field] = true end

local function selectedBlockSlot(state)
  local slot = tonumber(state.blockSlot) or 1
  if slot < 1 or slot > Pokeblocks.COUNT or slot ~= math.floor(slot) then slot = 1 end
  state.blockSlot = slot
  return slot
end

local function pokeblockModel(S, state)
  local slot = selectedBlockSlot(state)
  local rows = {}
  for i = 1, Pokeblocks.COUNT do
    local color = Pokeblocks.block(S.save, i).color
    rows[i] = { id = tostring(i), text = "Slot " .. i .. ", " .. (color == 0 and "Empty" or Pokeblocks.colorName(color)) }
  end
  local block = Pokeblocks.block(S.save, slot)
  local empty = block.color == 0
  local colors = {}
  for i, option in ipairs(Pokeblocks.colorOptions()) do
    colors[i] = { value = option[1], label = option[2] }
  end
  local fields = {
    { id = "color", label = "Color", kind = "choice", value = not empty and block.color or nil, options = colors,
      enabled = not empty, help = "The block's color, as the case and Blender name it." },
  }
  for _, field in ipairs(FLAVOR_FIELDS) do
    fields[#fields + 1] = { id = field, label = Pokeblocks.FIELD_NAMES[field], kind = "number",
      value = not empty and block[field] or nil, lo = 0, hi = Pokeblocks.MAX_BYTE, enabled = not empty,
      help = field == "feel" and "Feel adds to sheen when fed; the game counts at most 99."
        or "Raises the matching contest condition when fed." }
  end
  return {
    pickers = { { id = "view", label = "View", value = "pokeblocks", options = viewOptions(S) } },
    summary = "Pokéblock Case: " .. Pokeblocks.count(S.save) .. " of " .. Pokeblocks.COUNT,
    list = { label = "Pokéblock slots", rows = rows, selected = tostring(slot), filter = true },
    fields = fields,
    actions = {
      { id = "add", label = "Add block", enabled = Pokeblocks.firstFree(S.save) ~= nil },
      { id = "addHere", label = "Add here", enabled = empty },
      { id = "delete", label = "Delete block", enabled = not empty,
        confirm = not empty and ("Delete the " .. Pokeblocks.colorName(block.color)
          .. " Pokéblock in slot " .. slot .. "?") or nil },
    },
  }
end

local function pokeblockAction(S, state, action)
  local slot = selectedBlockSlot(state)
  if action == "add" or action == "addHere" then
    local added = Pokeblocks.add(S, action == "addHere" and slot or nil)
    if added and S.pokeblockSlot then state.blockSlot = S.pokeblockSlot end
    return added
  elseif action == "delete" then
    return Pokeblocks.clear(S, slot)
  end
  error("items does not handle action " .. tostring(action), 0)
end

-- ------------------------------------------------------------------- the page

function Page.model(S, state)
  local view = currentView(S, state)
  if view == "wallet" then
    return {
      pickers = { { id = "view", label = "View", value = "wallet", options = viewOptions(S) } },
      fields = walletFields(S),
    }
  elseif view == "badges" then
    return badgeModel(S, state)
  elseif view == "pokeblocks" then
    return pokeblockModel(S, state)
  end
  return stackModel(S, state, view == "pc")
end

function Page.pick(_, state, request)
  if request.picker == "view" then state.view = request.value end
end

function Page.select(S, state, request)
  local view = currentView(S, state)
  if view == "bag" then
    state.bagSelected = tostring(request.row)
  elseif view == "pc" then
    state.pcSelected = tostring(request.row)
  elseif view == "badges" then
    state.badge = tostring(request.row)
  elseif view == "pokeblocks" then
    state.blockSlot = tonumber(request.row)
  end
end

function Page.set(S, state, request)
  local view, field = currentView(S, state), request.field
  if field == "addItem" then
    state.addItem = request.value
  elseif field == "count" then
    return setStackCount(S, state, view == "pc", request.value)
  elseif WALLET_FIELD[field] then
    return perform(S, nil, function() return setWalletValue(S, field, request.value) end)
  elseif field == "color" or IS_FLAVOR_FIELD[field] then
    return perform(S, nil, function()
      return Pokeblocks.set(S, selectedBlockSlot(state), field, request.value)
    end)
  else
    error("items does not handle field " .. tostring(field), 0)
  end
end

function Page.toggle(S, _, request)
  return perform(S, nil, function() return toggleBadge(S, request) end)
end

function Page.action(S, state, request)
  local view = currentView(S, state)
  if view == "bag" or view == "pc" then
    return perform(S, nil, function() return stackAction(S, state, view == "pc", request.action) end)
  elseif view == "pokeblocks" then
    return perform(S, nil, function() return pokeblockAction(S, state, request.action) end)
  end
  error("items does not handle action " .. tostring(request.action), 0)
end

return Page
