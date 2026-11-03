# Status

**Current focus (2026-11-02):** the save editor (decision 38), then FireRed and
LeafGreen (decision 29). Gen 1
and Gen 2 are built; the owner playtests them during the week (Crystal to
the first gym: "It works perfectly"). Yellow's surfing minigame is the
owner's.

Each workstream section is edited only by the session working on it. Keep each
one short: state, next steps, blockers. Remove a section when its work is done
and recorded in the topic file.

## Repository

- `main` starts at upstream tag `v0.3.98` (commit `4312fb64`). Remotes:
  `upstream` (bryanthaboi/pokemon-gen1-recomp-project) and `origin` (the
  public fork `pocket-accessibility` under the owner's GitHub account).
- Commits use the owner's GitHub username and noreply address (decision 13).
- **Upstream v0.4.0, merged 2026-11-02** (`de56d2eb`, only `.gitignore` conflicted). Gold,
  Silver and Crystal must be imported again (cache format v18). On a disposable Crystal
  profile the save files were byte-identical after the import, and a save from before the
  merge continued on the new code (an early save with no party). Checked on old and new code from the same starting saves, on disposable
  profiles: 80 driver runs, then speech traces for the 28 that logged none, two rounds each.
  Every difference in speech traced to chance (battle rolls, genders, an elevator chosen
  through `pairs`, one FireRed elevator prompt that varies on both). Failures on both: Red
  `nav_controller` "auto-walk took the stairs"; the old `tests/access/nav` tests' known ones.
  Two hangs on new code only, neither reproduced in 4 reruns under lighter load: FireRed
  `gen3_battle` in the METAL CLAW prompt (1 of 6), Silver `gen2_nav_puzzle` at Blackthorn
  Gym (1 of 6). Cause not found; not proven unrelated. Upstream's `--standard` suite: same 11
  failed groups as before the merge; 5 new failures also fail on clean v0.4.0 (Windows `/tmp`,
  patch notes). `accessibility.event` fails upstream's event catalog gate, as before.
  Pushed 2026-11-02 at the owner's request, before the owner's Crystal test, which the owner plans to play that night and the next day.
  Owner's Crystal playthrough on the merged code (their report, 2026-11-03): through the fourth gym and its invisible floors "with no issues".
  `gen2_region_proof_test` fails only from a path with spaces. The new Gen 2 UI LAYOUT row was
  not reached by any driver. Not heard; no owner test.
- `POKEPORT_IMPORT_ONLY` with a current cache starts the game instead of quitting (old code
  too): scripted imports need a timeout.
- Driver runs: `gen2_menus` needs `POKEPORT_BOOT_CINEMA=1`; many drivers log speech only with
  `POKEPORT_ACCESS_TRACE=1`. At most 3 games at once, hidden, closed when done (owner's
  request, 2026-11-02: "when you're done with a test, close it").
- **Flashing warning (owner's words, 2026-11-02):** at the top of the README. Nintendo's public
  position is a player warning (support article 59596); no public limit on flashing found. Source
  read, not measured: BATTLE ANIMATION (Gen 1) and BATTLE SCENE (Gen 2, Gen 3) skip move
  animations; ball animations stay in Gen 1, non-move animations stay in Gen 2, and the battle intro
  transitions of all three generations have no check for the setting. The stale comment in Gen 1
  `BattleState` about coarse flashes applies only when the animation player fails. Importer
  accepts original ROMs only, so Virtual Console's reduced flashing is not present. No game
  changes (decision 10); any reduced-flash option is the owner's decision.
- **Chase (decision 40, 2026-11-02):** works in Crystal in the owner's play, by script in Gold and Silver; pushed at the
  owner's request. Regressions run: `auto_walk_test`, `gen2_nav`, `gen3_nav`, Red `navigation` and
  `autowalk_battle`. Owner accepted in Crystal, 2026-11-03: "Autowalk did do the chase", through Ilex Forest and
  on to Goldenrod. Gold and Silver by script only. README tells players the attempt counts.
- **Lost dialogue (2026-11-03):** Prism refuses some lines as invalid UTF-8 (`gold-silver-crystal.md`).
  `Speech.say` now retries in ASCII. Owner heard Jasmine's lost line after the fix, 2026-11-03: "It
  works. Perfect." Silent driver runs cannot catch this kind of failure. Other lost lines not rechecked.
- **Boulder pushing (decision 41, 2026-11-03):** by script in all three Gen 2 games. Owner accepted in Crystal, same day: "Gym
  completed", "Auto walk pushed them." Gold and Silver by script only. Earlier Silver `gen2_nav_puzzle` timeout: a Crystal rerun stopped at a lead with no PP
  in a wild battle, which fits it; the driver now keeps a Repel.
- `core.autocrlf false` keeps upstream's line endings.
- Issues enabled on the fork at the owner's request (2026-10-31); the README
  points bug reports there and to the owner's Discord username.
- The fork, like every fork, contains upstream's proprietary launcher files
  in its tree and history; the GitHub Fork route was chosen for that reason
  (decision 19). Our builds must not include them.

## Speech foundation

- **State:** done. Prism through LuaJIT FFI, one hook in `main.lua`. Heard by
  the owner through NVDA on 2026-10-31. Details: `speech.md`.
- **Later:** move to Prism 0.18.3 and re-check the declarations before packaging.

## Menus and text

- **State:** every Gen 1 screen class has a presenter except Yellow's
  surfing minigame and upstream's visual editors (palette, skin studio,
  touch controls), with no edits to screen files. Includes the mod manager,
  cable club, Union Room prep, save load report and Pikachu reactions. Mod screens can opt in
  with `accessibilityText`. Dialogue follows the game's A presses. Unit
  suites 28, 37, 13, 14 and 32 checks, all passing. Scripted game runs in
  disposable identities cover Red and Yellow. Details: `menus-and-text.md`,
  `battle.md`, `yellow.md`.
- **Next:** surfing minigame (design in `yellow.md`, deferred by the owner);
  network flows with a second player; talking to Pikachu in a game run; the
  owner's judgement on wording and verbosity from playing.

## FireRed and LeafGreen

- **State (2026-11-01):** started. Upstream runs Gen 3 through
  `src/core/Game3.lua` with no StateStack: menus are layers on
  `src/ui/game3/stack.lua` (singleton modules), dialogue is
  `src/ui/game3/message.lua`, yes/no `choice.lua`, battle a module. Baseline
  FireRed run: nothing spoken. Built: `src/access/CurrentGame.lua` (the live
  game through a runtime wrapper on `PlatformHooks.update`),
  `screens/gen3/Top.lua` (what is on screen, one proxy per opening),
  dialogue page by page and yes/no; verified in a FireRed run.
- **Merged (2026-11-01):** menus and boot, bag/party/summary/Pokédex/PC/
  shop/map, special screens, battle (every shown line spoken at 1X and
  200X). All unit suites pass; each branch traced in FireRed. Not heard.
- **Navigation (2026-11-01):** merged: object list, guided navigation,
  auto-walk with battle pauses, 200X, Surf, spinners, card key doors and
  Strength hints, traced in FireRed; Gen 1 and Gen 2 regressions clean.
  Gaps closed (2026-11-01, branch work): journeys on a one-pass planner
  (Silph Co. and Rocket Hideout walked in FireRed; real gates say "Needs
  Card Key" or "No route"), item balls picked up when they block the only
  way, the Tanoby Key room planned and followed, renaming, and runs on
  Icefall Cave ice, Seafoam currents, a Mansion switch and a waterfall.
  Quirks after that (decision 32): elevators are journey legs ending at the
  panel ("Needs Lift Key" without it), thin ice is fallen through on the
  way, planned floors read their load scripts, auto-walk and guided
  navigation agree. All run in FireRed. What remains is in
  `firered-leafgreen-navigation.md`. Not heard.
- **Scenery (2026-11-01):** flavor furniture hidden from the object list
  (decision 34; swept in FireRed, not heard).
- **Owner playtest (2026-11-02):** the owner reports reaching the first gym in
  FireRed, with auto-walk and guided navigation: "works really good". The owner
  has not found the Area category useful so far (expected before multi-floor
  dungeons; to revisit from Mt. Moon).
- **Dark maps need Flash (2026-11-02):** in Gen 1, 2 and 3, before Flash:
  auto-walk, guided navigation and far camera moves say "Too dark. Use Flash.",
  the list keeps what is in sight (decision 37; `drivers/dark_maps.lua` in Red,
  Crystal and FireRed, not heard). The harness lit the maps by setting the
  state Flash sets; using Flash from the party menu was not run. A journey
  stopping on reaching a dark floor is code only.
- **Misc category (2026-11-02):** FireRed's hidden flavor furniture listed
  under Misc, left out of All (decision 36; `drivers/npc_category.lua` in
  FireRed walked to a Bookshelf and a Poster, not heard).
- **NPCs category (2026-11-01):** people and Pokémon moved out of Objects into
  NPCs in Gen 1, 2 and 3 (decision 35; `drivers/npc_category.lua` in Red,
  Yellow, Crystal and FireRed, not heard). Blue, Gold and Silver share the code
  but were not run; Gen 2's bedroom decorations not run.
- **Owner first try (2026-11-01):** a brief test, "works great".
- **Screen gaps (2026-11-01):** Mystery Gift from the boot menu and every
  item the first runs had not reached (TM case and pouch from the bag,
  TAKE, Softboiled, Teachy TV demos, double-battle party, a clerk's shop,
  habitat pages, catch registration, wallpaper, MOVE, level-up window,
  "can fly", prize list) run in FireRed (`drivers/gen3_screens_more.lua`).
  Audit of `src/ui/game3/` layers: Teachy TV demo layers, mod screens,
  Union Room prep, the Berry Crush berry choice and the Union battle's text
  were silent and now have a path; ShaderFX menu and the Union battle's
  menus remain. Not heard.
- **Next:** the owner keeps playtesting FireRed. The end-to-end walkthrough after
  all merges speaks the intro, title, start menu, bag and dialogue.
- **LeafGreen:** deferred by the owner (decision 30); no clean dump on this
  PC yet. FireRed's whole UI first, with Pokémon Access as a behaviour
  reference.

## Launcher

- **State (2026-11-01):** first working version (`launcher/PocketLauncher/`,
  C# Windows Forms on .NET 10, decision 4): games list with imported state,
  Play, Import ROM (dialog or a ROM dropped on the icon), Credits with the
  required upstream credit. Built, accessibility tree checked through UI
  Automation, import and play run on a disposable profile. The owner's first
  try found the stale-import fallback (fixed with the game's own ready
  check), then judged it "Looks good" and approved the push (2026-11-01).
  Details: `launcher.md`.
- **Next:** the owner tries it; Edit save, Settings; packaging (closing the
  routes back to upstream's launcher, layout, save folder).

## Before any packaged release

- Our own launcher (decision 4). Upstream's self-updater off, upstream's
  launcher files excluded (`architecture.md`).
- Upstream License Term 1 also requires the credit in the app's credits,
  about or title screen and in our launcher.
- Decide on upstream's Discord rich presence.

## Gold, Silver and Crystal

- **State (2026-11-01):** every Gen 2 screen family and the battle have
  presenters (`src/access/screens/gen2/`: Menus, Items, Info, Special,
  Battle), merged from five agent branches, with unit suites (86 to 135
  checks each) and scripted runs in Crystal, Gold and Silver. Shared fixes
  made while merging: split words rejoined (real compounds keep the hyphen),
  `#` spoken as POKé, a re-shown yes/no question said once, a screen changed
  and covered in the same frame says its change first. The full Crystal
  walkthrough (boot to a won wild battle) speaks every screen. Details:
  `gold-silver-crystal.md`, `battle.md`.
- **Navigation (2026-11-01):** merged. Object list, guided navigation,
  auto-walk (with the Gen 2 steering-lag fix), journeys, controller, Q time,
  H and Shift+H battle health, and Strength puzzle help for Ice Path B1F and
  Blackthorn Gym 2F, run in all three games; Gen 1 regression unchanged.
  Full walkthroughs re-run after every merge in Crystal, Gold and Silver.
- **Audit (2026-11-01):** merged. Whole-game label sweep (388 Crystal maps,
  368 each in Gold and Silver: no hard errors; misleading labels fixed),
  required story spots walked in each edition with no layer blocks, edition
  differences all game data. Details: `gold-silver-crystal-navigation.md`.
- **Published (2026-11-01)** to the public fork as initial groundwork
  (decision 28); the README labels it untested by players.
- **Owner playtest:** Crystal from a new game to the first gym, 2026-11-01:
  "It works perfectly in Crystal." More of Crystal, and Gold and Silver,
  during the week.
- **Open product questions:** listed in `gold-silver-crystal.md`.

## Open questions for the owner

- Gen 2 product and wording questions: `gold-silver-crystal.md`.

## Navigation

- **State:** old navigation reused (decision 20) and wired in: F7 command
  layer, object list, filters, map name, position, tiles, pathfinding,
  renaming, controller scheme (decision 23), auto-walk (resumes after
  battles, spinners, card-key doors) and cross-map journeys to Area targets
  (decision 25). Silent sweep of the required story spots (gyms, Victory
  Road, Pokémon Tower, elevators) found no blocker; the Rocket Hideout
  panel approach was fixed. ACCESSIBILITY page in OPTIONS (decision 26):
  AUTO-WALK SPEED up to 200X (auto-walk now steers tile by tile) and
  DIALOGUE SPEECH page by page or all at once. Red, Blue and Yellow audit
  done (Yellow: Pikachu follower, covered elevator prompt; a door
  regression fixed; `yellow.md`). Old tests pass except the two known gaps.
  Details: `navigation.md`.
- **Next:** walking cues (no upstream event),
  Chaos Cut as an optional mod (decision 21); the owner's playtest.

## Save editor

- **State (2026-11-02):** native window finished, all pages (decision 39,
  `save-editor.md`). Owner's first use (2026-11-02): "save editor works nicely, and
  was able to get to the second gym in fire red."
- **Upstream bug, for the owner:** source reading says Gen 2's Spawn action writes a map
  id to `save.spawn`, while `World:healPoint` expects a `SPAWN_*` name, so a whiteout
  would find no spawn point. Not run in game, not patched (no game fixes). The page
  warns and asks to confirm.
