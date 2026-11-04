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

Labels our words stand for, because the screen draws them as images: Pokédex
bar and START menu, search row names, Ruby's trainer card labels, Ruby's summary
page titles, Ruby's pocket names, contest categories on the moves page.

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

- Emerald's own string for the contest page title is spelled "C0NTEST MOVES"
  in the running data; the layer says CONTEST.
- `PcMenu` root mode reads FireRed's `Text_AccessWhichPC` on B after `show()`
  without `closeOnExit` in Emerald: an upstream crash path only a script
  that opens the PC differently could reach. Seen from a driver, not from a real
  PC script.
