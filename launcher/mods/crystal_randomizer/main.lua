-- Crystal Randomizer: the core (CONTRACT.md holds how the pieces fit).
--
-- At New Game, after the player is named, Oak asks whether to shuffle the
-- adventure, then each module's own questions, then says the seed.  Answers and
-- seed go into mod.save, so they live in that save; a save without a seed plays
-- as vanilla.  Modules decide everything from the seed through ctx.rng, so
-- nothing is stored per choice and nothing is patched in the ROM.

-- Installed in this order: starters before trainers, which reads its results.
local MODULES = { "pokemon", "stats", "evolutions", "starters", "items", "tms", "shops", "wild", "trainers",
  "qol", "keyitems" }
-- Oak asks in the order a player thinks about a run, which is not install order.
local QUESTION_ORDER = { "wild", "trainers", "starters", "evolutions", "items", "keyitems", "tms", "shops",
  "pokemon", "stats", "qol" }
-- The setups Oak offers.  Anything but "custom" fills every answer from the
-- questions' own `recommended` / `everything` values instead of asking each.
local SETUPS = { labels = { "RECOMMENDED", "EVERYTHING", "CHOOSE EACH" },
  values = { "recommended", "everything", "custom" } }
local KEY_PREFIX = "rand_"

local function loadFile(mod, relative)
  local source = mod:read(relative)
  if not source then return nil, relative .. " is missing" end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. relative)
  if not chunk then return nil, err end
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  return result
end

return function(mod)
  local Rng, rngError = loadFile(mod, "rng.lua")
  if not Rng then
    mod.log:error("the randomizer cannot start: %s", tostring(rngError))
    return
  end

  -- The loaded save's state: nil seed means vanilla.
  local state = { seed = nil, options = {} }
  local listeners = {}

  local ctx = { shared = {} }
  function ctx.active() return state.seed ~= nil end
  function ctx.seed() return state.seed end
  function ctx.option(key) if state.seed then return state.options[key] end end
  function ctx.rng(stream, ...) return Rng.stream(state.seed or "vanilla", stream, ...) end
  function ctx.onSave(fn) listeners[#listeners + 1] = fn end
  function ctx.log(fmt, ...) mod.log:info(fmt, ...) end

  local function setState(seed, options)
    state.seed, state.options = seed, options or {}
    for key in pairs(ctx.shared) do ctx.shared[key] = nil end
    for _, fn in ipairs(listeners) do
      local ok, err = pcall(fn, state.seed ~= nil)
      if not ok then mod.log:error("a randomizer module failed to switch saves: %s", tostring(err)) end
    end
    if state.seed then ctx.log("randomized save, seed %s", state.seed) end
  end

  -- Modules: each loads on its own, so one broken module does not stop the rest.
  local modules = {}
  for _, name in ipairs(MODULES) do
    local module, err = loadFile(mod, "modules/" .. name .. ".lua")
    if type(module) == "table" and type(module.install) == "function" then
      local ok, installError = pcall(module.install, mod, ctx)
      if ok then
        modules[#modules + 1] = module
      else
        mod.log:error("module %s did not install: %s", name, tostring(installError))
      end
    elseif err and not tostring(err):find("is missing", 1, true) then
      mod.log:error("module %s did not load: %s", name, tostring(err))
    end
  end

  -- A seed people can read out and share: six digits.
  local function newSeed()
    local mixed = Rng.stream(tostring(os.time()), tostring(os.clock()), tostring({}))
    return ("%06d"):format(mixed:int(0, 999999))
  end

  -- Oak's questions.  A gate step decides at the moment it is reached whether
  -- its question is asked, because whether it applies depends on earlier answers.
  local function gate(id, wanted, makeStep)
    return {
      id = id, kind = "fn",
      run = function(speech, done)
        local answers = speech.answers or {}
        if answers[KEY_PREFIX .. "on"] == true and wanted(answers) then
          local step = makeStep(answers)
          if step then table.insert(speech.steps, speech.step + 1, step) end
        end
        done()
      end,
    }
  end

  mod.hooks:wrap("intro.oak_speech.build", function(next, steps, speech)
    steps = next(steps, speech)
    local anchor = "name_player"
    local found = false
    for _, step in ipairs(steps) do if step.id == anchor then found = true end end
    if not found then
      mod.log:error("Oak's speech has no %s step; the randomizer questions are not asked", anchor)
      return steps
    end
    local added = {
      { id = "rand_on", kind = "yesno", pic = "oak", saveKey = KEY_PREFIX .. "on",
        text = "Before you go...\nDo you want your\vjourney shuffled?" },
      gate("rand_q_setup", function() return true end, function()
        return { id = "rand_ask_setup", kind = "choice", pic = "oak", saveKey = KEY_PREFIX .. "setup",
          text = "How shuffled?\nPick a setup.", choices = SETUPS.labels,
          values = SETUPS.values, tx = 0, ty = 0, tw = 14 }
      end),
    }
    local byId = {}
    for _, module in ipairs(modules) do byId[module.id] = module end
    local ordered = {}
    for _, id in ipairs(QUESTION_ORDER) do
      if byId[id] then ordered[#ordered + 1] = byId[id]; byId[id] = nil end
    end
    for _, module in ipairs(modules) do
      if byId[module.id] then ordered[#ordered + 1] = module end
    end
    for _, module in ipairs(ordered) do
      for _, question in ipairs(module.questions or {}) do
        added[#added + 1] = gate("rand_q_" .. question.key, function(answers)
          if answers[KEY_PREFIX .. "setup"] ~= "custom" then return false end
          return question.onlyIf == nil or answers[KEY_PREFIX .. question.onlyIf] == true
        end, function()
          local step = { id = "rand_ask_" .. question.key, kind = question.kind or "yesno", pic = "oak",
            text = question.text, saveKey = KEY_PREFIX .. question.key }
          if question.kind == "choice" then
            local labels, values, wide = {}, {}, 8
            for i, option in ipairs(question.options or {}) do
              labels[i], values[i] = option.label, option.value
              wide = math.max(wide, #option.label + 3)
            end
            step.choices, step.values, step.tx, step.ty, step.tw = labels, values, 0, 0, math.min(wide, 20)
          end
          return step
        end)
      end
    end
    -- The seed is made and kept the moment the questions end, and Oak says it.
    added[#added + 1] = gate("rand_seed", function() return true end, function(answers)
      local options = {}
      local setup = answers[KEY_PREFIX .. "setup"] or "recommended"
      if setup == "custom" then
        for key, value in pairs(answers) do
          if key:sub(1, #KEY_PREFIX) == KEY_PREFIX and key ~= KEY_PREFIX .. "on"
              and key ~= KEY_PREFIX .. "setup" then
            options[key:sub(#KEY_PREFIX + 1)] = value
          end
        end
      else
        for _, module in ipairs(modules) do
          for _, question in ipairs(module.questions or {}) do
            local value = question[setup]
            if value == nil then value = false end
            options[question.key] = value
          end
        end
      end
      options.setup = setup
      local seed = newSeed()
      mod.save:set("seed", seed)
      mod.save:set("options", options)
      mod.save:set("version", 1)
      setState(seed, options)
      return { id = "rand_say_seed", kind = "say", pic = "oak",
        text = "Your seed is\n" .. seed .. ".\fShuffled. Good luck!" }
    end)
    for _, step in ipairs(steps) do
      if step.id == anchor then
        local at
        for i, s in ipairs(steps) do if s.id == anchor then at = i end end
        for offset, extra in ipairs(added) do table.insert(steps, at + offset, extra) end
        break
      end
    end
    return steps
  end)

  -- New Game starts vanilla until Oak's questions say otherwise.
  mod.events:on("save.created", function() setState(nil) end)
  -- Continue: the save's own bucket, read before the world stands.
  mod.events:on("save.loading", function(ev)
    local raw = ev and ev.raw
    local bucket = raw and raw.modData and raw.modData[mod.id or "crystal_randomizer"]
    if type(bucket) == "table" and type(bucket.seed) == "string" then
      setState(bucket.seed, type(bucket.options) == "table" and bucket.options or {})
    else
      setState(nil)
    end
  end)

  mod.log:info("Crystal Randomizer ready, %d modules", #modules)
end
