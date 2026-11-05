# Android

Controller only (decision 52). Work is on the unpushed branch `android-test`. Nothing here is released.

## What the test build proves (2026-11-05)

Throwaway debug APK, built outside the repository from upstream's `mobile/android` (love-android 11.5a)
and this branch's game, with app id `com.pocketaccess.androidtest`. It contains upstream's launcher, so it
must never be distributed (`LICENSE.MD`, term 2).

Run on a headless x86_64 emulator, Android 16, no audio:

| Check | Result |
|---|---|
| APK installs and the game starts | Yes |
| Prism 0.18.3 loads | Yes |
| Prism's choice of output | `Android Text to Speech` (no screen reader running) |
| Text reaches the speech engine | Google's engine logged synthesis requests after `speech ready`; the text itself was not captured |
| Still running after about 40 seconds | Yes |
| Speech heard | **No.** The emulator has no audio |
| Screen reader output (TalkBack) | Not tried |
| ARM, the AYN Thor, a controller, a ROM, gameplay | Not tried |

## What Android needs from Prism

Prism's Windows build is 0.17.3 and has no Android release, so Android uses 0.18.3's `prism-android.zip`.

- **Load it through Java first.** LuaJIT's `ffi.load` is a plain `dlopen`, which does not run `JNI_OnLoad`.
  Prism's stored Java VM then stays null and `prism_registry_acquire_best` crashes on a null pointer
  (read at address 0; established by disassembling the crash address in `libprism.so`). Listing `prism`
  in `GameActivity.getLibraries()` fixes it, and `ffi.load("libprism.so")` then finds the loaded copy.
- **Merge the AAR's manifest.** It declares `PrismInitProvider`, which hands Prism the app context, and the
  query for speech services. `files(...)` drops it; a `flatDir` repository keeps it. This did not stop the
  crash above, but Prism's documentation requires the context.
- **Core library desugaring** (`desugar_jdk_libs`) and **API 26** minimum.
- **64-bit only.** Prism has no 32-bit Android build, so the `armeabi-v7a` filter goes.
- **The config struct grew** in 0.18: `availability_baseline_callback`. `PrismBackend.lua` declares it,
  since `prism_config_init` returns the struct by value and a smaller declaration would be overrun.
  Windows' 0.17.3 fills less of it. The Windows speech unit tests pass (40 of 40; they use a fake
  backend). Real Windows speech has not been run again since this change.

`PrismBackend.lua` asks LÖVE for the system name, because LuaJIT reports Android as `Linux`, and on
Android tries the bare library name first.

The Java and Gradle edits exist only in the throwaway copy so far. They become upstream-file hooks, or
our own app module, when the launcher design is settled.

## Build notes

`ndk-build` cannot handle spaces in paths, so the build runs from a copy outside this folder. SDK API 36,
NDK 25.2.9519653, JDK 21, task `assembleEmbedNoRecordDebug`.

## Next

1. Run on the AYN Thor: USB debugging on, then hear speech and test the controller.
2. Design our launcher: a standard Android app with ordinary controls. Upstream's cannot be used (term 2),
   and term 1 requires its credit to be shown in ours. ROM picking, app id and signing are open. No
   updater on Android.
