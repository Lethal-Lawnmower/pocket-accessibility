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

Edit save (opens upstream's save editor, decision 5; the editor itself is
not yet screen-reader accessible), Settings (game options before start,
such as the Accessibility page's values), a bring-your-own Pokémon Access
sound folder (decision 8), packaging.
