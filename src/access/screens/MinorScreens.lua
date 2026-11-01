-- Presenters for the remaining Gen 1 screens: title and intro movies,
-- League PC, prize counter, slot machine, Hall of Fame, diploma, credits.
-- Same contract as Presenters.lua; each reads what its screen draws.
-- Evolution and trade speak through the text boxes they push; Yellow's
-- surfing minigame is a timing game and still needs its own design.

local MinorScreens = {}

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

local function monLine(game, mon)
  if type(mon) ~= "table" then return nil end
  local def = game.data and game.data.pokemon and game.data.pokemon[mon.species] or {}
  return string.format("%s, level %s", speakable(mon.nickname or def.name or mon.species),
    tostring(mon.level or "?"))
end

local function once(text)
  return function(state, memo)
    if memo.said then return nil end
    memo.said = true
    return text(state), true
  end
end

-- Title screen and intro movies: say where the player is and what to press.
MinorScreens.title = {
  matches = matcher("src.ui.TitleState"),
  poll = once(function() return "Title screen. Press start." end),
}
MinorScreens.introMovie = {
  matches = matcher("src.ui.IntroMovie"),
  poll = once(function() return "Intro. Press start to skip." end),
}
MinorScreens.yellowIntro = {
  matches = matcher("src.ui.YellowIntro"),
  poll = once(function() return "Intro. Press start to skip." end),
}

-- League PC (src/ui/LeaguePC.lua): Hall of Fame team number and member.
MinorScreens.leaguePC = {
  matches = matcher("src.ui.LeaguePC"),
  poll = function(state, memo)
    if memo.team == state.teamIndex and memo.mon == state.monIndex then return nil end
    memo.team, memo.mon = state.teamIndex, state.monIndex
    local team = state.teams and state.teams[state.teamIndex]
    local line = team and monLine(state.game, team[state.monIndex])
    if not line then return nil end
    return string.format("Hall of Fame number %d, %s", state.teamIndex or 0, line), true
  end,
}

-- Prize counter (src/ui/PrizeCounter.lua): coins on entry, then prize and
-- cost; the row after the last prize is NO THANKS.
MinorScreens.prizeCounter = {
  matches = matcher("src.ui.PrizeCounter"),
  poll = function(state, memo, entering)
    if not entering and memo.index == state.index then return nil end
    memo.index = state.index
    local prize = state.prizes and state.prizes[state.index]
    local text = prize and string.format("%s, %s coins", speakable(prize.name), tostring(prize.cost))
      or "NO THANKS"
    if entering then
      local save = state.game and state.game.save or {}
      text = string.format("Coins %d. %s", save.coins or 0, text)
    end
    return text, true
  end,
}

-- Slot machine (src/ui/SlotMachine.lua): its messages, the bet menu
-- (betIndex 0..2 is 3, 2, 1 coins as drawn), and "One more go?" YES/NO.
local BETS = { [0] = 3, [1] = 2, [2] = 1 }
MinorScreens.slotMachine = {
  matches = matcher("src.ui.SlotMachine"),
  poll = function(state, memo)
    local stage = state.stage
    local newStage = stage ~= memo.stage
    memo.stage = stage
    if state.message and state.message ~= memo.message then
      memo.message = state.message
      return speakable(state.message), false
    end
    if stage == "bet" and (newStage or memo.bet ~= state.betIndex) then
      memo.bet = state.betIndex
      local n = BETS[state.betIndex] or 0
      return string.format("Bet %d %s", n, n == 1 and "coin" or "coins"), true
    end
    if stage == "onemore" and (newStage or memo.yesno ~= state.yesno) then
      memo.yesno = state.yesno
      return state.yesno == 1 and "YES" or "NO", not newStage
    end
    if stage == "spin" and newStage then return "Spinning. Press A to stop each reel.", true end
    return nil
  end,
}

-- Hall of Fame (src/ui/HallOfFame.lua): each party member as it is shown.
MinorScreens.hallOfFame = {
  matches = matcher("src.ui.HallOfFame"),
  poll = function(state, memo)
    if memo.index == state.index then return nil end
    memo.index = state.index
    local party = state.game and state.game.save and state.game.save.party or {}
    local line = monLine(state.game, party[state.index or 0])
    if not line then return nil end
    return "Hall of Fame. " .. line, true
  end,
}

-- Diploma (src/ui/Diploma.lua): its text lines and the player's name.
MinorScreens.diploma = {
  matches = matcher("src.ui.Diploma"),
  poll = once(function(state)
    local game = state.game
    local t = game.data and game.data.text or {}
    local save = game.save or {}
    local name = save.player and save.player.name or ""
    return table.concat({ speakable(t.DiplomaText or "Diploma"),
      speakable(t.DiplomaPlayer or "Player") .. " " .. speakable(name),
      speakable(t.DiplomaCongrats or ""), speakable(t.DiplomaGameFreak or "GAME FREAK") }, ". ")
  end),
}

-- Credits (src/ui/Credits.lua): each credits screen's lines as it appears.
MinorScreens.credits = {
  matches = matcher("src.ui.Credits"),
  poll = function(state, memo)
    local screen = state.screen
    if screen == nil or screen == memo.screen then return nil end
    memo.screen = screen
    local lines = {}
    for _, line in ipairs(screen.lines or {}) do
      local okS, Strings = pcall(require, "src.core.Strings")
      lines[#lines + 1] = speakable(okS and Strings(line.text) or line.text)
    end
    if #lines == 0 then return nil end
    return table.concat(lines, ", "), true
  end,
}

MinorScreens.ordered = {
  MinorScreens.title,
  MinorScreens.introMovie,
  MinorScreens.yellowIntro,
  MinorScreens.leaguePC,
  MinorScreens.prizeCounter,
  MinorScreens.slotMachine,
  MinorScreens.hallOfFame,
  MinorScreens.diploma,
  MinorScreens.credits,
}

return MinorScreens
