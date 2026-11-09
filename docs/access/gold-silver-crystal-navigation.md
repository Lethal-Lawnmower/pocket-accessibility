# Gold, Silver and Crystal: navigation

Gen 2 differences for navigation (decision 27). Gen 1 behaviour is in
`navigation.md`; Gen 2 screens and open questions are in
`gold-silver-crystal.md`.

## How it works

The same commands, object list, guided navigation, auto-walk, journeys,
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
- **Object list:** signs are named by what they are or what they say ("Route 31, Violet City,
  Cherrygrove City" from a jumptext's capital lines); "Signpost N" by bg event ordinal only when a
  script says nothing (8 entries, cable club rooms; a sign's script key is a ROM address and never
  spoken); a sign on a bookshelf, PC, TV or
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
  morning, day or night. **Shift+E** on the Unown puzzle read the held piece until decision 46 removed it.
  Renaming uses Gen 2's naming screen.
- **Chase (decision 40):** walk to an object, talk to it; if it runs off, auto-walk again
  keeps after it (`nav/Chase.lua`). `drivers/gen2_chase.lua`, harness pressing A in text:
  the game set `EVENT_HERDED_FARFETCHD` in Crystal (33 presses), Gold (19), Silver (36);
  counts vary with the sides tried. `tests/access/chase_test.lua` 9/9. Owner accepted in Crystal, 2026-11-03; Gold and Silver not played.
- **Boulders in the way (decision 41):** a target with no route tries pushes that open one.
  `drivers/gen2_boulders.lua`: from Cianwood Gym's door, one auto-walk reached Chuck in Crystal,
  Gold and Silver, 3 pushes, with trainer battles; no Strength says so; setting off says "No route".
  By script, with a strong lead. Owner accepted in Crystal's Cianwood Gym, 2026-11-03. A search can be wrong about a floor's script, for
  example a floor whose boulders are meant to stay.
- **Warps apart (2026-11-03):** the owner found only "a way out" in Tohjo Falls. Its two exits to Route 27
  were merged as one target. Gen 2 now keeps non-adjacent warps to one map apart ("entrance 1 of 2"). On a copy
  of the owner's save, by script: falls entrance 1, then exit 2, across Surf and Waterfall to Route 27's east
  side. The journey from the west side to Route 26 now runs, through the falls, in all three games: journeys
  use field moves once walking fails, and the old walk into the falls and back out was a plan leaving a door
  cell sideways, across the water (fixed, below). By script; not heard.
- **Filling holes (decision 41):** with AUTO-WALK PUZZLES on, auto-walk to a boulder or hole on a
  stone floor fills it: `drivers/gen2_stone_auto.lua`, by script in all three games, Ice Path B1F 42 to
  46 pushes, Blackthorn 2F 22, then "All the holes are filled". With it off, `gen2_nav_puzzle` follows the
  hints as before. Pushes run at 1X and a walk to a pushing cell lets go during its last step: at any speed
  the game starts the next step in the tick it lands, and the player walked past the cell or into a hole.
  The harness gave a strong lead with a Repel. Owner used it on Ice Path and Blackthorn Gym in Crystal, 2026-11-03.
- **Switches (decision 41):** a target with no route flips signs that ask to be turned on or off,
  and learns from the map. `drivers/gen2_switches.lua` on a copy of the owner's Crystal save, switches
  1 and 3 on: Switch 1, Switch 2, Switch 1, then the warehouse (all three on). An earlier run without
  the rule against flipping straight back took 27 flips. Gold, Silver and Crystal, teleported in by the room's
  own entrance with all switches off: one auto-walk reached the warehouse in 11 flips (23 before it tried the
  least-flipped switch first). The earlier refusal in Gold and Silver was the driver standing in the wrong part
  of the room. Owner accepted in Crystal, 2026-11-03; Gold and Silver by script.
- **Strength puzzles (Ice Path B1F, Blackthorn Gym 2F):** targets come only
  from the stone table the world is polling. Holes are listed "Hole N" with
  their state ("empty; Boulder 3 can reach it; next push right", "filled").
  The search covers the whole floor, so boulders in no row are pushed aside
  when they block ("push right to clear the way for Boulder 3"); stone-table
  boulders are never pushed into dead cells. The instruction also says what
  is missing (a Strength user, the Plain Badge, Strength switched on).
- **Shuffled doors (map randomizer, 2026-11-08):** the Crystal Randomizer's `maps` module rewrites
  `destMap`/`destWarp` in `data.gen2Maps` in place, per save (`launcher/mods/crystal_randomizer/MAPS.md`). The
  object list, door labels, auto-walk's arrival map and the journey planner already read the live warps on every
  capture and plan, so a door is named by where it leads now with no refresh. Two fixes: a planned map
  (`Navigation:regionalMap`, cached per map) is rebuilt when its warp list or records were replaced rather than
  rewritten; and a 0xFF "back" warp gives a planner edge only on the map the player is on, since the backup warp
  says where the player came in to that map only (elsewhere it was an edge to the last door used, such as a
  Pokemon Center 2F "leading" to another town). On the player's map it is still named and planned by the backup
  warp. Crystal has six 0xFF warps (Pokemon Center 2F, both elevators, Fast Ship 1F); house exits are explicit.
  `tests/access/gen2_map_shuffle_test.lua` 28/28 (4 fail without the fixes); `drivers/gen2_map_shuffle.lua` in
  Crystal swaps New Bark's neighbours' and Elm's house doors by hand: both named by their new houses, auto-walk
  through 3,11 arrives in Elm's house, a journey from there to the neighbours' house leaves by 3,11 and enters by
  11,13, vanilla names return after the swap is undone. By script, silent; not heard, not run with the mod itself.
  Not covered: a randomizer that replaced the records of the map the player stands on would leave the game's own
  live map firing the old warps; labels follow `def.warps`, so the two would disagree until the map reloads.

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
stepping across in both generations is an owner call; on a journey it steps across); Area lists the
area's other floors and its item balls; targets no one can ever reach are not listed; custom names live in
Gen 2's shared options block, so they apply to every Gen 2 save, and renaming keeps 10 characters.

## Audit of the three editions (2026-11-01)

Silent runs, identities `pocket-access-audit-<game>`.

**Label sweep.** `gen2_nav_cart_test.lua` builds every map's object list
from a new game's flags: 388 maps and 3484 labels in Crystal, 368 and 3309
each in Gold and Silver. No Unknown, nil, raw id, ROM address, empty or
placeholder label; every warp, return warp and connection resolves; the
"Needs" texts match the game's badge table; 103 (Crystal) and 113 (Gold,
Silver) planned ice slides replay correctly by the game's own rule. Changes
made from it:

- Pokémon objects take the species their own script cries (the cartridge
  reuses species sheets: Miltank drew as "Tauros", Farfetch'd as "Moltres");
  a sheet with no cry says "Pokémon".
- Signs running a standard script or special take its name (Bookshelf,
  Trash Can, Gym Statue, Pokémon Center Sign, Mart Sign, Radio, PC, Unown
  Puzzle and others); the elevator panel is the Floor Panel; neighbouring
  signs with one script are one object (the Rocket base transmitter was 20
  signposts). Crystal's "Signpost N" entries fell from 568 to 365.
- The player's sheet on someone else is "Trainer"; pose and size variants
  name the person; an unnamed rival ("???") is "Rival"; PP, HP and compass
  points keep their spoken form (shared with Gen 1 item names).

**Editions.** Gold and Silver's map data are identical, label for label;
their scripts and text differ (edition-exclusive events). Crystal adds 21
maps: the Battle Tower, Dragon Shrine, the department store roof, the Poké
Seer, eight Ruins of Alph rooms, three mobile rooms and Wise Trio's Room
(Gold and Silver call that room Ecruteak Tin Tower Back Entrance). The 64
shared maps whose objects differ are game data (items, Crystal's added
people, Burned Tower 1F holes, the beasts' sheets). The layer keys on map
ids, so Crystal's shifted map numbers never reach a label.

**Story spots** (`drivers/gen2_story_spots.lua`, `gen2_story_followups.lua`;
every gym, story dungeon, the League, Kanto, Mt. Silver, Crystal's Battle
Tower; every warp, item ball and person walked to from every entrance):

| Edition | Maps | Reached | Gated by the game | Blocked by the layer |
|---|---|---|---|---|
| Crystal | 123 | 640 | 30 | 0 |
| Gold | 111 | 569 | 31 | 0 |
| Silver | 111 | 570 | 31 | 0 |

Gates: story states (Sprout Tower's rival, Slowpoke Well once cleared, the
Rocket base Lance scene, the Ilex Forest Revive behind the Farfetch'd, the
Fast Ship captain), the Rocket base passwords, the Goldenrod Underground
switches, Rock Smash rocks in Dark Cave (behind Flash since decision 37; see
`navigation.md`, "Dark maps"), and layout (Olivine Lighthouse 3F
Ether, reachable only from 4F's ladder; Gold and Silver's Burned Tower B1F
TM; Saffron Gym's pads; Diglett's Cave behind Snorlax). Follow-ups in all
three editions: Blackthorn 2F solved from the hints (22 pushes), then
Clair; Cianwood Gym after three Strength pushes, then Chuck; Ice Path B1F
solved from the hints. Lance's walk runs on through the Hall of Fame.

**Fixed from the runs** (both generations unless noted): ice slides and
currents that reach a warp carry the player onto it (Gen 2); auto-walk stops
after being turned back to the same cell three times ("Turned back again,
auto walk stopped"; Tin Tower sages); the turn to face a field move runs at
1X, so a fast AUTO-WALK SPEED no longer steps onto the waterfall; a person
who moved during a scene is followed, and one who left ends the walk ("<name>
is gone"); planner reasons are said in words ("No route to <target> from
here", "Could not plan a route to <target> in time"). Tests:
`gen2_nav_test.lua` 147/147, `auto_walk_test.lua` 47/47,
`gen2_nav_cart_test.lua` 35/35 on each edition's cache. Gen 1 rechecked by
the lead after merging: Red auto-walk battle and elevators, the Yellow
follower (identical to its baseline once the window was isolated: unisolated runs
failed at random because the game window took real keystrokes, which stop
auto-walk; `AGENTS.md` now requires `drivers/isolated.lua`).

**Audit gaps:** auto-walk does not smash rocks (the player walks there and acts); journeys do not plan
elevators (Goldenrod's Dept Store B1F is only reached that way), boulder pushes on a floor they cross (Ruins of
Alph's Omanyte side, through Union Cave's boulders), or scripted rides (Fast Ship, Magnet Train, Battle Tower).

## Every edition, every map (2026-11-03)

The owner asked that whatever works in Crystal also works in Gold and Silver. Everything below ran in each game
on its own maps, silent, identities `pocket-access-navg2-<game>`; a teleport or a set flag is the harness, walks
and answers are the layer. Level reached: run in game by script. None of it was heard.

| Feature | Driver | Crystal | Gold | Silver |
|---|---|---|---|---|
| Farfetch'd chase, Ilex Forest | `gen2_chase` | passed | passed: the game sets herded | passed: the game sets herded |
| Lighthouse to the top and back, 4 trips | `gen2_lighthouse` | passed | passed | passed |
| Rocket Base names | `gen2_editions` rocket | Locked Door, transmitter, statues | same | same |
| Rocket Base doors: refused, opened with passwords, list refreshes | `gen2_editions` rocket | passed | passed | passed |
| Boulder pushing, Cianwood Gym to Chuck, 3 pushes | `gen2_boulders` | passed | passed | passed |
| Hole filling: Ice Path B1F, Blackthorn 2F | `gen2_stone_auto` | 42, 22 pushes | 46, 22 | 46, 22 |
| After the holes, journey to Ice Path B3F | `gen2_stone_auto` | passed | passed | passed |
| Goldenrod Underground switches, all off to the warehouse | `gen2_switches` | fixed, 11 flips | fixed, 11 flips | fixed, 11 flips |
| Rocket Base "Secret Switch" | `gen2_editions` | named | named | named; no route depends on it |
| Tohjo Falls exits apart, each walked | `gen2_editions` tohjo | passed | passed | passed |
| Route 27 west to Route 26, through the falls | `gen2_editions` tohjo | fixed | fixed | fixed |
| Signs named | `gen2_nav_sweep` | fixed: 8 left | fixed: 8 left | fixed: 8 left |
| Tin Tower to the roof, with the story's flags set | `gen2_editions` journeys | passed; its stairs come with the beasts' scene | passed; a sage stands on the stairs before that | same as Gold |
| Burned Tower 1F to B1F, with the story's flags set | `gen2_editions` journeys | passed; its holes come with the rival | passed | passed |
| Legendary beasts | `gen2_story_spots` | named Raikou, Entei, Suicune | "Pokémon": their sheets are Growlithe's and their scripts cry nothing | same as Gold |
| Vermilion Gym | `gen2_editions` surge | Surge walked to, no gates | same | same |
| Vermilion's trash cans as switches | data read | not applicable | not applicable | not applicable |
| Saffron Gym's pads, door to Sabrina | `gen2_editions` kanto | fixed | fixed | fixed |
| Kanto's other gyms, door to leader | `gen2_editions` kanto | passed | passed | passed |
| Every text box | `gen2_text_sweep` | passed: 3988 | passed: 3031 | passed: 3031 |
| Crystal-only maps | `gen2_nav_sweep`, `gen2_story_spots` | listed and walked | not applicable | not applicable |
| Gold and Silver's Tin Tower Back Entrance | `gen2_story_spots` | not applicable | reached; the sages turn the player back, as scripted | same |

Vermilion Gym's cans in Gen 2 are not a puzzle: each one's whole script is one line of trash text, no switch, no
gate, Surge's way is open. So FireRed's hidden-switch search is not added; they are named "Trash Can" and left.

`gen2_text_sweep` shows every string of the edition's text table through `World:showText` and compares what
reached `Speech.say`. At the harness's speed a handful of one-word boxes were missed (4 to 7, not the same ones
each run); each was then shown alone with time around it and read. All three have the same token set. This covers
the box, not each script's way of opening one; silent, so Prism's own refusals are not seen.

**Whole-map numbers** (`gen2_nav_sweep`: every map stood on, every list item, journeys to every other floor of its
area with every field move and badge, from a new game's flags):

| | Crystal before | Crystal after | Gold before | Gold after | Silver after |
|---|---|---|---|---|---|
| Maps stood on | 389 | 389 | 369 | 369 | 369 |
| Journeys planned | 578 | 578 | 402 | 402 | 402 |
| Timed out | 28 | 0 | 18 | 0 | 0 |
| Refused | 247 | 89 | 128 | 39 | 39 |
| Slowest plan, CPU seconds | 1.50 | 0.47 | 1.50 | 0.44 | 0.50 |
| Listed but out of reach: door, wall or puzzle | 71 | 47 | 65 | 41 | 41 |
| Listed but out of reach: a person or boulder | 39 | 39 | 38 | 38 | 38 |
| Warps standing apart merged into one entry | 0 | 0 | 0 | 0 | 0 |

"Before" for journeys is the shared planner, with the other fixes in place. Signs: 365 "Signpost N" in Crystal's
audit, 332 in Gold and Silver by the same count before this pass, 8 in each now, by list item.

The refusals left, read one by one in Gold: story or puzzle gates (Tin Tower's sage, Route 5 and 6's officer, the
underground's locked doors, Ice Path before its holes are filled), rocks and boulders, elevators, unused maps
(Safari Zone Beta) and scripted rides. Crystal adds its Ruins word rooms and Battle Tower rooms. A refusal from a
new game's flags is not a bug by itself.

`gen2_story_spots`, with Flash kept set (the driver reaches the same places the new way): Crystal 660 reached, 26
gated, 22 "blocked"; Gold and Silver 589, 26, 23, line for line. Read one by one, the "blocked" are story scenes
that turn or take the player (Tin Tower's entrance sages, Fast Ship, Slowpoke Well's end, Lance's scene, the Hall of
Fame, a beast that runs) and walks that ended at this driver's frame limit while pushing or flipping under its own
speed multiplier, which `gen2_stone_auto` and `gen2_switches` prove at game speed. One Crystal walk in Vermilion
City stopped "Blocked" behind a wanderer, not repeated in two reruns; a walk now plans around a blocker three times
before saying so. The earlier "blocked 131" in the shared sweep were these, plus dark floors the driver had not lit.

Regressions for the shared files, by script: Red `navigation`, `journeys`, `elevators`, `autowalk_battle` no
failures, FireRed `gen3_nav`, `gen3_nav_gaps` and `gen3_surge` no failures; `gen3_switches` no failures in its first
500 seconds, where this run's limit closed it, past the Mansion floors. `auto_walk_test` 64/64, `gen2_nav_test`
159/159, `gen2_nav_cart_test` 40/40 on Gold's cache.

**Fixed from these runs** (all three games):

- *Journeys timed out on warp-heavy floors* (Ice Path, Dark Cave, Whirl Islands). The shared planner ran a route
  per transition per map. `gen2/Journey.lua` walks each map's graph once; a walk inside the building comes first,
  then anywhere, then field moves, and a goal only a missing move could reach says "Needs ...".
- *Plans left door, stair and cave cells sideways.* The game walks the player down off them whatever is held; a
  plan took Tohjo Falls' door across the water and turned back. Now only down.
- *Journeys walked up and down for ever on a mat.* Starting on the warp a leg needs, the walk steps off and back;
  the step off stayed in the list, and a mat fires only with its direction held. `AutoWalk` drops it and holds.
- *Connection legs pushed the wrong way.* A leg ending on a map's edge pushed the direction of its last step.
- *"X is here" for a journey that had not begun*, standing on the leg's own warp or edge.
- *A warp that lands on the same map* (Saffron Gym) never counted as the next leg: the map did not change.
- *A floor in the Area list was aimed at through its first warp*, refused whenever that warp was behind something.
  It now means getting onto the floor by any way in.
- *336 signs were "Signpost N"*: a single `jumptext` was not read. Signs now read their own text, what they say on
  their own way through before their branches ("Trash Can" for a can that only says trash).
- *Connections no one can use were listed* (Azalea to Route 34, Route 31 to Violet City: the way is a gatehouse),
  and furniture no one can reach (a Mart Shelf behind the counter). `Navigation:dropUnreachableTargets`.
- *Switch trying took 23 flips* from all off, in list order; 11 trying the least-flipped first.
- *A wanderer standing in the way ended the walk* with "Blocked". It plans around them, up to three times.

Shared files touched: `nav/AutoWalk.lua` (same-map legs, edge direction, starting on the warp, the step-off fix, a
step off never lands on another warp, planning around a blocker), `nav/SwitchWalk.lua` (least-flipped first; Gen 3 uses it too). Not touched:
`Navigation.lua`, `WorldSnapshot.lua`.
