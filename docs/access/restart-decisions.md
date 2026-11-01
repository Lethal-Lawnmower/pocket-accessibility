# Restart decisions

Started 2026-10-31 at the owner's request. All new restart work happens in this
repository (local folder `Claude Refactor`). The old project, which sits in the
parent folder, stays untouched as a reference archive. Relative paths below such
as `../pokemon-access` were written from the old project root.

## Why

The owner judged the old project over scope and bloated: roughly 14 parallel
intake/integration/audit checkouts, one per upstream version, plus very large
handoff and merge-log files. The restart carries over only what is chosen
deliberately.

## Agreed direction (owner, 2026-10-31)

- Our own build: upstream plus a thin accessibility layer (option 2 below).
- A small native Windows launcher app (C#, Windows Forms) with standard
  screen-reader-labelled controls, which also handles setup.
- Red, Blue and Yellow first; the eight defaults under "Decisions before
  migration" are accepted.
- Pokémon Access features redone our own way; its sound pack is bring-your-own.
- Amethyst's manager is a possible future distribution channel only.

**Authorized 2026-10-31:** the inventory below, then setting up this local git
repository from a fresh copy of upstream v0.3.98.
**Not yet authorized:** copying any old code in, a GitHub remote, pushing,
publishing, or contacting anyone.

## Repository setup (2026-10-31)

- `git init -b main`; branch `main` starts at upstream tag `v0.3.98`, commit
  `4312fb64c927b8892091075f159f09d7a211d4b5` (checked against the GitHub API).
  Remote `upstream` points to `bryanthaboi/pokemon-gen1-recomp-project`. No
  `origin` and no push. Objects were seeded from the old local clone (tag v0.3.32),
  then fetched from GitHub. Packed size is 137 MiB.
- Local commit identity is the old project's pseudonym (`Pocket Accessibility
  Project`, `.invalid` address), kept for continuity. Change before the first push
  if the owner prefers their GitHub identity.
- `core.autocrlf false` so upstream's line endings are preserved.
- Our files live in `docs/access/` (these notes). Planned locations: `src/access/`
  for the accessibility layer and `launcher/` for the Windows app. Upstream's
  `README.md` is unchanged for now.
- A marked block at the end of `.gitignore` adds ROM zips, `roms/`, `local-deps/`,
  `pokemon-access-sounds/`, Prism binaries and launcher build output. Upstream
  already ignores `*.gb`, `*.gbc`, `*.gba`, `*.sav` and `save/`. Verified with
  `git check-ignore` on sample paths.

### Private versus public, and the GitHub fork list (discussed 2026-10-31)

- Private development is allowed. GPLv3 obligations attach to *distribution*:
  anyone who receives a build must also be able to get its source, under the GPL.
  Upstream's added terms (checked in `LICENSE.MD` at v0.3.98) require attribution
  and restrict the launcher and names. None of them requires a public repository.
- Once builds are shared, the matching source must be available to recipients.
  A public repository is the simplest way to do that.
- A repository created separately and pushed (not made with GitHub's Fork button)
  never appears in upstream's fork list, even when public, and shows no
  "forked from" label. The README and in-app credit still give attribution.
  GitHub's Fork button would list it, but a fork of a public repository cannot
  be private. Pull requests to upstream would go through a fork in either case.
- No decision yet. The owner has not chosen a GitHub setup.

**Old project inventory:** [old-project-inventory.md](old-project-inventory.md)
(approved by the owner 2026-10-31, with the rule that no old map, code or game
fixes carry over, only accessibility; nothing copied yet).

The sections below are the reasoning, in the order it happened.

## Upstream relationship (decided: option 2)

How the new work relates to upstream `bryanthaboi/pokemon-gen1-recomp-project`:

1. **Hard fork** (the old approach): accessibility woven through engine and
   screen code. Every upstream update is a large merge.
2. **Thin layer on upstream**: upstream stays close to untouched; accessibility
   lives in its own package plus a small, listed set of hook points.
3. **Pure upstream mod**: no engine changes. Blocked today: upstream's mod
   sandbox (checked at v0.3.31, 2026-09-29) refuses `require("ffi")`, which a
   native speech library such as Prism needs, unless upstream adds a speech API.

Agent recommendation (not an owner decision): option 2, built so it can move
to option 3 if upstream ever offers a speech hook. Pin to a release tag and
update on purpose, not with every upstream release.

### Launcher constraint (verified 2026-10-31, upstream v0.3.31 `LICENSE.MD`)

Upstream's launcher is proprietary and excluded from the GPL (Additional Term 2):
`LauncherView.lua`, `LauncherSettings.lua`, `OnlinePanel.lua`, `CartLabelArt.lua`,
`CartShape.lua`, `src/mods/LauncherMods.lua`, the launcher UI code in
`RomImporter.lua`, `assets/launcher/` and `assets/labels/`. Any fork or modified
version must ship its own launcher, and that launcher must visibly show the
credit required by Term 1. The ROM import, verification and cache-extraction
logic in `RomImporter.lua` remains GPL and reusable.

Consequences:
- Options 1 and 2 both distribute a modified program, so both need our own launcher.
- Only option 3 (a mod running inside an unmodified official release) avoids that.
- The launcher's size is a scope choice. October's bloat came from a visual,
  multi-cartridge launcher (art, room identities, mascots). A minimal, audio-first
  launcher (pick game, import ROM, settings, start, credit) is the proposed scope.
- Unchecked: whether the old Purple launcher was derived from upstream's
  proprietary files. If so, none of it can carry over.

### Owner restriction (2026-10-31)

Rejected outright: any helper/bridge program that speaks on the mod's behalf over
a network or local socket. The owner called this "the absolute final enemy of
accessibility mods." Do not propose it again. Option 3 stays viable only if
speech can run in-process without a bridge.

### Accessibility Mod Manager (checked 2026-10-31)

`RealAmethyst/AccessibilityModManager` (C#, .NET 10, Windows and Linux; same
account as `DigimonNOAccess`, `pokemon-tcg-access`, `zelda3-access`). Read from
its `LICENSE` (Source-Available License 1.0) and `README.md` on GitHub.

- **Publishing our mod through it: permitted.** License 2(d) allows creating
  plugins. Authors run their own GitHub catalog with the `amm-author` CLI and
  submit it to the manager's directory. Packages are ZIPs with SHA-256 hashes;
  manifest actions are `copyFile`, `copyFolder` and `replaceFile`, plus optional
  user-confirmed lifecycle scripts and dependency installs (portable emulators
  are a documented case).
- **Modifying or reusing the manager: not permitted** without written permission
  (3(b) no modified distribution, 3(d) no derivative or competing app). Only
  contributions to the official repository are allowed.
- **Why it matters here:** the manager copies or replaces files inside the
  player's game folder. That is not upstream's sandboxed mod system, so FFI and
  Prism are not blocked, and we would not write or ship a launcher.
- **Unverified:** how upstream's official Windows release is packaged (loose Lua
  files or a fused LÖVE executable), whether upstream auto-update overwrites
  replaced files, and whether a player-patched official release falls under
  upstream License Term 2 ("used in any ... modified version").

### Upstream packaging and updater (checked 2026-10-31, release v0.3.98)

Sources: the v0.3.98 release asset list, and `scripts/build_windows.ps1`,
`docs/updater.md`, `src/update/Boot.lua` and `main.lua` at tag `v0.3.98`, read
through the GitHub API. No release archive was downloaded.

- Latest release is v0.3.98 (2026-10-29). Recent cadence is one release every
  one to three days. The tree now includes Gen 3 code (`src/ui/game3`, Emerald tests).
- **Windows ships fused.** `gen1recomp-X.Y.Z-windows.zip` contains
  `gen1recomp.exe` (`love.exe` with `game.love` appended), LÖVE's DLLs and
  `gen1tls.dll`. There are no loose Lua files to `replaceFile`. Replacing the
  executable would mean distributing a modified upstream build, including the
  proprietary launcher, which License Term 2 forbids.
- **Self-updater:** packaged builds look in the save directory's `updates/`
  folder for a newer `gen1recomp-X.Y.Z.love` and prepend-mount it at `/`
  (`Boot.lua`, around line 298), so update files win over everything else,
  including any loose override files. Downloads are started from the launcher
  and applied on the next launch. Source checkouts never self-update.
- **Conclusion:** using the manager to patch the official Windows release does
  not work. There is nothing to patch file by file. A save-directory overlay
  would be an unsupported hack that update payloads shadow, and it would still
  be legally gray.
- **What remains viable with the manager:** distributing our own complete build
  (fork, thin accessibility layer, our own minimal launcher) as a manager package,
  so the manager handles players' installs and updates instead of us writing an
  updater. Not yet checked: whether the manager accepts a standalone game, not
  just a mod for an installed game. Its docs mention portable emulator packages.

### Owner direction (2026-10-31, provisional)

The owner leans toward our own thin build (upstream plus an accessibility layer
plus our own minimal launcher), with Amethyst's manager as a *potential* future
distribution channel. The owner has a caveat that is not yet stated.
**Not authorized:** publishing anything to the manager, creating a catalog, or
contacting Amethyst or upstream.

### Save editor ("cheat app") licensing (checked 2026-10-31, tag v0.3.98)

The owner asked whether the cheat tool attached to upstream's launcher is also
off limits. The only matching tool found is the save editor, `tools/save-editor/`
(party, boxes, items, events, map, Pokédex, trainer). Its README says it is
opened from the launcher's save-slot **Edit** label or standalone with
`love . --editor`. It is **not** in License Term 2's proprietary launcher list,
so it is GPL and reusable with attribution. Only the launcher's Edit button is
proprietary; our launcher would need its own entry point. No file or code-search
hit for "cheat" exists in the tree. The owner confirmed on 2026-10-31 that the
save editor is the tool meant. The old project kept an accessible save editor
built on upstream's `Kit`, which is a carry-over candidate.

### Project goal and Pokémon Access (checked 2026-10-31)

Owner restated the goal: port all of Pokémon Access (`nuive/pokemon-access`
3.1.0, local copy in `../pokemon-access`) to the PC port, plus our own
improvements. Its feature set, from its readme: object list with filters and
renaming (j/k/l), map name and renaming, read on-screen text, pathfinding to the
selected object with HM options, position, battle HP, surrounding tiles, a
wall-aware camera with pathfind-to-camera, and the Unown puzzle helper.

The thin-layer design fits this. Most of these features *read* game state (map,
collision, warps, NPCs, sign text, party, battle) and *send* input. In the PC
port that state lives in Lua tables we can query directly, so they need few or
no hooks, unlike the emulator scripts, which decode RAM. Hooks are mainly needed
for event-driven speech: text box, menus, cursor, battle messages.

**Licensing gap:** neither `nuive/pokemon-access` nor its predecessor
`tspivey/pokecrystal-access` declares a license (GitHub reports none, and the
local tree has no license file). By default that means all rights reserved.
Reimplementing the *features and behaviour* is fine. Copying its code or its
authored data (map and object names, translations, messages) is not, unless the
authors grant permission. Its bundled `a-star.lua` (MIT, RapidFire Studio) and
`serpent.lua` (MIT, Paul Kulchenko) carry their own licenses. No earlier
licensing decision about Pokémon Access was found in `../Documentation`.

**Owner clarification (2026-10-31):** not a one-to-one port. Redo the
Pokémon Access experience our own way.

**Spot check of the old fork** (`../pokemon-gen1-recomp-project`, `git grep`
for nuive, pokecrystal-access, tspivey, RapidFire and serpent): no copied
Pokémon Access code or libraries were found. `src/accessibility/` cites
Pokémon Access only as a behavioural reference, and its comments say so. This
is a string search, not a full provenance audit. **One exception to track:** the
old fork can play Pokémon Access's own sound pack (`pokemon-access/sounds`,
used by `Earcons.lua` and `scripts/play_accessible.py`) when one is configured
externally, with procedural cues as the fallback. Those sounds are unlicensed
third-party assets. Do not bundle them without permission; prefer our own sounds.

**Owner decision (2026-10-31): bring-your-own Pokémon Access sounds**, the same
model as the ROMs. Boundaries: we never ship, host, mirror or repackage the
files. Our launcher may let the player point to a folder they already have, and
may link to the official `nuive/pokemon-access` repository. Our own default
sound set must work fully without the pack. Mapping its filenames (for example
`s_water.wav`) to our events is interoperability, not copying.

### Launcher scope (proposed 2026-10-31, owner asked for lightweight)

The old launcher took roughly 80 hours (owner's figure). The new one is a
spoken list menu with plain text on screen for sighted helpers, and nothing else.

**In scope:** Play (lists only games whose ROM is imported), Import ROM (detect
ROMs in a `roms` folder beside the program, plus drag and drop; reuse upstream's
GPL import, verification and cache code), Edit save (opens upstream's save
editor), Settings (sound pack folder, speech options), Credits (upstream credit,
required, shown and spoken; Pokémon Access acknowledgement), Quit.

**Out of scope:** cartridge art, labels, mascots, themes, animations, online
panel, mod browser, update checker (the manager or a manual download covers
that), multi-generation rooms. Adding any of these needs a fresh owner decision.

**Alternative raised by the owner (2026-10-31): a setup tool instead of a
launcher.** The agent suggested a setup *mode* in the same program, not a
separate application: it runs on first start or from a "Setup" shortcut,
imports ROMs, sets the sound pack and picks a game. Normal start then boots
straight into the chosen game. One shortcut per game (Play Red, Play Blue, Play
Yellow) can bypass the choice. The save editor stays reachable from setup. The
credit must still appear there (License Term 1 covers any "front end, menu
shell, or other program used to start or select the game") and in the game's
credits.

**Owner decision (2026-10-31): setup mode built only from standard Windows
dialogs.** No custom-drawn menus or styling. Message boxes for choices and
confirmations (LÖVE's `love.window.showMessageBox` creates a native box with
custom button labels), and the standard Windows Open dialog for picking a ROM or
the sound-pack folder (LÖVE 11.5 has none built in, so this needs a small FFI
call to the Windows common dialog; check whether upstream already has a desktop
picker first). The user's own screen reader reads these dialogs natively. That
does not conflict with the Prism rule, which covers speech the project itself
generates.

**Superseding owner decision (2026-10-31): a small native Windows launcher
application**, "a generic Windows application with buttons that are properly
labeled for a screen reader", with Amethyst's Accessibility Mod Manager as the
model. This replaces the setup-mode-inside-the-game idea above. Notes:

- One standard window built with stock Windows controls (game list; Play,
  Import ROM, Edit save, Settings and Credits buttons). Setup lives here too.
  The user's screen reader reads the controls natively.
- Agent recommendation: C# with Windows Forms on .NET 10. Stock controls expose
  accessibility names with little effort, and it matches the manager's stack.
  .NET SDKs 6, 8 and 10 (10.0.300) and the desktop runtime 10.0.8 are installed
  on this PC (checked 2026-10-31). Open trade-off: framework-dependent (small,
  needs the .NET Desktop Runtime, as the manager does) or self-contained (larger).
- The launcher starts the game program with command-line arguments (choose game,
  import ROM, open the save editor). Upstream already accepts `--editor`,
  `--save` and `--update`, so the game side needs only a small addition. ROM
  import stays in upstream's GPL Lua code, run by the game program on request.
- It shows the upstream credit (License Term 1). Windows only; acceptable while
  the first release targets Windows.
- Scope guard: the out-of-scope list above still applies.

**Lead to verify:** upstream's `docs/updater.md` describes a `--update`
shortcut path that runs `bootGame` without the launcher on screen, which
suggests the game can start without upstream's launcher. Not yet read in code.

### Decisions before migration (raised and accepted 2026-10-31)

The owner accepted all eight recommended defaults below (in brackets) on
2026-10-31. Item 8 remains a verification task, not a decision.

**Manager role clarified by the owner:** Amethyst's manager installs, updates
and starts the program. It does not choose between games, so our own launcher
still handles game selection (Red, Blue, Yellow), ROM import, settings, the save
editor entry and the credit.

1. First-release game scope [Red, Blue and Yellow only; Gen 2 and 3 later].
2. Upstream base [a fresh copy of the latest release tag, v0.3.98 at time of
   writing, not the old fork's history].
3. Project license: effectively fixed as GPLv3 with upstream's Section 7 terms,
   because this is a derivative. The credit must appear (and be spoken) in our launcher.
4. Version control [git from day one; private GitHub repository once the
   ignore rules keep ROMs, saves, sound packs and caches out].
5. Documentation size [one current-status file, one decision log, a short topic
   doc per subsystem, a hook list; no evidence catalogs or per-version intake folders].
6. Controls [carry over the old project's recorded bindings; review them, don't import blindly].
7. Upstream update rhythm [deliberate, e.g. monthly or for a needed fix, never per release].
8. Prism: confirm the build and license we bundle (still unverified here).
