# Navigation

Getting around the overworld: object list, pathfinding, camera ("sonar"),
terrain and footstep cues, puzzle help. Reused from the old project under
decision 20, adapted to v0.3.98. Status: wired into the game and working
for the core Pokémon Access commands; walking cues and wall bumps not yet
checked in a game run. Gold, Silver and Crystal run the same layer through
a coordinator subclass (`nav/gen2/`) and `nav/WorldAdapter.lua`; their
differences are in `gold-silver-crystal-navigation.md`.

## Reused modules (`src/access/nav/`)

Each file starts with an origin header naming the old file and commit
(`purple-gen1-gen2-preview`, `71cdd419`).

| Module | Role | Old tests ported |
|---|---|---|
| `Pathfinder` | Routes on one map | 60/60 |
| `RegionalPathfinder` | Routes across maps | 82/82 |
| `TerrainSemantics` | What a cell is (grass, water, ledge, door, bush...) | 131/131 |
| `TraversalSemantics` | Special movement (spinners, currents, holes) | (covered by snapshot) |
| `WorldSnapshot` | Map, player, warps, connections, signs, objects; the object list | 70/91, see below |
| `PuzzleAssistance` | Detours through puzzle rooms | 50/50 |
| `Navigation` | The old coordinator (`Accessibility.lua`), navigation half: commands, object list, routes, sonar, world events, renaming | commands 247/247, world events 37/37, journey 27/27, interactive objects 12/13 |
| `init.lua` | Creates the coordinator for a loaded Gen 1 game, speech adapter, key routing | (game run) |
| `Earcons` | Sound cues, optional bring-your-own Pokémon Access pack | 21/21 |
| `CommandRouter` | Pokémon Access keys behind a command layer (F7) | 193/193 |
| `CutTrees` | Read-only lookup of cuttable trees | via terrain tests |
| `ChaosCut` | Labels for the optional Chaos Cut mod (decision 21) | via snapshot tests |

Old tests live in `tests/access/nav/`. The ones that need generated game
data are run from inside a test identity's Red cache, with the repository on
`LUA_PATH`, so no ROM data is copied into the repository:

```
cd "$APPDATA/LOVE/pocket-access-run/red"
LUA_PATH="<repo>/?.lua;<repo>/?/init.lua;;" luajit "<repo>/tests/access/nav/world_snapshot_tests.lua"
```

## Adaptations so far

- `CutTrees`: upstream generates no `cutTiles` data. The lookup now falls
  back to upstream's own rule from `OverworldState:tryCut` (OVERWORLD tile
  0x3d, GYM tile 0x50). Fixed the one terrain failure.
- Dropped dependency: none of these modules patch game behaviour. The old
  fork's in-game Cut fix (`src/world/CutTrees.lua` used by the overworld) is
  not carried over (decision 10); only the read-only lookup is.

## Known gaps

- `world_snapshot_tests`: 21 failures cascade from one synthetic fixture
  warp (destination LAST_MAP) that v0.3.98's `Map:warpAtCell` /
  `isWarpTileCell` no longer report as active, so it drops out of the browse
  list and every later index shifts. To check against real maps once the
  object list runs in game; adapt the filter or the fixture then.
- Wall bumps (decision 24): only the game's own bump sound. The old spoken
  bump descriptions depended on a `world.bumped` event the old fork added to
  upstream; that code stays dormant.
- Interactive objects 12/13: the bedroom SNES does not appear in the object
  list (the PC does). Not yet investigated.
- Camera ("sonar") is off by default (decision 22): its keys pass through
  to the game and F8 help omits them unless `accessibilityCamera` is set in
  the save options. `CommandRouter.isCameraAction` decides which actions
  count; `tests/access/camera_option_test.lua` 8/8. No menu sets the
  option yet, and the camera path was not re-checked in a game run.
- Walking: step and terrain cues, ledges and continuous route guidance
  while moving have not been exercised in a game run yet.

## How it is wired (`src/access/nav/init.lua`)

- `Access.install` wraps `love.keypressed` *before* upstream: the old
  `CommandRouter` sees every key first and consumes recognised commands.
  F7 toggles the command layer (WASD is then reserved, arrows still move),
  F8 reads help, F6 repeats.
- The coordinator is created once a Gen 1 game is loaded (Game module with
  `save` and `data`) and re-created when the save or the mod event bus
  (`Runtime.events`) changes. It subscribes to upstream's `map.entered` and
  `world.stepped` events.
- Speech goes through an adapter over `src/access/Speech` (Prism). The old
  start-up line ("Screen reader ready. Press F6 to repeat. Press F7 for
  accessibility command mode. Press F8 for help.") plays once per game load.
- `updateNavigation()` (added) runs routes, events and cues each frame; the
  old `describe()` screen speech is not driven (new presenters do that).

## Other adaptations in the coordinator

- Speech stack replaced by the adapter (BackendLoader, Speech, SpeechTrace).
- T (read screen text) repeats the last screen speech from the new
  presenters (`Speech.lastScreenText`).
- Renaming (Shift+K, Shift+M) prefills upstream's NamingScreen glyph list
  with the current name; the old fork had added an initial-text option to
  that upstream file instead.

## Game run (2026-10-31)

`tests/access/drivers/navigation.lua` (keys sent through `love.keypressed`),
disposable identity `pocket-access-run`: F8 help, F7 on and off, map name,
position, object list with directions ("PC, 5 up 3 left"), filter change,
surrounding tiles, pathfinding start ("1 right"), and Pallet Town's warps
("Oaks Lab: 4 down 3 right"). Not yet heard by the owner.

## Controller (decision 23)

| Input | Action |
|---|---|
| Hold left trigger | Navigation modifier (on the map, the game no longer sees it, so it does not lower game speed; the left shoulder still does) |
| Left trigger + D-pad up / down | Previous / next object category (All, Warps, ...) |
| Left trigger + D-pad left / right | Previous / next object in the category |
| Left stick click | Auto-walk to the selected object; again to stop |
| Right stick click | Guided navigation to the selected object (the P command); again to stop |

Wired in `src/access/nav/init.lua` through `love.gamepadaxis`,
`gamepadpressed` and `gamepadreleased` wrappers that run before upstream.
D-pad presses used for navigation are marked with upstream's
`Input:padEventSeen`, so its pad polling does not also move the player.
The old router's own gamepad defaults (shoulders and triggers) are not
wired.

## Auto-walk (`src/access/nav/AutoWalk.lua`)

New, not reused. Uses `Navigation:selectedRouteGoals` (extracted from the
old `describeRouteToSelected`, so both aim at the same cells),
`worldRouteRequest` and `Pathfinder.find`. Each step's direction is held on
upstream's `Input` as its own source (`access_autowalk`) and released at the
next cell. Speaks "Walking to ...", then "Arrived at ..." with the
interaction hint (for example "Face up and interact"), or why it stopped:
blocked for 90 frames, off the route, or any key or button pressed while
walking.

Route policies: plain walking first, then the old coordinator's policy 2
(HMs the party knows, card-key doors with the Card Key), as guided
navigation does. Pushed off the route (spinner, current) it re-plans
quietly, up to 8 times per walk. It lets go and waits while a spinner
slides or a door or stair transition runs (`spinnerSliding`,
`player.spinning`, `transitioning`). A closed card-key door with the key in
the bag is faced and opened with one A press (upstream opens them in its A
interaction, `OverworldState:tryCardKeyDoor`).

Battles pause it and it resumes afterwards (owner request, 2026-10-31):
any screen opening pauses the walk and releases the direction; returning to
the same map recomputes the route from where the player stands and says
"Resuming walk to ...". Extended from battles to every game-caused
interruption (card-key door messages, scripted text) so doors do not end
the walk. A
trainer walks over on the open map first, so upstream's
`world.trainer_engaged` event pauses the walk immediately and it waits for
the battle. A changed map after a battle (blacked out) stops it.
Presses during the battle do not cancel the paused walk. A door or staircase counts as arrival when its transition opens on
the destination cell.

Verified: `tests/access/auto_walk_test.lua` 23/23 (including pause and resume);
`tests/access/drivers/nav_controller.lua` game run: trigger plus D-pad
cycled categories ("Warps", "All") and objects, left stick click walked to
the PC ("Arrived at PC. Face up and interact") and in a second run took the
stairs ("Arrived at AAAAAAA's House 1F"), right stick click started and
stopped guided navigation. Not yet tried with a physical controller or
heard by the owner. `drivers/autowalk_battle.lua`: walking north on
Route 1, a wild PIDGEY interrupted, the battle played normally, and after
"Got away safely!" the trace says "Resuming walk to North connection to
Viridian City". The trainer path is unit-tested only.

## Hard-places sweep (`tests/access/drivers/hard_places_sweep.lua`)

Auto-walks to every warp and item ball on the maps most likely to break
navigation when finishing Red, from each map's entrances, winning battles
on the way. Run silently with `POKEPORT_ACCESS_SILENT=1` (logs speech,
never sends it to the screen reader); `SWEEP_MAPS` limits the maps.

Results, 2026-10-31 (after the fixes above):

| Map | Result |
|---|---|
| Safari Zone West | All 9 reached, including the Gold Teeth ("Arrived at Gold Teeth. Face left and interact"); some only from the matching entrance |
| Safari Zone Center | All exits reached; the Nugget reports no path from every entrance (not yet checked by hand) |
| Rocket Hideout B2F, B3F | All reached, across spinner floors, including the elevator |
| Silph Co. 5F, 7F, no Card Key | All reached except the Protein and TM Swords Dance, which are behind locked doors |
| Silph Co. 5F, 7F, with Card Key | All reached; locked doors opened on the way |

History: the first run reached 9 of 63. Causes were the sweep teleporting
during a door transition (frozen player, a harness bug), auto-walk stopping
on spinners, trying only plain walking, and not opening card-key doors.
An early run also sent its speech to the owner's screen reader and looped
on a no-damage move; both were fixed in the sweep (silent mode, a damaging
move, healing, a battle time limit).

### Required story spots, 2026-10-31

Same sweep with gyms targeting their trainers (`people = true`), plus two
follow-up drivers: `victory_road_tower.lua` (solve the Victory Road 1F
switch by following the boulder hints; Pokémon Tower with the Silph Scope)
and `elevators.lua` (ride each car: door, panel, floor menu, exit).
All runs silent.

| Spot | Result |
|---|---|
| Viridian Gym (spinners) | Every trainer, Giovanni, the Revive and both statues reached |
| Saffron Gym (pad maze) | Sabrina and every trainer reached; every pad reached from some pad |
| Vermilion Gym | All 15 trash cans reached; Lt. Surge "Cannot reach yet" behind the gate, as in the game. Finding the two switches is left to the player; no puzzle hint |
| Cinnabar Gym | Quiz machine 1 and the first trainer reached; everything behind the quiz doors "Cannot reach yet" (doors closed in a fresh save; opening them was not run) |
| Victory Road 1F | The switch is listed with "Boulder 1 can reach it; next push down". Selecting Boulder 1, auto-walking to it ("Arrived at Boulder 1. push down toward Pressure Switch 1") and pushing the hinted way put it on the switch; auto-walk then reached the 2F ladder |
| Victory Road 2F, 3F | Every target reached except the 3F boulder drop hole (needs a boulder). Their switches were not solved in a run |
| Pokémon Tower | With the Silph Scope: 5F Nugget, all 7F Rockets and Mr. Fuji reached. Without it the ghost battle never ends, as in the game |
| Elevators (Celadon, Silph, Rocket Hideout) | Door, then "Floor panel", then "Which floor do you want? 1F, 1 of 6", then the chosen floor named as the car's exit. The exit mat needs one press down after "Arrived", as in the game |

Fixed in this pass:
- Interaction cells skip the map's own warp tiles unless no other cell
  works (`Navigation:interactionGoals`). Auto-walk to the Rocket Hideout
  panel had stepped onto the car's exit and left the elevator.
- Elevator panels are named "Floor panel" instead of "Signpost 1"
  (`WorldSnapshot`, sign list).

Harness notes: "is here" means the player already stands in position (the
boulder loop counts it as arrived). A single-frame push tap sometimes only
turns the player, so the boulder took 28 taps; a held press is what a
player does. "Pallet Town is here" on gym exits is the teleport's stale
last map, not a game state.

Not covered: Seafoam boulder puzzles, the Victory Road 2F and 3F switches in
a run, opening Cinnabar's quiz doors, and Surf or Cut in auto-walk (it stops
when blocked).

## Auto-walk speed (decision 26)

OPTIONS, ACCESSIBILITY, AUTO-WALK SPEED: GAME SPEED (default) or a level of
the game's own speed ladder (NORMAL to 200X).

- `nav/WalkSpeed.lua` sets `game.speedOverride` only while
  `AutoWalk.walking()`; a battle, dialogue or any screen pauses the walk and
  hands the speed back, so battle and menu speeds stay the player's. The
  previous value is restored unless something else (skin fast-forward)
  changed it meanwhile. Link play and fixed-speed minigames still lock 1X.
- **Steering per tile.** At 20X and above one real frame covers several
  tiles, and the per-frame update ran the player past every turn (trace:
  held "down" from (7,1) to the wall at (7,7), then rerouted back up onto
  the stairs). Auto-walk now also steers from upstream's `world.stepped`
  event (`AutoWalk.stepped`), which fires inside the game's step when a
  tile is finished, before the next step reads input. The per-frame update
  still handles arrival, reroutes, doors, warps and pauses.
- **Arrival at warps:** a walk to a warp also counts as arrived when the
  map it leads to is reached (`targetMapId`); at speed the last step can
  pass between two updates, which had reported "Left the map".

Verified 2026-10-31: `settings_test.lua` 22/22, `auto_walk_test.lua` 30/30.
`drivers/settings.lua` (silent): logic speed 200 while walking and 1 after;
"Arrived at AAAAAAA's House 1F" at 200X; Mom reached from the stairs at
200X. Hard-places sweep at 200X (`SWEEP_SPEED=200`) on Viridian Gym and
Silph Co. 5F: every target reached that is reached at normal speed. Owner
tried the page 2026-10-31 and approved pushing ("It looks real good").

Regression found in the Red, Blue and Yellow audit (2026-10-31): steering
on `world.stepped` let go of the direction on the last cell, and warps that
fire only while pressed (the Rocket Hideout elevator door, entered moving
down) stranded the player on the door, in Red and Yellow alike. A walk to a
warp now keeps pressing on its last cell; other walks still let go there so
a fast speed cannot overshoot. `drivers/elevators.lua` rides all three cars
again in both games. Blue: a short sweep (Safari Zone West, Viridian Gym,
Silph Co. 5F) matches Red; Yellow results are in `yellow.md`.

## Cross-map journeys (decision 25)

- **Area category** (`Navigation:areaBrowse`): the last object category.
  Lists item balls still in place (the old `regionalObjectVisible` skips
  collected items) on the other maps of the current area, named with their
  map, for example "Gold Teeth, Safari Zone West". An area is every map
  sharing the first two words of its id (SAFARI_ZONE_*, SILPH_CO_*,
  ROCKET_HIDEOUT_*); a group needs at least two maps. Built from map data
  only.
- **Guided navigation** to an Area target (`startAreaJourney`) starts the
  old cross-map planner (`regionalNextLeg` / `startRegionalLeg`) directly;
  its map-entry handling continues leg to leg.
- **Auto-walk** to an Area target asks the planner for each leg, walks it,
  and on each new map plans the next leg. On a leg's transition cell it
  keeps pressing into warps that fire only while pressed. When a teleport
  pad lands it on the pad the next leg needs, it steps off and back on. A
  map change counts as arrival only when the player was finishing the
  route; otherwise a journey re-plans and a single-map walk reports
  "Left the map".
- **Inactive data warps:** map data lists some warps the game never fires
  (Silph Co. 1F has one to 3F off any warp tile). The planner now skips
  them with the same rule the object list uses
  (`WorldSnapshot.browsableWarp`, shared).

Verified 2026-10-31: `auto_walk_test.lua` 30/30 (two-map journey);
regional 82/82, journey 27/27, puzzles 50/50 still pass;
`drivers/journeys.lua` (silent): Gold Teeth from Safari Zone Center
(Center, East, North, West, arrived), Card Key from Silph Co. 1F (1F, 2F,
3F, 5F, pad to 9F, pad back to 5F, arrived), guided navigation to an Area
target started ("2 up"). Not yet heard by the owner. Area lists only item
balls; other targets (NPCs, specific doors) on other maps are not offered.
