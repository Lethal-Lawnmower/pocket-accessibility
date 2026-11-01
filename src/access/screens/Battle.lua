-- Battle speech for Gen 1 (src/battle/BattleState.lua).
--
-- Battle text never goes through TextBox: BattleState keeps its own message
-- queue and draws its own menus (drawTextArea).  This presenter follows the
-- same fields that drawing uses:
--   phase "messages": self.current is the message being typed; each new
--     message table is spoken once, whole, queued behind the previous one
--     so quick auto-advancing lines are not cut off;
--   phase "menu": FIGHT / PKMN / ITEM / RUN (Safari: BALL / BAIT / THROW
--     ROCK / RUN) by menuIndex, opened with both sides' HP so each turn
--     starts with the current state;
--   phase "moveSelect": the move under moveIndex with type and PP;
--   phase "mimicSelect": the move under mimicIndex.
-- Party and bag inside battle are PartyMenu and ListMenu screens pushed on
-- top, so the general presenters read them.

local Battle = {}

local function speakable(text)
  text = tostring(text or "")
  text = text:gsub("{[A-Z_]+}", ""):gsub("<PK>", "PK"):gsub("<MN>", "MN")
  -- a line ending in a hyphen continues the same word on the next line
  text = text:gsub("%-%s*[\n\v]%s*", "-")
  return (text:gsub("%s*[\n\v\f]%s*", " "))
end
Battle.speakable = speakable

local function monName(state, mon)
  local def = state.data and state.data.pokemon and state.data.pokemon[mon.species] or {}
  return speakable(mon.nickname or def.name or mon.species)
end

-- Your side as the HUD shows it (exact HP), the enemy as Gen 1 shows it (a
-- bar only, so a percentage).
local function sides(state)
  local parts = {}
  local player = state.player and state.player.mon
  if player and player.stats then
    parts[#parts + 1] = string.format("%s, HP %d of %d", monName(state, player),
      player.hp or 0, player.stats.hp or 0)
  end
  local enemy = state.enemy and state.enemy.mon
  if enemy and enemy.stats and (enemy.stats.hp or 0) > 0 then
    local percent = math.ceil(100 * math.max(0, enemy.hp or 0) / enemy.stats.hp)
    parts[#parts + 1] = string.format("enemy %s, level %d, HP %d percent",
      monName(state, enemy), enemy.level or 0, percent)
  end
  return table.concat(parts, ". ")
end
Battle.sides = sides

local function menuLabel(state, index)
  if state.safari then
    local labels = { "BALL, " .. tostring(state.safari.balls or 0) .. " left", "BAIT", "THROW ROCK", "RUN" }
    return labels[index]
  end
  return ({ "FIGHT", "POKéMON", "ITEM", "RUN" })[index]
end

local function moveName(state, id)
  local def = state.data and state.data.moves and state.data.moves[id]
  return speakable(def and def.name or id), def
end

-- The move-select line, as drawTextArea shows it: name, then "disabled" or
-- type and PP.
local function moveLine(state)
  local moves = state.player and state.player.curMoves or {}
  local mv = moves[state.moveIndex]
  if not mv then return "empty" end
  local name, def = moveName(state, mv.id)
  if state.player.disabledSlot == state.moveIndex then return name .. ", disabled" end
  if not def then return name end
  local okT, TypeChart = pcall(require, "src.battle.TypeChart")
  local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
  local typeName = def.type and okT and TypeChart.displayName(def.type, state.data) or def.type
  local maxPP = okP and Pokemon.maxPP(def.pp, mv.ppUps) or def.pp
  return string.format("%s, %s, PP %d of %d", name, tostring(typeName or ""), mv.pp or 0, maxPP or 0)
end

Battle.presenter = {
  matches = function(state)
    local BattleState = package.loaded["src.battle.BattleState"]
    return BattleState ~= nil and getmetatable(state) == BattleState
  end,
  poll = function(state, memo)
    local phase = state.phase
    local newPhase = phase ~= memo.phase
    memo.phase = phase

    if phase == "messages" then
      local item = state.current
      if item == nil or item == memo.message then return nil end
      memo.message = item
      local text = speakable(item.text)
      if text:match("^%s*$") then return nil end
      return text, false
    end

    if phase == "menu" and not state.demo then
      if not newPhase and memo.menu == state.menuIndex then return nil end
      memo.menu = state.menuIndex
      local label = menuLabel(state, state.menuIndex)
      if newPhase then return sides(state) .. ". " .. tostring(label), true end
      return label, true
    end

    if phase == "moveSelect" then
      if not newPhase and memo.move == state.moveIndex then return nil end
      memo.move = state.moveIndex
      local text = moveLine(state)
      if newPhase then
        text = text .. ", " .. string.format("%d of %d", state.moveIndex,
          #(state.player and state.player.curMoves or {}))
      end
      return text, true
    end

    if phase == "mimicSelect" then
      if not newPhase and memo.mimic == state.mimicIndex then return nil end
      memo.mimic = state.mimicIndex
      local m = state.mimicMoves and state.mimicMoves[state.mimicIndex]
      if m == nil then return nil end
      local text = moveName(state, type(m) == "table" and m.id or m)
      if newPhase then text = "Mimic which move? " .. text end
      return text, true
    end
    return nil
  end,
}

return Battle
