# Status

**Current focus (2026-11-03):** the owner's plan: FireRed tonight (Tuesday), then Emerald Wednesday and
Thursday; the owner returns to work Friday and expects little time after that. Earlier: the save editor (decision 38), FireRed and
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
- **Switch trying (decision 41, 2026-11-03):** owner accepted in Crystal, same day: "Yep, it flipped." Gold and Silver
  unproven. Owner asked to push once the Elite Four were beaten, and reported that, 2026-11-03: "Stomp the
  Elite Four in about 30 seconds. We're done." First owner playthrough of Crystal, on v0.4.0.
- **Filling holes (decision 41, 2026-11-03):** owner accepted in Crystal, 2026-11-03, on Ice Path and Blackthorn Gym. Gold and Silver by script only.
- `core.autocrlf false` keeps upstream's line endings.
- Issues enabled on the fork at the owner's request (2026-10-31); the README
  points bug reports there and to the owner's Discord username.
- The fork, like every fork, contains upstream's proprietary launcher files
  in its tree and history; the GitHub Fork route was chosen for that reason
  (decision 19). Our builds must not include them.

## Speech foundation

- **State:** done. Prism through LuaJIT FFI, one hook in `main.lua`. Heard by
  the owner through NVDA on 2026-10-31. Details: `speech.md`.
- **Later:** move to Prism 0.18.3 and re-check the declarations, after the first package.

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

- **Controls guide buttons (2026-11-09):** a player report said the button
  glyphs in the new-game controls guide were not read. Pages 2 and 3 draw each
  button as a picture in the background, so only the descriptions were spoken.
  Each description now starts with its button (Control Pad, A, B, START,
  SELECT, L and R, in the cart's order). Also gave words to the pad glyphs
  `DPAD_UP`/`DOWN`/`LEFT`/`RIGHT`/`ANY`, which were dropped. Unit test 147/147;
  heard in the trace of a silent FireRed `gen3_menus` run; not heard by a
  person; LeafGreen shares the code, not run.
  Pushed to `main` on 2026-11-09 at the owner's request ("Push it"), with the
  Hoenn polish; not released. The owner said to hold the release; touch
  support is next.
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
- **Audit (2026-11-03):** whole-map audit and fixes, by script; results in
  `firered-leafgreen-navigation.md`. Pushed at the owner's request before an owner test. Not heard.
- **Mods window (decision 42, 2026-11-03):** built and tested by script. The owner installed mods on the real profile and played Crystal
  with Music2-HGSS; speech still works by ear. Details and what is not done in `launcher.md`.
- **Vermilion Gym (2026-11-03):** auto-walk searches the trash cans in FireRed, by script only; see
  `firered-leafgreen-navigation.md`. Not in Gen 1 or Crystal.
- **Story pass against Crystal (2026-11-03):** boulders opening a way, Area floors, journeys through puzzles,
  Mansion's switches across floors, Saffron's pads, sign names. Run in game by script, not heard, not a full
  playthrough; table in `firered-leafgreen-navigation.md`.
- **LeafGreen (decision 44, 2026-11-04):** on `main`, pushed, by script, not heard or played. It shares FireRed's profile, maps and
  constants; only the navigation gate changed. All 18 Gen 3 drivers ran on LeafGreen 1.0 with no failures after two test
  fixes (`npc_category` and `dark_maps` treated only `firered` as Gen 3; `gen3_menus_more` needs `gen3_menus`'s save first). Dumps of 1.0 and 1.1,
  Ruby, Sapphire 1.0 to 1.2 and Emerald 1.0, checked by SHA-1, are in the private dumps folder beside the repository. 1.1 not run. Differences in the story, such as
  version-only Pokémon, were not walked.
- **Ruby, Sapphire, Emerald (decision 44, 2026-11-04):** merged to `main` with LeafGreen at the owner's request ("main"), pushed 2026-11-04 ("push it"). Screens in `ruby-sapphire-emerald.md`, navigation in
  `ruby-sapphire-emerald-navigation.md`. Run in game by script, silent; not heard, no playthrough: the harness sets party, badges and flags, teleports and skips
  scenes. Agent reports, then one sweep of the merged code by the lead. Emerald's load scripts and the Wailmer barrier are honoured, so a new game's Lilycove is closed.
  Lead's sweep of merged `gen3-all`, 2026-11-04, all 7 games: no crashes. Each Hoenn game: 8 of 8 gym leaders reached by one auto-walk, 0 bad labels. Failures left:
  `rse_nav_sweep` "no generic labels" (537 Emerald, 566 Ruby and Sapphire: mostly "Person", sprites a variable picks, on maps the player is not on); `rse_story`'s story blocks (Aqua and Magma
  Hideouts, New Mauville, Seafloor Cavern's entrance), Emerald's Shoal Cave Ice Room (one run), Trick House 7 in Ruby and Sapphire, Sky Pillar on foot (correctly "Needs Mach Bike"); Emerald's move
  tutor did not finish in `rse_screens_field` once, and the test's cleanup then failed. FireRed `gen3_battle` hit its 600-second limit once in a loaded sweep and passed alone (status has an earlier 1-in-6 hang there).
  Owner's first look, 2026-11-04: "It looks good. Emerald feels okay, but this is very early testing." Not acceptance.
  Polish (decision 65, 2026-11-09), run in game, silent, not heard: "Blocked by <who>" and New Mauville's locked door instead of "No route"; Ruby and Sapphire's Trick House 7 solved by a lever planner (Ruby walked to the scroll); a Berry Blender tone before the BEST range; the link receptionist no longer "Trainer". `rse_nav_sweep` 3/3 on Emerald and Ruby (the "Person" labels are sheets the game picks on arrival; named on live maps); `rse_story` G 8/8 gyms on both. Upstream: Emerald's Strength message lacks the Pokémon's name (recorded, not fixed).
  Forgetting a move (2026-11-09, the owner asked: the old Access scripts could not): level up, move tutor and TM run in game on Emerald and Ruby, silent; every forget-screen row now says "N of 5" and the fifth "new move" (FireRed too). Not heard. `ruby-sapphire-emerald.md`, Battle.
  For the owner: Dewford Gym is not "dark" under decision 37, because Flash is refused there and its level falls as trainers lose; and the wording questions at the end of `ruby-sapphire-emerald.md`.
- **Release 0.0.4 built, not published (2026-11-10), commit `569d0436`.** Windows zip 110.3 MiB, sha256
  `7cc132d8…`, audit passed; APK 31.4 MiB, versionCode 4, signed with the release certificate (`fc4af609…`);
  iOS IPA 23.1 MiB, version 0.0.4 build 11, CI run 42949722364, no ROMs or saves inside, sha256 `eb4351b5…`.
  Publishing approved by the owner (decision 72).
- **Release 0.0.4: on hold (2026-11-10).** The owner wants it framed as an iOS and mobile release with
  Android untested; then: "Don't build release yet. We got a few things to do." Builds started and stopped
  (Windows package, signed APK, iOS CI run 42948758354 cancelled); nothing kept or published. Ready for later:
  README "iPhone" section, `ios.yml` takes a `version` input (`gh workflow run ios.yml --ref ios-build -f
  version=X.Y.Z`), Prism 0.18.3 `prism-android.zip` from ethindp/prism releases, and draft notes (agent's
  scratchpad, not in the repo).
- **`main` pushed 2026-11-10** at the owner's request ("push to main"): 33 commits since `dcc7e7aa` (2026-11-09), after a scan for private material, paths and binaries. No release.
- **Touch, 2026-11-10 (fifth addendum to decision 66):** AUTO walks by a tap (another tap stops) and swipes
  step; two-finger swipes no longer turn into a do-nothing rotation when one finger lags. Test and silent
  Crystal run pass; not on a device. Pushed to `ios-build` for a new iPhone build at the owner's request (2026-11-10: "Yes, build a new version, I don't mind."), with the day's other local commits (PC Clock 1.1.0, randomizer 0.2.0, docs); `main` not pushed. CI run 42943178684 (`ca8cca2e`) passed (build and simulator smoke test); the IPA is in the owner's Downloads as `PocketAccessibility-unsigned-2026-11-10-touch.ipa`. The owner, after trying it on the iPhone: "Works great." (2026-11-10), then: "tried the mods and save editor." A screenshot shows three mods from the index installed on the iPhone (`ios.md`).
- **PC Clock for Hoenn (decision 70, 2026-11-10):** the PC Clock mod 1.1.0 sets Ruby, Sapphire and Emerald's
  wall clock from the device and keeps the time of day on the device's. By script, 10 of 10 on each game; not
  played or heard; the owner kept it in the one mod. `main` not pushed.

## Launcher

- **State (2026-11-01):** first working version (`launcher/PocketLauncher/`,
  C# Windows Forms on .NET 10, decision 4): games list with imported state,
  Play, Import ROM (dialog or a ROM dropped on the icon), Credits with the
  required upstream credit. Built, accessibility tree checked through UI
  Automation, import and play run on a disposable profile. The owner's first
  try found the stale-import fallback (fixed with the game's own ready
  check), then judged it "Looks good" and approved the push (2026-11-01).
  Details: `launcher.md`.
- **Packaged folder (2026-11-03):** `launcher/package_release.py` builds it, and every route to upstream's launcher is
  closed. Tested by script only, not heard, not published. Open for the owner: `launcher.md`, "Packaged release".
- **Next:** the owner tries the package; Settings.

## Before any packaged release

- Done by script (`launcher.md`, "Packaged release"): our own launcher, upstream's updater off, upstream's launcher files out, Term 1 credit.
- Android (owner, 2026-11-05): next, controller only; touch controls left to whoever wants to try them. A standard Android app as the launcher is the idea to check. 0.0.2 is on hold until the owner says. Test build on the branch `android-test`: on the AYN Thor Red imports and runs, Prism uses TalkBack, and the owner's brief test went well (`android.md`). Our own launcher (decision 53) has the ROM folder, the game list, the sounds, the save editor and, since 2026-11-08, a Mods screen (decision 60: emulator only, no device test, as the owner noted); the package now brings the PC Clock (on) and Crystal Randomizer (off) (decision 61), and computers start borderless with the owner's display settings (decisions 62 and 63), all released in 0.0.3; on the emulator all 11 games boot and navigation, sounds and the editor work (`android.md`, "Emulator results"). Not yet tested by the owner on the Thor. On 2026-11-05 the owner had `android-test` merged into local `main` ("Don't push anything to GitHub") and asked for the rest of the games, navigation, sounds and the save editor to be done silently in the background; later work stays on `android-test` until merged. That work was merged into local `main` at the owner's request the same day ("merge it to main"). Pushed to GitHub at the owner's request the same day ("remove the quote and then push"), after one quote about a third party was taken out of the unpushed history.
- Android touch (decision 66, 2026-11-09): the owner's gestures with TalkBack kept on. Passthrough proved on the owner's Pixel Tablet with NVGT Bridge (owner confirmed a D-pad tap with TalkBack running; `android.md`). The owner asked for our own service built into the app and then "start building, use subagents": two agents on separate worktree branches, one for the Android service and launcher page (`launcher/android`), one for the game-side gestures (`src/access/touch/`). Both merged into local `main` the same day: the service `TouchPassthroughService` with a launcher "Touch controls" page (compiles; aapt shows the service; the APK's existing INTERNET permission comes from upstream, so the text says the service never uses the internet), and the gestures in `src/access/touch/` with Manual, Hybrid and Auto walking (`touch_gestures_test` 136/136; silent scripted runs in Crystal, FireRed and Red stepped, opened menus, auto-walked and walked Hybrid legs). The owner's first tablet test (bridge off, our service on): "It works." At the owner's request upstream's on-screen D-pad and buttons are now hidden while gestures are on. Open questions are in `android.md`. Pushed to `main` at the owner's request ("push it", 2026-11-09), with landscape left / right halves and longer three-finger taps; not released. Release held (owner, 2026-11-09). Halves removed at the owner's request (2026-11-10, decision 66 second addendum): two-finger swipes navigate, anywhere on the screen. The two-finger turns removed the same day (third addendum): walking modes only in the options; in AUTO a swipe walks to the selected point. Unit tests and silent Crystal runs pass; committed locally, not pushed, not on a device. Player docs for the gestures written the same day at the owner's request (README, both launchers' Touch controls pages; the Android page compiles, the iOS page is not built yet). Directions while stepping: a one-finger tap on the map, as K (owner agreed, 2026-11-10; fourth addendum); unit tests and a silent Crystal run pass.
- **iPhone works (2026-11-10):** the owner sideloaded the first build with Sideloadly, ROMs copied over USB, Crystal runs, and the owner reports "It works." Details and what is not itemised yet: `ios.md`. Main was pushed with the iOS work at the owner's request (2026-11-10).
- **iPhone save editor and Mods (decision 69, 2026-11-10):** done and tried by the owner. Lua serves the save and mod backends through the launcher's bridge; SwiftUI renders them; installs from the index are unpacked by the backend's `unpack`. CI compiled it on the fifth try (GitHub's macOS runners were full four times; the owner: "If it's busy, we can wait"): run 42868805188 (`cbba68cb`), then 42943178684 (`ca8cca2e`) with the touch changes. On the iPhone the owner "tried the mods and save editor"; a screenshot shows three mods installed from the index, and Exp Share worked in the game ("Yeah, EXP sure did"). Owner request, same day: clearer labels for which games a mod is for ("if possible ... if not, no big deal"). Done on iPhone and Android: each row now says "For Gen 1" or "For Red, Blue and Yellow", or "Not for Pokémon Crystal; for Gen 1", from the backend's existing `games` label (`ModTargets.label`), worded for speech. Android's file compiles; the Swift waits for the next iOS CI build; not on a device. Details: `ios.md`.
- **Haptics (decision 68, 2026-11-10):** the owner chose haptics from four ideas for a more elegant touch scheme. Built: a light tick per step and a firmer click on bumps, Android (JNI, predefined effects) and iOS (Swift `PocketHaptics`), HAPTICS option. Unit tests pass; not run on a device, not felt by the owner. The Pixel Tablet probably cannot vibrate; the Thor or the iPhone can. Committed locally (`44a9ff1b`), not pushed; a debug APK with the test id is built, not installed (no device connected). The iPhone needs a new IPA from CI, which needs a push to `ios-build`. **Felt on the iPhone by the owner, 2026-11-10: "Haptics work."** Android not felt yet.
- iPhone and export / import (decision 67, 2026-11-09): planned only. One complete iOS app tested in the simulator before each install; a local export and import of games, saves, mods and settings on every platform. Step 1 (groundwork on the PC) done at the owner's request ("start step one"): upstream's iOS build read, Prism 0.18.3 has an iOS VoiceOver backend, and our layer runs unchanged on LÖVE 12 for Windows in silent drivers (`ios.md`). Nothing built for iOS. Step 2 approved by the owner ("if that's the next step and nothing is gonna get us in trouble, then yeah, go ahead", 2026-11-09): a GitHub Actions workflow on a separate `ios-build` branch, no ROMs, Prism downloaded at build time, upstream's launcher left out, builds kept 7 days. The first run on `ios-build` (2026-11-10) was green: the unsigned IPA builds, and in the iPhone simulator our layer starts, Prism speaks through the system voice and the app refuses to start without a game, with no errors (`ios.md`). Next: our own iOS launcher and VoiceOver direct touch, started at the owner's request ("start that now", 2026-11-09) by an agent on its own branch; CI iterations go to `ios-build`. Run 42733599145 (2026-11-10, `c8fe1339`) green on its first try: in the simulator the app opens on our launcher, a CI-only autostart of Red starts the game, which refuses without a ROM, and the launcher comes back with the reason; no crash or Lua error. The unsigned IPA (24 MB) is in `dist/ios-ci/` (gitignored), ready for the owner's first install. Leaving a game: the owner chose a two-finger triple tap on a title screen (2026-11-10, decision 66 addendum), built and checked in a silent FireRed run. The IPA with it (`2938eba3`) is in `dist/ios-ci/`; its CI run passed on a rerun after one silent first launch (`ios.md`).
- Player feedback, Android, Emerald on 0.0.3 (relayed by the owner 2026-11-10; read, nothing built): playing
  portrait with upstream's on-screen pad, walking by footsteps. (1) "joystick presses do nothing" when setting a
  button: unclear whether a physical controller's sticks are not seen (SDL may treat an unmapped controller as a
  joystick, not a gamepad) or the on-screen pad simply has no sticks; ask which controller. (2) Asks for the
  navigation inputs (stick clicks; also needs the left-trigger modifier) on the on-screen pad, above the face
  buttons in portrait, or L and R as alternatives. Relevant: TOUCH GESTURES (unreleased) gives navigation by
  gestures but hides the pad while on. The owner told the player touch controls are being redesigned
  (2026-11-10). Pad buttons not planned; the owner: "We don't need to tie up communication loose ends."
- Release 0.0.3 (2026-11-08): published at the owner's request (decision 64), tag `v0.0.3` at `5109be9b`. Windows zip 110.2 MiB, sha256 `1553e151…4a5a53`, audit passed; APK 31.3 MiB, versionCode 3, sha256 `b00d89fb…2c3d56`, signed with the same certificate as 0.0.2 (so it installs over it). GitHub's digests match the local files. Not run from the package: the Windows start (borderless and the new defaults), the bundled mods in a real Windows save folder, the APK on a device, and the Windows updater from 0.0.2 to 0.0.3. Before publishing, decision 6's text was withdrawn from the current docs; it is still in the public history, and the owner chose on 2026-11-08 to leave the history as it is.
- Release 0.0.2 (2026-11-05): published at the owner's request ("Publish now", decision 55), tag `v0.0.2` at `87c029eb`. Windows zip 109.9 MiB, sha256 `0f29e91c…aee0b6`; first Android APK, 31 MiB, sha256 `a6f73f0b…d2e6de`, signed with the release key. GitHub's digests match the local files. Windows package built and audited, not run; the APK as an update over the earlier release test was not tried (the owner chose to publish without it).
- Release 0.0.1 (2026-11-04): published at the owner's request (decision 49), tag `v0.0.1`. Tested by script only (`launcher.md`, "Verification: release 0.0.1"). The updater's first real test against GitHub is the next release. Owner, 2026-11-04: Android and Linux are going to be added; not started. Online play: not in the package, because its screens are upstream's proprietary launcher (`launcher.md`).

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
- **Every edition, every map (2026-11-03, owner's request):** whatever works in Crystal proved in Gold and
  Silver on their own maps, and whole-map sweeps (`gen2_nav_sweep`, `gen2_text_sweep`): journeys no longer time
  out, Saffron's pads are walked, signs named, unusable targets not listed. Table and numbers in
  `gold-silver-crystal-navigation.md`. By script; not heard. Gold and Silver not played.
  Driver note: `gen2_story_spots` needs about 12 minutes per game.
- **Randomizer 0.2.0 (2026-11-10):** the owner suspected repeated starters. Measured: related choices
  between neighbouring slots and a biased starter triangle (GEODUDE, LARVITAR, CHIKORITA in a third of seeds
  each). Fixed for new seeds; old saves keep their world. Tests on both generators and one silent Crystal run
  pass; `core_test` failed twice unexplained. Not played. Details: `gold-silver-crystal.md`, "Fairer shuffling".
- **Shuffled doors (2026-11-08):** navigation follows the map randomizer's rewritten warps: labels, auto-walk
  and journeys; two small planner fixes. Unit test and a Crystal run with two New Bark doors swapped by hand
  pass; not run with the randomizer mod itself, not heard. Details: `gold-silver-crystal-navigation.md`.
- **Open product questions:** listed in `gold-silver-crystal.md`.

## Open questions for the owner

- Gen 2 product and wording questions: `gold-silver-crystal.md`.

## Navigation

- **Parity across games (decision 43, 2026-11-03):** merged to `main` on 2026-11-04 at the owner's request ("Yes, merge it"), pushed the same day ("push it"). By script only; not heard, no
  owner test. Results: `red-blue-yellow-navigation.md`, `firered-leafgreen-navigation.md`, `gold-silver-crystal-navigation.md`.
  Open: `gen3_story` part B stops at its limit in Celadon Gym on a level-up stat screen in the harness's battle, so Erika, Misty and Brock
  were not walked to in that run; cause in the harness suspected, not proven. Part D, Sevii: reach only, not walked. `victory_road_tower`'s test is stale.
  Whole-map walks and the rest of the drivers were not rerun after the last two fixes (a battle before Surf; Victory Road 2F).

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
- **Red, Blue, Yellow parity and whole-map audit (2026-11-03):** Crystal's puzzles built for Gen 1 and
  every target on every map walked by script: `navigation.md`. Not heard, no owner test.
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
