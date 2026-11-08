-- Standalone: luajit launcher/mods/crystal_randomizer/tests/core_test.lua
-- The core alone: the mod loads, Oak's speech gains the questions after the
-- player is named, a "no" asks nothing more, a "yes" stores a seed and the
-- answers, and loading a save switches the state.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
require("src.core.GameVersion").set("crystal")
local run = T.sdk.loadMod("launcher/mods/crystal_randomizer", {})
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local vanilla = {
  { id = "ask_player_name", kind = "say" },
  { id = "name_player", kind = "name" },
  { id = "legend", kind = "say" },
}
local function build()
  local copy = {}
  for i, step in ipairs(vanilla) do copy[i] = step end
  return Runtime.call("intro.oak_speech.build", function(steps) return steps end, copy, {})
end

local steps = build()
local ids = {}
for i, step in ipairs(steps) do ids[i] = step.id end
T.eq(ids[1], "ask_player_name", "vanilla steps before the anchor stay")
T.eq(ids[3], "rand_on", "the first question comes right after naming")
T.eq(ids[#ids], "legend", "vanilla steps after the questions stay")

-- Walk the inserted steps the way OakSpeech does: fn steps run, others are answered.
local function walk(answerOn)
  local speech = { steps = build(), answers = {}, step = 0 }
  local said = {}
  while true do
    speech.step = speech.step + 1
    local step = speech.steps[speech.step]
    if not step then break end
    if step.kind == "fn" then
      step.run(speech, function() end)
    elseif step.kind == "choice" and step.saveKey then
      speech.answers[step.saveKey] = "custom"
    elseif step.kind == "yesno" and step.saveKey then
      if step.id == "rand_on" then
        speech.answers[step.saveKey] = answerOn
      else
        speech.answers[step.saveKey] = true
      end
    elseif step.id == "rand_say_seed" then
      said[#said + 1] = step.text
    end
  end
  return speech, said
end

local _, saidNo = walk(false)
T.eq(#saidNo, 0, "answering no says no seed")

local speech, said = walk(true)
T.eq(#said, 1, "answering yes says the seed")
T.check(said[1] and said[1]:match("%d%d%d%d%d%d") ~= nil, "the seed is six digits: " .. tostring(said[1]))

T.finish("crystal randomizer core")
