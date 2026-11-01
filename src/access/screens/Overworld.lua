-- Overworld speech.  For now: Yellow's Pikachu reactions, which the game
-- shows only as a picture and a cry when you talk to Pikachu.  Navigation
-- (object list, pathfinding, cues) will extend this presenter later.
--
-- Gen 1's overworld is the OverworldController module itself
-- (src/core/Game.lua: `self.overworld = OverworldState`), so it is matched
-- by identity.  A reaction appears as state.emote with a pikaPic image
-- (PikachuFollower playEmotion).  The image is traced back to its emotion
-- through the game's own data: field.pikachu.emotions[e] runs a "pikapic"
-- op whose script number indexes field.pikachu.pics, which holds the image.

local Overworld = {}

-- Words for each entry of pokeyellow's PikachuEmotionTable
-- (engine/pikachu/pikachu_emotions.asm), which is the numbering upstream's
-- PikachuFollower uses (for example 11 sleep, 22 scared, 26 wake up).
local EMOTION_WORDS = {
  [1] = "blinks", [2] = "is excited", [3] = "twitches its ears", [4] = "is happy",
  [5] = "is sad", [6] = "looks away", [7] = "jumps", [8] = "smiles",
  [9] = "turns its back", [10] = "is full of joy", [11] = "is asleep",
  [12] = "is bored", [13] = "looks to the side", [14] = "is angry and sparking",
  [15] = "pumps its fist", [16] = "shows a heart", [17] = "is mad", [18] = "winks",
  [19] = "shows two hearts", [20] = "is in love", [21] = "is in a bucket",
  [22] = "is scared", [23] = "is confused", [24] = "shakes its head",
  [25] = "lets out lightning", [26] = "wakes up", [27] = "is surprised",
  [28] = "is crying", [29] = "is full of joy", [30] = "is in love",
  [31] = "is confused", [32] = "is confused",
}
Overworld.EMOTION_WORDS = EMOTION_WORDS

-- image path -> emotion number, built once per data table
local imageMaps = setmetatable({}, { __mode = "k" })

local function emotionForImage(data, image)
  local pikachu = data and data.field and data.field.pikachu
  if not (pikachu and pikachu.emotions and pikachu.pics) then return nil end
  local map = imageMaps[pikachu]
  if not map then
    map = {}
    for e = 1, 32 do
      for _, cmd in ipairs(pikachu.emotions[e] or {}) do
        if cmd.op == "pikapic" then
          local anim = pikachu.pics[cmd.script]
          if anim and anim.image and map[anim.image] == nil then map[anim.image] = e end
        end
      end
    end
    imageMaps[pikachu] = map
  end
  return map[image]
end
Overworld.emotionForImage = emotionForImage

Overworld.presenter = {
  matches = function(state)
    local OverworldState = package.loaded["src.world.OverworldController"]
    return OverworldState ~= nil and state == OverworldState
  end,
  poll = function(state, memo)
    local emote = state.emote
    local pic = emote and emote.pikaPic or nil
    if pic == memo.pic then return nil end
    memo.pic = pic
    if not pic then return nil end
    local game = state.game or (package.loaded["src.core.Game"])
    local data = game and game.data
    local e = emotionForImage(data, pic)
    local words = e and EMOTION_WORDS[e]
    return "Pikachu " .. (words or "reacts"), true
  end,
}

return Overworld
