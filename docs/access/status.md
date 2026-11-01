# Status

**Current focus (2026-11-01):** Gold, Silver and Crystal (decision 27): the
same treatment Red, Blue and Yellow got. Gen 1 is done apart from Yellow's
surfing minigame, which the owner is picking up.

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

## Before any packaged release

- Our own launcher (decision 4). Upstream's self-updater off, upstream's
  launcher files excluded (`architecture.md`).
- Upstream License Term 1 also requires the credit in the app's credits,
  about or title screen and in our launcher.
- Decide on upstream's Discord rich presence.

## Gold, Silver and Crystal

- **State (2026-11-01):** started. Upstream v0.3.98 already runs all three
  (`src/core/Game2.lua`, screens in `src/ui/gen2/`, world in
  `src/world/gen2/`) on Gen 1's StateStack, so ScreenReader sees their
  screens with no new hook. Baseline game run (Crystal and Gold, new game to
  a wild battle): only TextBox dialogue spoke; every Gen 2 screen and the
  battle were silent; navigation is gated off for Gen 2 (`nav/init.lua`).
  Done so far: split words rejoined in dialogue (all games), the
  ACCESSIBILITY page in Gen 2's OPTION screen, a presenter registry
  (`src/access/screens/gen2/`) with shared helpers, a walkthrough driver.
  The three games are imported into disposable identities
  (`pocket-access-gold`, `-silver`, `-crystal`).
- **In progress:** six agents on separate branches (decision 27 allows
  subagents): menus, items and PCs, info screens (party, summary, Pokédex,
  Pokégear), special screens and minigames, battle, and navigation (one
  adapter for both generations; Strength puzzle help for Ice Path B1F and
  Blackthorn Gym 2F). Each branch is reviewed and merged by the lead.
- **Then:** integrate, run Crystal, Gold and Silver end to end, audit the
  differences between the three, document, and hand to the owner to listen.
- **Open product questions (agent defaults until the owner decides):**
  Unown puzzle without solving hints; Card Flip describes only what a
  sighted player sees; Unown wall words said, then spelled; headbutt trees
  listed as objects.

## Open questions for the owner

- See the Gen 2 product questions above.

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

Launcher, save editor accessibility.
