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

The menu holds Refresh game list, Choose ROM folder, Edit a save, Mods, the three sounds items and Credits.
License Term 1's credit stays on the main screen. The icon is ours, not upstream's.

Android's picker refuses the storage root and the Download folder itself; a folder inside either works.

Not yet: choosing a save slot and zipped ROMs. (Sounds, the save editor, mods and release signing were added
later; their sections are below.)

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

Back on Android 16: the app targets API 36, so Android uses predictive Back and no longer calls
`onBackPressed`; the screen simply finished and left the game's blank activity (the backend) in front.
Found on the emulator on 2026-11-08 while testing the Mods screen; the save editor's earlier test used the
menu's Close. `BackKey.java` registers a Back callback, and both screens also close their backend in
`onDestroy` however they end.

## Mods (2026-11-08)

The owner asked whether Android had the mod browser, and on hearing it did not: "Yes, please. Don't have a
device to test, so it's probably something worth noting." So this screen is **not tested by the owner on a
device**, and no real device (the Thor included) has run it.

It follows the Windows Mods window (`ModsForm.cs`) with standard controls, through the same backend route as
the save editor:

- `launcher/ModBackend` is split like the save backend: `modservice.lua` answers (`installed`, `index`,
  `sources`, `addSource`, `removeSource`, `setEnabled`, `check`), `main.lua` is the Windows stdin loop.
  `AndroidSaveBackend.serve` picks the service from `POCKET_BACKEND` (`save` or `mods`).
- `ModsActivity.java`: a Game dropdown (games imported at least once; on and off are per game, as upstream
  stores them), a Show dropdown (Installed mods or Browse the mod index), a status line read out politely,
  and the list. Selecting a mod opens its actions: Turn on or off for the game, Remove, Details; in the index,
  Install (or Install again or update) and Details. Install asks first and lists any warnings from the index.
- The first time, the same warning as Windows, with the same marker file
  (`pocket-access-mods-warning-accepted`); Cancel closes the screen.
- `ModInstaller.java`, written for this launcher (upstream's installer is in its Term 2 code): https only;
  the zip goes to `mods-incoming`, only files under its shallowest `manifest.json` are unpacked, and a name
  that points outside the folder, more than one mod, or over 4 GiB unpacked refuses the install. Then
  upstream's own manifest check runs through the backend (`check`), the id must match the index's, and the
  new copy replaces `mods/<id>` keeping its `baseroms`. Progress is read out at quarter steps.
- A change takes effect the next time a game starts, as on Windows.

Emulator, 2026-11-08, test build of `main` (run level; nothing heard, not the Thor): the warning, then
"No mods installed"; the index listed 204 mods; 0 EXP Challenge 1.0.1 downloaded and installed, showed as
"installed 1.0.1" in the index and "On" in Installed mods; turned off and shown "Off"; Details listed its
games; Remove emptied `mods`. Back returned to the launcher, and Red then started. Not checked: that an
installed mod loads in a game on Android, and TalkBack reading of this screen.

## Scripted tests on the emulator

`build_apk.py --test-hooks` adds `TestStartActivity`, which sets environment variables from an intent, so
drivers run on Android. Never for a build for players. `tests/access/drivers/android_run.lua` moves to the
pushed test folder and copies what drivers print to `driver.log`. The runs are silent and the emulator has
no window or audio.

## Emulator results (2026-11-05)

Scripted, silent, on the headless x86_64 emulator (Android 16), test build of this branch. Run level only:
nothing here was heard, and the emulator is not the Thor.

| Check | Result |
|---|---|
| Import and boot, all 11 games (`packaged_boot`, 600 frames each) | All finished, no crash; right game and generation; no Term 2 module or file; updater off |
| Imports | Every game imported from a plain ROM path; first driver output 8 s (Gen 1 and 2) to 33 s (Emerald) after start |
| Red controller navigation (`nav_controller`) | PASS: trigger plus D-pad categories and objects, auto-walk took the stairs, guided navigation started and stopped |
| Crystal keys and controller (`gen2_nav_controller`, run without `isolated.lua`) | Every step answered: categories, objects, auto-walk to 1F, guided navigation, stop |
| FireRed navigation (`gen3_nav`) | 13 of 13 PASS, through Route 1 into Viridian City |
| `gen3_nav` on Emerald | 3 FAIL: that driver expects FireRed's Pallet Town, so it does not apply; Emerald's own drivers are below |
| Sounds | Download from the launcher's menu: 33 sounds in `common`, `gb`, `gba`. `sound_pack` on Red: the game's cues use the pack, 23 load from it, none fall back |
| Save editor, Red | Opened, 8 pages; Trainer page fields with ranges and help; money set to 1234 and saved to the real save folder; Close returned to the launcher; reopened with 1234; then Red started |
| Save editor, Crystal | Opened, Party page shown |
| Emerald menus (`rse_menus`) | Finished, no BAD or FAIL |
| Emerald story (`rse_story`, stopped at its 40-minute limit) | 238 journeys planned, 68 refused, as on Windows; 3 FAIL, the same 3 as on Windows from the same commit: story doors and guards that a new game's flags keep shut (`ruby-sapphire-emerald-navigation.md`, Known gaps) |
| After a game or the editor | The launcher came back, and the next game started (new process each time) |

Problems found and fixed on the way:

- Java's loopback address could be IPv6 while the backend connected to 127.0.0.1: the editor now binds 127.0.0.1.
- With no save yet, upstream's default save path is relative on Android: the backend now uses the save folder.
- `os.exit` after the editor closed aborted on a destroyed mutex in Android's render thread, which Android
  reports as a crash: the backend now uses `_exit`.
- `isolated.lua` minimised the window, which on Android sends the app to the background, where SDL pauses
  the game: it no longer does so on Android.
- The game's first announcement named F7 and F8; on Android it now names the controller.

Installed on the Thor 2026-11-05 at the owner's request ("push it to the Thor ... So I can test it"): the
player build (no test hooks) of `main` at `df2b3259`, over the earlier test install, keeping its data. Its
version name is still upstream's `11.5a`.

Owner, 2026-11-05, during the first full setup on the Thor (Emerald imported): "some lines aren't reading",
otherwise "the import looks good". Checked so far: the Thor's log has no refused or failed speech, so this
is not the Crystal problem (Prism refusing text as invalid UTF-8, which `Speech.lua` speaks again as ASCII).
Prism's TalkBack backend sends each line as an announcement and, for an interrupting line, first stops
TalkBack's speech. Launches from the launcher now set `POKEPORT_ACCESS_TRACE=1`, so every line sent is in Android's log for
comparison (decide before a release).

**Open, owner's report outranks the log.** In Emerald's opening, the owner did not hear the line on screen,
"But everyone calls me the POKéMON PROFESSOR.", and insists speech is not working there. The log shows that
line sent, TalkBack requesting it from Google's voice, and about 1.5 s of audio played on the accessibility
stream, the same length per word as lines the owner did hear; nothing stopped it. So the cause is after the
log's reach (audio routing, focus, ducking against the game's sound, or TalkBack itself) and is not found. The
owner chose not to pursue it for now ("Not worth fixing something that might be good for other people").
Next time: capture `dumpsys audio` during a missed line, and try with the game's music off.

## Touch with TalkBack on (research, 2026-11-09)

Decision 66 sets touch gestures for the game with TalkBack kept on. What was found before building:

- **No app-side passthrough.** The public SDK (checked `android.jar` for API 36 and 37) has no way for an
  app to ask TalkBack to pass its touches through, unlike iOS's direct interaction. The only API is
  `AccessibilityService.setTouchExplorationPassthroughRegion` (API 30), which only an accessibility
  service can call. An earlier claim in this session that Android 14 added an app-side request was wrong.
- **Stock TalkBack** (17.1 on the Pixel Tablet) offers games nothing else; Unity's accessibility plugin
  tells players to turn TalkBack off.
- **NVGT Bridge** (github.com/trypsynth/nvgt-bridge, MIT, release 1.2 of 2026-01-27) is a separate
  accessibility service, enabled alongside stock TalkBack. For games switched on in its list it sets that
  passthrough region over the game and gives touch back to TalkBack for dialogs, the keyboard, the
  notification shade, apps on top and screen off. An app declares support with manifest meta-data
  `dev.nvgt.capability.DIRECT_TOUCH` = `true`, and the bridge then switches it on by itself.
- **Backtalk** (a TalkBack fork) has the same direct touch built in.
- **Options:** support NVGT Bridge and Backtalk (the meta-data line, players install the bridge once), or
  write our own service into the APK (players enable it in Accessibility settings; same sideloading
  restriction). Not decided.
- **Not yet tested.** Upstream's on-screen touch controls are still drawn over the game (see above), so a
  first device check needs no new build: with the bridge on, does a tap reach upstream's touch buttons
  while TalkBack runs.
- **Installed on the Pixel Tablet (2026-11-09, owner approved "yeah, grab it"):** NVGT Bridge 1.2 from its
  GitHub release (`com.nvgt.bridge`, sha256 `c5dc2611…7d6411`, signed CN=Aryan Choudhary, the original
  NVGTBridge author; permissions only QUERY_ALL_PACKAGES and VIBRATE, no INTERNET), and Pocket Accessibility
  0.0.3 (sha256 matches the release). Neither is switched on; enabling the service and TalkBack is the
  owner's step. The tablet has no ROM yet.
- **A concern to test:** the bridge works per app, and our launcher (an ordinary TalkBack app) and the game
  are one package, so with the bridge on the launcher may lose Explore by Touch too. Our own service could
  tell the game's activity from the launcher's; the bridge's open pull request #185 (per-view marking)
  would also do it.
- **Built in (decision 66, 2026-11-09):** the owner wants our own service in the APK, not a separate
  install. NVGT Bridge is used only to check on the tablet that passthrough works with TalkBack 17.1.
  Players who sideload our APK will still meet Android's "Allow restricted settings" step before the
  service can be switched on; the launcher must explain it.
- **ROMs on the tablet (2026-11-09, owner's request):** all 17 dumps from `red/` copied to
  `Download/Pokemon ROMs` for the owner's own play.
- **Bridge setup on the tablet (2026-11-09):** the owner enabled the service (it has no launcher icon;
  its settings were opened with `am start -n com.nvgt.bridge/.SettingsActivity`). Double-tapping the
  "Pocket Accessibility, off" row with TalkBack changed nothing (the haptics row did change). A settings
  file enabling `com.pocketaccessibility.app` was pushed to `Download/nvgt-bridge-settings.json` for the
  bridge's restore option. Note for our own service: its switch must work with TalkBack's double tap.
- **First device result (2026-11-09, owner's report):** after the restore, TalkBack worked normally in
  the launcher and the bridge took over on the game screen (`org.love2d.android.GameActivity`, Crystal,
  portrait), so the launcher concern above did not happen with the bridge. The owner reported a tap on
  upstream's on-screen D-pad worked; a screenshot taken afterwards showed the cursor on NEW GAME, so
  the move was not confirmed from the PC.

## Next

1. The owner's tests on the Thor: the new launcher menu, sounds, the save editor, the Mods screen (the owner
   noted they have no device to test it on, 2026-11-08), and navigation with the Thor's own controls.
2. Run a release build on the Thor before publishing one (the emulator cannot run it: arm64 only).

## Release builds (set up 2026-11-05, decision 54)

```bash
python launcher/android/build_apk.py --release --app-id com.pocketaccessibility.app --keystore <key folder> --version-name 0.0.2 --version-code 2 --work <path without spaces> --prism-zip <prism-android.zip>
```

- **App id** `com.pocketaccessibility.app`. Test builds keep `com.pocketaccess.androidtest`, a separate app
  with separate saves. Never change the release id: Android would treat it as a new app, and saves stay behind.
- **Signing key**: RSA 4096, alias `pocket-accessibility`, made once and kept by the owner outside the
  repository with its password. Upstream's `app/build.gradle` reads it through the `GEN1RECOMP_ANDROID_*`
  variables, which the script sets. It refuses a key folder inside the repository. Every release must use
  this key, or Android refuses the update. Certificate SHA-256
  `fc4af609f7d84c8cc5874cd4c1abd7cf6bdcd8929806c03dcfa8349b882d5956`.
- **Version**: `--version-name` is what players see; `--version-code` must grow with every release.
- **Release type**: not debuggable, Java code shrunk. `proguard-rules.pro` keeps Prism's and djinni's
  classes, which native code calls by name; the mapping showed only compiler-made helper classes renamed.
- **No speech in the log**: a release build does not set `POKEPORT_ACCESS_TRACE`.
- **Licenses**: `build_apk.py` writes every bundled library's license (LÖVE, love-android, SDL2, LuaJIT,
  FreeType, OpenAL Soft, mpg123, Ogg, Vorbis, Theora, ModPlug, Oboe/Apache-2.0, AnimaEngine, Prism and its
  parts) to `assets/licenses.txt`, with where the source is. The launcher shows them under Credits, Licenses.
- The test release build: 31 MiB, verified with `apksigner` (signed by this key) and `aapt` (id, version,
  label). Run on the Thor 2026-11-05 as its own app: launcher opened, the sounds download worked, the owner
  chose the ROM folder and started Emerald, which imported (`rom-cache.complete`) and is running with
  TalkBack speaking, no crash. Owner: "looks good". So shrinking did not break Prism.
