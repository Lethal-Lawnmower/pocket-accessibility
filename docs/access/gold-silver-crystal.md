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

Gen 1 behaviour is in `navigation.md`. The same commands, object list, guided navigation, auto-walk, journeys,
controller scheme and AUTO-WALK SPEED run on the Gen 2 world. Reused from the
old project's Gen 2 navigation (`purple-gen1-gen2-preview`,
`src/accessibility/gen2/`, commit `71cdd419`, upstream v0.3.32) under decision 20, navigation half only; each file names
its origin.

| Module | Role |
|---|---|
| `nav/WorldAdapter.lua` | Per-generation access for `init`, `AutoWalk`, `WalkSpeed`: the game, "on the map", transitions, battle marker, steering re-latch |
| `nav/gen2/Navigation.lua` | Coordinator subclass: every world question from COLL bytes, the live World, warps, bg events, connections, badges and party moves |
| `nav/gen2/WorldSnapshot.lua` | Projects a Gen 2 map into the object list (signs, holes, return warp, item names) |
| `nav/gen2/TerrainSemantics.lua` | COLL classifier (ice, currents, waterfall, whirlpool, ledges, ladders, stairs up/down, holes) |
| `nav/gen2/PuzzleAssistance.lua` | Stone-table rules and the floor-wide Strength search |

Design: a coordinator subclass (the base already isolates the world in
`worldState` and overridable methods, and the old Gen 2 code was written that
way), plus a small adapter for the code outside the coordinator. Gen 1 code
paths are unchanged.

- **Reaching the game:** Game2 is a `main.lua` local. The mod loader binds the
  Gen 1 Game facade (`Gen2Compat`) to it; its `.overworld` is the World and
  `world.game` is the Game2 instance. No upstream edit.
- **On the map:** Gen 2's overworld is not a stack state. An empty stack with
  no script, text, menu, field-move animation or battle holding the world is
  the map (`WorldAdapter.gen2.scriptHeld`, World:busy's fields without
  `moveState` and `mapSetup`). Door fades (`mapSetup`), ice slides, currents
  and the step off an arrival door are transitions: auto-walk lets go and waits.
- **Object list:** signs are "Signpost N" by bg event ordinal (a sign's script
  key is a ROM address and never spoken); a sign on a bookshelf, PC, TV or
  other standard tile takes that name and the tile is not listed twice;
  facing-only signs keep their facing; if-set and if-not-set signs appear
  only while the game would read them; hidden items are not listed (Gen 1
  lists none). The 0xFF "back" warp resolves through the world's backup warp,
  else "Exit". Connections are named from `mapId`. Item balls are named by
  item (looked up by index). Cut trees, headbutt trees, whirlpools,
  waterfalls (climbed from below), smashable rocks and boulders are objects
  with what they still need ("Needs Cut and Hive Badge", "Needs Headbutt").
  Pits are "Drop to ..." under Objects.
- **Map names:** the humanised map id, as in Gen 1 ("GOLD's House 2F",
  "Route 29"). Crystal's entry sign is also spoken when it differs from the
  map name ("Blackthorn City" on entering Blackthorn Gym 2F); Gold and Silver
  show no sign. Agent recommendation, not an owner decision.
- **Routing:** side walls on the standing and neighbouring cells (across map
  seams on the live map), two-cell ledge hops off the ledge cell, ice slides
  and currents as one move, Surf at the shore, Cut and Whirlpool "use, then
  move", Waterfall climbed in one move, big objects as 2x2, warps blocked
  unless the goal. Cross-map plans use the same graph; connections skip
  cells where the strip ends or a side wall refuses the landing.
- **Auto-walk on Gen 2:** Game2 latches the held direction before the world
  steps and starts the next step in the same tick as the landing, so after
  steering inside `world.stepped` auto-walk re-reads the input into the world
  (`World:pollInput`). Verified in Crystal: without it every turn came one
  tile late, walks overshot by a cell and a 200X walk failed "Off the route".
  A carpet warp gets its own direction held. Cut, Surf, Whirlpool and
  Waterfall on the route are started with one A press facing the obstacle;
  the game asks, the walk pauses until the player answers, then resumes; asked
  again at the same place, it stops with the instruction.
- **Q** reads weekday, 12-hour time with AM/PM (as the Pokégear prints it) and
  morning, day or night. **Shift+E** on the Unown puzzle reads the held piece.
  Renaming uses Gen 2's naming screen.
- **Strength puzzles (Ice Path B1F, Blackthorn Gym 2F):** targets come only
  from the stone table the world is polling. Holes are listed "Hole N" with
  their state ("empty; Boulder 3 can reach it; next push right", "filled").
  The search covers the whole floor, so boulders in no row are pushed aside
  when they block ("push right to clear the way for Boulder 3"); stone-table
  boulders are never pushed into dead cells. The instruction also says what
  is missing (a Strength user, the Plain Badge, Strength switched on).

H and Shift+H read the Gen 2 battle's shown health (`battle.md`).

| Navigation check (2026-11-01) | Crystal | Gold | Silver |
|---|---|---|---|
| Bedroom, downstairs (Mom's scene interrupts, then "Resuming walk"), outside, a sign, the west connection, Route 29 at 200X with a ledge hop | yes | yes | yes |
| Journey Sprout Tower 1F to the 3F Potion: four floor changes, three trainer battles interrupting and resuming | yes | yes | yes |
| Cut (Route 30) and Surf (New Bark Town to Route 27) through the game's prompt | yes | yes | yes |
| Guided navigation (P) | yes | yes | yes |
| Ice Path B1F solved from the hints | 43 pushes | 47 | 46 |
| Blackthorn Gym 2F solved from the hints | 22 pushes | 22 | 22 |
| Ice Path 1F slides at game speed and 200X | yes | not run | not run |
| Keys, controller and renaming | yes | yes | not run |

Unit and cartridge tests: `gen2_nav_test.lua` 119/119;
`gen2_nav_cart_test.lua` 24/24 on each game's extracted cache (both puzzle
floors solved under the game's own push rule; with `GEN2_NAV_CACHE` unset it
reports NO CHECKS). Gen 1 unchanged: every access suite passes, the old
navigation suites keep their results (interactive objects 12/13 and world
snapshot 71/92 known gaps), and Red sweeps, elevators, a battle walk and the
Yellow follower run matched. Re-run by the lead after merging (Crystal):
journey, trainer pauses, Surf prompt said once, guided navigation.

Gen 2 navigation gaps: whirlpool and waterfall routing are tested without a
game run; auto-walk to a connection stops on the edge cell (as in Gen 1;
stepping across in both generations is an owner call); Area lists item balls
only; custom names live in Gen 2's shared options block, so they apply to
every Gen 2 save, and renaming keeps 10 characters.

## Verification

| Area | Level reached |
|---|---|
| Baseline (2026-11-01) | Game run, Crystal and Gold, new game to a wild battle (`drivers/gen2_walkthrough.lua`): only TextBox dialogue spoke before this work. |
| Info screens | `gen2_info_test.lua` 106/106. `drivers/gen2_info.lua` run in Crystal, Gold and Silver (identities `pocket-access-info-<game>`): every section reached and spoken. Not run: Softboiled target mode, the battle party list, phone DELETE, out-of-area calls, Buena's Password station, Kanto on the map and AREA screens, the dex PRNT action. |
| Special screens and minigames | `gen2_special_test.lua` 135/135 (checks that `Mail.lines`, `Mail.mailbox` are never called and decorations are never created by reading). `drivers/gen2_special.lua` run in Crystal, Gold and Silver (identities `pocket-access-special-<game>`): every screen reached. The driver forces some state (party, coins, decorations, mail, a Hall of Fame team, the first spin's reels); the contest, Battle Tower, Buena, mail and Union list screens were opened directly, not through their scripts. Unit tests only: some slot tells, Gen 2 Union prep (needs a second player), the arena failure message. |
| Menus and boot | `gen2_menus_test.lua` 122/122. `drivers/gen2_menus.lua` traced Crystal (three runs), Gold and Silver (identities `pocket-access-menus-<game>`); Gold's vending step not reached in that run (traced in the other two). The vending, elevator and Bank of Mom scripts were started by key; evolution and the egg were pushed directly. Re-run in Crystal after the lead's shared fixes: Mom's line says "cute POKéMON", and the re-shown yes/no question is said once, then "YES". Unit tests only: contest status, coin boxes, grid script menus. |
| Items and PCs | `gen2_items_test.lua` 110/110. `drivers/gen2_items.lua` traced Crystal (173 utterances), Gold and Silver (identities `pocket-access-items-<game>`); the tutor is Crystal only. Re-run in Crystal after the lead's covered-screen hook: "Release PKMN?", then "NO". Not run: the pack in battle, bargain and herb shops, the bedroom PC, OAK's PC and HALL OF FAME rows, the swap question, the World-driven Blackthorn deleter (pushed directly). |
| Heard by the owner | Not yet. |

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
