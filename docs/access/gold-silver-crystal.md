# Gold, Silver and Crystal

Differences from the Gen 1 layer for the three Gen 2 games (decision 27).
Gen 1 behaviour is in `menus-and-text.md`, `battle.md` and `navigation.md`;
this file holds only what is different or Gen 2 only.

## How Gen 2 sits on upstream

Upstream v0.3.98 runs Gold, Silver and Crystal through `src/core/Game2.lua`
(not `Game.lua`), with screens in `src/ui/gen2/`, the overworld in
`src/world/gen2/` and the script VM in `src/script/gen2/`. Gold and Silver
share the `gs` engine; Crystal is `crystal`.

- **Same stack.** `Game2` uses the `src.core.StateStack` module table as
  its stack, so `ScreenReader` sees Gen 2 screens with no new hook. Free
  roaming leaves the stack empty: the top is nil there.
- **Same dialogue box.** Script text goes VM, then `World:showText`, then a
  pushed `src.render.TextBox`, so the Gen 1 dialogue presenter speaks it.
  Yes/No goes through the same `ChoiceBox`.
- **Own screen classes.** Gen 2 module names repeat Gen 1's (`PartyMenu`,
  `StartMenu` ...) at other paths, so no Gen 1 presenter matches a Gen 2
  screen. Presenters live in `src/access/screens/gen2/` (`Menus`, `Items`,
  `Info`, `Special`, `Battle`), collected by `gen2/init.lua`.
  `gen2/Common.lua` holds what they share: Gen 2 text commands (`#` is
  POKé, `<PO><KE>`, `<LV>`), the Typer message pattern many screens use for
  their own message box (`typer.page`), Chrome list rows, metatable matching.
- **Held screens.** Some screens draw another screen that is not on the
  stack (a mart's selling pack, MapRadio's radio, MoveTutor's party). The
  holder's presenter speaks the held screen.
- **Options.** Gen 2 has its own OPTION screen; the ACCESSIBILITY page is
  added there too and stored in Gen 2's options block (`menus-and-text.md`,
  decision 26).

Battle speech is in `battle.md` (section "Gen 2").

## Screens

| Screen (`src/ui/gen2/` class) | On entry or return | On change |
|---|---|---|
| Copyright, GAME FREAK and intro cards (`CopyrightSplash`, `GameFreakPresents`, `CrystalSplash`, `GoldSilverIntro`, `CrystalIntro`) | One line per card, queued ("GAME FREAK presents.", "Intro. Press start to skip."); the cards are images, so the copyright years are not spoken | (once) |
| Title (`TitleState`) | "POKéMON <edition> Version. Copyright GAME FREAK inc. Press start." once the entrance lands; the edition comes from the imported game | (once) |
| Main menu (`MainMenu`) | "Main menu", row, position, weekday and time | Row; CONTINUE panel: name, badges, Pokédex, time, "A to continue, B to go back" |
| Clock and day wheel (`InitClock`) | The question page, the value, YES/NO | Value; YES/NO; a scrolled page says only its new line |
| Gender (`GenderSelect`, Crystal), name choice (`NamePick`) | Question, then "Boy, 1 of 2" (queued); "Name. NEW NAME, 1 of 5" | Row |
| Naming keyboard (`NamingScreen`) | Prompt (and the Pokémon for a nickname), name so far, cell | As Gen 1; bottom targets "lower case" or "UPPER CASE", "delete", "end, confirm name" |
| Start menu (`StartMenu`) | "Start menu", contest status, row, position, description (with MENU ACCOUNT on) | Row and description; QUIT prompt and YES/NO |
| Options (`OptionsMenu`) and group pages | "Options" or the group row's name, label, value, position (BACK counts) | Value only on the same row |
| Save (`SaveMenu`) | "Save", name, badges, Pokédex, time, the question, YES/NO (queued) | Overwrite question; saving and saved lines, queued |
| Script menus (`ScriptMenu`) | Item (with price), position, columns for a grid, money or coins | Item |
| Elevator (`ElevatorMenu`) | "Elevator. Now on <floor>", floor, position | Floor; "current floor" |
| Bank of Mom (`BankOfMom`) | Saved, held, the amount, the digit | Amount; digit and value |
| Evolution, egg hatching (`EvolutionAnim`, `EggHatchAnim`) | Each message, queued; "Press B to stop the evolution." when it can be stopped; "Egg hatching." | Next message |
| Pack (`PackMenu`, also held by marts and the item PC) | "<pocket> pocket", item (TM: number and move), quantity, position, description | Item and description; pocket change repeats pocket and position; sub-menu; quantity ("Throw away how many? Quantity 1, up to 3"); YES/NO; each message page |
| Mart (`MartMenu`) | Clerk line, BUY/SELL/QUIT, position; the buy list adds money, price and description | Item and price; amount, total and maximum; confirm pages, then YES/NO; new money after a sale or purchase; SELL reads the held pack |
| Pokémon Center PC (`CenterPcMenu`) | Turn-on message, "Access whose PC?", row, position | Row; messages; OAK's PC YES/NO |
| Bill's PC (`PcMenu`) | "What?", row, position | Row; "Which BOX?", box name, "N of 20 POKéMON"; CHANGE BOX save pages and YES/NO; notices |
| Boxes (`BoxMenu`) | Box or party name, prompt, Pokémon (nickname, level, gender, species if nicknamed, held item or mail), position | Pokémon; box; "What's up?" sub-menu; MOVE: "Move to where?", destination, "before <Pokémon>" or "empty"; messages; "Release PKMN?" said before its YES/NO |
| Item PC (`ItemPcMenu`) | "What do you want to do?", row, position | List with the chosen row as context; quantity; YES/NO; messages; DEPOSIT reads the held pack; "moving <item>" for SELECT |
| GIVE/TAKE (`HeldItemMenu`) | Pokémon, GIVE, position | Row; messages; swap question and YES/NO |
| Move lists (`MoveDeleter`) | Move, PP (deleter and PP pick) or name only (forget list, as drawn), position | Move |
| Move tutor (`MoveTutor`, Crystal) | "Teach which PKMN?", Pokémon, level, ABLE or NOT ABLE, position (reads its held party list) | Row |
| Party (`PartyMenu`) | The prompt as drawn, the row (nickname, species when different, level, HP, status, "holding an item" or "holding mail"), position (CANCEL counts) | Row; sub-menu label (with position when it opens); SWITCH says "Move to where?" plus the row; after a switch the Pokémon now under the cursor; "able" or "not able" from the screen's own TM check; item messages once the HP bar stops |
| Summary (`SummaryMenu`) | Nickname, species, number, level, gender, shiny; the page; "page N of 3" | Page; Pokémon switch; move screen: move, PP, type, power, position, description; reorder ("<move>. Where?", then the moved move); egg page |
| Pokédex (`PokedexMenu`) | "Pokédex", mode, seen and owned, row, position (unseen rows say "unknown") | Row; entry: name, kind, number, height and weight once caught, the action under the arrow, the description; page 2; AREA ("<NAME>'S NEST", region, nest landmarks or "none"); OPTION, SEARCH (rows, values, results), UNOWN MODE (letter and word) |
| Pokégear (`Pokegear`) | Card label and its face (clock day and time, map landmark, radio frequency and station), position on the strip | Card; map landmark ("you are here"); phone: prompt, contact with slot of 10, CALL/DELETE/CANCEL; radio: frequency and station on each knob step, then each show line, queued |
| Fly map and town map (`Pokegear` with `fly` or `townMap`) | "FLY. Where? <destination>, you are here, N of M" or "MAP. <landmark>" | Destination or landmark |
| Incoming call (`CallerBox`) | "Phone call, <name>, <class>" while it rings | (once) |
| House radio (`MapRadio`) | "Radio, <station>" | Each show line, queued |
| Trainer card (`TrainerCard`) | "Trainer card", name, ID, money, Pokédex count, time, page N of 3 | JOHTO BADGES or KANTO BADGES with the badges earned |

| Card Flip (`CardFlip`) | Coins and the question with YES/NO; each hand: coins, "Hand N of 12" | Bet square and its payout ("PIKACHU level 1, pays 72"), "played" on a blanked card; the cards played so far; the turned card, the result, coins |
| Slots (`SlotMachine`) | Coins, prompt, bet with the lines it buys | Each reel once stopped, top to bottom; reel tells ("Reel 2 pauses"); the result with the matched symbol named; play again, queued |
| Unown puzzle (`UnownPuzzle`) | Picture, controls, the cell | Cell ("piece 7, row 2, column 3" or "empty"); took or placed piece; complete. No placement hints |
| Alph stamp (`UnownPrinter`) | Title, letter, position | Letter or VACANT |
| Contest switch (`ContestMenu`) | Question, both Pokémon with level and health, YES/NO | YES/NO |
| Battle Tower (`BattleTowerMenu`, Crystal) | Question, level, position, "Up raises the level" once | Level; refusal; cancel question |
| Buena (`BuenaPassword`, Crystal) | Word, or prize with points and the balance | Row |
| Day-Care, NPC trade (`DayCareMenu`, `TradeMenu`) | Each page as typing starts; the line a `cont` page repeats is not said again | YES/NO, queued once typed |
| Decorations (`DecorationMenu`) | "Decoration", what is set up, row | Row; category; messages |
| Mail (`MailCompose`, `MailRead`, `MailMenu`, `MailboxMenu`) | Compose keyboard as the naming screen; read: stationery, message, author; menu and mailbox rows | Cell, typed glyph, deleted, case |
| Photo card, Magnet Train, diploma, Unown wall words | Read once (wall words: the word, then spelled) | (once) |
| Trade animation (`TradeAnim`) | "Trade. B skips", the Pokémon given | Text beats and the Pokémon received, queued |
| Hall of Fame (`HallOfFame`) | Induction: each member and the player card, queued; PC viewer: header, member, position | Member; header on a new team |
| Credits (`Credits`) | (each screen) | Each screen's lines, queued; THE END |
| Union Room list, Gen 2 battle and trade prep, arena (`union/List`, `Gen2BattlePrep`, `Gen2TradePrep`, `ArenaState`) | As Gen 1's link screens | (as Gen 1) |

A screen that changes and is covered in the same frame (the box screen's
release question with its YES/NO) says the change first: its presenter's
`covered()` is asked by `ScreenReader`, and the new top queues behind it. A
scrolled (`cont`) message page says only its new line (`Common.typerText`).

Silent on purpose: `OakSpeech` (its own text repeats the dialogue page
already spoken), `MenuFade`, `BlankScreen`. The yes/no fallback that
re-shows an already spoken question in a new instant box (field moves, Fly)
stays quiet so the selection speaks next (`Presenters.textBox`; Gen 1 never
takes that path).

Rows follow what the screen draws: the party list draws no gender, and its
held item is only an icon, so speech says "holding an item" without naming
it. A missing PP count means full; only an explicit 0 is said as 0. Radio
lines queue rather than interrupt, so a show is heard in order. The clock is
read when its card is reached, not on every minute. Labels a screen keeps
in file-local tables (decoration sides, slot bet rows, the diploma text) are
read from the screen's own functions with `debug.getupvalue` by name, never
copied, and stay silent if upstream renames them. Reading never changes
game state: the radio is read from the screen's record (never through
`ensureTuned` or `tuneRadio`), the Unown list from the save field (not
`Unown.dex`, which creates it).

## Navigation

Gen 2 navigation and the cross-edition audit are in
`gold-silver-crystal-navigation.md`.

## Verification

| Area | Level reached |
|---|---|
| Baseline (2026-11-01) | Game run, Crystal and Gold, new game to a wild battle (`drivers/gen2_walkthrough.lua`): only TextBox dialogue spoke before this work. |
| Info screens | `gen2_info_test.lua` 106/106. `drivers/gen2_info.lua` run in Crystal, Gold and Silver (identities `pocket-access-info-<game>`): every section reached and spoken. Not run: Softboiled target mode, the battle party list, phone DELETE, out-of-area calls, Buena's Password station, Kanto on the map and AREA screens, the dex PRNT action. |
| Special screens and minigames | `gen2_special_test.lua` 135/135 (checks that `Mail.lines`, `Mail.mailbox` are never called and decorations are never created by reading). `drivers/gen2_special.lua` run in Crystal, Gold and Silver (identities `pocket-access-special-<game>`): every screen reached. The driver forces some state (party, coins, decorations, mail, a Hall of Fame team, the first spin's reels); the contest, Battle Tower, Buena, mail and Union list screens were opened directly, not through their scripts. Unit tests only: some slot tells, Gen 2 Union prep (needs a second player), the arena failure message. |
| Menus and boot | `gen2_menus_test.lua` 122/122. `drivers/gen2_menus.lua` traced Crystal (three runs), Gold and Silver (identities `pocket-access-menus-<game>`); Gold's vending step not reached in that run (traced in the other two). The vending, elevator and Bank of Mom scripts were started by key; evolution and the egg were pushed directly. Re-run in Crystal after the lead's shared fixes: Mom's line says "cute POKéMON", and the re-shown yes/no question is said once, then "YES". Unit tests only: contest status, coin boxes, grid script menus. |
| Items and PCs | `gen2_items_test.lua` 110/110. `drivers/gen2_items.lua` traced Crystal (173 utterances), Gold and Silver (identities `pocket-access-items-<game>`); the tutor is Crystal only. Re-run in Crystal after the lead's covered-screen hook: "Release PKMN?", then "NO". Not run: the pack in battle, bargain and herb shops, the bedroom PC, OAK's PC and HALL OF FAME rows, the swap question, the World-driven Blackthorn deleter (pushed directly). |
| Heard by the owner | Crystal, 2026-11-01: the owner played from a new game up to the first gym and reported "It works perfectly in Crystal." Screens, dialogue, battles and navigation along that stretch are owner-tested; the rest of Crystal, and Gold and Silver, are not yet. |

## Open questions for the owner

- Trainer card page 3 ("KANTO BADGES"): upstream's plain draw puts Kanto
  names on the Johto badge flags (with only BOULDER earned it shows
  BOULDER and CASCADE). Speech copies the screen. Keep matching the screen,
  or read the save's Kanto badges?
- Item wording (agent choices): descriptions follow the row on every move;
  ABLE and NOT ABLE in capitals as printed (Gen 1 says "able"); "moving
  <item>"; "PKMN", "W/O MAIL" and "(S)" are the screens' own text.
- Boot and menu wording (agent choices): boot lines repeat on every attract
  loop; "Press B to stop the evolution."; "Egg hatching."; "A to continue,
  B to go back" on the CONTINUE panel.
- Audit wording and choices (agent choices): Pokémon objects named from
  their cry, sign names from the game's standard scripts, "Trainer",
  "Rival", "Turned back again", "<name> is gone", "No route to ... from
  here". Should auto-walk smash rocks the way it uses Cut and Surf? Should
  push hints cover boulders outside the stone tables (Cianwood Gym)? Raise
  the planning budget for long Area journeys (done 2026-11-03, see Olivine Lighthouse floors)?
- Navigation defaults (agent recommendations): map name is the humanised
  id plus Crystal's entry sign when it differs; hidden items are not listed
  (as in Gen 1); field obstacles are listed with what they still need; item
  balls are named by item (as in Gen 1).
- Minigame defaults (agent recommendations): the Unown puzzle names
  pieces by number and never says where a piece belongs; Card Flip says
  only what a sighted player sees (squares, payouts, cards played), no
  odds; Unown wall words are said, then spelled.
- Wording: "PRNT" said as written; "holding an item" without the item's
  name; "Phone call" and "Radio" are our words.

## Known gaps

- An outgoing call's first line ("PROF.ELM: ……") is covered by the call's
  first page in the same frame and is not heard.
- The phone card's signal meter (no service) is not spoken; no key re-reads
  the clock on request.
- Union Room name tags, the Ruins of Alph chamber walls opening and the
  heal machine animation are not spoken. A whole-board summary and a
  repeat-held-piece key for the Unown puzzle would need command keys.

## Upstream observations (recorded, not fixed)

- Trainer card page 3 reads the Johto badge flags (above).
- The summary ignores presses while its second swap sound plays, so a B
  straight after a reorder is lost.
- The radio card's draw tunes the radio and starts its music as soon as
  RADIO is highlighted, before A.
- The item PC's "Item Storage System opened." breaks across two pages.
- MoveDeleter draws a missing PP as "00" (speech says the maximum instead).
- Naming keyboard deletes bytes, not characters, so DEL leaves half of é,
  ×, ♂ or ♀, and those count double toward the length limit (source read).
- Field-move yes/no prompts (Cut, Headbutt, Fly) need an extra A press to
  close the question before the YES/NO box opens with the question
  re-shown; on the cartridge the box opens straight over the question.
- Mail keyboard: `<PK>`, `<MN>`, `<PO>`, `<KE>` are appended as
  multi-character strings but counted by bytes, so one token counts as 4
  letters and DEL leaves `<PK` (reproduced headless with the real class).
- Gold and Silver's NPC trade line names the two Pokémon the wrong way
  round ("traded MACHOP for DROWZEE" when DROWZEE was given); Crystal's is
  right (game-run traces; the cartridge wording itself was not checked).
- The slot machine's lucky odds are never used (`opts.lucky` is never passed).
- From source only: `Game2:useFieldItem`'s TM branch opens the party
  without the TM check, so rows show HP instead of able.

## Early Tin Tower and Suicune (Crystal)

Owner's play, 2026-11-03: walked into Tin Tower with four badges and fought Suicune at level
40, no Clear Bell. Source read (pret `maps/EcruteakTinTowerEntrance.asm`, `TinTower1F.asm`, and
the extracted scripts): the entrance only blocks once the Radio Tower is cleared, and before
that the sage says to go through with the Fog Badge; Tin Tower 1F's first scene is the battle.
So the cartridge's scripts allow it; not run on hardware. The fight happens once. Not explained:
the save has the entrance's scene at 1, which the scripts read here set only with the Clear Bell.

## Olivine Lighthouse floors (Crystal)

Owner's play, 2026-11-03: could not navigate up from the floors, and used the 5F Rare Candy
in the object list to move around. Checked on a copy of the owner's save, by asking for a route
from each warp cell on each floor (routes started, only partly walked): each floor is split
into separate sides. The usual climb reaches 5F's side with the Rare Candy and TM Swagger, where
6F says "No route". 6F's side comes from 4F's "Drop to Olivine Lighthouse 3F, entrance 2 of 2",
then 3F to 4F entrance 2, then 4F to 5F entrance 2. This is the game's layout, not a block.
Same-map routes cannot see through a drop. Fixed 2026-11-03 at the owner's request, nothing
lighthouse-specific: the shared journey planning limit went from 0.5 to 1.5 seconds (planning
measured 0.7 to 0.9), which applies to every generation, and Gen 2's Area list now names each
other map of the building or zone, so a floor stays a target with its items gone. Manual play
is unchanged. `drivers/gen2_lighthouse.lua` walked 1F to 6F, the wrong side of 5F to 6F, 6F to
1F and 3F to 5F in Crystal, Gold and Silver, drops included, by script. Not heard. A floor with
two sides is aimed at through one warp, so its arrival side is whichever that warp is on.

## Unread lines at the lighthouse (owner report, 2026-11-03, open)

The owner heard lines missing when talking to Jasmine and Amphy on Olivine Lighthouse 6F. Replayed
on a copy of the save with Jasmine's first speech restored and A pressed at three speeds: every
page and scrolled line reached `Speech.say` in order. So the loss, if it is ours, is after that
point or in another state (after the medicine). Not reproduced; nothing heard by an agent.
Second report, 2026-11-03, Jasmine in Olivine Gym after the badge ("Um… I don't know how to say
this, but good luck…"). Replayed on a copy of the save with the owner's options, A held 2, 6 and
15 frames: both lines reached `Speech.say`, in order, valid UTF-8, no failure logged. In these
scripted runs `logicSpeed` read 1, so the owner's game speed was not reproduced. Owner, same day: hears only "I don't know how to say this", nothing after. Forced game speeds 1, 2, 4,
8 and 30, tap and hold: "but good luck…" still reached `Speech.say` on the second press, so game speed
alone is not the cause in scripted runs. Owner's real game with `POKEPORT_ACCESS_TRACE=1`: the line
was sent and Prism refused it, `[warn] [access] speech failed: Invalid UTF-8`, though the logged
bytes are valid and end in U+2026. "Um… I don't know how to say this," passed. Scripted runs set
`POKEPORT_ACCESS_SILENT`, which returns before Prism, so they could not see this. Fix in
`Speech.say`: a line refused that way is said again in ASCII; the cause inside Prism is unknown.

## Team Rocket Base (owner report, 2026-11-03, open)

The owner had "slight trouble" navigating here; the place and message are not known yet. On a copy
of a save from before the base (state not the owner's): routes exist from B1F's entrance to B2F, but
B3F and two items have "No route" from there. A scripted walk toward B2F kept being interrupted and
resumed, and had not arrived after 16000 frames, at (5,4). Cause not established.
On a copy of the owner's save at B1F's entrance, 2026-11-03 (strong test lead, game speed 8): the walk
reached B2F with no interruption. Most targets route. The floor target "Team Rocket Base B3F" and the
Ultra Ball say "No route" from there, though other B3F items route: a floor target is aimed at through
one warp, which may be on a side not open yet.

Second save, 2026-11-03, B2F with both passwords. The owner was unsure what to do next. B3F's password
door ("Signpost 1") has "No route" from the east side; its side is reached through B2F. Walked by
script on a copy: B3F entrance 4, B2F entrance 2, B3F entrance 1, Signpost 1, A: "The door opened!".
Order per pret's `TeamRocketBaseB3F.asm` and `B2F.asm`: door, Executive, Murkrow (listed "Pokémon")
gives HAIL GIOVANNI, B2F's locked door ("Signpost 1" there), Electrodes. Only the door was run here.
Owner: "very clunky for a first-time user". Fixed the routing, 2026-11-03: Gen 2 now sets
`autoWalkJourneys`, as FireRed does, so auto-walk to a target on this map with no route here goes
through other maps. Script on a copy: from B3F's east side, select Signpost 1, one auto-walk reached the
door through B2F; A opened it. `gen2_nav`, `gen2_nav_more` and unit suites still pass. Not heard. For
comparison, Pokémon Access (source read: `a-star.lua`, `gb.lua`, `pokemon.lua`; game files searched
for the base): paths within the current map only, spoken, no auto-walk, signposts as "signpost N".
Owner: Signpost for these was "very, very, very confusing". Named from the scripts' own text, 2026-11-03
(`WorldSnapshot.signRoleFromText`): a script that changes the map and mentions a door is "Locked Door",
"labeled X" is X, "the X slot" is "X Slot". `gen2_nav_cart_test` sweep on each game: Switch 1 to 3, Card
Key Slot, and Rocket Base doors. Relies on English text. Owner tried the build and asked to push, 2026-11-03: "I think
that's as good as we're gonna get it."

Chase bug found in this check and fixed: it compared names, so walking from one Rocket to another
started a chase. It now needs the same object, or the old id gone and one object with that name.
Gold's chase rerun after the fix.

## Device clock (2026-11-08, decision 56)

Built into the layer for everyone (`src/access/PcClock.lua`, installed first thing in `Access.install`, with
or without speech). It began as a separate mod; the owner made it the default the same day, and the mod was
removed. Upstream already reads the host clock through the offset taken when Oak's and Mom's questions are
answered (`src/core/gen2/Clock.lua`), so the time already followed daylight saving and the weekday; this
removes the answers:

- `InitClock.new` opens on the device's hour, minute and weekday with `autoConfirm`, the screen's own
  walk-through, and says "Clock set from your device: ..." or "Day set from your device: ...".
- `Clock.minutes` and `Clock.weekday` read with the offset at zero and put it back, so the save keeps its
  own setting and `POKEPORT_ACCESS=0` still plays it.
- Mom's daylight saving question still appears: upstream stores `rtc.dst` and never moves the clock with it.

Tested by script (`tests/access/drivers/pc_clock.lua`) on Crystal, Gold and Silver, disposable profiles,
9 of 9 each: both screens answered themselves within 8 frames with the device's values and said so; the
game's time and weekday equalled the device's after a new game, after both screens and after a forced
6-hour offset; the save kept that offset. Without it (the earlier mod run with the mod removed) the clock
read 10:00 and the screens waited. Not played by the owner yet; Android not tried.

## Crystal Randomizer mod (2026-11-08, decision 57)

`launcher/mods/crystal_randomizer`: a mod (api 2, `engine_internals`, Crystal only), set up at New Game by
Oak's questions, one seed per save in `mod.save`; a save without a seed is vanilla. The player-facing
summary and its limits are in its `README.md`; how the core and modules fit is `CONTRACT.md`. Built by four
agents (wild, trainers, starters and items, types and moves) against that contract, with the core and the
integration done here.

How each module changes the game: wild rewrites `data.gen2Encounters` per save and wraps
`encounter.fishing`; trainers wrap the `trainer.party` hook (no data changed); starters and gifts wrap
`script.command` and pass rewritten copies of rows, with Elm's text under new text keys; items rewrite the
item ball and hidden item ids in `data.gen2Maps` per save; types and moves swap `def.types` and
`def.levelMoves` per save. Every module keeps the vanilla values and restores them exactly. No engine file
was edited.

Verified by script only: each module's own luajit test (pokemon 7914 checks, wild 1000, trainers 401,
starters 82, items 69, core 7, all passing; the module tests also passed on the real imported Crystal
tables), each agent's silent game run, and `tests/full_driver.lua` in a silent Crystal run with the mod
installed in a disposable profile: a New Game through Oak's real speech asked every question and said the
seed the save kept; Route 29's grass, its item ball and Chikorita's types and moves changed; Continue from a
copy of the save gave the same world; a copy without the randomizer's data was vanilla; the randomized copy
came back the same. Installed in the owner's own save folder's `mods` at their request (2026-11-08, "Yep, let's do it"), for their next Crystal New Game; not yet played or heard by the owner. Known gaps are in the mod's README.

### Randomizer research (2026-11-08, for the next version; nothing built yet)

The owner, after seed 876506 felt "kind of normal" (with "keep them about as strong", early routes swap
common early species for other common early species, often familiar ones): look at how other randomizers
do it first, including mechanics not yet thought of. Read: the Universal Pokémon Randomizer ZX and FVX
release notes and feature summary (upr-fvx.github.io), a PokéCommunity settings guide, the Archipelago
Crystal option template (a community gist) and Archipelago's Red/Blue and Emerald option pages. Web search
summaries only; the FVX wiki's full feature list was not read.

What they do that this mod does not:

- Wild: three replacement modes, random per slot, one replacement per map (ours) and global one-to-one,
  where each species is used once across the game; "catch 'em all" so every species can be found; keep a
  route's type theme. Similar strength there starts at a 10% band and widens to a minimum pool, as ours.
- Trainers: the rival's starter is the one strong against yours; gym leaders and the Elite Four keep one
  type each; force fully evolved Pokémon from a chosen level; a level percentage for trainers and wild.
- Starters: choose exactly, or three-stage starters, or a type triangle.
- Evolutions randomized; trade evolutions turned into level or item evolutions (useful even without the
  randomizer: most players here cannot trade).
- TMs: their contents and compatibility; reusable TMs. Move data, base stats, shops ("better marts").
- Quality: experience modifier, blind trainers (only battle when spoken to), minimum catch rate.
- Larger: key item and map randomizers (Archipelago, a Crystal map randomizer), which need logic so the
  game stays winnable.

### Randomizer version 2 (2026-11-08, decision 58)

The owner: "use up to 10 sub-agents to build all of that" (the research list). Nine agents built or
extended one module each against `CONTRACT.md`; the core gained Oak's setup choice (RECOMMENDED, EVERYTHING,
CHOOSE EACH), so a player is not asked thirty questions. The mod's `README.md` lists every question and what
each does. New modules: `stats`, `evolutions`, `tms`, `shops`, `qol`, `keyitems`. Engine files: none edited;
the `tms` module wraps `Game2:consumeItem` on the running game for reusable TMs (Gen 2 has no item hook),
and `qol` sets map trainers' `sight` to 0 per save for blind trainers. Our own layer: navigation now names a
TM or HM ball by its number and current move (`src/access/nav/gen2/WorldSnapshot.lua` `machineLabel`).

Module tests, all passing together: core 7, pokemon, stats, evolutions 26846, starters 4167, items 76,
tms 141, shops 625, wild 14979, trainers 1558, qol 88, keyitems 2176 checks; each also passed on the real
imported Crystal tables, and each agent's own silent game run passed. The whole mod then passed `tests/full_driver.lua` through Oak's real New Game twice, RECOMMENDED (seed 191463: wild and items changed, Chikorita's types kept) and EVERYTHING (seed 647304: types changed too), with Continue, a plain save and back all as expected; seed 876506, a version 1 save, kept its version 1 world exactly. Version 2 installed in the owner's save folder the same day at their request ("Yes, update it"); not yet played by the owner. Saves started with version 1 keep
their version 1 world (wild module legacy path). The HM shuffle model (`keyitems`) is the agent's reading of
the scripts with deliberately strict rules; it found 288 beatable HM orders of 5040 and has not been proved
by a playthrough, which is why only CHOOSE EACH offers it.

Known gaps beyond the README's list: the Pack still says the old quantity after an item is used on a
Pokémon (seen with METAL COAT; probably the Pack not refreshing, not checked with a stone); UP-GRADE and the
other trade items may be hard to find; legendaries can appear on ordinary trainers; day-care experience is
not multiplied; an exported cartridge save made on a map with blind trainers carries their sight as 0.

### Door randomizer (2026-11-08, decision 59)

The owner asked whether a map randomizer existed, then: "use the same 10 subagents." Seven agents built
`mapgraph`, `maprules`, `mapplacer`, `maps`, `mapmoves`, navigation changes in `src/access/nav/gen2/Navigation.lua`
(test `tests/access/gen2_map_shuffle_test.lua`) and the end-to-end test `tests/maps_e2e.py`, against
`launcher/mods/crystal_randomizer/MAPS.md`, which holds the design, what was built and the verification. Oak's
question "Shuffle where doors lead?" (OFF, HOUSES, CAVES, EVERYTHING) is off in both setups. The end-to-end
test found one real fault (Tohjo Falls placed behind the closed Safari Zone gate's wall); fixed in `maprules`,
then 12 of 12 silent runs passed. Not played by the owner.
