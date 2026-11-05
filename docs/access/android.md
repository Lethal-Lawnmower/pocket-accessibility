# Android

The game is controller only (decision 52); the launcher is an ordinary touch app (decision 53). Work is on the unpushed branch `android-test`. Nothing here is released.

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

Run on the AYN Thor over wireless debugging (Android 13, arm64, TalkBack on):

| Check | Result |
|---|---|
| APK installs and the game starts | Yes |
| Prism's choice of output | `Android screen reader` |
| Red dump imports (copied to the app's save folder as a `.gb`) | Yes; upstream's picker was not used |
| Game runs from a new save slot | Yes, title intro seen in a screenshot; started with scripted taps on upstream's touch screen |
| Controller | The Thor reports `Xbox Wireless Controller`; the owner was asked to use it in the menus |
| Speech and controller | Owner, asked whether the game speaks and the buttons respond: "Looks good, yeah." (2026-11-05). Brief test; battles, the map and navigation not reported |
| Touch overlay | Upstream's on-screen controls are drawn over the game; not yet removed |

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

## Launcher

`launcher/android` holds our Java and resources; `launcher/android/build_apk.py` builds the APK. The script
copies upstream's `mobile/android` outside the repository and edits the copy (architectures, API 26, Prism,
app name, manifest), so no upstream file changes, and it fails if upstream's text has moved. It also leaves
out everything the Windows package leaves out, including every Term 2 file.

```bash
python launcher/android/build_apk.py --prism-zip <prism-android.zip> --clean
```

ANDROID_HOME and JAVA_HOME (JDK 21) must be set. The Prism zip is not in the repository.

The flow follows melonDS on Android, written fresh (that app is GPL-3.0 and none of its code is used):

1. First start: **Choose ROM folder** opens Android's folder picker.
2. The launcher hashes each dump in the folder and below it, and lists the games it recognises.
3. Selecting a game copies its dump to the app's cache if it needs importing, sets the `POKEPORT_*`
   variables through `Os.setenv`, and starts the game's activity with the `game` extra. The copy is deleted
   when the player returns.
4. If the game refuses to start, its reason (`pocket-access-start-refused.txt`) appears in a dialog.

The menu holds Refresh game list, Choose ROM folder and Credits. License Term 1's credit stays on the main
screen. The icon is ours, not upstream's.

Android's picker refuses the storage root and the Download folder itself; a folder inside either works.

Not yet: Pokémon Access sounds, mods, the save editor, choosing a save slot, zipped ROMs, and a release app
id and signing.

Tested on the Thor, 2026-11-05: the owner chose the folder with the picker and started Red from the list,
and reported "worded fine" (read as "worked fine", possibly dictation). The device agrees: Red's cache marker
exists, no refusal file, the game loaded and is running, and the log shows about 1.6 seconds from speech ready
to game loaded, so the launcher's "a minute or two" notice overstates Red.

Asked to close Red and start it again, the owner reported "So works fine. We're good." The device shows the
first game's process ended and the launcher came back in a new process (the import copy was deleted as
designed), but its log holds no second game start, so a second start from the launcher is not established.
Not tested: Generations 2 and 3, a second import.

## Sounds

The launcher's menu has Download, Import and Remove Pokémon Access sounds, and the once-only notice
offers the download, as on Windows (decisions 50 and 51). `SoundPacks.java` follows `SoundPackImporter.cs`:
only WAV files of at most 4 MiB from the pack's own folders, a zip's names checked so none lands outside the
folder, the old pack kept until the new one is complete. Import takes a folder from Android's picker. The
pack lands in the save folder as `pocket-access-sounds`, where `Earcons.lua` already looks.

## Save editor

The same backend as Windows (`launcher/SaveBackend`, now split: `service.lua` answers, `main.lua` is the
Windows stdin loop). Android has no second program to talk to, so:

1. `SaveEditorActivity` opens a socket on this device only, with a one-time token, and starts the game's
   activity with `POCKET_EDITOR_PORT` and `POCKET_EDITOR_TOKEN` set.
2. `PackagedBuild.install`, on `main.lua`'s first line, sees them and runs
   `src/access/AndroidSaveBackend.lua`, which connects, presents the token and answers until the socket
   closes, then exits. It blocks before anything of the game starts, and because it never pumps events,
   SDL does not pause it behind the editor screen.
3. The editor screen comes back in front. The game's activity shows for a moment first.
4. Closing finishes both activities, then closes the socket; the backend's exit ends the process and Android
   brings back the launcher.

The screen (`SaveEditorPage.java`, after `PagePanel.cs`): a Page dropdown; the list on one side and the
pickers, summary, fields and buttons on the other; Save, Undo, Redo, Reload and Close in the menu; Back asks
about unsaved changes. Opened from the menu's Edit a save, or a long press on a game.

## Scripted tests on the emulator

`build_apk.py --test-hooks` adds `TestStartActivity`, which sets environment variables from an intent, so
drivers run on Android. Never for a build for players. `tests/access/drivers/android_run.lua` moves to the
pushed test folder and copies what drivers print to `driver.log`. The runs are silent and the emulator has
no window or audio.

## Next

1. Confirm a second game start from the launcher in the log.
2. Try a Generation 2 and a Generation 3 game, and time their imports.
3. Decide the app id and signing with the owner before any release.
