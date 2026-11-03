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
- **Chase (decision 40):** walk to an object, talk to it; if it runs off, auto-walk again
  keeps after it (`nav/Chase.lua`). `drivers/gen2_chase.lua`, harness pressing A in text:
  the game set `EVENT_HERDED_FARFETCHD` in Crystal (33 presses), Gold (19), Silver (36);
  counts vary with the sides tried. `tests/access/chase_test.lua` 9/9. Owner accepted in Crystal, 2026-11-03; Gold and Silver not played.
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

**Audit gaps:** auto-walk does not smash rocks or push boulders outside the
stone tables (the player walks there and acts); Cianwood Gym's boulders
have no push hints; the Goldenrod Underground switches, Vermilion Gym's
trash cans and the Ruins chamber statues stay "Signpost N" (their scripts
name nothing); single-map auto-walk does not take same-map pads
(Saffron Gym), as in Gen 1.
