# iOS

Planned (decision 67, 2026-11-09). Built by CI since 2026-11-10 (see "Build" and "Launcher"); nothing has run on an iPhone yet. The goal is one complete app (launcher, game,
speech, touch, sounds) per install, because a free Apple account signs for 7 days and allows few apps. Builds are
plain unsigned IPAs that the player signs on the device with their own Apple ID. Target device for testing: the
owner's iPhone 15 Pro Max.

## Upstream's iOS build (read 2026-11-09, upstream v0.3.98 tree)

- `mobile/ios/` with `scripts/build_ios.sh` (macOS and Xcode only). `--fetch` clones `love2d/love` and
  `love2d/love-apple-dependencies` at `main` (`LOVE_SOURCE_REF`, `APPLE_DEPENDENCIES_REF`): an unreleased
  LÖVE 12.0 with SDL3, not a pinned commit. We should pin both refs for repeatable builds.
- `conf.lua` declares `t.version` "12.0" on iOS and "11.5" elsewhere; Windows and Android stay on 11.5.
- The game is staged as `game.love` inside the app. ROMs, mods and saves live in the app's public Documents
  folder (`UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`), visible in the Files app.
- Native bridges in `mobile/ios/native/`: `GRBootstrap.m` (URL scheme, Files inbox sweep), `GRPickerBridge.swift`
  (document picker), `GRHealthBridge.swift` (step counts for a Pokéwalker mod).
- Entitlements: HealthKit only, for that mod. A free account may not be able to sign HealthKit; our build should
  leave it out unless the owner wants the mod.
- Portrait only, bundle id `com.theboisclub.gen1recompplusplus` (override `GEN1_BUNDLE_ID`); we need our own.
- Upstream's launcher is part of the game payload and is proprietary (`LICENSE.MD` term 2). It must be left out,
  as the Android and Windows packages do, so iOS needs our own launcher.

## Prism on iOS (checked 2026-11-09)

Prism 0.18.3 (the version Android uses) ships `prism-ios-arm64.zip` and `prism-ios-simulator-arm64.zip`, each
with dynamic and static libraries. `libprism.dylib` has a `VoiceOverBackend` ("VoiceOver (iOS)") that posts
`UIAccessibilityAnnouncementNotification` and checks `UIAccessibilityIsVoiceOverRunning`, plus an AVSpeech
backend. The zips also contain `libtolk`, `libSRAL`, `libUniversalSpeech` and `libSpeechCore`; only Prism itself
may be loaded or shipped (Tolk is never used). Static linking into the app binary is likely simplest for LuaJIT's
FFI on iOS; not tried. Not heard on a device.

## Our layer on LÖVE 12 (checked 2026-11-09)

LÖVE 12.0 for Windows x64 from LÖVE's own CI (`love2d/love` run 41957924703, commit `def24510`, 2026-11-05),
kept outside the repository. Upstream's `conf.lua` asks for 11.5 off iOS, which makes LÖVE 12 stop at a
version warning, so the runs used a temporary, uncommitted change to declare 12.0. Silent, isolated runs:

| Run | LÖVE 11.5 | LÖVE 12.0 |
|---|---|---|
| `touch_gestures` driver, Crystal, FireRed, Red | all gestures, Hybrid legs, no upstream button pressed | the same |
| `gen3_menus` driver, FireRed | 110 spoken lines, 25 steps, no timeouts or errors | identical text except the random trainer ID |

The same session found and fixed a driver fault unrelated to LÖVE 12: after landscape was cut left and right,
the touch driver's 1024 x 768 window put "bottom" touches in the navigation half. It now places fingers by zone.

Not covered: iOS itself (file paths, LuaJIT without JIT, SDL3 touch on iOS, VoiceOver direct interaction),
Gen 1 and Gen 2 menu drivers on LÖVE 12, and performance.

## Build (step 2)

Written 2026-11-09 on Windows. **First run (2026-11-10, run 42728549413 on `ios-build` at `a1538df9`, macos-15,
12 min 50 s): green.** The build made both apps and the unsigned IPA. The smoke test's own summary in the iPhone
simulator: `[access] speech ready: AVSpeech` (no VoiceOver in the simulator, so Prism chose the system voice),
`say!: Pocket Accessibility ready.`, then `start refused` (expected: no ROM and no iOS launcher yet); app still
running at the end; no Lua error, crash report or uncaught exception. Found in its console:
- the process is still named `gen1recomp++` (upstream's product name), although the display name is ours;
- after `start refused` the app starts the game again and again (the startup lines repeat); harmless here, but the
  refusal must end cleanly on iOS, and our launcher will replace this path anyway;
- SDL notes `UIApplicationSupportsIndirectInputEvents` is missing from the plist (mouse support only).
Not verified: anything on a real iPhone, VoiceOver, touch, a game running (no ROM in CI).

| File | Role |
|---|---|
| `launcher/ios/build_ipa.py` | Builds both apps and the IPA on macOS; `--payload-only OUT.love` exports and audits game.love anywhere. |
| `launcher/ios/simulator_smoke.sh` | Installs the simulator app on a throwaway iPhone simulator, launches it, checks the log. |
| `.github/workflows/ios.yml` | `macos-15`; on pushes to `ios-build` and by hand only. Builds, uploads the IPA and logs (7 days), runs the smoke test. |

How the build works:

- **Pinned sources.** LÖVE `love2d/love` at `def245102c67909f9902095af613b1ae05249b62` (the LÖVE 12 tested on
  Windows above) and `love2d/love-apple-dependencies` at `a5522634f1e581a1ebab73bf3ab4bd7a853b7a3e` (its `main` at
  that time; 2026-07-24, LuaJIT update). Fetched by commit into `mobile/ios/love-src/` in the layout
  `build_ios.sh --fetch` makes (that option takes only branch names). A pins file there forces a fresh fetch
  when the pins change.
- **Upstream's script, unchanged.** `scripts/build_ios.sh --package-only` applies its Info.plist overlay,
  `patch_love_src.py` (native bridges), the game.love wiring and warning settings. No upstream file is edited.
- **Our payload.** game.love is replaced by our own export: `package_release.export_game` and launcher/
  pruning exactly as `build_apk.py`, plus the marker file, then an audit (no launcher, ROM, save or generated
  file; required files and every ROM manifest present).
- **Our identity.** Bundle id `com.pocketaccessibility.app`, display name "Pocket Accessibility", upstream's
  `gen1recomp++` URL scheme and HealthKit text removed from the plist, `CODE_SIGN_ENTITLEMENTS` empty (no
  HealthKit), and the speech-bubble icon drawn by the script in place of upstream's cover art (a project mark).
  The executable keeps LÖVE's name, `love`. *(Corrected 2026-11-10: upstream's `patch_love_src.py` names
  the product `gen1recomp++`, as the first CI run showed; since the launcher pass the product and executable
  are `PocketAccessibility`, see "Launcher".)*
- **Two xcodebuild runs**, Release, arm64 only, deployment target 15.0: simulator signed ad hoc (`-`), device
  with `CODE_SIGNING_ALLOWED=NO`. The device app is zipped as
  `dist/ios/PocketAccessibility-<version>-unsigned.ipa` (`dev-<commit>` without `--version`).
- **Prism** 0.18.3, `prism-ios-arm64.zip` and `prism-ios-simulator-arm64.zip`, downloaded at build time and
  checked against SHA-256 values in the script. Only `dynamic/release/lib/libprism.dylib` is taken, into the
  app's `Frameworks/`, with Prism's `NOTICE` and `LICENSES/` in the app's `licenses/` folder. Read from the
  zips: the library's install name is `@rpath/libprism.dylib`, its minimum iOS is 14.0, and it links only system
  frameworks (Foundation, AVFoundation, UIKit, CoreFoundation, libc++, libobjc). Dynamic was chosen over static
  because the FFI binding then needs one extra search path and no linker changes: on iOS `PrismBackend.lua`
  tries `@executable_path/Frameworks/libprism.dylib` first (`speech.md`). The simulator app is signed ad hoc
  again after the library is added.
- **Licenses in the app** so far: ours (`LICENSE.MD`), LÖVE's `license.txt`, Prism's. SDL3, LuaJIT, FreeType,
  HarfBuzz, Ogg, Vorbis, Theora and ModPlug texts from love-apple-dependencies are not gathered yet: a
  publication blocker, not a build blocker.

What the smoke test checked in step 2 (superseded by "What the smoke test checks" below): newest iOS runtime, newest iPhone; the app launched with
`POKEPORT_ACCESS_TRACE=1` (speech is not silenced: nobody listens to a CI simulator, and the real Prism call
is tested). It reads the app's console (`simctl launch --console-pty`) and the unified log for process `love`.
It passes when it sees `[access] speech ready: <backend>` and `[access] say!: Pocket Accessibility ready.`, no
Lua error or traceback, no crash report or uncaught exception, and the app either still running after 75 s
or ended by `[access] start refused: ...`. Without a ROM and without our iOS launcher that refusal is the
expected ending (`PackagedBuild.noLauncher`). It prints which backend Prism chose.

Unverified, in order of risk: that `patch_love_src.py` still finds its anchors in the pinned LÖVE; that LÖVE
12's iOS build links with the runner's Xcode; that `print` reaches the console or the unified log; that LuaJIT
on iOS provides FFI and `dlopen` accepts `@executable_path`; which backend Prism picks with VoiceOver off;
how LÖVE ends the app on `love.event.quit` (answered from source in "Startup architecture": it restarts the
Lua state; the first CI run's repeating start-up was this). Still to do for step 2: our iOS launcher (built
next, below), VoiceOver labels,
ROM-free Lua tests in the workflow, and the full license set.

## Launcher (written 2026-11-10; CI green the same day)

CI run 42733599145 at `c8fe1339` compiled it on the first try. Smoke test: the app opened on the launcher
(`[pocket-launcher] shown (1)`); with the CI-only `POCKET_LAUNCHER_AUTOSTART=red` the launcher started Red, Prism
loaded (AVSpeech), the game refused (no ROM), and the launcher came back (`shown (2)`) with the refusal; no crash or
Lua error. Not yet on a phone, not with VoiceOver.

Run 42737383943 (`2938eba3`, the triple-tap exit) built fine, but its first plain launch printed nothing and
the app was gone after 25 s, with no crash report; the second launch in the same run passed, and a rerun of the
job passed both. Cause unknown (a cold simulator is the likely suspect, not proven). The smoke test now retries a
completely silent first launch once, with a warning, and keeps the silent run's logs.

Our own native launcher, fresh code in `launcher/ios/native/` (SwiftUI, iOS 15): upstream's launcher stays out
(Term 2) and no Delta or other GPL/AGPL code is used. Standard controls only (a list, buttons, navigation links,
headings, one alert), so VoiceOver reads it with no speech code; the launcher itself never uses Prism.

| File | Role |
|---|---|
| `PocketLauncherBridge.swift` | `PocketLauncherBridge` (Objective-C name, read by Lua): shows the launcher, waits, sets the environment, marks the game screen, the close action, CI autostart, `[pocket-launcher]` log lines. |
| `PocketLauncherModel.swift` | The game catalog (mirrors `GameVersion.lua`; `launcher_catalog_test.lua` checks it), ROM scan by size and SHA-1 (CryptoKit), Import ROMs, refusal file, sounds import and removal. |
| `PocketLauncherViews.swift` | The screens: games, ROMs, Touch controls, Sounds, Credits and licenses. |
| `src/access/IosLauncher.lua` | The game side: calls the bridge from `PackagedBuild.install` and polls the close action from `Access.install`'s update hook. Does nothing off iOS. |

What it does, following Android's launcher where it fits:

- **Games.** One row per game with a recognised dump or an existing import (`<game>/rom-cache.complete` in the
  save folder, as Android checks), with "Ready" or "Imports the first time you play". Choosing a row plays it.
- **Where ROMs are.** On iOS the game's save folder is the app's Documents folder (upstream's
  `patch_love_src.py`), which Files shows as Pocket Accessibility. **Import ROMs** opens the system document
  picker (several files at once) and copies Game Boy and Game Boy Advance dumps (`.gb`, `.gbc`, `.gba`) into
  `Documents/ROMs`, created at every launcher showing so Files shows it. The scan reads `Documents/ROMs` and
  `Documents` itself (not deeper), so dumps dropped there through Files are found after **Refresh game list**.
  Files of 1, 2 or 16 MiB are hashed with SHA-1 and matched to the catalog, as Android's `RomFolderScanner`;
  hashes are kept for the life of the process.
- **Play.** As Android's `GameStarter`: the import variables are cleared, `POKEPORT_PORTMASTER_MANAGED=1`, and
  for a first play `POKEPORT_IMPORT_ROM` (the file in Documents itself, no copy needed), `POKEPORT_VERSION` and
  `POKEPORT_FORCE_IMPORT=1`; always `POKEPORT_GAME`. An import is announced and starts 3 s later, as on Android.
- **Refusals.** The reason the game writes (`pocket-access-start-refused.txt`) is shown in an alert when the
  launcher comes back, then deleted.
- **Touch controls page.** Explains the Game screen, Direct Touch (below), the decision 66 gestures, the
  settings rows and how to leave a game. No service is needed on iOS.
- **Sounds page.** The download is left out: Android's `SoundPacks` unpacks the project's zip, and iOS has no
  zip reader in its SDK (one would have to be written). Instead the page links the same GitHub zip
  (`nuive/pokemon-access`, master) for Safari, explains unpacking it in Files, and **Import sounds from a
  folder** copies only WAV files of at most 4 MiB from the `sounds` folder (or the folder above it) into
  `pocket-access-sounds`, keeping the old pack until the new one is complete, as Android's folder import. Also
  **Remove**.
- **Credits and licenses.** License Term 1's credit is on the main screen; the page lists the texts
  `build_ipa.py` puts in the app's `licenses/` folder.
- **Left out for now:** the save editor, the Mods screen, choosing a save slot, zipped ROMs, re-importing a game
  on purpose, the sounds download.

Upstream's native bridges (`GRBootstrap.m`, `GRPickerBridge.swift`, `GRHealthBridge.swift`) stay in the app:
they are upstream code under its license, compiled by `patch_love_src.py`, and nothing of ours calls them. Their
Files sweep does nothing here (Documents is already the save folder) and the URL scheme they listen for is no
longer declared, so they do not compete with the launcher.

**Build.** After `build_ios.sh --package-only`, `build_ipa.py` copies the Swift files to
`platform/xcode/ios/pocket/` and adds them to love-ios's Sources phase in `project.pbxproj`, the same mechanism
`patch_love_src.py` uses, with its own object ids (`50C4E7A1...`). It also renames the product and executable to
`PocketAccessibility` in love-ios's three configurations (both upstream's `gen1recomp++` and LÖVE's `love`
entries, since each configuration then held two), so the process is no longer `gen1recomp++`, and adds
`UIApplicationSupportsIndirectInputEvents`. The app audit fails if the executable is not `PocketAccessibility`,
does not contain the bridge's class name, or lacks that plist key. Checked on Windows: the project edit applied
to the pinned LÖVE's `project.pbxproj` after `patch_love_src.py`'s own edit (a scratch copy), twice without
duplicating anything; no Swift was compiled.

**First device install (2026-11-10, owner's request "Let's get this on my device"):** the unsigned IPA from
`2938eba3` was copied into the PC's iCloud Drive folder, but the owner's iCloud does not sync (no paid storage),
so the copy was removed again. How the IPA reaches the phone is still to be settled with the owner, one step at
a time. Not yet installed or tried.
Owner's route (2026-11-10): sideload the IPA directly with Sideloadly from the Windows PC over USB (AltStore never
worked for them). With the owner's approval: Apple's website iTunes 12.13.12.3 (signed by Apple) installed, plus
Apple Mobile Device Support 20.0.1.47 from its bundle (the quiet install had skipped it); the Microsoft Store
iCloud removed; Apple's website iCloud 7.21 with Apple Application Support 8.7 and Bonjour 3.0 installed (iCloud
asked for a restart, not yet done). Sideloadly 0.71 Windows installer (sha256 `2E7D9A80…6362E`, 144 MB) is not
code-signed; Defender found nothing; left in the owner's Downloads for the owner to run. Free Apple ID: 7 days,
3 apps; Sideloadly's daemon on the PC can re-sign.
A silent elevated run of the Sideloadly installer was cancelled at the Windows permission prompt; the owner then
chose to restart Windows first (iCloud had asked for it). Next after the restart: install Sideloadly (its NSIS
manifest asks for no elevation, so it may run without the prompt), connect the iPhone by USB, trust the PC,
Developer Mode if asked, sign in to Sideloadly with the owner's Apple ID (the owner types it), sideload
`dist/ios-ci/PocketAccessibility-dev-2938eba38d-unsigned.ipa`, trust the developer profile on the phone.
**Installed (2026-11-10):** after the restart Sideloadly 0.72 installed per user without elevation, saw the trusted
iPhone over USB, and signed in with the owner's Apple ID. One two-factor attempt came back HTTP 401 at
`gsa.apple.com/auth/verify/phone/securitycode`; a fresh code went through. The IPA sideloaded and the owner
"got into the app" (owner's report; launcher, VoiceOver and gestures not yet reported). ROMs over USB (owner's request): `pymobiledevice3` 11.50.3 (PyPI) installed for the user on the PC; Sideloadly
installed the app as `com.pocketaccessibility.app.<team id>` (team id appended), file sharing on. The owner's 17
dumps were pushed with `pymobiledevice3 apps push <bundle> <file> Documents/ROMs/<name>`; a house_arrest listing
shows all 17 with the right sizes, plus one Crystal file the owner had already imported through the app.
**First game on the iPhone (2026-11-10):** the owner's screenshot shows Crystal's title screen running full screen
in portrait (logo, Suicune, "©2001 GAME FREAK inc."), with no on-screen buttons drawn and a thin outline around
the whole screen (probably VoiceOver's focus on the "Game screen" element). Speech, Direct Touch and gestures not
yet reported.

## Startup architecture

Read from the pinned sources (LÖVE `def24510`; SDL 3.4.10 from love-apple-dependencies `a5522634`,
`src/video/uikit/SDL_uikitappdelegate.m` at `release-3.4.10`), kept outside the repository:

- SDL 3.4 uses the scene life cycle: `SDLUIKitSceneDelegate` shows the launch-screen window (level normal + 1)
  and then runs `main()` from `postFinishLaunch` on the main thread; SDL's event pump runs the main run loop.
  When `main()` returns SDL does not exit the process.
- LÖVE's `main()` (`src/love.cpp`) loops over `runlove`, and on iOS forces every quit into a restart: "on iOS we
  should never programmatically exit the app". Each `runlove` is a new Lua state: `boot.lua` runs `conf.lua`,
  creates SDL's window, then requires `main.lua`. That loop was the first CI run's repeated start-up after
  `start refused`.

Chosen: **block inside Lua, at the top of `main.lua`, in a nested run loop.** `PackagedBuild.install` (main.lua's
first line, already ours) calls `IosLauncher.waitForGame`, which calls `+[PocketLauncherBridge waitForGame]`
through LuaJIT's FFI and the Objective-C runtime (`objc_getClass`, `sel_registerName`, `objc_msgSend` cast to
its exact type; upstream's liblove patch reaches its Swift classes the same way). The bridge opens its own
`UIWindow` on SDL's scene at level normal + 2 with a `UIHostingController`, hides SDL's windows from VoiceOver
(`accessibilityElementsHidden`), and runs `CFRunLoopRunInMode` until the player chooses, the pattern SDL's own
message boxes use. Then it sets the variables, hides its window, gives SDL's window back the key, and returns;
`main.lua` reads the variables. When the game quits or refuses, LÖVE's restart runs `main.lua` again and the
launcher returns, in the same process.

Why: no SDL or LÖVE source is patched and nothing is swizzled; no new upstream hook; the same `main.lua` path
as every other platform; and the restart LÖVE already does is the way back. Rejected: swizzling SDL's private
`postFinishLaunch` (private names, and it would still not cover the return), patching `love.cpp`'s loop, and
exporting a C symbol for the FFI (dead stripping and symbol visibility in a Release app). Costs: SDL's window
already exists, black, while the launcher shows; and anything LÖVE leaves running across its restart (threads)
is upstream's existing iOS behaviour.

**Leaving a game.** The game has no quit on a phone (its QUIT returns to the title). The Game screen carries a
VoiceOver custom action, "Close the game and return to the launcher"; Lua checks for it every 10 updates and
calls `love.event.quit()`, which goes through `main.lua`'s `love.quit` exactly as a window close elsewhere
(nothing is saved). Reaching the action needs Direct Touch off (actions are a VoiceOver gesture). Closing the
app from the App Switcher also works and costs nothing but the unsaved game; the app opens on the launcher. A
gesture inside the game for this would be an owner decision and was not added. The owner decided it on
2026-11-10 (decision 66): a **two-finger triple tap on a title screen** (Gen 2 and 3 boot main menus count)
returns to the launcher, saying "Returning to the launcher"; elsewhere it says "To return to the launcher, go
to the title screen first". The same gesture works on Android and with touch on PC. Checked in a silent FireRed run.

## Direct touch

While a game runs, SDL's view (root of the window whose controller is `SDL_uikitviewcontroller`) is one
VoiceOver element: label "Game screen", trait `allowsDirectInteraction`, the close action, and VoiceOver is
moved to it. A timer re-applies this once a second in case LÖVE recreates its window; it stops while the
launcher shows, and the launcher's views never get the trait. TOUCH GESTURES now defaults on for iOS as for
Android (`Settings.touchDefault`), so the ACCESSIBILITY rows appear there too.

What iOS does (web research 2026-11-10, Apple forums and AppleVis; not tried on a device): since iOS 14 the trait
alone is not enough. VoiceOver says the area is a direct touch area and that the rotor turns Direct Touch on for
the app; the choice is remembered per app (Settings, Accessibility, VoiceOver, Rotor, Direct Touch Apps). iOS 17
added `UIAccessibility.DirectTouchOptions` (silent on touch, requires activation); we set none. Unknown until the
phone: whether the rotor can be reached while Direct Touch is on, how the screen-edge gestures behave, and how
our three-finger taps interact with VoiceOver.

## What the smoke test checks (since the launcher)

`simulator_smoke.sh` launches the app twice on a throwaway iPhone simulator, no ROM:
1. **launcher**, 25 s: Lua asked for the launcher, `[pocket-launcher] shown (1)`, no game started and no game
   speech.
2. **refusal**, 75 s, `POCKET_LAUNCHER_AUTOSTART=red` (honoured once per process, CI only): `autostart red`,
   `starting red`, `[access] speech ready`, "Pocket Accessibility ready.", `[access] start refused`, then
   `shown (2)` and `refusal shown:`: the way back works in one process.
Both: still running at the end, no Lua error or traceback, no crash report, no uncaught exception, and no
`[access] ios launcher unavailable`. The unified log is read for process `PocketAccessibility`.

**Verified: nothing yet.** Lua tests on Windows only (`ios_launcher_test` 16/16 with a stand-in bridge;
`launcher_catalog_test` 102/102 with the Swift catalog; `touch_gestures_test` 151/151 with the iOS default). The
Swift has never been compiled. Riskiest for CI, in order: Swift compile errors (written without a Mac); the
FFI lookup of `objc_getClass` and the `objc_msgSend` cast under LuaJIT on iOS; SwiftUI drawing and the picker in
the nested run loop; finding SDL's view by its controller's class name; the duplicate `PRODUCT_NAME` keys.

## Next

1. A CI run of this branch; fix what it shows.
2. First install on the owner's iPhone: launcher with VoiceOver, Import ROMs, Play and first import, Direct Touch
   through the rotor, the gestures, Prism through VoiceOver, the close action, a refusal.
3. Then: save editor and Mods screens, a sounds download (needs a zip reader), save slots.

## Plan

1. Groundwork on the PC (this section): done for the build, Prism and LÖVE 12 as above.
2. A GitHub Actions workflow on macOS: build the IPA with pinned LÖVE refs, our layer, Prism static, our own
   launcher, no upstream launcher; run the simulator without ROMs (launch, launcher screens, VoiceOver labels,
   Prism start-up, ROM-free Lua tests). Needs the owner's approval to push; on a public repository its builds
   would be downloadable, so how artifacts are kept is the owner's call.
3. The owner's one-time phone setup (Developer Mode, a sideloading tool signing with their Apple ID).
4. First install: launcher, game, speech and touch together. VoiceOver direct interaction on the game view
   replaces Android's touch service.

ROMs never go to GitHub or any other server, including private repositories and workflow secrets. ROM-based
testing stays on the owner's PC (the same Lua game code) and phone.
