-- src/access/Haptics.lua without a phone: off Android and iOS it does nothing; with a
-- stand-in backend it pulses on steps and on each generation's bump sound, follows the
-- HAPTICS option, and spaces pulses out.  The native routes (JNI, Objective-C) are covered
-- only on a device (docs/access/android.md and ios.md, "Haptics").
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq

local clock = 100
_G.love = {
  system = { getOS = function() return "Windows" end },
  timer = { getTime = function() return clock end },
}

local Haptics = require("src.access.Haptics")

-- ------------------------------------------------------------ off a phone
eq(Haptics.available(), false, "no haptics on a computer")
eq(Haptics.stepped(), false, "a step sends nothing")
Haptics.update()

-- ------------------------------------------------------------ a stand-in device
local played = {}
local function fresh()
  played = {}
  Haptics._setBackendForTests({ play = function(kind) played[#played + 1] = kind return true end })
  Haptics._resetWrappersForTests()
end
fresh()
eq(Haptics.available(), true, "with a backend haptics are available")
eq(Haptics.stepped(), true, "a step pulses")
eq(played[1], "step", "as a step")
eq(Haptics.stepped(), false, "a second step in the same instant is dropped")
clock = clock + 0.06
eq(Haptics.stepped(), true, "a step 60 ms later pulses again")
eq(Haptics.bumped(), true, "a bump has its own spacing")
eq(played[3], "bump", "and plays as a bump")
clock = clock + 0.06
eq(Haptics.bumped(), false, "a bump 60 ms after a bump is dropped")
clock = clock + 0.1
eq(Haptics.bumped(), true, "and one 160 ms after pulses")
eq(Haptics.pulse("nonsense"), false, "an unknown kind sends nothing")

-- ------------------------------------------------------------ the HAPTICS option
local on = false
Haptics.setEnabledCheck(function() return on end)
clock = clock + 1
eq(Haptics.stepped(), false, "with HAPTICS off nothing is sent")
on = true
eq(Haptics.stepped(), true, "with it on the step pulses")
Haptics.setEnabledCheck(function() error("options unreadable") end)
clock = clock + 1
eq(Haptics.stepped(), false, "an unreadable option sends nothing")
Haptics.setEnabledCheck(function() return true end)

-- ------------------------------------------------------------ bump sounds
fresh()
local sounds = {}
package.loaded["src.core.Sound"] = {
  play = function(data, name) sounds[#sounds + 1] = name return "played " .. name end,
}
local gen2World = {}
gen2World.bumpSound = function(self) sounds[#sounds + 1] = "Sfx_Bump" end
local world = setmetatable({}, { __index = gen2World })
package.loaded["src.core.game3.se_ids"] = { SE_WALL_HIT = 7 }
package.loaded["src.core.game3.audio"] = {
  playSe = function(id, opts) sounds[#sounds + 1] = id return true end,
}

Haptics.update() -- Gen 2's World not loaded yet: its wrapper waits
clock = clock + 1
eq(package.loaded["src.core.Sound"].play({}, "Press_AB"), "played Press_AB",
  "Gen 1: another sound plays through, its result kept")
eq(#played, 0, "and does not pulse")
package.loaded["src.core.Sound"].play({}, "Collision")
eq(played[1], "bump", "Gen 1: the collision sound pulses a bump")
eq(sounds[#sounds], "Collision", "and still plays")

clock = clock + 1
package.loaded["src.core.game3.audio"].playSe(5)
eq(#played, 1, "Gen 3: another sound effect does not pulse")
package.loaded["src.core.game3.audio"].playSe(7, {})
eq(played[2], "bump", "Gen 3: SE_WALL_HIT pulses a bump")
clock = clock + 1
package.loaded["src.core.game3.audio"].playSe("SE_WALL_HIT")
eq(played[3], "bump", "by name as well")

package.loaded["src.world.gen2.World"] = gen2World
Haptics.update() -- now loaded
clock = clock + 1
world:bumpSound()
eq(played[4], "bump", "Gen 2: World:bumpSound pulses a bump")
eq(sounds[#sounds], "Sfx_Bump", "and still plays")

Haptics.update()
Haptics.update()
clock = clock + 1
package.loaded["src.core.Sound"].play({}, "Collision")
eq(#played, 5, "later updates never wrap twice (one pulse per sound)")

-- ------------------------------------------------------------ no device vibration
Haptics._setBackendForTests(nil)
Haptics._resetWrappersForTests()
package.loaded["src.core.Sound"] = { play = function() end }
local before = package.loaded["src.core.Sound"].play
Haptics.update()
eq(package.loaded["src.core.Sound"].play, before, "without haptics no sound is wrapped")

for _, name in ipairs({ "src.core.Sound", "src.world.gen2.World", "src.core.game3.audio",
                        "src.core.game3.se_ids" }) do
  package.loaded[name] = nil
end
check(true, "done")
T.finish("haptics")
