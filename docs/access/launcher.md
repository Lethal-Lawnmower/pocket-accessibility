# Launcher

Our own launcher (decision 4): a small Windows Forms app in
`launcher/PocketLauncher/` that picks a game, imports ROMs and starts the
game program. Upstream's launcher is proprietary (License Term 2) and is
never used. Status (2026-11-01): first working version; the owner opened
it, found the stale-import problem (fixed), and approved it ("Looks good").

## What it does now

| Control | Behaviour |
|---|---|
| Games list (Alt+G) | Every game upstream supports (Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, LeafGreen, Ruby, Sapphire, Emerald; owner request 2026-11-01), the ones our speech does not cover yet marked "no speech yet", each "<name>, imported", "not imported" or "needs importing again" (imported by an older build). Starts on the first playable game. Enter plays the selected game. |
| Play (Alt+P) | Starts the selected game directly. The launcher minimises while the game runs and comes back with focus on the list when the game closes. A game that is not imported gets a message pointing to Import ROM. |
| Edit save (Alt+E) | Opens the native save editor on the selected game's current save (`save-editor.md`), over the launcher until it closes. Same import check as Play. |
| Mods (Alt+M) | Opens the Mods window for the selected game, below. |
| Import ROM (Alt+I) | A standard Open dialog for `.gb`, `.gbc` and `.gba`. The file's SHA-1 says which game it is; anything else is refused with a message. The game program imports it and quits; a message box says whether it worked. |
| Credits (Alt+C) | A read-only text box, readable line by line: project, copyright, the upstream credit, Prism, Pokémon Access as inspiration, license, the no-warranty statement, source, the Nintendo disclaimer. License (Alt+L) and Third-party notices (Alt+T) open those texts the same way. |
| Exit (Alt+X) | Closes the launcher. |
| Credit line | Upstream's required credit (License Term 1), always visible in the window. |
| Status bar | Ready, playing, importing, or what went wrong. Results the player must hear also come as message boxes, which screen readers announce. |

A ROM dropped on the launcher's icon, or opened with it, is imported at
start. Only standard controls with explicit accessible names; the tab
order is the reading order.

## How it starts the game

Through environment variables upstream's `main.lua` already reads, so the
game needs no change (`architecture.md`, "Launcher to game interface"):

| Variable | Purpose |
|---|---|
| `POKEPORT_GAME=<id>` | Boot that game directly, skipping upstream's launcher |
| `POKEPORT_VERSION`, `POKEPORT_IMPORT_ROM`, `POKEPORT_IMPORT_ONLY=1` | Import a ROM headless and quit |
| `POKEPORT_PORTMASTER_MANAGED=1` | Keeps upstream's self-updater off (`src/update/Boot.lua`, `Check.lua`, `Prelaunch.lua` check it; it changes nothing else). Source checkouts never self-update; a packaged build would replace our layer with plain upstream |

Never `--game` on the command line (fails before `main.lua` from source).
A game started with `POKEPORT_GAME` exits when its window closes (upstream
#887), so the launcher sees the game end.

**Imported or not.** The launcher asks the game: `launcher/ReadyCheck` is
a windowless LÖVE program (no window, so it never takes focus) that loads
the game's own `src/import/CacheContract.lua` against the same save folder
and writes "ready" or "missing" per game (about 0.1 seconds). A missing
game whose cache marker (`<save folder>\<game>\rom-cache.complete`) names
one of its ROMs was imported by an older build: "needs importing again".
Only if the check cannot run does the launcher fall back to the marker
alone. Imports always pass `POKEPORT_FORCE_IMPORT=1`; without it an
import-only run of a game the check accepts boots the game instead.

Why: on 2026-11-01 the first version read only the marker. The owner's real
profile held caches from an older build (format v10; this build needs v12
to v17), the launcher called Crystal imported, and Play opened upstream's
own launcher with "Update required". The ready check now lists all six
games there as needing importing again.

**Paths.** Packaged, the game folder is `game` beside the launcher. From a source
checkout it is the first folder above the launcher holding `main.lua` and
`src/access/init.lua`. LÖVE is `love\love.exe` beside the launcher or the
standard install. The save folder is `%APPDATA%\LOVE\<identity>`
(`pokemon-love2d`, the same saves the owner uses now). Overrides:
`POCKET_LOVE`, `POCKET_GAME_DIR`, and `POKEPORT_IDENTITY` (passed through to
the game, so tests use a disposable profile). A missing Prism DLL gets a
warning at start: the games run but cannot speak. The launcher checks the same places as the game (`speech.md`).

**Game list.** `GameCatalog.cs` mirrors ids, cache folders and accepted ROM
hashes from `src/core/GameVersion.lua`; `tests/access/launcher_catalog_test.lua`
fails when they drift.

## Build and run

```
dotnet build launcher/PocketLauncher -c Release
launcher\PocketLauncher\bin\Release\net10.0-windows\PocketLauncher.exe
```

Needs the .NET 10 SDK to build and the .NET 10 Windows Desktop runtime to
run. Build output is ignored by git.

## Mods window (decision 42)

The first time a profile opens it, a Windows message box says mods are not endorsed or tested,
accessibility may break, and they are other people's code; Cancel backs out. OK leaves a marker file,
`pocket-access-mods-warning-accepted`, in the save folder. The window has two tabs, with Control+Tab
between them:

- **Installed:** a checked list. Space turns the selected mod on or off for the selected game only,
  written where the loader reads it (`options.modsByVersion`); arrow keys never toggle. A read-only
  details box follows, and Remove (Alt+R), which asks first and deletes the folder. Mods that ship with
  the game can be switched but not removed.
- **Find mods:** search (Alt+S), "Only mods that could be for this game" (Alt+O, on by default), the list,
  a read-only details box with upstream's compatibility warnings, Install (Alt+N), From zip file (Alt+Z),
  Refresh list (Alt+F) and Indexes (Alt+D). Install asks first and repeats the warnings. Installing a listed
  mod again is how it updates.
- **Game filter:** of 196 official listings, 137 name no games, and that says nothing about the mod: Emerald
  Lens and the QoL Suite are Gen 3 and name none. So listings naming this game come first, then those naming
  none, marked "games not listed". The first version treated no games as Gen 1 and hid them, which was wrong.
  After an install, the mod's own manifest decides, and the message says if it will not run on this game.
- **Indexes:** a list with the official index, which cannot be removed; add by `owner/repo` or https address,
  after a warning; remove the selected one. The official index comes first, so another index cannot replace
  one of its listings. Details name the other index a listing came from.
- **From zip file:** a standard Open dialog, then a warning that nothing has checked the file. The same
  unpacking and manifest check as a listed mod, using the id in its manifest.

Parts:

- `launcher/ModBackend`: windowless LÖVE program, like the save backend, with the same `@@PA ` JSON lines
  through `BackendClient.cs`. Commands: `index` (`version`, `force`), `installed` (`version`), `setEnabled`
  (`version`, `modId`, `enabled`), `check` (`folder`, `version`), `sources`, `addSource` (`input`),
  `removeSource` (`feed`). Carts in the feed are left out.
- `ModInstaller.cs`: https only; the shallowest `manifest.json` marks the mod's root (of 25 real zips
  sampled, 20 at the top, 5 one folder down); anything that climbs out is refused and nothing is written
  outside a scratch folder (`mods-incoming`) until the game's own manifest check passes and the id matches
  the listing. An update carries over `baseroms`, files the player imported for that mod. Limits: 2 GB
  download, 4 GB unpacked.

Not done:

- **Dependencies are not installed for you.** The warning names what is missing (5 of 196 listed mods
  have dependencies). Upstream's installer does more here; ours is a first version.
- **Mods that need imported files or asset packs** cannot be set up: upstream does that in its own
  launcher's Importers tab, which we cannot use. They install, then the game skips them. Example from the
  test: "required asset pack unavailable".
- **Mod options, load order, per-mod update checks and carts** have no controls here.
- **Other indexes are unvetted by us.** Found on GitHub, 2026-11-03: forks of the official index with about 238
  mods, 42 not official, including 24 single FireRed `frlg_qol_*` mods; and a separate one with 303, 114 not
  official, Gen 1 focus. Search GitHub for `gen1recomp-mod-index`.
  The official index holds some releases that fail its sandbox scan, and blocks one author who published a
  sandbox escape (its `blocklist.json`), so a listing absent from it may be absent for a reason.
- **Speech:** a mod's own screens speak only as far as decision 17 reaches.

## Verification: Mods window (2026-11-03)

Scripted only, on disposable profiles; the owner has not tried it, and no screen reader was involved.
UI Automation is the interface NVDA uses, so this shows names and states are exposed, not how they sound.

| Level | Result |
|---|---|
| Build | To a separate folder, because the owner's launcher had the normal one open: no warnings, no errors. |
| Live index | 196 mods; 29 for Crystal, 189 for Red. |
| Warning | Shown first time; Cancel leaves no marker and no window; OK opens it; not shown again. |
| Install | Brief Oak from the live index through the window: files in `mods/oak_brief`, scratch folder gone. |
| On and off | Space and UI Automation's toggle both change the row and `options.lua`; arrow keys change nothing. |
| In game | The game's loader, on a copy of a Red profile (`tests/access/drivers/mods_loaded.lua`): on gives `state loaded`, off gives `state disabled`. The mod's effect in play was not checked. |
| Install bar (2026-11-04, owner: "we should probably have an installer bar") | A standard progress bar named "Install progress" shows only during an install; the status strip gives the stage and percent; each stage and quarter is raised as a UI Automation notification, the standard way a window tells a screen reader, not a speech integration. The installer's reports were run on Brief Oak from the live index. The window's bar itself: built, not seen or heard; UI Automation cannot read a window on the separate test desktop. |
| Layout | First version: Install and Refresh sat behind Close on Find mods. Seen in the owner's screenshot; the UI Automation positions had logged it and I missed it. Fixed by letting the lists and details boxes take the spare height. Positions rechecked at normal size and at the smallest size (520 by 480): no control reaches Close. |
| Remove | No keeps the folder, Yes deletes it; Remove is disabled for mods that ship with the game. |
| Zips | 12 made-up zips directly through the unpacker, including `../`, backslash, absolute, rooted and `:` paths: normal layouts unpack, the rest are refused, nothing escapes; an update keeps `baseroms`. A throwaway test, not in the repository. |
| Game filter | FireRed: 148 rows, the 11 naming it first, then those naming no games; Emerald Lens now listed. |
| Indexes | A fork of the official index added through the window: 238 mods; plain http refused; official cannot be removed; removed again: 196, installed mods stay. |
| Other index's mod | Auto Surf installed from that index; on a copy of a FireRed profile the loader reports `state loaded`. Effect in play not checked. |
| From zip file | The button opens the Open dialog, but the test could not type into it on the second desktop, so the dialog step is not tested. Past the dialog, with a stand-in for the backend's check: a zip installs by its manifest id and the chosen file is kept; an invalid manifest and an id holding a path are refused. |
| Owner (2026-11-03) | Reports HeartGold and SoulSilver music playing in Crystal through a mod on the real profile: "All is perfect in life." Speech still works with it, by the owner's ear. |
| Not tested | A real failed download; a mod with dependencies; a real update; the 2 GB and 4 GB limits. |

The window test ran on a second Windows desktop (`CreateDesktop`), so it could not take the owner's focus
or keys while a game was open. Use this for launcher tests from now on.

## Verification (2026-11-01)

| Level | Result |
|---|---|
| Build | `dotnet build -c Release`: no warnings, no errors. |
| Accessibility tree | Read through Windows UI Automation (the interface NVDA uses): window "Pocket Accessibility"; text "Games:" (Alt+G); list "Games" with six items ("Pokémon Crystal, imported", "Pokémon Gold, not imported" ...); buttons Play, Import ROM..., Credits, Exit with Alt keys; the credit text; status bar "Status" with "Ready.". |
| Import and Play | Disposable profile, driven through UI Automation: a Crystal ROM passed to the launcher was identified and imported ("Pokémon Crystal, imported"); the confirmation box read "Pokémon Gold imported. Press Play to start." in a second run; Play started Crystal directly (a probe driver recorded `version=crystal phase=play`, no upstream launcher) and the launcher returned to Ready when the game closed. |
| ROM identification | All seven of the owner's dumps hash to catalog entries. |
| Owner's first try (2026-11-01) | Crystal was listed as imported and Play opened upstream's launcher ("Update required"): the cache was from an older build. Fixed with the ready check: the list on the owner's profile now reads "needs importing again" for all six games, and a test profile still reads Crystal imported (UI Automation). |
| Owner | Opened on the owner's profile after the fix: "Looks good"; push approved. Not yet used to import and play a game. |

## Packaged release

Nothing is published; a packaged release needs the owner's approval (decision 19).

```
python launcher/package_release.py --dotnet self-contained --out <new folder outside the repository>
```

The script exports the game with `git archive HEAD`, so only committed files can go in, from an allowlist in
the script. Only LÖVE and Prism come from outside the repository. Its last step audits the finished folder:
no ROMs, saves, caches, logs, `.pdb`, `tolk.dll` or `portable.txt`; no launcher files; no other program files;
every `require` in the kept Lua resolves. It needs git, the .NET 10 SDK, LÖVE 11.5 and the unpacked Prism release
(`--prism-release`; the DLL must match that release byte for byte, or its licenses might not apply).

| In the folder | What |
|---|---|
| `PocketLauncher.exe` | One file, no `.pdb`. |
| `love\` | LÖVE 11.5, the nine files it needs. |
| `game\` | `main.lua`, `conf.lua`, `src`, `assets`, `data`, `tools\save-editor`, the ROM manifests, `LICENSE.MD`, `README.md`, `launcher` (its source, and the three backends it runs), `local-deps\prism\prism.dll`, and the marker `pocket-access-package.txt`. |
| `licenses\`, `THIRD-PARTY-NOTICES.txt`, `README.txt` | Every license text the notices name. The notices also open from Credits. |

**Left out:** every Term 2 file (`src/import/RomImporter.lua` whole, because it holds launcher interface code);
launcher-only screens that are not on the Term 2 list by name but cannot work without it (`src/import/online/`, `BoxPanel`,
`BoxUI`, `BoxTools`, `BoxDetails`, `BoxOrganizer`, `ShowcaseEditor`, `LauncherSplash`, `LauncherThemeVideo`); `mods/`
(no mod is bundled, decision 42; `mods/example_mew_starter` holds sprites generated from a ROM cache); upstream's unused logos
(`assets/logo` except `pokemon_logo.png`, which the title screen draws); every other top-level file and folder. Upstream's
`scripts/pack_love.sh` cannot be used: it requires `LauncherView.lua` and packs everything.

**How the game runs without those files.** `src/access/PackagedBuild.lua`, active only when the marker exists:

- `src.import.RomImporter` resolves to `src/access/PackagedImporter.lua`: the GPL import steps only, written from those
  functions of `RomImporter.lua` (`isReady`, `startData`, `_startExtractThread`, `_pumpExtract`, `_completeImport`). No
  interface code was used. The cache it writes is compared with upstream's below.
- `src.mods.LauncherMods` and `src.import.LauncherSplash` resolve to small stand-ins.
- **Routes that opened upstream's launcher now end the program.** A cache failing the full check at Play, or a start
  with no game: the game writes the reason to `pocket-access-start-refused.txt` in the save folder and exits with code 40;
  our launcher says it in a message box and refreshes the list. Quitting from a game or arena screen ends the process, and our launcher
  comes back. A Discord invite or outside launch request is ignored, so a running game is not dropped. A
  failed box-storage recovery at boot is refused the same way, with its own message.
- `HostShell.restart` only quits, and a leftover relaunch marker is removed, because it would turn the next Play into
  a start with no game.
- Upstream's updater cannot run: unfused and not version-stamped already keep it off, and the module turns it off
  for a direct start too.

**Saves.** Unfused, so saves stay in `%APPDATA%\LOVE\pokemon-love2d`, the folder source runs use. Nothing moves.

**Paths.** `GamePaths.cs` looks for `game` and `love\love.exe` beside the launcher first; no environment variables needed.

**Self-contained or runtime-required: the owner's decision.** `--dotnet` has no default.

| | Self-contained | Runtime required |
|---|---|---|
| Size, unzipped | 114.6 MiB | 65.6 MiB |
| Size, zipped | 66.1 MiB | 22.3 MiB |
| Player must install | Nothing | The .NET 10 Desktop Runtime. Without it Windows shows a .NET message, not checked with a screen reader. |
| .NET inside the package | Yes, so its license terms apply to what we pass on | No |
| Text on disk | The runtime pack the build copies in carries the MIT license and third-party notices; the package includes both. `C:\Program Files\dotnet\LICENSE.txt` is a separate Microsoft license for the install. Which governs has not been confirmed by anyone qualified | Not needed |

**Known gaps.**

- `--editor` on a direct start of the game program opens upstream's editor, and an icon draw would fail: its icons are in
  `assets/launcher`. Our launcher never does this; it uses its own window and backend.
- `IssueReport.lua` links to upstream's tracker. Its only caller is `RomImporter.lua`, so nothing in the package reaches it.
- The `LauncherMods` stand-in reports no mods to account sync. Sync needs a sign-in in upstream's launcher, so it should not
  arise, but that path was not run.
- `.github/workflows/release.yml` is upstream's, unchanged: pushes to `main` run upstream's packaging, if Actions are on. Not touched.
- **Upstream's Discord rich presence:** still on, as from source (owner decision).
- Prism stays at 0.17.3 (`speech.md`).

## Verification: packaged folder (2026-11-03)

By script only, on disposable profiles, on a second Windows desktop. No one has listened to it or played it, and it was not
run on a second PC, so a PC with no .NET, no LÖVE and no Visual C++ runtime is untested.

| Level | Result |
|---|---|
| Build | The script, both `--dotnet` choices. Audit passed: 2,264 files; 61 left out by rule, plus `mods/`. No local paths in the runtime-required launcher, the one form whose program bytes can be searched. |
| Import | Red, Crystal, Emerald from the package. Red and Crystal caches byte-identical to upstream's importer from source (532 and 1,347 files). Blue through the launcher, with the ROM passed to it. Emerald's dump came from another folder; FireRed's import was not run, no clean dump being in the ROM folder. |
| Boot, driver | Red, Crystal, Emerald and FireRed (a copy of a test profile's cache), 600 frames each, no errors. No Term 2 module or file present, unfused, updater off with no environment variable, saves in `%APPDATA%\LOVE\<identity>`. |
| Boot, as Play starts it | Red, Crystal, FireRed with no driver: running with the game's window title after 25 seconds; closed with exit 0; intro and title speech logged (Red's title screen; the other two reached their intros). |
| Launcher | No environment variables: found `game` and `love`; ready check listed the imported games. Play started `love\love.exe` on `game`, and the launcher came back Ready on close. Runtime-required launcher: same list. |
| Refusals | Cache marker broken after the list was read, then Play: message box "Pokémon Red did not start...", no game process left, list refreshed. No game chosen: exit 40 and the message. Scripted start of a game not imported: exit 40. |
| Returns | Through the driver host on Red and Emerald: invite and launch request ignored, game kept running; arena-style return ended the process, exit 0, no marker left, nothing restarted. A real Discord invite was not sent. |
| Stale marker | A leftover relaunch marker: Red still started, marker gone. |
| Failed box recovery | Not run; source read only. |
| Credits | Copyright, no-warranty line, FireRed. License (39,539 characters) and Third-party notices open and read through UI Automation. |
| Mods, Edit save | Mods window: warning, then 196 mods from the live index. Edit save on a copied Red save: the window lists the party. Nothing edited or installed. |
| Prism | `prism.dll` loaded from the package (`speech ready: OneCore` on the second desktop, with silent runs on). Choosing NVDA from the package and audible speech are **not** tested. |
| Not tested | A real play session or save from the package; Gold, Silver, Yellow, LeafGreen, Ruby, Sapphire imports; a mod running from the package; a second PC. |

## Tools menu and Pokémon Access sounds (2026-11-05)

The owner: "Can we have it be in the alt menu?... Have basically check for updates and import Pokemon Access sounds." A standard menu bar with Tools: Check for updates (packaged only), Import Pokémon Access sounds, Remove Pokémon Access sounds. The updates button moved here.

The first time the launcher opens, unless sounds are already imported, a native task dialog says the sounds are not included and offers Download sounds or Not now (owner, 2026-11-05: built-in sounds "are meant only to hold you over"; shown once). A marker in the save folder keeps it from showing again. Tools has Download Pokémon Access sounds too, which asks first.

The download (decision 51) takes that project's current zip straight from its GitHub repository to the player's PC, keeps only real WAV files of 4 MiB or less under its `sounds` folder, and shows a bar and announcements. If the repository is gone, it says so, and the built-in sounds stay.

Import takes a folder the player already has (decision 8: never shipped or hosted): the sounds folder or the folder above it, needing `common` and `gb`. `SoundPackImporter.cs` copies WAV files of 4 MiB or less to `pocket-access-sounds` in the save folder through a scratch folder, keeping the old pack until the new one is complete. `Earcons.new` uses it when no other path is set; a cue with no file there falls back to the built-in sound. Not bundled, not in the package.

Owner's test, 2026-11-05, on their real profile with Crystal: "Yeah, it works great." Emerald too: "Emerald works. We're good." This covers the notice, the download and the sounds as they heard them in Crystal.

## Updates (2026-11-04)

The owner: "We could make a separate updater app then." `launcher/PocketUpdater` is a second small program with standard controls. The launcher's Tools menu, Check for updates (shown only when
`PocketUpdater.exe` is beside it), starts it with `--from-launcher` and closes, so the launcher can be replaced; the updater reopens the launcher when it closes.

- **Asks** this repository's `releases/latest`. It takes only an asset named `PocketAccessibility-*-windows-x64.zip`, only from this repository's download address over https, and only if GitHub reports its SHA-256 (the asset's `digest`).
- **Installs** after the player presses Update now, with no launcher or game from this folder running: download, checksum, unpack to `update-incoming`, check the required files and that `version.txt` matches the release, then move each packaged item into `update-old` and the new one in. Any failure puts every item back. Files the package does not hold are left alone. Saves, imports and mods are in the save folder.
- **It does not replace itself.** The owner: "The updater should be a one-and-done thing, right?" `PocketUpdater.exe` is skipped in the swap, so a fixed updater reaches players only through a fresh download of the zip.
- **No check at launch:** it asks GitHub only when the player chooses to. Add one if the owner wants it.
- **Announcements:** bar named "Update progress", status strip, and automation notifications for each stage and quarter, as in the Mods window.
- `package_release.py --version` writes `version.txt`, publishes both programs and writes the zip. A release's tag is `v<version>`. A source checkout has no updater, and its button is hidden.

Self-contained, each program holds its own .NET: the updater is 49.2 MiB unpacked and takes the zip from 66.1 to 109.9 MiB. Every update downloads that whole zip.

## Verification: release 0.0.1 (2026-11-04)

Self-contained, from commit f6c0815f (the zip with the updater and the Discord link), 164.2 MiB unzipped, 109.9 MiB zipped. By script only, on a disposable profile, on a second Windows desktop, with the package's own LÖVE. No one has played or heard it,
and it was not run on a second PC. All eleven games, with their newest revisions in Gen 3: import exit 0, then a 600-frame boot through the driver, packaged, updater off, no traceback, and the ready check
says ready for each. The launcher stayed open for 25 seconds. Its window could not be read on that desktop, so its list and Play were not driven this time.

Owner's calls, recorded 2026-11-04 ("do whatever you need to do"; name: "release 0.0.1"): self-contained .NET, so nothing else needs installing; upstream's Discord rich presence left on as upstream ships it; 61 upstream
files and `mods/` left out as above; Prism 0.17.3; the source is the package's game folder plus the tagged commit. If the ready check cannot run, the list falls back to the marker and Play's refusal message is the safety net.

## Next

Settings (game options before start,
such as the Accessibility page's values), a bring-your-own Pokémon Access
sound folder (decision 8).
