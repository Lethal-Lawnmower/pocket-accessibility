# Ruby, Sapphire and Emerald: screens

Differences from FireRed and LeafGreen (`firered-leafgreen.md`) for the Hoenn
games (decision 29). Navigation is in
`ruby-sapphire-emerald-navigation.md`. Nobody has heard these runs: every run
in game named here was silent and read from its log.

## How it sits on upstream

Hoenn uses FireRed's engine with its own screens in `src/ui/game3/rse/`
(Emerald, some shared) and `src/ui/game3/rs/` (Ruby and Sapphire), chosen by
`src/core/game3/profiles/*`: `ui.screens` replaces a module, `ui.skins`
draws and drives FireRed's module, `boot` names the boot objects.

- **Boot** is objects in `boot.custom` (`boot_modules.lua`), not fields of the
  boot state. `gen3/Top.lua` reports them as kinds `hoenn_intro`,
  `hoenn_title`, `hoenn_main_menu`, `hoenn_birch`, `hoenn_combo`; a layer over
  them (OPTION, Mystery Gift) is the screen while open.
- **Presenters** are `gen3/Hoenn*.lua`, first in `gen3/init.lua`. A few
  share a module with FireRed (bag, Emerald's summary), so they match only
  when `H.isHoenn()` holds. FireRed's presenters stay in charge of what reads
  the same (dialogue, yes/no, party, naming, box storage, evolution, battle).
- **Text printers** of `rse/scene_kit.lua` type a token list.
  `HoennCommon.printerSay` builds the pages from the tokens, so a page is
  spoken whole as it starts, the dialogue pacing the owner chose; ALL AT ONCE
  applies.
- **Text keys** differ: Ruby and Sapphire name most strings differently, and
  upstream applies `ui.textAliases` only while its screens run.
  `HoennCommon.rom` follows the aliases; `Items.party` runs under
  `Screens.withTextAliases`.
- **OPTION** and our ACCESSIBILITY page: `Settings.installGen3` also wraps the
  profile's own option module (`_st.pages` in Emerald, `_pages` in Ruby and
  Sapphire); values live in the game's own options block.

## Screens

| Screen | On entry | On change |
|---|---|---|
| Intro, title | "Intro. Press start to skip."; "POKéMON <edition> Version. Press start." once start counts | |
| Main menu | "Main menu", row, position, CONTINUE panel (player, time, Pokédex, badges) | Row; error pages page by page |
| Birch's speech | Each page as it starts | Gender and (Ruby, Sapphire) name list with position; name yes/no |
| Title combos (clear save, reset clock, Emerald's Berry fix) | Their text; clear save opens on NO; the reset screen's present and previous time; the Berry fix pages | YES/NO; the field being set with its value, CONFIRM; result lines |
| Mystery Events (Ruby, Sapphire main menu) | Its printer pages | Event and news rows with position; news title and body, a new line as it scrolls; load prompts |
| OPTION, ACCESSIBILITY | Title, label, value, position | Label and value; value only on the same row |
| Save | Location, player, badges, Pokédex, time, the question, YES | YES/NO, next line |
| Trainer card | Lines of the card, badges counted, stars | Back side (Ruby's labels are images: our words) |
| Bag (all five pockets) | "<pocket> pocket", row with position, description; TM rows with move, type, power, accuracy, PP | Row and description; action grid; toss, deposit, yes/no, results |
| Party | FireRed's presenter; Ruby and Sapphire prompts through their own text | |
| Summary | Header, page title, "page N of 4" (info, skills, battle moves, contest moves), page | Page; move detail; contest appeal and jam as numbers (hearts on screen); moving a move |
| Pokédex | "POKéDEX. seen N, owned M", row, position | Row ("not seen" for dashes); START menu; entry (with HT and WT in feet and inches); bar; AREA places or AREA UNKNOWN; CRY; SIZE; search rows and parameters with descriptions; registration after a catch |
| Shop (and decoration shops) | Clerk line, BUY/SELL/QUIT with position | Rows with price and description; quantity, cost, IN BAG; yes/no; money; selling through the bag |
| Player's PC, item storage, box storage | Question or row with description | Rows; quantities; deposit through the bag; boxes by FireRed's presenter |
| Starter choice | Birch's message, name, category, position | Selection; "Do you choose this POKéMON?"; yes/no |
| Wall clock | The time in words (the clock is a picture) | Each minute, every five while the hand runs fast; confirm question, yes/no |
| Town map, Fly | "Town map" or "FLY to where?", place, "you are here" | Place once the cursor stops; "can fly" |
| Evolution, egg | FireRed's presenter in Emerald; Ruby's egg scene through its printer | |
| Map name popup | The name, queued, through the shared overlay (Emerald, Ruby windows) | |
| Pokénav menus (main, CONDITION, search) | "POKéNAV", "A rematch is nearby" when the blue light blinks, row, position, description | Row, position, description; "There are no RIBBON winners", "No TRAINERS are registered" |
| Pokénav map | "HOENN MAP", zoom level, place with landmarks, "you are here", help bar | Place once the cursor stops; "no place" where the window is empty; zoom level. S.S. Tidal position in Ruby and Sapphire |
| Condition graph (party, search) | "CONDITION, PARTY" or the search category, name, gender, level, box or IN PARTY and rank (search), position, the five conditions and sheen as numbers, marks | Next Pokémon; CANCEL; marking box with each symbol's state, OK, CANCEL |
| Condition search results | Category, name, gender, level, rank, position, help bar | Row |
| Match Call (Emerald) | "MATCH CALL", registered, battles, trainer, place, "wants a rematch", position, help bar | Row; CALL, CHECK, CANCEL; Check page (strategy, Pokémon, introduction); the call through its printer, page by page; "That TRAINER is close by"; tutorial opening |
| Incoming call (Emerald) | "POKéNAV call" (the icon, our words), each page | |
| Trainer's Eyes (Ruby, Sapphire) | "TRAINER'S EYES", registered, battles, trainer, place, "wants a rematch", position, help bar | Row; detail (strategy, Pokémon, introduction), next trainer |
| Ribbons | "RIBBONS", name, gender, level, count, position | Row; summary: next Pokémon, count; each ribbon's description with position, gift ribbons included |
| Contest stage (all rounds) | Rank and category; each round "Round N of 5", appeal order with trainer, total hearts, stars, status and judge's attention | Announcer page by page; move rows with category, combo or repeated, position, appeal and jam hearts as numbers, description; hearts after each appeal or jam; stars; status; excitement N of 5, maximum, reset; next-turn order; totals after the round. Narration is queued; the move list interrupts it |
| Contest results | Rank and category | Each banner; preliminary stars; round 2 hearts (minus when lost); places 1st to 4th; winner; "Press A" (the scene waits with nothing on screen) |
| Contest painting | "Painting", caption; the artist's copy has no caption, so the name | |
| Choosing a contest Pokémon | FireRed's party presenter; Ruby and Sapphire through `rs_contest_party`, with ABLE and NOT ABLE from their image descriptors | Row |
| Pokéblock case (field, Safari battle) | "POKéBLOCK CASE", name, level, position, flavours, feel | Row; "Moving"; USE, TOSS, CANCEL; toss question, yes/no, result; STOW CASE |
| Use Pokéblock, feeding | "CONDITION", name, gender, level, position, nature, five conditions and sheen as numbers; CANCEL | Row; question, yes/no; "ate" line through its printer; "Press A" before the change; each "was enhanced" line, new numbers |
| Berry Blender | Its messages; player names and berries once thrown; berry through the bag (location blender) | Ranking with BEST, GOOD, MISS counts; results with berries, maximum speed, time; "made" line; yes/no. The timing game is silent, see below |
| Berry tag (bag CHECK TAG) | "BERRY TAG", number, name, position, size, firmness, flavours, description | Next berry |
| Decorating | Action row, position, description | Rows; categories with owned count, "not for this room", position; items with description, "in use in your base" or "room"; messages; yes/no |
| Decorating, placing and putting away | Item, width, height, keys, cursor from where the player stood, "can be placed" or "cannot be placed" (putting away: the decoration under the cursor, PC, or "nothing here") | Each step the new offset and the same state; question, yes/no, result |
| Base registry, trader's choice | Rows with position; DEL REGIST., CANCEL; "There is no REGISTRY" | Rows |
| Mailbox | "MAILBOX", sender, position | Row; "What would you like to do" line with READ, MOVE TO BAG, GIVE, CANCEL; yes/no; result |
| Letter (Emerald, Ruby, Sapphire readers) | Stationery name, every line, "From" and sender, the icon's Pokémon (Ruby, Sapphire), "Press A" | |
| Word editors in Ruby and Sapphire (profile, sayings, bard's song, trendy phrase, mail) | The editor's instruction, phrase so far, "word 1 of 4" with its word | Slot; footer DEL. ALL, CANCEL, OK; groups or letters with position; side buttons; word with position; chosen phrase; questions and refusals, yes/no. Emerald uses FireRed's Easy Chat presenter |
| Roulette | Wager question, yes/no; "Roulette", coins, bet a ball, instructions | Before each bet: coins, balls left, squares hit so far; each square with what it pays or "already hit"; bet, coins; where the ball landed; the game's result lines; keep playing |
| Slots | "Slot machine", keys, coins | Bet with its lines and coins; "Spinning"; each reel top to bottom as it stops; win with payout and winning lines, or "No win"; Power meter; Reel Time spins; quit question; SELECT: payouts and Reel Time text |
| Move tutor | Prompt, move, position, type, power, accuracy, PP, description | Row; contest page: category, appeal and jam hearts as numbers, description; questions, yes/no; learning lines; forgetting through the summary presenter |
| Frontier Pass (Emerald) | "Frontier pass", Battle Points, symbols earned, what is under the cursor | Under a free cursor: the button's name and description; Battle Points' number; a symbol's silver or gold; in empty space "Nothing here. Nearest", the nearest button and the way to it, then only that as it changes |
| Frontier map (a phase of the pass) | "Frontier map", "You are at" or "You are near" a landmark, landmark, position, description | Landmark, position, description |
| Frontier result and ranking windows, link battle and link contest records, blender speed records, BP box (Emerald) | Passive, queued: every row of the window in reading order; "<n> BP" | Ranking Hall's next level page; new amount |
| Exchange corner, Frontier tutors (Emerald) | List row with price, position, the description the screen draws beside it | Row, price, description |
| Battle Dome tree | "BATTLE TOURNEY", trainer or match, "out" with the round, position | Trainer with position; match number, who meets whom, result line; CANCEL or EXIT. Between rounds: "Still in" and names, "Press A" |
| Battle Dome cards | Next opponent: class, name, three Pokémon, potential, style, stats | From the tree the same, or match number, both sides with Pokémon, "out", result line, and which arrows lead on |
| Battle Factory rental | "RENTAL POKéMON", the prompt, species, category, position | Species, "chosen first", position; SUMMARY, RENT or DESELECT, OTHERS; the refusal; the three chosen, yes/no. Summary by its presenter |
| Battle Factory swap | "POKéMON SWAP", the prompt, species, category, position | Row, position, either side; POKéMON FOR SWAP, CANCEL; SUMMARY, SWAP, RECHOOSE; "already in party"; accept and quit questions, yes/no |
| Battle Pyramid bag | "Pyramid bag", row with quantity, position, description; CLOSE BAG | Row; the actions' question and rows; toss count, question, yes/no, result; moving an item; refusals |
| Pyramid start menu | "Battle Pyramid Floor N" or "Peak" before the row | REST through the save presenter with the pyramid's own line; RETIRE through dialogue and yes/no |
| Trainer Hill time board | Every mode with its time | |
| Battle Tower record board (Ruby, Sapphire) | Passive, queued: title, both levels, current and record | |
| Credits | Each page of titles and names; each Pokémon once; "THE END. Press A" | Queued, never cut off |
| Diploma | The certificate as one text (Emerald through FireRed's presenter) | |
| Glass workshop, day-care STORE menu and level menu, cable lobby | Row with position; "Do what with <name>?"; "empty" for a blank day-care row | Row |
| Link battle records (Ruby, Sapphire), coins box, money box | Passive, queued: results and rows; "<n> COINS", "MONEY" | New amount |
| Auto-scrolling message (Ruby, Sapphire) | Its text, once, queued | |
| Cable car, Rayquaza scene | "Cable car ride", "Rayquaza scene" (no text and nothing to press in them) | |

Labels our words stand for, because the screen draws them as images: Pokédex
bar and START menu, search row names, Ruby's trainer card labels, Ruby's summary
page titles, Ruby's pocket names, contest categories on the moves page, and in
the Pokénav (`gen3/HoennPokenav.lua`): menu rows, left headers, graph axes,
sparkles (the sheen number stands for them), marking symbols, gender signs,
rematch marker, blue light, call icon, and Ruby and Sapphire's help bars (read
off the images; only map, Trainer's Eyes, search graph, markings are said).

Known gaps in contests and the blender (`gen3/HoennContest.lua`,
`drivers/rse_screens_contest.lua`): the Berry Blender's timing game is silent by
design. Its arrow, BEST, GOOD and MISS sprites and changing speed digits are real
time with no readable text, and a spoken cue would arrive after the moment; a player
hears only the game's own sounds, which come after a press. Whether a cue is wanted
is the owner's decision. Pictures are not described: the painting, the winner's
banner, the judge. Heart bars in the results are said as the stars and hearts they
are built from, not as a length. Not run: link contest and link blender text, a
contest entered from the reception script (the driver opens the modules the natives
open, with the same options), turn-skipped "can't participate", the blender's YES
path and its two refusals.

Labels our words stand for in those screens: contest category and rank, hearts,
stars, status and judge symbols (protected, nervous, cannot appeal, judge's
attention), excitement, next-turn labels, places, the combo and repeated colours,
CONDITION and its axes, sheen, the blender's score icons, Ruby and Sapphire's BERRY
TAG title.

Known gaps in the field screens (`gen3/HoennField.lua`,
`drivers/rse_screens_field.lua`). Timing stays silent, as nothing readable shows:
the roulette ball while it rolls, spinning reels, Reel Time's own game. Placing
says offsets from where the player stood, not what is drawn around the cursor.
"pays N times" and the reels are in our words, read from the same tables.
Reached with a helper rather than from play, and named here: a won slots spin (the
driver sets the machine's bias), the base decorating menu (opened with the PC
script's options on the base's map; that script's own menu also opened it), Ruby and
Sapphire's Mystery Events rows (fetch and list drawing stubbed: nothing is contacted,
see below), cable lobby (driver's rows, a real lobby needs a link), list menu rows
(driver's labels). Not run: Reel Time's spins line, a placed decoration in the
bedroom, Trendy phrase and interview editors from their scripts (only the modules),
the Mail composer's blank-mail refusal, Rayquaza's Ruby and Sapphire counterpart (they have none).
Trick House: its entrance script read as dialogue; the rooms are ordinary field
text, not walked. Multichoice in Hoenn reads through FireRed's choice presenter
(Emerald's coins clerk, Ruby and Sapphire's prize clerk ran by their scripts).

Labels our words stand for in those screens: decoration in-use markers, word
editor footer and side buttons, roulette colours and Pokémon, slot symbols, Power
and Reel Time, payout chart, secret base cursor position, CONTEST and BATTLE MOVES
headers on Ruby's tutor, the stationery name and icon.

Known gaps in the Frontier (`gen3/HoennSpecial.lua`,
`drivers/rse_screens_frontier.lua`). Reached by the game's own scripts: the results
windows (tower, factory), Ranking Hall pages, cable box records, blender speed
records, exchange corner, tutors, Trainer Hill board, and the Dome room's menu into
the opponent card and tree. Reached by a helper, which set the session state the
challenge would have set and passed the native's options, because a whole challenge
is not played: the static and previous Dome trees and the second round, Factory
rental and swap (`Factory.init`, `generateInitialRentalMons`, the rest of the rentals
as the other side), the refusal and same-species lines (forced by the driver), the
Pyramid floor (`Pyramid.init`, `seedFloor`, then its map), both toss-choice and battle
bag openings, Pike's room, Ruby and Sapphire's record board (the native's one call).
The other facility results windows ran as modules. Not run: the pass's Battle Record
row with a record saved and its playback; the Pyramid bag's refusal messages and GIVE
through the party; the bag used in a real battle; a real Pyramid or Pike challenge
from its lobby; Dome's EXIT button; a Ranking Hall row with a name, or link multi's
two names. The Frontier Pass cursor is free: "nearest" and its way are ours, measured
from the screen's own button rectangles, not from what the player can see; the head on
the map outdoors is said as the nearest landmark.

Labels our words stand for in those screens: "Frontier pass", MAP, TRAINER CARD,
CANCEL and the medals on the pass, "Frontier map", the pass's "Nothing here" and
"Nearest", Dome's CANCEL and EXIT, "out", "against", "Still in", "More with" and the
arrows, Factory's "chosen" for its coloured balls, "Pyramid bag", "empty" for a blank
ranking row.

Known gaps in the Pokénav: the map's city picture is not described; the map
says nothing about which places can be flown to. Emerald's graph, list and map
read fields once the screen's own animation allows, so entry speech starts as
the fade ends. A real step-triggered incoming call, the tutorial reached from
its script, and gift ribbon text in a real save were not run: the driver opens
the same window, shell and fields directly.

## Battle

`gen3/Battle.lua` reads Hoenn battles unchanged. The only addition: the
`{POKEBLOCK}` glyph in Emerald's Safari menu is said (`Common.TAG_WORDS`).
Safari there is BALL, POKéBLOCK, GO NEAR, RUN. Weather and ability lines are
ordinary battle messages ("Wild KYOGRE's DRIZZLE made it rain!", "The sandstorm
rages."), so they speak like any message.

Run in game in Emerald (`drivers/rse_battle.lua`): wild catch with Pokédex page
and nickname question, level up with learn-move questions, SHIFT trainer battle,
run, Safari, double battle with both menus and targets, weather; every scene
TALLY missed=0.

## Verification

Level reached for everything here: run in game, silent, read from logs. Not
heard, not owner accepted. Most deep screens were opened by the driver the way
their native calls them, with session state set by the driver, not reached by
playing there; each row above and the known gaps say what is not run.

| Check | Result |
|---|---|
| `drivers/rse_menus`, `rse_screens`, `rse_battle` | Final sweep on Emerald, Sapphire (and `rse_screens` on Ruby; `rse_menus` and `rse_battle` earlier on Ruby): no BAD, FAIL or driver error; every battle scene TALLY missed=0 |
| `drivers/rse_screens_pokenav`, `_contest`, `_field`, `_frontier` | Run on their games when written; not repeated after later commits |
| FireRed `gen3_menus`, `gen3_menus_more`, `gen3_screens_more`, `gen3_items`, `gen3_special`, `gen3_battle` | Run to their end after all Hoenn commits: no BAD, FAIL or driver error; battle TALLY missed=0. Logs read for errors, not compared line by line with an earlier run |
| Unit tests (`tests/access/*_test.lua`, except `gen2_nav_cart_test`) | All pass |

## Upstream observations (recorded, not fixed)

- Ruby and Sapphire's contest stage prints "Appeal no. MAY! Which move will be
  played?" in the running game: `rse/contest.lua` `nativeText` turns the text's
  `FC 00` into `FD 01`, which the Ruby dialect expands to the player's name, not the
  round number. Read from the printer's tokens, not seen on a screen. Speech says
  that line as printed, and "Round N of 5" beside it from the contest's own counter.
- Ruby and Sapphire's Mystery Events list crashes when it has rows: `drawList` asks
  for `gText_SelectorArrow3`, not in their text cache ("ROM text ... is not in the
  script cache"). Only a list with rows reaches it, which needs online data. Speech
  is written and seen behind a driver stub of that draw call.
- Emerald's party GIVE with mail gives the item with no composer and no letter: "ZIGGY
  was given the ORANGE MAIL to hold", `mon.mail` nil. Ruby and Sapphire open the composer.
- Hall of Fame PC prints `???` for any Pokémon above 151 without the national
  Pokédex (`KANTO_SPECIES_END` in `hall_of_fame_pc.lua`), so Hoenn's own say `???`
  there while the Hall of Fame scene gave the regional number. Speech says what it prints.
- Ruby and Sapphire's Hall of Fame PC title has lost its number ("HALL OF FAME No.")
  and the day-care STORE prompt its name ("Do what with ?"). Speech adds the number
  and the name from the screen's own fields.
- `cable_car.lua` opened directly in Ruby never starts; through its script it rides.
- Emerald's own string for the contest page title is spelled "C0NTEST MOVES"
  in the running data; the layer says CONTEST.
- `PcMenu` root mode reads FireRed's `Text_AccessWhichPC` on B after `show()`
  without `closeOnExit` in Emerald: an upstream crash path only a script
  that opens the PC differently could reach. Seen from a driver, not from a real
  PC script.
