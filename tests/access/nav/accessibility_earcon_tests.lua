local S = require("tests.harness").suite("accessibility earcons")
local Earcons = require("src.access.nav.Earcons")

local calls = {}
local earcons = Earcons.new({ sink = function(record)
  calls[#calls + 1] = record
  return true
end })

S.check(earcons:play("grass", { pan = -2, volume = 3 }),
  "known cue reaches the injected sink")
S.same(calls[1], { id = "grass", pan = -1, volume = 1 },
  "pan and volume are safely clamped")
S.check(earcons:play("water", { pan = 0.25, volume = 0.4 }),
  "spatial cue accepts fractional settings")
S.same(calls[2], { id = "water", pan = 0.25, volume = 0.4 },
  "semantic cue record is deterministic")
S.eq(#earcons.history, 2, "cue history supports ordered trace tests")

S.eq(earcons:setVolumeLevel(-3), 0,
  "accessibility cue volume clamps to mute")
S.check(earcons:play("menu", { volume = 0.8 }),
  "muted cues still produce a deterministic trace")
S.eq(calls[3].volume, 0, "master cue volume scales the emitted record")
S.eq(earcons:setVolumeLevel(99), 7,
  "accessibility cue volume clamps to the 0-7 maximum")

local ok, reason = earcons:play("missing")
S.check(not ok and reason:find("unknown earcon", 1, true),
  "unknown cue is a controlled failure")
earcons:setEnabled(false)
ok, reason = earcons:play("default")
S.check(not ok and reason == "earcons disabled",
  "disabled cues do not reach the sink")
S.eq(#calls, 3, "disabled/unknown cues emit no audio")

local bad = Earcons.new({ sink = function() error("sink boom") end })
ok, reason = bad:play("wall")
S.check(not ok and reason:find("sink boom", 1, true),
  "sink exceptions cannot crash gameplay")

S.check(Earcons.PROFILES.grass and Earcons.PROFILES.wall
  and Earcons.PROFILES.pass and Earcons.PROFILES.ledge
  and Earcons.PROFILES.move_up and Earcons.PROFILES.move_down
  and Earcons.PROFILES.move_left and Earcons.PROFILES.move_right,
  "required navigation cue profiles exist")

S.eq(Earcons.SOUND_FILES.grass, "gb/s_grass.wav",
  "external parity pack maps grass to the Red/Blue Pokemon Access cue")
S.eq(Earcons.SOUND_FILES.ledge, "common/s_mad.wav",
  "external parity pack preserves the reference pre-ledge warning")

local loaded, played = {}, {}
local packed = Earcons.new({
  soundPackPath = "C:\\external\\sounds",
  assetLoader = function(root, relative, pan)
    loaded[#loaded + 1] = { root = root, relative = relative, pan = pan }
    return {
      stop = function() played[#played + 1] = "stop" end,
      setVolume = function(_, volume) played[#played + 1] = volume end,
      play = function() played[#played + 1] = "play" end,
    }
  end,
})
S.check(packed:play("grass", { pan = 0.23, volume = 0.5 }),
  "configured external Pokemon Access cue plays before procedural fallback")
S.eq(loaded[1].root, "C:\\external\\sounds",
  "external cue loader receives the configured sound root")
S.eq(loaded[1].relative, "gb/s_grass.wav",
  "external cue loader receives the stable file mapping")
S.check(math.abs(loaded[1].pan - 0.2) < 0.000001,
  "external cue loader receives quantized spatial pan")
S.same(played, { "stop", 0.5, "play" },
  "external cue honors the same stop volume and play contract")

S.finish()
