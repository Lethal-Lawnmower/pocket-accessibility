"""Builds Pocket Accessibility Touch, the optional companion app that holds the touch service
(decision 73), with the Android SDK's own tools: aapt2, javac, d8, zipalign and apksigner.
No Gradle and no upstream code: the app is this folder only.

    python launcher/android-touch/build_touch_apk.py --out <file.apk>
        a test build: app id com.pocketaccess.touchtest, signed with the Android debug key
    python launcher/android-touch/build_touch_apk.py --release --keystore <key folder>
        --version-name 0.0.5 --version-code 1 --out <file.apk>
        the release: app id com.pocketaccessibility.touch, signed with the release key (the same
        key as the game app; the folder holds pocket-accessibility-release.jks and password.txt)

Needs ANDROID_HOME (build-tools and platform 36) and JAVA_HOME (JDK 17 or later).
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
REPO = HERE.parent.parent
TEST_APP_ID = "com.pocketaccess.touchtest"
RELEASE_APP_ID = "com.pocketaccessibility.touch"
KEYSTORE_FILE = "pocket-accessibility-release.jks"
KEY_ALIAS = "pocket-accessibility"
MIN_SDK, TARGET_SDK = 30, 36
EXE = ".exe" if os.name == "nt" else ""
BAT = ".bat" if os.name == "nt" else ""


def tool(sdk, name, suffix):
    builds = sorted((sdk / "build-tools").iterdir(), key=lambda p: [int(x) if x.isdigit() else x for x in p.name.split(".")])
    path = builds[-1] / (name + suffix)
    if not path.exists():
        sys.exit(f"{path} not found")
    return str(path)


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        sys.exit(f"failed: {command[0]}\n{result.stdout}\n{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--release", action="store_true")
    parser.add_argument("--keystore", type=Path, help="the release key folder; never inside the repository")
    parser.add_argument("--version-name", default="test")
    parser.add_argument("--version-code", type=int, default=1)
    parser.add_argument("--sdk", type=Path, default=os.environ.get("ANDROID_HOME"))
    parser.add_argument("--jdk", type=Path, default=os.environ.get("JAVA_HOME"))
    args = parser.parse_args()
    if not args.sdk or not args.jdk:
        sys.exit("set ANDROID_HOME and JAVA_HOME (or pass --sdk and --jdk)")
    if args.release:
        if not args.keystore or args.version_name == "test":
            sys.exit("a release needs --keystore and --version-name")
        if REPO in args.keystore.resolve().parents:
            sys.exit("the release key must stay outside the repository")
        keystore, alias = args.keystore / KEYSTORE_FILE, KEY_ALIAS
        password = "file:" + str(args.keystore / "password.txt")
        app_id = RELEASE_APP_ID
    else:
        keystore, alias, password = Path.home() / ".android" / "debug.keystore", "androiddebugkey", "pass:android"
        if not keystore.exists():
            sys.exit(f"no debug key at {keystore}: build any app once in Android Studio, or pass --release")
        app_id = TEST_APP_ID

    sdk, jdk = args.sdk, args.jdk
    android_jar = sdk / "platforms" / f"android-{TARGET_SDK}" / "android.jar"
    if not android_jar.exists():
        candidates = sorted((sdk / "platforms").glob(f"android-{TARGET_SDK}*"))
        if not candidates:
            sys.exit(f"no android-{TARGET_SDK} platform in {sdk}")
        android_jar = candidates[-1] / "android.jar"
    aapt2, zipalign = tool(sdk, "aapt2", EXE), tool(sdk, "zipalign", EXE)
    d8, apksigner = tool(sdk, "d8", BAT), tool(sdk, "apksigner", BAT)
    javac = str(jdk / "bin" / ("javac" + EXE))
    env = dict(os.environ, JAVA_HOME=str(jdk))

    with tempfile.TemporaryDirectory(prefix="pa-touch-") as work:
        work = Path(work)
        manifest = (HERE / "AndroidManifest.xml").read_text(encoding="utf-8")
        manifest = manifest.replace(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
            f'<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{app_id}" '
            f'android:versionCode="{args.version_code}" android:versionName="{args.version_name}">', 1)
        (work / "AndroidManifest.xml").write_text(manifest, encoding="utf-8")

        run([aapt2, "compile", "--dir", str(HERE / "res"), "-o", str(work / "res.zip")])
        gen = work / "gen"
        run([aapt2, "link", "-o", str(work / "base.apk"), "-I", str(android_jar),
             "--manifest", str(work / "AndroidManifest.xml"), "--java", str(gen),
             "--custom-package", "com.pocketaccess.touch",
             "--min-sdk-version", str(MIN_SDK), "--target-sdk-version", str(TARGET_SDK),
             str(work / "res.zip")])

        classes = work / "classes"
        sources = [str(p) for p in (HERE / "src").rglob("*.java")] + [str(p) for p in gen.rglob("*.java")]
        run([javac, "-source", "17", "-target", "17", "-nowarn", "-Xlint:none", "-encoding", "UTF-8",
             "-classpath", str(android_jar), "-d", str(classes)] + sources, env=env)
        dex = work / "dex"
        dex.mkdir()
        run([d8, "--release", "--min-api", str(MIN_SDK), "--lib", str(android_jar), "--output", str(dex)]
            + [str(p) for p in classes.rglob("*.class")], env=env)

        unaligned = work / "unaligned.apk"
        shutil.copy(work / "base.apk", unaligned)
        with zipfile.ZipFile(unaligned, "a", zipfile.ZIP_DEFLATED) as apk:
            apk.write(dex / "classes.dex", "classes.dex")
        aligned = work / "aligned.apk"
        run([zipalign, "-p", "-f", "4", str(unaligned), str(aligned)])
        args.out.parent.mkdir(parents=True, exist_ok=True)
        run([apksigner, "sign", "--ks", str(keystore), "--ks-key-alias", alias, "--ks-pass", password,
             "--key-pass", password, "--out", str(args.out), str(aligned)], env=env)
    print(f"{app_id} {args.version_name} ({args.version_code}) -> {args.out}")


if __name__ == "__main__":
    main()
