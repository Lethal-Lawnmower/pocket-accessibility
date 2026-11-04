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
| Title combos (clear save, reset clock, Berry fix) | Their text, yes/no, the time being set | Source read only, never run |
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

## Upstream observations (recorded, not fixed)

- Ruby and Sapphire's contest stage prints "Appeal no. MAY! Which move will be
  played?" in the running game: `rse/contest.lua` `nativeText` turns the text's
  `FC 00` into `FD 01`, which the Ruby dialect expands to the player's name, not the
  round number. Read from the printer's tokens, not seen on a screen. Speech says
  that line as printed, and "Round N of 5" beside it from the contest's own counter.
- Emerald's own string for the contest page title is spelled "C0NTEST MOVES"
  in the running data; the layer says CONTEST.
- `PcMenu` root mode reads FireRed's `Text_AccessWhichPC` on B after `show()`
  without `closeOnExit` in Emerald: an upstream crash path only a script
  that opens the PC differently could reach. Seen from a driver, not from a real
  PC script.
