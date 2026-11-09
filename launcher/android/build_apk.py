"""Builds the Android app: our launcher, the game without upstream's launcher, and Prism.

    python launcher/android/build_apk.py --prism-zip <prism-android.zip> [--app-id ID] [--clean]

Upstream's mobile/android project is copied and edited outside the repository, so
no upstream file changes.  The copy is needed anyway: ndk-build cannot handle a
path with spaces.  Prints the finished APK's path.  See docs/access/android.md.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import package_release  # noqa: E402  (shares what the Windows package leaves out)

REPO = HERE.parent.parent
MARKER = "pocket-access-package.txt"
TEST_APP_ID = "com.pocketaccess.androidtest"
RELEASE_APP_ID = "com.pocketaccessibility.app"
KEYSTORE_FILE = "pocket-accessibility-release.jks"
KEY_ALIAS = "pocket-accessibility"
LAUNCHER_ACTIVITY = """    <activity
        android:name="com.pocketaccess.launcher.MainActivity"
        android:exported="true"
        android:label="${NAME}"
        android:theme="@android:style/Theme.DeviceDefault">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
    <activity
        android:name="com.pocketaccess.launcher.SaveEditorActivity"
        android:label="Save editor"
        android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboard|keyboardHidden"
        android:theme="@android:style/Theme.DeviceDefault" />
    <activity
        android:name="com.pocketaccess.launcher.ModsActivity"
        android:label="Mods"
        android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboard|keyboardHidden"
        android:theme="@android:style/Theme.DeviceDefault" />
"""


def edit(path, *pairs):
    """Exact replacements; fails when upstream's file no longer has what is expected."""
    with open(path, encoding="utf-8", newline="") as file:
        raw = file.read()
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    for old, new in pairs:
        if old not in text:
            sys.exit(f"{path.name} no longer contains: {old}")
        text = text.replace(old, new, 1)
    with open(path, "w", encoding="utf-8", newline="") as file:
        file.write(text.replace("\n", "\r\n") if crlf else text)


def set_identity(shadow, app_id, version_name, version_code):
    """App id and version, on every build, so one copy serves test and release builds."""
    properties = shadow / "gradle.properties"
    text = properties.read_text(encoding="utf-8")
    text = re.sub(r"(?m)^app\.application_id=.*$", f"app.application_id={app_id}", text)
    text = re.sub(r"(?m)^app\.version_name=.*$", f"app.version_name={version_name or 'test'}", text)
    text = re.sub(r"(?m)^app\.version_code=.*$", f"app.version_code={version_code or 1}", text)
    properties.write_text(text, encoding="utf-8")


def prepare_project(shadow, prism_zip):
    """First build only: the copy and every edit to it."""
    shutil.copytree(REPO / "mobile" / "android", shadow,
                    ignore=shutil.ignore_patterns(".gradle", "build", "local.properties"))
    # 64-bit only: Prism has no 32-bit Android build.  API 26 is Prism's minimum.
    edit(shadow / "love" / "build.gradle", ("abiFilters 'armeabi-v7a', 'arm64-v8a'", "abiFilters 'arm64-v8a'"))
    edit(shadow / "love" / "build.gradle", ("minSdk 19", "minSdk 26"))
    edit(shadow / "app" / "build.gradle",
         ("minSdk 19", "minSdk 26"),
         ("    lint {\n        abortOnError false\n    }\n}\n\ndependencies {\n",
          "    lint {\n        abortOnError false\n    }\n"
          "    compileOptions {\n        coreLibraryDesugaringEnabled true\n"
          "        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n    }\n"
          "}\n\nrepositories {\n    flatDir { dirs 'libs' }\n}\n\ndependencies {\n"
          "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.5'\n"
          # a flatDir dependency keeps the AAR's manifest, which declares PrismInitProvider
          "    implementation(name: 'prism-release', ext: 'aar')\n"))
    edit(shadow / "gradle.properties", ("app.name=gen1recomp (dev)", "app.name=Pocket Accessibility"))
    # A release build shrinks the Java code; Prism's classes are reached from native code by name.
    with open(shadow / "app" / "proguard-rules.pro", "a", encoding="utf-8") as rules:
        rules.write("\n# Pocket Accessibility: Prism and the library it uses are called through JNI\n"
                    "-keep class com.github.ethindp.prism.** { *; }\n"
                    "-keep class com.dropbox.djinni.** { *; }\n"
                    "-keep class com.snapchat.djinni.** { *; }\n"
                    "-keep class com.pocketaccess.launcher.** { *; }\n")
    edit(shadow / "app" / "src" / "main" / "AndroidManifest.xml",
         # Upstream's self-updater and step counter: off or absent here.
         ('  <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n', ""),
         ('  <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />\n', ""),
         ('      android:icon="@mipmap/ic_launcher"\n      android:roundIcon="@mipmap/ic_launcher_round"\n',
          '      android:name="com.pocketaccess.launcher.PocketApplication"\n'
          '      android:icon="@drawable/pocket_icon"\n'),
         # Only our launcher appears on the home screen, and upstream's links open upstream.
         ('        <category android:name="android.intent.category.LAUNCHER" />\n', ""),
         ('      <intent-filter>\n        <action android:name="android.intent.action.VIEW" />\n'
          '        <category android:name="android.intent.category.DEFAULT" />\n'
          '        <category android:name="android.intent.category.BROWSABLE" />\n'
          '        <data android:scheme="gen1recomp++" android:host="launch" />\n      </intent-filter>\n', ""),
         ('    <activity\n        android:name="org.love2d.android.GameActivity"',
          LAUNCHER_ACTIVITY + '    <activity\n        android:name="org.love2d.android.GameActivity"'))
    libs = shadow / "app" / "libs"
    libs.mkdir(exist_ok=True)
    with zipfile.ZipFile(prism_zip) as archive:
        (libs / "prism-release.aar").write_bytes(archive.read("release/prism-release.aar"))


def copy_launcher(shadow, test_hooks):
    """Our Java and resources, refreshed on every build."""
    target = shadow / "app" / "src" / "main" / "java" / "com" / "pocketaccess" / "launcher"
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(HERE / "src" / "com" / "pocketaccess" / "launcher", target)
    shutil.copytree(HERE / "res", shadow / "app" / "src" / "main" / "res", dirs_exist_ok=True)
    if test_hooks:
        shutil.copytree(HERE / "test-src" / "com" / "pocketaccess" / "launcher", target, dirs_exist_ok=True)
        manifest = shadow / "app" / "src" / "main" / "AndroidManifest.xml"
        if "TestStartActivity" not in manifest.read_text(encoding="utf-8"):
            edit(manifest, ('    <activity\n        android:name="org.love2d.android.GameActivity"',
                            '    <activity android:name="com.pocketaccess.launcher.TestStartActivity" android:exported="true" />\n'
                            '    <activity\n        android:name="org.love2d.android.GameActivity"'))


# What the app holds besides our own code, and the license text each needs shipped with it.
# Paths are relative to the repository; Prism's come from its release zip.
BUNDLED_LICENSES = [
    ("Pocket Accessibility and the Pokémon Gen 1 Recompilation Project", "LICENSE.MD"),
    ("AnimaEngine", "src/import/gen5/ANIMAENGINE_LICENSE"),
    ("LÖVE", "mobile/android/love/src/jni/love/license.txt"),
    ("LÖVE for Android", "mobile/android/license.txt"),
    ("SDL2", "mobile/android/love/src/jni/SDL2/LICENSE.txt"),
    ("LuaJIT", "mobile/android/love/src/jni/LuaJIT-2.1/COPYRIGHT"),
    ("FreeType", "mobile/android/love/src/jni/freetype2/docs/FTL.TXT"),
    ("OpenAL Soft", "mobile/android/love/src/jni/openal-soft/COPYING"),
    ("OpenAL Soft: PFFFT", "mobile/android/love/src/jni/openal-soft/LICENSE-pffft"),
    ("mpg123", "mobile/android/love/src/jni/mpg123-1.17.0/COPYING"),
    ("libogg", "mobile/android/love/src/jni/libogg-1.3.2/COPYING"),
    ("libvorbis", "mobile/android/love/src/jni/libvorbis-1.3.5/COPYING"),
    ("libtheora", "mobile/android/love/src/jni/libtheora-1.2.0alpha1/COPYING"),
    ("libmodplug", "mobile/android/love/src/jni/libmodplug-0.8.8.4/COPYING"),
    ("Oboe, and Apache-2.0 for AndroidX and the Java library desugaring", "mobile/android/love/src/jni/oboe/LICENSE"),
]
LICENSE_HEADER = """Licenses of what this app contains. The source of this app, including the unmodified
libraries above, is at https://github.com/Lethal-Lawnmower/pocket-accessibility, and Prism's at
https://github.com/ethindp/prism. Pokémon game data is never included: it comes from your own cartridge dump.
"""


def write_licenses(shadow, prism_zip):
    """One text file the launcher's Licenses screen reads; sections start with a === line."""
    parts = [LICENSE_HEADER]
    for name, path in BUNDLED_LICENSES:
        parts.append(f"=== {name}\n" + (REPO / path).read_text(encoding="utf-8", errors="replace").strip() + "\n")
    with zipfile.ZipFile(prism_zip) as archive:
        for entry in sorted(archive.namelist()):
            if entry.startswith("LICENSES/") and not entry.endswith("/"):
                part = entry.split("/")[1]
                name = "Prism" if part == "prism" else f"Prism: {part}"
                parts.append(f"=== {name}\n" + archive.read(entry).decode("utf-8", "replace").strip() + "\n")
    assets = shadow / "app" / "src" / "main" / "assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "licenses.txt").write_text("\n".join(parts), encoding="utf-8")


def pack_game(shadow):
    """The committed game, leaving out what the Windows package leaves out."""
    with tempfile.TemporaryDirectory() as work:
        game = Path(work)
        commit, excluded = package_release.export_game(game)
        # of launcher/, the game only needs what its save editor and Mods screen run
        for path in (game / "launcher").iterdir():
            if path.name not in ("SaveBackend", "ModBackend"):
                shutil.rmtree(path) if path.is_dir() else path.unlink()
        (game / MARKER).write_text(f"Packaged by launcher/android/build_apk.py from commit {commit}.\n", encoding="utf-8")
        missing = package_release.missing_requires(game)
        if missing:
            sys.exit(f"the game requires modules that were left out: {missing}")
        for why, paths in excluded.items():
            print(f"left out ({why}): {len(paths)} files")
        assets = shadow / "app" / "src" / "embed" / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(assets / "game.love", "w", zipfile.ZIP_DEFLATED, compresslevel=6) as love:
            for path in sorted(game.rglob("*")):
                if path.is_file():
                    love.write(path, path.relative_to(game).as_posix())
    return commit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prism-zip", required=True, type=Path)
    parser.add_argument("--app-id", default=TEST_APP_ID,
                        help=f"the test id by default; a release uses {RELEASE_APP_ID}")
    parser.add_argument("--release", action="store_true",
                        help="a signed release build: needs --keystore, --version-name and --version-code")
    parser.add_argument("--keystore", type=Path,
                        help="the folder holding the release key and its password.txt; never inside the repository")
    parser.add_argument("--version-name", help="the version players see, for example 0.0.2")
    parser.add_argument("--version-code", type=int, help="a whole number that grows with every release")
    parser.add_argument("--clean", action="store_true", help="start again from upstream's project")
    parser.add_argument("--test-hooks", action="store_true",
                        help="add the activity scripted runs start through; never for a build for players")
    parser.add_argument("--work", type=Path, default=Path(tempfile.gettempdir()) / "pa-android-app",
                        help="build folder; no spaces in its path")
    parser.add_argument("--jdk", default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--sdk", default=os.environ.get("ANDROID_HOME"))
    args = parser.parse_args()
    if not args.sdk or not args.jdk:
        sys.exit("set ANDROID_HOME and JAVA_HOME (JDK 21), or pass --sdk and --jdk")
    if " " in str(args.work):
        sys.exit("ndk-build cannot handle spaces: choose a --work path without any")

    environment = dict(os.environ, ANDROID_HOME=str(args.sdk), JAVA_HOME=str(args.jdk))
    if args.release:
        if args.test_hooks or args.app_id == TEST_APP_ID:
            sys.exit("a release uses its own app id and no test hooks")
        if not (args.keystore and args.version_name and args.version_code):
            sys.exit("a release needs --keystore, --version-name and --version-code")
        if REPO in args.keystore.resolve().parents:
            sys.exit("the release key must stay outside the repository")
        password = (args.keystore / "password.txt").read_text(encoding="ascii").strip()
        # upstream's app/build.gradle reads these four
        environment.update(GEN1RECOMP_ANDROID_KEYSTORE=str(args.keystore / KEYSTORE_FILE),
                           GEN1RECOMP_ANDROID_KEYSTORE_PASSWORD=password,
                           GEN1RECOMP_ANDROID_KEY_ALIAS=KEY_ALIAS,
                           GEN1RECOMP_ANDROID_KEY_PASSWORD=password)

    if args.clean:
        shutil.rmtree(args.work, ignore_errors=True)
    if not args.work.is_dir():
        prepare_project(args.work, args.prism_zip)
    set_identity(args.work, args.app_id, args.version_name, args.version_code)
    copy_launcher(args.work, args.test_hooks)
    write_licenses(args.work, args.prism_zip)
    (args.work / "local.properties").write_text(
        "sdk.dir=" + str(args.sdk).replace("\\", "/") + "\n", encoding="utf-8")
    commit = pack_game(args.work)

    wrapper = args.work / ("gradlew.bat" if os.name == "nt" else "gradlew")
    kind = "release" if args.release else "debug"
    subprocess.run([str(wrapper), "--no-daemon", f"assembleEmbedNoRecord{kind.capitalize()}", "--console=plain"],
                   cwd=args.work, env=environment, check=True,
                   creationflags=0x08000000 if os.name == "nt" else 0)
    apk = args.work / "app" / "build" / "outputs" / "apk" / "embedNoRecord" / kind / f"app-embed-noRecord-{kind}.apk"
    if not apk.is_file():
        sys.exit(f"no APK at {apk}: a release built without signing is written under another name")
    print(f"game from commit {commit}\n{apk}")


if __name__ == "__main__":
    main()
