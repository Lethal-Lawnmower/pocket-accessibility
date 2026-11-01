-- Gen 2 shared reading helpers (decision 27): text commands made speakable,
-- the Typer message pattern, Chrome list rows and metatable matching.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local T = require("tests.harness")
local check, eq = T.check, T.eq

require("src.access.screens.Presenters")
local Common = require("src.access.screens.gen2.Common")

eq(Common.speakable("You don't have a\n#MON!"), "You don't have a POKéMON!", "# is the POKé command")
eq(Common.speakable("<PO><KE>GEAR"), "POKéGEAR", "start menu ligature")
eq(Common.speakable("<LV>12"), "level 12", "level mark")
eq(Common.speakable("Hello<NEXT>there"), "Hello there", "layout command is a space")
eq(Common.speakable("<UNKNOWN_TOKEN>CANCEL"), "CANCEL", "leftover token dropped, not spelled")
eq(Common.lines({ "This is crea-", "tures." }), "This is creatures.", "lines joined, split word rejoined")

local memo = {}
local screen = { typer = { page = { "Welcome to our", "POKéMON CENTER!" } } }
eq(Common.typerText(screen, memo), "Welcome to our POKéMON CENTER!", "new typer page spoken whole")
eq(Common.typerText(screen, memo), nil, "same page not repeated")
screen.typer.page = { "Shall I heal your", "POKéMON?" }
eq(Common.typerText(screen, memo), "Shall I heal your POKéMON?", "next page spoken")
eq(Common.typerText({}, {}), nil, "no typer, nothing")
screen.typer.page = { "POKéMON?", "We'll need your" }
Common.typerText(screen, memo)
screen.typer.page = { "We'll need your", "POKéMON for a while." }
eq(Common.typerText(screen, memo), "POKéMON for a while.", "scrolled page drops the repeated line")

eq(Common.listRow({ index = 2, items = { { label = "CONTINUE" }, { label = "NEW GAME" } } }), "NEW GAME", "list row")
eq(Common.listRow({ index = 3, items = {} }), nil, "missing row is silent")

local Fake = {}
Fake.__index = Fake
package.loaded["src.ui.gen2.FakeScreen"] = Fake
local isFake = Common.matcher("FakeScreen")
check(isFake(setmetatable({}, Fake)), "matcher finds an instance")
check(not isFake({}), "matcher rejects other tables")
check(not Common.matcher("NotLoaded")(setmetatable({}, Fake)), "an unloaded class never matches")
package.loaded["src.ui.gen2.FakeScreen"] = nil

eq(Common.sentences({ "Darn…", "Coins 57" }), "Darn… Coins 57", "a part ending in an ellipsis takes no extra stop")
eq(Common.sentences({ "Hello", "there" }), "Hello. there", "plain parts are joined as sentences")

T.finish("gen2 common")
