"""Builds the Android app: our launcher, the game without upstream's launcher, and Prism.

    python launcher/android/build_apk.py --prism-zip <prism-android.zip> [--app-id ID] [--clean]

Upstream's mobile/android project is copied and edited outside the repository, so
no upstream file changes.  The copy is needed anyway: ndk-build cannot handle a
path with spaces.  Prints the finished APK's path.  See docs/access/android.md.
"""
import argparse
import os
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


def prepare_project(shadow, prism_zip, app_id):
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
    edit(shadow / "gradle.properties",
         ("app.application_id=com.theboisclub.pokemonred.dev", f"app.application_id={app_id}"),
         ("app.name=gen1recomp (dev)", "app.name=Pocket Accessibility"))
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


def copy_launcher(shadow):
    """Our Java and resources, refreshed on every build."""
    target = shadow / "app" / "src" / "main" / "java" / "com" / "pocketaccess" / "launcher"
    shutil.rmtree(target, ignore_errors=True)
    shutil.copytree(HERE / "src" / "com" / "pocketaccess" / "launcher", target)
    shutil.copytree(HERE / "res", shadow / "app" / "src" / "main" / "res", dirs_exist_ok=True)


def pack_game(shadow):
    """The committed game, leaving out what the Windows package leaves out."""
    with tempfile.TemporaryDirectory() as work:
        game = Path(work)
        commit, excluded = package_release.export_game(game)
        shutil.rmtree(game / "launcher", ignore_errors=True)
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
    parser.add_argument("--app-id", default="com.pocketaccess.androidtest")
    parser.add_argument("--clean", action="store_true", help="start again from upstream's project")
    parser.add_argument("--work", type=Path, default=Path(tempfile.gettempdir()) / "pa-android-app",
                        help="build folder; no spaces in its path")
    parser.add_argument("--jdk", default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--sdk", default=os.environ.get("ANDROID_HOME"))
    args = parser.parse_args()
    if not args.sdk or not args.jdk:
        sys.exit("set ANDROID_HOME and JAVA_HOME (JDK 21), or pass --sdk and --jdk")
    if " " in str(args.work):
        sys.exit("ndk-build cannot handle spaces: choose a --work path without any")

    if args.clean:
        shutil.rmtree(args.work, ignore_errors=True)
    if not args.work.is_dir():
        prepare_project(args.work, args.prism_zip, args.app_id)
    copy_launcher(args.work)
    (args.work / "local.properties").write_text(
        "sdk.dir=" + str(args.sdk).replace("\\", "/") + "\n", encoding="utf-8")
    commit = pack_game(args.work)

    wrapper = args.work / ("gradlew.bat" if os.name == "nt" else "gradlew")
    environment = dict(os.environ, ANDROID_HOME=str(args.sdk), JAVA_HOME=str(args.jdk))
    subprocess.run([str(wrapper), "--no-daemon", "assembleEmbedNoRecordDebug", "--console=plain"],
                   cwd=args.work, env=environment, check=True,
                   creationflags=0x08000000 if os.name == "nt" else 0)
    apk = args.work / "app" / "build" / "outputs" / "apk" / "embedNoRecord" / "debug" / "app-embed-noRecord-debug.apk"
    print(f"game from commit {commit}\n{apk}")


if __name__ == "__main__":
    main()
