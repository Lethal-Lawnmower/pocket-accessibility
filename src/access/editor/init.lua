-- Screen-reader access to upstream's save editor (docs/access/save-editor.md).
--
-- Tab and Shift+Tab move between controls; the arrows also stop on text, like a
-- screen reader's browse mode.  Enter or Space activates by clicking the control
-- through the editor's normal mouse path, so every action takes the same route
-- as a sighted click: modal shields, confirmations and saving are all upstream's.
-- App.lua calls Editor.attach once (listed hook).
local Capture = require("src.access.editor.Capture")
local Speech = require("src.access.Speech")

local Editor = {}

local INTRO = "Tab and arrows move, Enter activates, Control S saves"
-- A pause in typing before saying what a search now finds.
local RESULTS_DELAY = 0.6
local FEEDBACK_FRAMES = 4
local MAX_SCROLL_TRIES = 40
local MAP_MOVES = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function shiftDown()
  return love.keyboard and love.keyboard.isDown and love.keyboard.isDown("lshift", "rshift")
end

local function gameName(version)
  local info = version and require("src.core.GameVersion").info(version)
  return info and (info.name or info.displayName or info.title) or tostring(version or "")
end

local function say(text, interrupt)
  if text and text ~= "" then Speech.say(text, { interrupt = interrupt == true }) end
end

function Editor.attach(App, Kit)
  if not Speech.available() then return false end
  local Motion, Touch, PadInput = require("Motion"), require("TouchEditor"), require("PadInput")
  local VirtualKeyboard = require("src.ui.kit.VirtualKeyboard")
  local capture = Capture.install(Kit, Touch)

  local items, index = {}, 1
  local currentKey, currentSpeech
  local shownModal, modalReturn
  local shownTab, shownStatus, shownNote, shownToast, shownField
  local introduced = false
  -- A click changes the page over the next frames; watch that long for its
  -- result, so the words spoken are the settled ones.
  local pendingMove, feedbackFrames = nil, 0
  local modalKey
  local resultsDue, shownPopupValue, freshNumberField
  local pointerAt
  local moveTries = 0

  function modalKey(S)
    if VirtualKeyboard.active then return "keyboard" end
    if S.editPopup then return "edit:" .. tostring(S.editPopup.id or S.editPopup.mode) end
    if S.navPopup then return "nav:" .. tostring(S.navPopup.key) end
    if S.speciesPicker then return "species" end
    if S.movePicker then return "move" end
    if S.itemPicker then return "item" end
    return nil
  end

  local function current() return items[index] end

  local function speakCurrent(prefix)
    local item = current()
    if not item then
      say(prefix, true)
      return
    end
    currentKey, currentSpeech = item.key, Capture.describe(item)
    say(prefix and (prefix .. ". " .. currentSpeech) or currentSpeech, true)
  end

  local function find(key)
    for i, item in ipairs(items) do
      if item.key == key then return i end
    end
  end

  -- The chrome comes first in draw order; a page's own content starts after the
  -- page dropdown.
  local function pageStart()
    for i, item in ipairs(items) do
      if item.id == "navigate-tab" then return math.min(i + 1, math.max(#items, 1)) end
    end
    return 1
  end

  local function nextIndex(from, delta, controlsOnly)
    local i = from + delta
    while items[i] do
      if not controlsOnly or items[i].control then return i end
      i = i + delta
    end
    return nil
  end

  -- Wheel notches at an item: the next frame's pointer sits on it.
  local function wheel(notches, item)
    pointerAt = item
    -- the map's zoom asks for the real pointer; everything else uses Kit's
    local getPosition = love.mouse.getPosition
    love.mouse.getPosition = function() return item.x, item.y end
    App.wheelmoved(0, notches)
    love.mouse.getPosition = getPosition
  end

  -- Notches that take `scroller` from where it is to an end (48 pixels each,
  -- Kit.scrollPixels), positive towards its top.
  local function notchesToEnd(scroller, top)
    local pixels = top and scroller.offset or scroller.max - scroller.offset
    local count = math.ceil(pixels / (48 * Kit.scale)) + 1
    return top and count or -count
  end

  local function move(delta, controlsOnly)
    local item = current()
    if not item then return end
    local target = nextIndex(index, delta, controlsOnly)
    local scroller = item.scroller
    local tries = moveTries
    moveTries = 0
    if tries <= MAX_SCROLL_TRIES then
      local function request(offset)
        pendingMove = { delta = delta, controlsOnly = controlsOnly, offset = offset, tries = tries + 1 }
      end
      -- leaving a list that has more rows out of view: bring them in first
      if scroller and (not target or items[target].scroller ~= scroller) then
        local room = delta > 0 and scroller.offset < scroller.max or delta < 0 and scroller.offset > 0
        if room then
          request(scroller.offset)
          wheel(delta > 0 and -1 or 1, item)
          return
        end
      end
      -- entering a list left scrolled partway: start from its near end, or what
      -- is scrolled past could never be reached in this direction
      local entered = target and items[target].scroller
      if entered and entered ~= scroller then
        local away = delta > 0 and entered.offset > 0 or delta < 0 and entered.offset < entered.max
        if away then
          request(nil)
          wheel(notchesToEnd(entered, delta > 0), items[target])
          return
        end
      end
    end
    pendingMove = nil
    if target then
      index = target
      speakCurrent()
    else
      say(delta > 0 and "End of page" or "Top of page", true)
    end
  end

  local function jump(i)
    if items[i] then
      index = i
      speakCurrent()
    end
  end

  local function click(x, y)
    App.mousepressed(x, y, 1)
    feedbackFrames = FEEDBACK_FRAMES
  end

  local function activate()
    local item = current()
    if not item then return end
    if not item.control then return speakCurrent() end
    if item.enabled == false then return say("Unavailable", true) end
    click(item.x, item.y)
  end

  -- The focused control is the pointer: hover follows it, and the wheel scrolls
  -- the list it sits in.
  local pointer = PadInput.pointer
  PadInput.pointer = function(...)
    local item = App.getState() and (pointerAt or current())
    if item and item.x then return item.x, item.y, true end
    return pointer(...)
  end

  local function pageName(S)
    for _, item in ipairs(items) do
      if item.id == "navigate-tab" then return item.label end
    end
    return tostring(S.tab)
  end

  -- The map's picture is the one thing with no controls in it.  Shift+arrows
  -- walk a cell cursor over it; the Player and Heal buttons then act on that cell
  -- exactly as they do on a clicked one.
  local function moveMapCell(S, step)
    local ok, map = require("MapBrowser").preview(S)
    if not ok then return say(tostring(map), true) end
    local cell = S.mapClickCell
    local x, y
    if cell then
      x, y = cell.cx + step[1], cell.cy + step[2]
    else
      -- first press: where the player stands on this map, else its middle
      local playerMap, px, py = require("Gen").playerMap(S.save)
      local onMap = playerMap == S.mapId
      x = onMap and px or math.floor((map.widthCells or 0) / 2)
      y = onMap and py or math.floor((map.heightCells or 0) / 2)
    end
    if not map:inBounds(x, y) then return say("Edge of map", true) end
    S.mapClickCell = { cx = x, cy = y }
    local parts = { x .. ", " .. y }
    local warp = map:warpAtCell(x, y)
    if warp then parts[#parts + 1] = "warp to " .. tostring(warp.def.destMap or warp.def.map or "unknown") end
    if map.isWalkableCell then
      local checked, walkable = pcall(map.isWalkableCell, map, x, y)
      if checked then parts[#parts + 1] = walkable and "walkable" or "blocked" end
    end
    say(table.concat(parts, ", "), true)
  end

  local function settle(S, modalAtStart)
    local popup = S and S.editPopup
    local fresh = capture.finish(popup and popup.wheelRect)
    pointerAt = nil
    -- A transition or a modal's first frame draws nothing that can take input,
    -- and a popup opened partway through a frame shows only part of the page.
    if not S or #fresh == 0 or Motion.active() or modalKey(S) ~= modalAtStart then return end
    items = fresh

    local modal, tab, field = modalAtStart, S.tab, Kit.focus
    local status, note, toast = S.status, S.note, S.toast
    local restored = currentKey and find(currentKey)

    if not introduced then
      introduced = true
      index = pageStart()
      local prefix = "Save editor. " .. gameName(S.version) .. ". Page " .. pageName(S) .. ". " .. INTRO
      if S.loadError or S.missingCache then prefix = tostring(status) .. " " .. prefix end
      shownModal, shownTab, shownStatus, shownNote, shownToast, shownField = modal, tab, status, note, toast, field
      speakCurrent(prefix)
      return
    end

    if modal ~= shownModal then
      local opening = modal ~= nil
      if opening and shownModal == nil then modalReturn = currentKey end
      shownModal, currentKey = modal, nil
      pendingMove, feedbackFrames = nil, 0
      if opening then
        -- start on what is chosen now, or the first control after the title
        local title = items[1] and not items[1].control and items[1].text or nil
        index = nextIndex(0, 1, true) or 1
        local searchField
        for i, item in ipairs(items) do
          if item.selected and index == (nextIndex(0, 1, true) or 1) then index = i end
          if item.role == "field" and not searchField then searchField = i end
        end
        -- a picker with a search box opens ready to type; its Enter takes the
        -- first result and Tab or the arrows walk the results
        if searchField then index = searchField end
        -- a number popup opens on its typing button, the quickest way to a value
        if popup and popup.mode == "number" then
          for i, item in ipairs(items) do
            if item.label == "Type a value" then index = i end
          end
          title = tostring(title) .. ", " .. tostring(popup.value)
        end
        speakCurrent(title)
        if searchField then click(items[index].x, items[index].y) end
      else
        index = modalReturn and find(modalReturn) or math.min(index, #items)
        modalReturn = nil
        speakCurrent()
      end
    elseif tab ~= shownTab then
      shownTab = tab
      index = pageStart()
      pendingMove, feedbackFrames = nil, 0
      speakCurrent("Page " .. pageName(S))
    elseif pendingMove then
      local request = pendingMove
      pendingMove = nil
      index = restored or math.min(index, #items)
      local item = current()
      local scrolled = request.offset == nil or (item and item.scroller and item.scroller.offset ~= request.offset)
      -- no movement means the list is at its end: step out of it normally
      moveTries = scrolled and request.tries or MAX_SCROLL_TRIES + 1
      if item then move(request.delta, request.controlsOnly) end
    else
      index = restored or math.min(index, #items)
      local item = current()
      if item then
        local speech = Capture.describe(item)
        if not restored or (feedbackFrames > 0 and speech ~= currentSpeech) then
          speakCurrent()
          -- "Type a value" turns into the box it stands for: start in it
          if feedbackFrames > 0 and item.role == "field" and not field then click(item.x, item.y) end
        else
          currentKey, currentSpeech = item.key, speech
        end
      end
    end
    feedbackFrames = math.max(0, feedbackFrames - 1)
    if popup and popup.mode == "number" and popup.value ~= shownPopupValue then
      if shownPopupValue ~= nil then say(tostring(popup.value), false) end
      shownPopupValue = popup.value
    elseif not popup then
      shownPopupValue = nil
    end

    if resultsDue and love.timer.getTime() >= resultsDue then
      resultsDue = nil
      local at = current()
      if field and at and at.role == "field" then
        local first = nextIndex(index, 1, true)
        -- what Enter would take, when the next thing is a result row
        if first and items[first].role == "row" then
          say("First: " .. items[first].label, false)
        elseif modal or field then
          say(first and "No results" or nil, false)
        end
      end
    end

    if field ~= shownField then
      shownField = field
      if field then say("Editing. Type, then Enter.", false) end
      -- a number box opens holding the old value: the first digit replaces it
      freshNumberField = field and (tostring(field):find("^value%-edit") or field == "touch-exact") and true or nil
    end
    if status ~= shownStatus or toast ~= shownToast then
      local changed = status ~= shownStatus or toast ~= nil
      shownStatus, shownToast = status, toast
      if changed then say(status, false) end
    end
    if note ~= shownNote then
      shownNote = note
      say(note, false)
    end
  end

  -- Each opening starts afresh.  A standalone start names no file; upstream's
  -- default is a pre-slots path, so find the save the game itself would load.
  local load = App.load
  App.load = function(path, opts)
    items, index, currentKey, currentSpeech = {}, 1, nil, nil
    shownModal, modalReturn, introduced, pendingMove, feedbackFrames = nil, nil, false, nil, 0
    resultsDue, shownPopupValue, freshNumberField = nil, nil, nil
    if not path and opts and opts.version then path = Editor.activeSavePath(opts.version) end
    return load(path, opts)
  end

  local draw = App.draw
  App.draw = function(...)
    local before = App.getState()
    local modalAtStart = before and modalKey(before)
    capture.begin()
    local result = draw(...)
    settle(App.getState(), modalAtStart)
    return result
  end

  local keypressed = App.keypressed
  App.keypressed = function(key)
    local S = App.getState()
    if not S then return keypressed(key) end
    if key == "tab" then
      if Kit.focus then Kit.blur() end
      return move(shiftDown() and -1 or 1, true)
    end
    if Kit.focus and (key == "up" or key == "down") then
      Kit.blur()
      return move(key == "down" and 1 or -1, false)
    end
    if Kit.focus or VirtualKeyboard.active then
      if key == "backspace" then say("Backspace", true) end
      freshNumberField = nil
      resultsDue = love.timer.getTime() + RESULTS_DELAY
      return keypressed(key)
    end
    if key == "return" or key == "kpenter" or key == "space" then return activate() end
    if S.missingCache then return keypressed(key) end
    if S.tab == "map" and S.mapId and shiftDown() and MAP_MOVES[key] and not modalKey(S) then
      return moveMapCell(S, MAP_MOVES[key])
    end
    if key == "down" then return move(1, false)
    elseif key == "up" then return move(-1, false)
    elseif key == "home" then return jump(1)
    elseif key == "end" then return jump(#items)
    elseif key == "f2" then return speakCurrent()
    elseif key == "f1" then
      local item = current()
      if item and item.help then return click(item.help.x + item.help.w / 2, item.help.y + item.help.h / 2) end
      return say("No help here", true)
    end
    return keypressed(key)
  end

  local textinput = App.textinput
  App.textinput = function(text)
    if Kit.focus or VirtualKeyboard.active then
      if freshNumberField then
        for _, item in ipairs(items) do
          if item.id == Kit.focus then
            for _ = 1, #tostring(item.value or "") do Kit.keypressed("backspace") end
          end
        end
        freshNumberField = nil
      end
      say(text, true)
      resultsDue = love.timer.getTime() + RESULTS_DELAY
    end
    return textinput(text)
  end

  return true
end

local function exists(path)
  local file = path and io.open(path, "rb")
  if file then file:close() end
  return file ~= nil and file ~= false
end

-- The file the game loads for `version`, or nil to leave upstream's default.
function Editor.activeSavePath(version)
  local SaveData = require("src.core.SaveData")
  -- as upstream's Edit button does: finish any interrupted box transfer first
  pcall(function() require("src.box.Transaction").recover(SaveData.persistenceFs()) end)
  local slot = SaveData.activeSlot(version)
  local path = slot and SaveData.slotDiskPath(version, slot)
  if exists(path) then return path end
  local flat = love.filesystem.getSaveDirectory() .. package.config:sub(1, 1) .. SaveData.saveFilename(version)
  if exists(flat) then return flat end
  return path
end

return Editor
