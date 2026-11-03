-- Every text box of an edition reaches speech: each string in the game's own text
-- table is shown through World:showText, A pressed through its pages, and what
-- Speech.say was given is compared with what the box held, word by word.  Lines that
-- drop words are logged as MISSING.  TEXT_STEP=n takes every nth string.
-- Harness only: nothing here plays a script.  Silent, so a test pass, not heard.
return function(game)
  local L = dofile("tests/access/drivers/gen2_nav_lib.lua").new(game)
  local U = L.U
  L.settle(2000, true)
  game.options.textSpeed = "FAST"
  game.driverSpeed = 8
  local version = tostring(game.save.version)
  local world = game.world
  local keys = {}
  for key, text in pairs(world.text or {}) do
    if type(text) == "string" and text:gsub("{[^}]*}", ""):find("%a") then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local step = tonumber(os.getenv("TEXT_STEP")) or 1
  local function wordsOf(text)
    local cleaned = text:gsub("{[^}]*}", " "):gsub("%-%s*%c%s*", ""):gsub("%A+", " "):lower()
    local list = {}
    for word in cleaned:gmatch("%a+") do
      if #word > 1 then list[#list + 1] = word end
    end
    return list
  end
  local shown, missing, stuck = 0, 0, 0
  -- what was lost is tried again with time around it, a lone box as in play; only what
  -- is lost again counts
  local retry = {}
  local function retried(key)
    local text = world.text[key]
    L.settle(60, true, 30)
    L.heard()
    local closed = false
    world:showText(text, function() closed = true end)
    U.wait(45)
    for _ = 1, 60 do
      if closed then break end
      L.tap("a", 25)
    end
    U.wait(30)
    return L.heard()
  end
  for index = 1, #keys, step do
    local key = keys[index]
    local text = world.text[key]
    L.heard()
    local closed = false
    local ok, why = pcall(world.showText, world, text, function() closed = true end)
    if not ok then
      U.log("ERROR", version, key, tostring(why))
    else
      shown = shown + 1
      -- a player reads before pressing; a box of one word can open and close between
      -- two of the layer's polls under the harness's speed otherwise
      U.wait(4)
      local frames = 0
      while not closed and frames < 1500 do
        L.tap("a", 3)
        frames = frames + 5
      end
      if not closed then
        stuck = stuck + 1
        U.log("STUCK", version, key, (text:sub(1, 60):gsub("%c", "/")))
        while game.stack:top() do game.stack:pop() end
      end
      U.wait(2)
      -- a word split across lines may be kept with its hyphen or joined: compare runs of
      -- letters with the gaps gone, so neither reading counts as lost
      local heard = L.heard():gsub("%A+", ""):lower()
      local lost = {}
      for _, word in ipairs(wordsOf(text)) do
        if not heard:find(word, 1, true) then lost[#lost + 1] = word end
      end
      if #lost > 0 then
        retry[#retry + 1] = { key = key, words = lost }
      end
    end
  end
  local firstPass = #retry
  for _, entry in ipairs(retry) do
    local text = world.text[entry.key]
    local raw = retried(entry.key)
    local heard = raw:gsub("%A+", ""):lower()
    local lost = {}
    for _, word in ipairs(wordsOf(text)) do
      if not heard:find(word, 1, true) then lost[#lost + 1] = word end
    end
    U.log("RETRY", version, entry.key, "first lost", table.concat(entry.words, " "):sub(1, 40), "now lost", table.concat(lost, " "):sub(1, 40), "heard", raw:sub(1, 80))
    if #lost > 0 then
      missing = missing + 1
      U.log("MISSING", version, entry.key, table.concat(lost, " "):sub(1, 80), "| box:", (text:sub(1, 90):gsub("%c", "/")))
    end
  end
  U.log("SWEEP", version, "texts", #keys, "shown", shown, "lost at harness speed", firstPass, "lost with time around it", missing, "stuck", stuck)
  U.log("DONE")
end
