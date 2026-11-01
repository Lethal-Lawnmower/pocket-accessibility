-- Presenters for link play: the cable club (src/link/LinkState.lua: host,
-- join, address entry, trade and battle setup) and the Union Room battle
-- and trade preparation screens (src/ui/union/prep/).  Same contract as
-- Presenters.lua; each mirrors what its screen's draw() shows.

local LinkScreens = {}

local function matcher(path)
  return function(state)
    local mod = package.loaded[path]
    return mod ~= nil and getmetatable(state) == mod
  end
end

local function speakable(text)
  text = tostring(text or "")
  text = text:gsub("{[A-Z_]+}", ""):gsub("<PK>", "PK"):gsub("<MN>", "MN")
  return (text:gsub("%s*[\n\v\f]%s*", " "))
end

local function joinNonEmpty(parts, sep)
  local out = {}
  for i = 1, table.maxn(parts) do
    if parts[i] ~= nil and parts[i] ~= "" then out[#out + 1] = tostring(parts[i]) end
  end
  return table.concat(out, sep or ". ")
end

-- ------------------------------------------------------------ cable club

local function gameText(state, key)
  local data = state.game and state.game.data
  return data and data.text and data.text[key] or nil
end

local function addressText(state)
  local ok, CodeEntry = pcall(require, "src.link.CodeEntry")
  if not ok or not state.addr then return "" end
  local okText, text = pcall(CodeEntry.text, state.addr)
  return okText and tostring(text or ""):gsub("%s+$", "") or ""
end

local function portText()
  local ok, Net = pcall(require, "src.link.Net")
  if not ok or type(Net.defaultPort) ~= "function" then return "?" end
  local okPort, port = pcall(Net.defaultPort)
  return okPort and port ~= nil and tostring(port) or "?"
end

local function tradeFocus(state)
  local t = state.trade or {}
  local party = state.game and state.game.save and state.game.save.party or {}
  if state.pickChoice then
    local labels = speakable(gameText(state, "TradeCenter_SelectMon.statsTrade") or "STATS TRADE")
    local words = {}
    for w in labels:gmatch("%S+") do words[#words + 1] = w end
    return words[state.pickChoice] or labels
  end
  if state.side == "mine" then
    local ok, label = pcall(state.listLabel, state, party[state.index], t, state.index)
    return string.format("yours, %s, %d of %d", speakable(ok and label or "?"), state.index or 0, #party)
  elseif state.side == "theirs" then
    local theirs = t.theirParty or {}
    local ok, label = pcall(state.listLabel, state, theirs[state.theirIndex])
    return string.format("theirs, %s, %d of %d", speakable(ok and label or "?"),
      state.theirIndex or 0, #theirs)
  elseif state.side == "cancel" then
    return speakable(gameText(state, "CancelTextString") or "CANCEL")
  end
  return nil
end

-- One line describing the current stage, as LinkState:draw lays it out.
local function stageText(state)
  local s = state.stage
  if s == "menu" then
    return "Link cable. " .. (state.index == 1 and "HOST A GAME" or "JOIN A GAME")
      .. ". UDP port " .. portText()
  elseif s == "hosting" then
    return "Hosting. Friend joins at " .. tostring(state.net and state.net.address or "?")
      .. ". Waiting for join"
  elseif s == "addrEntry" then
    local text = "Enter host address: " .. (addressText(state) ~= "" and addressText(state) or "empty")
    if state.status and state.status ~= "" then text = text .. ". " .. speakable(state.status) end
    return text
  elseif s == "joining" then
    return "Joining. Calling " .. tostring(state.net and state.net.target or "")
  elseif s == "modeSelect" then
    return "Connected. " .. (state.index == 1 and "TRADE" or "BATTLE")
  elseif s == "battleOptions" then
    local v = state.levelChoice
    return "Battle options. Levels: " .. ((v == nil or v == "ANY") and "ANY" or ("AUTO " .. tostring(v)))
  elseif s == "waitHello" then
    return "Connected. Checking the other game"
  elseif s == "waitMode" then
    return "Connected. Waiting for the host to choose"
  elseif s == "notice" then
    local title = state.verdict == "engine_skew" and "UPDATE YOUR GAME"
      or state.verdict == "ruleset_skew" and "CHECK YOUR RULES" or "CHECK YOUR MODS"
    local lines = {}
    for i, line in ipairs(state.noticeLines or {}) do lines[i] = speakable(line) end
    return joinNonEmpty({ title, table.concat(lines, " "),
      state.noticeExits and "A: back" or "A: trade anyway" })
  elseif s == "battleWait" or s == "battleRunning" then
    return "Link battle. Exchanging data"
  end
  return nil
end

-- Lines of the trade's text window (willText) or the cancelled message.
local function tradeMessage(state)
  local t = state.trade or {}
  if state.confirmed == false or t.stage == "declined" then
    return speakable(gameText(state, "TradeCanceled") or "Trade canceled")
  end
  local w = state.willText
  if w and w.lines then return speakable(table.concat(w.lines, " ")) end
  return nil
end

LinkScreens.cableClub = {
  matches = matcher("src.link.LinkState"),
  poll = function(state, memo, entering)
    local t = state.trade or {}
    if state.stage ~= "trade" then
      local text = stageText(state)
      if text == nil or (text == memo.text and not entering) then return nil end
      memo.text = text
      return text, true
    end
    -- trade screen: message window, YES/NO, waiting, then the cursor
    local message = (state.confirmed == false or t.stage == "declined") and "declined" or state.willText
    if message ~= memo.message then
      memo.message = message
      local text = tradeMessage(state)
      if text then return text, true end
    end
    local confirming = t.stage == "confirming" and state.willText and state.willText.done
      and state.confirmed == nil
    local choice = confirming and state.confirmChoice or nil
    if choice ~= memo.choice then
      memo.choice = choice
      if choice then
        local labels = speakable(gameText(state, "TwoOptionMenuStrings.TradeCancelMenu") or "TRADE CANCEL")
        local words = {}
        for w in labels:gmatch("%S+") do words[#words + 1] = w end
        return words[choice] or (choice == 1 and "TRADE" or "CANCEL"), memo.choiceSeen ~= nil
      end
    end
    memo.choiceSeen = choice
    local waiting = t.stage == "waitRecords" or t.stage == "waitParty" or t.stage == "waitPick"
      or (t.stage == "confirming" and state.confirmed ~= nil)
    if waiting ~= memo.waiting then
      memo.waiting = waiting
      if waiting then return speakable(gameText(state, "WaitingText") or "Waiting..."), false end
    end
    local focus = tradeFocus(state)
    if focus == memo.focus and not entering then return nil end
    memo.focus = focus
    if entering then focus = "Trade center. " .. tostring(focus) end
    return focus, true
  end,
}

-- ------------------------------------------------------------ Union Room

-- Both prep screens keep a page model (`model` for battle, `ctl` for trade)
-- whose page() returns { title, lines, info, items, cursor, notice } and
-- whose label/formatLines turn them into text.  Every body line is read
-- (not just the window that fits on screen).
local function unionPage(state)
  local owner = state.model or state.ctl
  if not owner or type(owner.page) ~= "function" then return nil end
  local ok, pg = pcall(owner.page, owner)
  if not ok or type(pg) ~= "table" then return nil end
  local function label(v)
    local okL, text = pcall(owner.label, owner, v)
    return okL and text or v
  end
  local function lines(list)
    if type(owner.formatLines) ~= "function" then return {} end
    local okF, out = pcall(owner.formatLines, owner, list)
    return okF and type(out) == "table" and out or {}
  end
  local body = {}
  for _, l in ipairs(lines(pg.lines)) do body[#body + 1] = speakable(l) end
  for _, l in ipairs(lines(pg.info)) do body[#body + 1] = speakable(l) end
  local items = pg.items or {}
  local item = items[pg.cursor or 1]
  local itemText = item and (speakable(label(item.label)) .. (item.disabled and ", unavailable" or "")) or nil
  return speakable(label(pg.title)), table.concat(body, " "), itemText, pg.cursor or 1, #items,
    pg.notice and speakable(label(pg.notice)) or nil
end

local function unionPresenter(path)
  return {
    matches = matcher(path),
    poll = function(state, memo, entering)
      local title, body, itemText, cursor, count, notice = unionPage(state)
      if title == nil then return nil end
      if notice ~= memo.notice then
        memo.notice = notice
        if notice then return notice, false end
      end
      local pageChanged = entering or title ~= memo.title or body ~= memo.body
      if not pageChanged and cursor == memo.cursor then return nil end
      memo.title, memo.body, memo.cursor = title, body, cursor
      local focus = itemText and string.format("%s, %d of %d", itemText, cursor, count) or nil
      if pageChanged then return joinNonEmpty({ title, body, focus }), true end
      return focus, true
    end,
  }
end

LinkScreens.unionBattlePrep = unionPresenter("src.ui.union.prep.Gen1BattlePrep")
LinkScreens.unionTradePrep = unionPresenter("src.ui.union.prep.Gen1TradePrep")

LinkScreens.ordered = {
  LinkScreens.cableClub,
  LinkScreens.unionBattlePrep,
  LinkScreens.unionTradePrep,
}

return LinkScreens
