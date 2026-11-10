# iOS

Planned (decision 67, 2026-11-09). Nothing is built for iOS yet. The goal is one complete app (launcher, game,
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

Written 2026-11-09 on Windows; **it has never run**. Nothing below is verified on macOS, in the simulator or on
a phone until the first workflow run says so.

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
  The executable keeps LÖVE's name, `love`.
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

What the smoke test checks (`simulator_smoke.sh`): newest iOS runtime, newest iPhone; the app launched with
`POKEPORT_ACCESS_TRACE=1` (speech is not silenced: nobody listens to a CI simulator, and the real Prism call
is tested). It reads the app's console (`simctl launch --console-pty`) and the unified log for process `love`.
It passes when it sees `[access] speech ready: <backend>` and `[access] say!: Pocket Accessibility ready.`, no
Lua error or traceback, no crash report or uncaught exception, and the app either still running after 75 s
or ended by `[access] start refused: ...`. Without a ROM and without our iOS launcher that refusal is the
expected ending (`PackagedBuild.noLauncher`). It prints which backend Prism chose.

Unverified, in order of risk: that `patch_love_src.py` still finds its anchors in the pinned LÖVE; that LÖVE
12's iOS build links with the runner's Xcode; that `print` reaches the console or the unified log; that LuaJIT
on iOS provides FFI and `dlopen` accepts `@executable_path`; which backend Prism picks with VoiceOver off;
how LÖVE ends the app on `love.event.quit`. Still to do for step 2: our iOS launcher, VoiceOver labels,
ROM-free Lua tests in the workflow, and the full license set.

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
