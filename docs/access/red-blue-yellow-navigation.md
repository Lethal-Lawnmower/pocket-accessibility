# Red, Blue and Yellow navigation

Split from `navigation.md` on 2026-11-03, which still has the shared design.

## Crystal's puzzles in Red, Blue and Yellow (2026-11-03)

The owner asked that what Crystal got also works here, so nobody reports "it doesn't work in
Red". `nav/gen1/Navigation.lua` is a subclass of the shared coordinator, as Gen 2's is, and
`nav/BoulderPlan.lua` is its Strength search. Results are in the tables below; none of it heard,
none owner tested.

| Feature | State | How |
|---|---|---|
| Auto-push, holes, switches on a floor | Built | Auto-walk to a boulder, hole or switch does the floor; a target only boulders block gets its way opened and is then walked to. Any boulder may fill any target, as in the game. Holes come from `field.seafoam`; Victory Road's switches stay in `PuzzleAssistance`'s table, because their cells exist only in upstream's script closures. Strength is switched on through `useStrengthFieldMove`: Gen 1 has no A prompt. AUTO-WALK PUZZLES is now on the page in every generation |
| Seafoam holes listed | Built | "Hole 1" and so on, under Objects, with state. Floor holes (Seafoam, Mansion 3F, Victory Road 3F) are no longer walked onto by accident: they are walkable tiles with no warp, and routes crossed them |
| Mansion switches | Built | `switchSigns` over `TraversalSemantics`; quiz machines are excluded, since they have an answer |
| Lt. Surge's cans | Built | `hiddenSwitchSigns`, `floorMarks`. Presses, not `save.trashPuzzle.second`: first even cans (the game rolls `Random & $e`), then the neighbours of the can that worked (`trashCans.adjacent`, `yellowTable`) and can 0 (the known bug). `save.trashPuzzle.first` is read only once the game has said the first lock opened |
| Warps kept apart | Built | `WorldSnapshot` no longer gates on generation. 23 merged pairs in Red before, 0 now: Pewter Museum's two doors, the S.S. Anne cabins, Route gates' two sides |
| Signs by their own text | Built | `Sign: ` and the first page, the next page too if the first is short (22 signs start "TRAINER TIPS!"); screens with no text are named from their id ("Vending Machine 1", "TV") |
| Door names | Built | Rocket Hideout's lift gates are in `field.cardKeyDoors` but open by beating guards: they said "Needs Card Key" and a route with the key pressed A at them. Now "Lift gate; closed until this floor's guards are beaten". Silph Co. keeps "Closed Door". Pads on one floor are "Teleport pad N; lands 8 up 4 left from it". Spinner tiles stay unlisted, handled by routes |
| Field moves on a walk | Built | `stepInteraction` with `use`: calls what the party menu calls, after the same checks. Game text is the player's A |
| Journeys | Built | `autoWalkJourneys` on; walking first, then field moves; floors in Area; one flood per floor per plan (`regionalFlood`). Holes are ways down on Mansion 3F and Victory Road 3F |
| Text boxes, UTF-8 retry | Already shared | `Speech.say` is generation-neutral. Silent runs cannot show it |

Limits: a journey does not do a puzzle on the way. Victory Road's floors say "No route" until the
floor's switch is on, and the Mansion's B1F until a switch is flipped. Cinnabar's quiz doors stay
the player's; auto-walk says "Behind doors the quiz machines open". A Seafoam boulder only falls
to the floor below, so each lower floor's boulders appear after the one above is done.

## Whole-map audit of Red, Blue and Yellow (2026-11-03)

`drivers/gen1_nav_sweep.lua` lists every target on every map and asks for a route from every way
onto the map. `drivers/gen1_nav_walk.lua` really walks to each and checks the outcome (a warp must
change the map, a connection must cross when pressed). `drivers/gen1_puzzles.lua` runs the cases
above. Unit: `gen1_nav_test.lua`. Level reached: run in game, silent, with the harness teleporting and
giving a party with badges.

| Whole-map numbers, last run | Red before | Red | Blue | Yellow |
|---|---|---|---|---|
| Maps, listed targets | 224, 1835 | 224, 1912 | 224, 1912 | 225, 1933 |
| "Signpost N" | 201 | 0 | 0 | 0 |
| Warps to one map merged though not side by side | 23 | 0 | 0 | 0 |
| Connections with goal cells that bump (land, counted on water too before) | 47 | 0 | 0 | 0 |
| Targets with no standing cell at all | 7 | 3 | 3 | 3 |
| Targets no route reaches from any way onto the map | 33 | 38 | 38 | 42 |
| Walks | 1704 | 1681 | 1684 | 1702 |
| Walks ending as they should | 1576 | 1656 | 1662 | 1676 |

The target counts rise with the list (separated warps, holes). What the 25, 22 and 26 failing walks
are: story gates turning the player back as they should (Elite Four rooms, Cinnabar Gym's lock, the
thirsty guards, a gate with no Bicycle, the S.S. Anne with no ticket, the Safari game ending), Seafoam's
currents with no boulders down, and a harness start on water at B4F. Three said "Cannot reach" just after
a rival's scene; a retry now waits for him to walk off (those maps rerun in Red: 92 of 92). Yellow's first run
was thrown out after a walk into the Hall of Fame restarted the game; the driver now skips that door.

Puzzles, run in all three games by `gen1_puzzles`: Seafoam 1F, B1F, B2F, B3F holes (B1F and B2F need their
second boulder from the other side; the walk says so); Victory Road 1F, 3F, 2F switches, 3F's drop and 2F's
second switch; Rare Candy behind boulders on Victory Road 1F and in the Warden's House; Diary, Secret Key and
TM Solarbeam by flipping; Lt. Surge from the door in 7, 10 and about 70 can presses (one run each, so no
range is claimed); Surf off Pallet and, in Red only, Cut with no Surf at Vermilion Gym's tree. No Strength: "Boulders block
the way. Teach Strength"; no Cut or Surf: "Needs Cut and Surf". Area, from each dungeon's first floor (Red and
Yellow): superseded by the table in "After merging all three games", below.

Regressions, on the merged code: Red and Yellow `elevators`, `dark_maps`, `nav_controller`; Red `journeys` (Gold
Teeth, Card Key), `navigation`, `autowalk_battle`, `npc_category`, `settings`, `victory_road_tower`; Yellow
`yellow_follower`; Crystal `gen2_nav`, `gen2_boulders` (Chuck by 3 pushes). All access unit suites pass; `gen2_menus_test`'s
real-screen line now expects 3 rows. Old suites: as before except `Route 23 exposes...` (it asks for Objects, which
decision 35 moved to NPCs; not new). `hard_places_sweep` not rerun; no FireRed ROM on this machine for a run (unit only).

Bugs found by walking, all fixed:

- **Exit mats reached sideways** said "Arrived" and stayed in the room: pressed outward now
  (`warpPressDirection`, from upstream's `Warp.extraCheck`). Standing on the mat already: same press.
- **Standing on a door or stair** said "is here": a step off and back on, as the game needs.
- **Stairs taken straight back at a fast speed:** a held direction on landing fired the arrival
  stairs (Celadon Mart, Silph Co.). `map.entered` now lets go inside the game's step.
- **Ledge chains at a fast speed** hopped past the turn, with no way back (Route 4): hops run at 1X.
- **Mid-hop tile read as off the route** ("Cannot reach"): `transitioning` includes `ledgeHop`.
- **Cut through a tree block's fence cells:** only the tree's tile counts now.
- **Water tile numbers indoors:** routes crossed Museum and Mansion walls with Surf.
- **Connection cells that bump:** Pewter's south edge has 2 cells in 28 that cross. Goals are only
  cells that land somewhere passable; Route 22's north edge, with none, is no longer listed.
- **Pads on one floor** re-planned after the jump and said "Cannot reach": the jump is the arrival.
- **Stall behind a wandering person:** plans round them after 45 frames, before "Blocked".
- **A guard's text on a door's last cell** counted as arrival: it pauses, like other text.
- **A journey's way on underfoot** said "is here" (Rocket Hideout, 0 of 13 Area targets to 12 of 13).

Leads closed:

- `nav_controller` "auto-walk took the stairs": a harness failure, not a game one. `isolated.lua` makes
  `love.gamepad*` no-ops, so nothing arrived. The driver now uses the module's handlers; passes in Red
  (sweep summary before: fail on Red and Yellow).
- Yellow "No route to Signpost 1" in Cerulean: true. Guard 2 stands in the only way until the story moves
  him. It now says "Sign: CERULEAN CITY...: Blocked by Guard 2".

Still listed and unreachable, on purpose or by story: Fuchsia's pen Pokémon and its fenced sign, the
Bird on Copycat's wall, Yellow's Chansey and clipboard behind Pokémon Center counters, Safari rest
houses' PCs, link-room Opponents, and the Union Room's unnamed object (cable club only).

## After merging all three games (2026-11-03)

All three navigation branches merged on `integration-parity`, then every game's drivers rerun on disposable
profiles, hidden, silent. By script; nobody has heard or played it. Harness setup teleports and gives parties.

Found by that rerun. Neither came from the merge: both also failed on the Gen 1 branch alone.

- **Route 12, four targets:** "Turned back again". The walkway takes Surf many times, and each counted as the game
  turning the player back, up to the limit of 8. A walk's own field move no longer counts or says "Resuming".
- **Seafoam, floor bounce:** a journey from 1F to B2F bounced between 1F and B1F on one staircase, naming each floor,
  until it gave up. The search sees boulders where they are only on the current floor, so a floor they close looked
  open by going out and back in. A journey now takes no warp twice (`takenTransitions` in `regionalNextLeg`). It
  still ends in "No route" from 1F until the holes are filled, after one trip down and back.
- **Pokémon Tower 7F, "No route":** two causes. The search spent its 96 states on Lavender Town's houses when started
  from 2F, so the limit is 400. And in the game, 6F's Rare Candy ball is in the only way to the stairs. A journey now
  plans through balls on floors ahead, walks to 6F, and says "Blocked by Rare Candy, auto walk stopped". Pick it up and walk again.
  A refusal now takes up to about 0.35 seconds (measured on 6F), about 0.1 before.
- **Test error, `gen1_puzzles` areas:** it stopped waiting when a puzzle took over from the walk, so it reported puzzle
  journeys as failures. `victory_road_tower` has the same fault and still reports "not started". Not fixed there:
  its lines are not evidence either way.

| Area journeys from the first floor | Red, Blue | Yellow |
|---|---|---|
| Silph Co. | 24 of 24 | 23 of 24 (the rival's "Turned back again" at 11F) |
| Rocket Hideout | 12 of 13 (B4F's Iron) | 12 of 13 |
| Mt. Moon | 4 of 4 | 4 of 4 |
| Pokémon Tower | 12 of 13 (7F, Rare Candy named) | 12 of 13 |
| Pokémon Mansion | 4 of 11 ("No switch opens a way") | 4 of 11 |
| Seafoam | 3 of 4 (B2F until holes are filled) | 3 of 4 |
| Victory Road | 8 of 8, doing floors on the way | 8 of 8 |
| Safari Zone, S.S. Anne, Diglett's Cave, Rock Tunnel | all | all |

Mansion read 5 of 11 when `areas` ran alone and 4 of 11 after the other cases (Iron, 3F): switch state left by earlier
cases. Its journeys from 1F stop at the switch search. Reaching B1F from 1F by floors is not solved in Gen 1. FireRed's is (`remoteSwitch`).

Whole-map walks after the fixes, Red only: 1656 of 1679 ended as they should, against 1651 before; the other 23 are story
gates and test setup (Elite Four doors, locked Cinnabar doors, thirsty guards, ticket and Safari). Blue and Yellow's whole-map walks
ran only before these fixes (1651 of 1679, 1669 of 1698). Their other navigation drivers ran after them: no failures, no crashes.

A ledge left auto-walk at 1X for the rest of a route when its direction stayed held, until a battle or a stop: found 2026-11-04 by
`gen3_nav`, whose 200X check passed only when a wild battle happened. Fixed in `AutoWalk` (landing ends the hop's 1X). `gen3_nav` then 3 of 3 on LeafGreen,
`gen2_nav` passes on Crystal. A Route 4 check that wrote nothing was a test error: the search for "Red Version" had picked FireRed's dump, newly in the same folder.

Whole run on the final merged code, Red's own dump, 2026-11-04: 1655 of 1679 walks as they should. The one new miss since the table above is the Game Corner Prize Room's
"Prize Vendor 3" sign; not investigated. Area journeys as in the table. No speed setting was set in that run, so it does not test the ledge fix on a Gen 1 route.

A wild battle on the way to the water left "Could not use Surf" on the second ask (FireRed `gen3_nav_gaps`, one run in the rerun):
a battle now clears that memory. Waterfall part then passed 6 of 6.
