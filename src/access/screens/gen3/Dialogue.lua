-- Gen 3 dialogue and yes/no (FireRed, LeafGreen; decision 29).
--
-- Field and script text is src/ui/game3/message.lua: Message.show splits a
-- text into `_pages` (a new table per message; each page is at most two
-- lines joined by "\n") and every page waits for A.  A page is spoken whole
-- as soon as the game starts showing it, the Gen 1 and 2 pacing the owner
-- chose; DIALOGUE SPEECH set to ALL AT ONCE (decision 26) speaks every page
-- when the message opens.  A word the cartridge splits across a page break
-- ("crea-" / "tures") is finished on the earlier page.  Battle text uses
-- the same module but is read by the battle presenter, and braille pages by
-- the braille presenter.
--
-- Yes/no and multiple choice are src/ui/game3/choice.lua (`options`,
-- `cursor`, `kind`), shown over a message that stays open: the question is
-- spoken first (gen3/Top.lua reports it as covered), then the selection,
-- queued behind it; later moves interrupt.

local Common = require("src.access.screens.gen3.Common")
local Gen2Common = require("src.access.screens.gen2.Common")
local Settings = require("src.access.Settings")

local Dialogue = {}

local function presenters()
  return package.loaded["src.access.screens.Presenters"]
end

local function say(lines)
  return Gen2Common.speakable(presenters().joinLines(lines))
end

Dialogue.message = {
  matches = Common.matcher("message"),
  poll = function(state, memo)
    local Message = state.mod
    local pages = state.key
    if not Message or Message._pages ~= pages or Message._frame == "braille" then return nil end
    if Settings.dialogueWhole(state.game) then
      if memo.whole then return nil end
      memo.whole = true
      local all = {}
      for _, page in ipairs(pages) do
        for _, line in ipairs(Common.lines(page)) do all[#all + 1] = line end
      end
      local text = say(all)
      if text == "" then return nil end
      return text, true
    end
    local page = Message._page or 1
    if memo.page == page then return nil end
    memo.page = page
    local lines = Common.lines(pages[page])
    if memo.spokeFirstOf == page then table.remove(lines, 1) end
    -- finish a word split across the page break on this page
    local nextLines = pages[page + 1] and Common.lines(pages[page + 1]) or nil
    if #lines > 0 and nextLines and nextLines[1]
        and presenters().splitWord(lines[#lines], nextLines[1]) then
      lines[#lines + 1] = nextLines[1]
      memo.spokeFirstOf = page + 1
    end
    local text = say(lines)
    if text == "" then return nil end
    return text, true
  end,
}

Dialogue.choice = {
  matches = Common.matcher("choice"),
  poll = function(state, memo, entering)
    local Choice = state.mod
    if not Choice or Choice.done ~= state.key then return nil end
    local options = Choice.options or {}
    local cursor = Choice.cursor or 1
    if not entering and memo.cursor == cursor then return nil end
    local first = memo.cursor == nil
    memo.cursor = cursor
    local option = options[cursor]
    if type(option) == "table" then option = option.label or option.text end
    local text = Common.speakable(option)
    if text == "" then return nil end
    if Choice.kind == "multi" and (first or entering) then
      text = text .. ", " .. Common.position(cursor, #options)
    end
    -- the first selection queues behind the question; moves interrupt
    return text, not first
  end,
}

Dialogue.ordered = { Dialogue.message, Dialogue.choice }

return Dialogue
