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
