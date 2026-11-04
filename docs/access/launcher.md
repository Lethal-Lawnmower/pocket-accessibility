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
| Credits (Alt+C) | A read-only text box, readable line by line: project, the upstream credit, Prism, Pokémon Access as inspiration, license, source, the Nintendo disclaimer. |
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

**Paths.** For now the launcher runs from a source checkout: the game folder
is the first folder above the launcher holding `main.lua` and
`src/access/init.lua`; LÖVE is `love\love.exe` beside the launcher or the
standard install. The save folder is `%APPDATA%\LOVE\<identity>`
(`pokemon-love2d`, the same saves the owner uses now). Overrides:
`POCKET_LOVE`, `POCKET_GAME_DIR`, and `POKEPORT_IDENTITY` (passed through to
the game, so tests use a disposable profile). A missing Prism DLL gets a
warning at start: the games run but cannot speak.

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

## Before a packaged release

- **Layout.** One folder: the launcher, LÖVE 11.5 (zlib license), the game
  folder, Prism (MPL-2.0, license and build confirmed first, decision 9).
  The launcher either self-contained (no runtime install, larger) or needing
  the .NET 10 Desktop runtime: to decide.
- **Upstream's launcher files** (Term 2 list in `LICENSE.MD`) left out of the
  build. Three routes would still try to open upstream's launcher, and must
  be closed by a small listed hook before release: a game whose cache fails
  the full check (the ready check now stops this from our launcher, but not
  a cache that breaks between the check and Play), the online, arena and Discord-invite screens that return
  to the launcher (`returnToLauncher`, which restarts the process), and any
  start without a game choice.
- **Save folder.** A fused build keeps saves in `%APPDATA%\<identity>`, not
  under `LOVE`; the launcher must follow whatever the build uses, and the
  owner's existing saves must carry over.
- **Upstream's Discord rich presence:** keep or switch off (owner decision).

## Next

Settings (game options before start,
such as the Accessibility page's values), a bring-your-own Pokémon Access
sound folder (decision 8), packaging.
