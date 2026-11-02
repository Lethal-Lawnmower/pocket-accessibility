# Status

**Current focus (2026-11-01):** FireRed and LeafGreen (decision 29). Gen 1
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
  What remains is in `firered-leafgreen-navigation.md`. Not heard.
- **Owner first try (2026-11-01):** a brief test, "works great".
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

## Not started

Save editor accessibility.
