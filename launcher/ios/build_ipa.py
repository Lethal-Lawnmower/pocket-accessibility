"""Builds the iOS app: the game without upstream's launcher, LÖVE 12 at a pinned commit, and Prism.

    python3 launcher/ios/build_ipa.py [--version X.Y.Z] [--logs DIR]     (macOS with Xcode)
    python3 launcher/ios/build_ipa.py --payload-only OUT.love            (any system: game.love only)

Writes, under dist/ios/ (git-ignored):
    iphonesimulator/PocketAccessibility.app     for the iOS Simulator, signed ad hoc
    iphoneos/PocketAccessibility.app            for a device, unsigned
    PocketAccessibility-<version>-unsigned.ipa  Payload/PocketAccessibility.app, zipped; the
                                                player signs it with their own Apple ID

Upstream's scripts/build_ios.sh does most of the preparation and is run unchanged with
--package-only: the Info.plist overlay, upstream's native bridges (patch_love_src.py),
game.love wired into the Xcode project, and warning settings.  Around it, this script
  1. fetches LÖVE and its Apple libraries at pinned commits into mobile/ios/love-src/, the
     folder build_ios.sh expects, laid out the way its --fetch does (--fetch can only take a
     branch name, not a commit);
  2. replaces the game.love build_ios.sh packed (which holds upstream's proprietary launcher)
     with ours, exported like the Android and Windows packages;
  3. renames the app, drops upstream's URL scheme and HealthKit, and draws our own icon;
  4. runs xcodebuild itself, twice, so neither build needs a signing identity;
  5. adds Prism's libprism.dylib (only that library) and the license texts to each app.
Nothing is uploaded.  See docs/access/ios.md, "Build (step 2)".
"""
import argparse
import hashlib
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import package_release  # noqa: E402  (shares what the Windows package leaves out)

REPO = HERE.parent.parent
MARKER = "pocket-access-package.txt"

BUNDLE_ID = "com.pocketaccessibility.app"
DISPLAY_NAME = "Pocket Accessibility"
APP_NAME = "PocketAccessibility"
CONFIGURATION = "Release"
DEPLOYMENT_TARGET = "15.0"  # upstream's; Prism's libraries need 14.0

# LÖVE 12.0 (unreleased) at the commit whose Windows build our layer was tested on
# (docs/access/ios.md), and love-apple-dependencies' main as of that commit (its last
# change, 2026-07-24, updated LuaJIT).
LOVE_REPO = "https://github.com/love2d/love.git"
LOVE_COMMIT = "def245102c67909f9902095af613b1ae05249b62"
DEPENDENCIES_REPO = "https://github.com/love2d/love-apple-dependencies.git"
DEPENDENCIES_COMMIT = "a5522634f1e581a1ebab73bf3ab4bd7a853b7a3e"

# Prism release assets and their SHA-256, checked on every download (read 2026-11-09).
PRISM_VERSION = "0.18.3"
PRISM_ASSETS = {
    "iphoneos": ("prism-ios-arm64.zip",
                 "a6fc169aa3ba10e9c2fb57ce4d2e6f81442ffcb945f6e1b826871630607e527b"),
    "iphonesimulator": ("prism-ios-simulator-arm64.zip",
                        "7b3716c157f4be8f6d2117fcc93347f4e4e27387276d9b9436081fdb6c79fa66"),
}
# The only file taken from Prism's lib folder.  The zips also hold libtolk, libSRAL,
# libUniversalSpeech and libSpeechCore, which are never shipped (decisions 3 and 9).
PRISM_DYLIB = "dynamic/release/lib/libprism.dylib"

# build_ios.sh's fixed locations (all git-ignored).
IOS_DIR = REPO / "mobile" / "ios"
LOVE_SRC = IOS_DIR / "love-src"
CACHE = IOS_DIR / "cache"
XCODE_DIR = LOVE_SRC / "platform" / "xcode"
LIBS_DIR = XCODE_DIR / "ios" / "libraries"
LOVE_FILE = XCODE_DIR / "ios" / "resources" / "game.love"
INFO_PLIST = XCODE_DIR / "ios" / "love-ios.plist"
APP_ICONS = XCODE_DIR / "Images.xcassets" / "iOS AppIcon.appiconset"
PINS_FILE = LOVE_SRC / ".pocket-access-pins"
BUILD_DIR = IOS_DIR / "build" / "pocket-access"
DIST = REPO / "dist" / "ios"

# Files the game cannot start without; the same gate as build_ios.sh's, plus our layer.
REQUIRED_IN_GAME = [
    "main.lua", "conf.lua", MARKER, "src/access/init.lua", "src/access/speech/PrismBackend.lua",
    "src/update/Boot.lua", "src/ui/kit/Kit.lua", "tools/save-editor/App.lua",
    "tools/save-editor/Kit.lua", "tools/save-editor/panels/Party.lua",
]

# Never inside an app, whatever else changes.
FORBIDDEN_SUFFIXES = {".gb", ".gbc", ".gba", ".sav", ".srm", ".rtc", ".log", ".zip"}
FORBIDDEN_LIBRARIES = ("libtolk", "libSRAL", "libUniversalSpeech", "libSpeechCore")


def say(message):
    print(f"==> {message}", flush=True)


def fail(message):
    sys.exit("IOS BUILD FAILED: " + message)


def run(command, cwd=REPO, log=None, env=None):
    """Runs a command; with log, its output goes to that file and only the end is printed on failure."""
    print("$ " + " ".join(str(part) for part in command), flush=True)
    if log is None:
        subprocess.run([str(part) for part in command], cwd=cwd, env=env, check=True)
        return
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "w", encoding="utf-8", errors="replace") as out:
        result = subprocess.run([str(part) for part in command], cwd=cwd, env=env,
                                stdout=out, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
        errors = [line for line in lines if " error: " in line or line.startswith("error:")]
        print("\n".join(errors[-40:] or lines[-80:]))
        fail(f"{command[0]} exited with {result.returncode}; full output in {log}")


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# ------------------------------------------------------------------ game.love

def pack_game(love_path):
    """The committed game, leaving out what the Android and Windows packages leave out."""
    with tempfile.TemporaryDirectory() as work:
        game = Path(work)
        commit, excluded = package_release.export_game(game)
        # of launcher/, the game only needs what its save editor and Mods screen run,
        # and the bundled mods (src/access/BundledMods.lua); the same rule as build_apk.py
        for path in (game / "launcher").iterdir():
            if path.name not in ("SaveBackend", "ModBackend", "mods"):
                shutil.rmtree(path) if path.is_dir() else path.unlink()
        # src/access/PackagedBuild.lua reads this file's presence: no upstream launcher here
        (game / MARKER).write_text(f"Packaged by launcher/ios/build_ipa.py from commit {commit}.\n",
                                   encoding="utf-8")
        missing = package_release.missing_requires(game)
        if missing:
            fail(f"the game requires modules that were left out: {missing}")
        for why, paths in excluded.items():
            print(f"left out ({why}): {len(paths)} files")
        love_path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(love_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as love:
            for path in sorted(game.rglob("*")):
                if path.is_file():
                    love.write(path, path.relative_to(game).as_posix())
    audit_game(love_path)
    return commit


def audit_game(love_path):
    """Fails when game.love holds a launcher file, a ROM, a save or generated data, or lacks a needed file."""
    with zipfile.ZipFile(love_path) as love:
        names = set(love.namelist())
    blocked = package_release.TERM2_FILES | package_release.LAUNCHER_ONLY_FILES
    prefixes = tuple(package_release.TERM2_DIRS + package_release.LAUNCHER_ONLY_DIRS
                     + ["data/generated/", "assets/generated/", "save/"])
    problems = [f"launcher or generated file: {n}" for n in sorted(names) if n in blocked or n.startswith(prefixes)]
    problems += [f"forbidden file: {n}" for n in sorted(names)
                 if Path(n).suffix.lower() in FORBIDDEN_SUFFIXES | {".love"}]
    manifests = re.findall(r'manifest\s*=\s*"([^"]+)"',
                           (REPO / "src" / "core" / "GameVersion.lua").read_text(encoding="utf-8"))
    problems += [f"missing: {n}" for n in REQUIRED_IN_GAME + manifests if n not in names]
    if problems:
        fail("game.love audit:\n  " + "\n  ".join(problems))
    say(f"game.love audit passed: {len(names)} files, {love_path.stat().st_size / 1048576:.1f} MiB")


# ------------------------------------------------------------------ LÖVE sources

def fetch_commit(repo, commit, dest):
    """One commit, without history.  `git clone --branch` cannot take a commit; GitHub serves one by id."""
    for attempt in range(1, 4):
        shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir(parents=True)
        try:
            run(["git", "init", "-q"], cwd=dest)
            run(["git", "remote", "add", "origin", repo], cwd=dest)
            run(["git", "-c", "http.version=HTTP/1.1", "fetch", "-q", "--depth", "1", "origin", commit], cwd=dest)
            run(["git", "checkout", "-q", "--detach", "FETCH_HEAD"], cwd=dest)
            return
        except subprocess.CalledProcessError:
            say(f"fetching {repo} failed (attempt {attempt})")
    fail(f"could not fetch {repo} at {commit}")


def fetch_love():
    """mobile/ios/love-src at the pinned commits, laid out as build_ios.sh's fetch_love_ios does."""
    pins = f"love {LOVE_COMMIT}\nlove-apple-dependencies {DEPENDENCIES_COMMIT}\n"
    if PINS_FILE.is_file() and PINS_FILE.read_text(encoding="utf-8") == pins:
        say("love-src already at the pinned commits")
        return
    # a tree from build_ios.sh --fetch, or older pins: start again, since patch_love_src.py's
    # .orig stashes belong to the tree they were made from
    shutil.rmtree(LOVE_SRC, ignore_errors=True)
    work = CACHE / "pocket-access-fetch"
    say(f"fetching LÖVE {LOVE_COMMIT[:8]} and love-apple-dependencies {DEPENDENCIES_COMMIT[:8]}")
    fetch_commit(LOVE_REPO, LOVE_COMMIT, work / "love")
    fetch_commit(DEPENDENCIES_REPO, DEPENDENCIES_COMMIT, work / "dependencies")
    shutil.move(str(work / "love"), str(LOVE_SRC))
    LIBS_DIR.mkdir(parents=True, exist_ok=True)
    (XCODE_DIR / "shared").mkdir(parents=True, exist_ok=True)
    # cp -R as build_ios.sh does: xcframeworks may hold symbolic links
    run(["cp", "-R", f"{work / 'dependencies' / 'iOS' / 'libraries'}/.", LIBS_DIR])
    run(["cp", "-R", f"{work / 'dependencies' / 'shared'}/.", XCODE_DIR / "shared"])
    shutil.rmtree(work, ignore_errors=True)
    PINS_FILE.write_text(pins, encoding="utf-8")


# ------------------------------------------------------------------ our identity

def edit_info_plist():
    """Our name; no upstream URL scheme (its links open upstream's launcher) and no HealthKit text."""
    with open(INFO_PLIST, "rb") as file:
        info = plistlib.load(file)
    info["CFBundleDisplayName"] = DISPLAY_NAME
    info["CFBundleName"] = DISPLAY_NAME
    info.pop("CFBundleURLTypes", None)
    info.pop("NSHealthShareUsageDescription", None)
    with open(INFO_PLIST, "wb") as file:
        plistlib.dump(info, file)


def icon_pixel(x, y):
    """Our speech bubble (launcher/android/res/drawable/pocket_icon.xml) on a 108-unit square."""
    def inside_rounded(px, py, left, top, right, bottom, radius):
        cx = min(max(px, left + radius), right - radius)
        cy = min(max(py, top + radius), bottom - radius)
        return left <= px <= right and top <= py <= bottom and (px - cx) ** 2 + (py - cy) ** 2 <= radius ** 2

    def inside_tail(px, py):  # the triangle (46,72) (30,86) (30,72)
        return 30 <= px and 72 <= py and (px - 30) * 14 + (py - 72) * 16 <= 16 * 14
    return inside_rounded(x, y, 22, 30, 86, 72, 6) or inside_tail(x, y)


def write_icon_png(path, size=1024):
    """A 1024 px PNG without alpha (Apple rejects alpha on the large icon), from the standard library."""
    dark, light = b"\x1f\x29\x37", b"\xf9\xfa\xfb"
    rows = []
    for row in range(size):
        y = (row + 0.5) * 108 / size
        rows.append(b"\x00" + b"".join(light if icon_pixel((col + 0.5) * 108 / size, y) else dark
                                       for col in range(size)))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b""))
    path.write_bytes(png)


def replace_icons():
    """build_ios.sh drew upstream's cover art (a project mark, never packaged); every size becomes ours."""
    source = BUILD_DIR / "pocket-access-icon.png"
    source.parent.mkdir(parents=True, exist_ok=True)
    write_icon_png(source)
    icons = sorted(APP_ICONS.glob("*.png"))
    if not icons:
        fail(f"no icons in {APP_ICONS}")
    for icon in icons:
        width = subprocess.run(["sips", "-g", "pixelWidth", str(icon)], capture_output=True, text=True,
                               check=True).stdout.split()[-1]
        run(["sips", "-z", width, width, source, "--out", icon], log=BUILD_DIR / "sips.log")
    say(f"app icon: ours, {len(icons)} sizes")


# ------------------------------------------------------------------ Prism

def fetch_prism(sdk):
    name, expected = PRISM_ASSETS[sdk]
    target = CACHE / f"prism-v{PRISM_VERSION}" / name
    if not (target.is_file() and sha256(target) == expected):
        target.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://github.com/ethindp/prism/releases/download/v{PRISM_VERSION}/{name}"
        say(f"downloading {url}")
        with urllib.request.urlopen(url, timeout=300) as response, open(target, "wb") as out:
            shutil.copyfileobj(response, out)
        actual = sha256(target)
        if actual != expected:
            target.unlink()
            fail(f"{name} has SHA-256 {actual}, expected {expected}")
    return target


# ------------------------------------------------------------------ Xcode

def xcodebuild(sdk, marketing_version, build_number, logs):
    """love-ios for one SDK, with build_ios.sh's settings but no signing identity."""
    destination = "generic/platform=iOS" if sdk == "iphoneos" else "generic/platform=iOS Simulator"
    command = [
        "xcodebuild", "-project", XCODE_DIR / "love.xcodeproj", "-target", "love-ios",
        "-configuration", CONFIGURATION, "-sdk", sdk, "-destination", destination,
        f"SYMROOT={BUILD_DIR / 'Build' / 'Products'}", f"OBJROOT={BUILD_DIR / 'Build' / 'Intermediates'}",
        f"PRODUCT_BUNDLE_IDENTIFIER={BUNDLE_ID}",
        f"MARKETING_VERSION={marketing_version}", f"CURRENT_PROJECT_VERSION={build_number}",
        "INFOPLIST_KEY_UIFileSharingEnabled=YES", "INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace=YES",
        f"IPHONEOS_DEPLOYMENT_TARGET={DEPLOYMENT_TARGET}",
        # Prism's simulator library is arm64 only, and every current Mac and iPhone is arm64
        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=NO", "DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING=YES",
        # no HealthKit: a free Apple account may not be able to sign it (docs/access/ios.md)
        "CODE_SIGN_ENTITLEMENTS=",
    ]
    if sdk == "iphoneos":
        # unsigned: the player's sideloading tool signs with their Apple ID
        command += ["CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
                    "DEVELOPMENT_TEAM="]
    else:
        # the simulator on Apple silicon runs only signed code; ad hoc needs no certificate
        command += ["CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=-"]
    say(f"xcodebuild love-ios ({CONFIGURATION}, {sdk}); log: {logs / f'xcodebuild-{sdk}.log'}")
    run(command, cwd=XCODE_DIR, log=logs / f"xcodebuild-{sdk}.log")
    products = BUILD_DIR / "Build" / "Products" / f"{CONFIGURATION}-{sdk}"
    apps = sorted(products.glob("*.app"))
    if len(apps) != 1:
        fail(f"expected one app in {products}, found {[a.name for a in apps]}")
    return apps[0]


def finish_app(built, sdk, game_love, prism_zip):
    """Our copy of the built app, with Prism and the license texts; returns its path."""
    app = DIST / sdk / f"{APP_NAME}.app"
    shutil.rmtree(app.parent, ignore_errors=True)
    app.parent.mkdir(parents=True)
    run(["cp", "-R", built, app])  # keeps the symbolic links a framework may hold

    # Xcode's incremental resource copy can keep an older game.love (build_ios.sh compares bytes too)
    bundled = app / "game.love"
    if not bundled.is_file() or sha256(bundled) != sha256(game_love):
        say(f"{sdk}: game.love in the built app was missing or stale; copying ours in")
        shutil.copy2(game_love, bundled)
    frameworks = app / "Frameworks"
    frameworks.mkdir(exist_ok=True)
    licenses = app / "licenses"
    licenses.mkdir(exist_ok=True)
    with zipfile.ZipFile(prism_zip) as archive:
        # src/access/speech/PrismBackend.lua opens @executable_path/Frameworks/libprism.dylib on iOS
        (frameworks / "libprism.dylib").write_bytes(archive.read(PRISM_DYLIB))
        (licenses / "Prism").mkdir()
        (licenses / "Prism" / "NOTICE").write_bytes(archive.read("NOTICE"))
        for entry in archive.namelist():
            if entry.startswith("LICENSES/") and not entry.endswith("/"):
                target = licenses / "Prism" / entry
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(entry))
    shutil.copy2(REPO / "LICENSE.MD", licenses / "Pocket-Accessibility-LICENSE.txt")
    shutil.copy2(LOVE_SRC / "license.txt", licenses / "LOVE-license.txt")

    if sdk == "iphonesimulator":
        # the files added above broke the ad hoc seal Xcode made: sign again, the library first
        run(["codesign", "--force", "--sign", "-", "--timestamp=none", frameworks / "libprism.dylib"])
        run(["codesign", "--force", "--sign", "-", "--timestamp=none", "--preserve-metadata=entitlements", app])
    audit_app(app)
    return app


def audit_app(app):
    with open(app / "Info.plist", "rb") as file:
        info = plistlib.load(file)
    problems = []
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        problems.append(f"bundle id is {info.get('CFBundleIdentifier')}")
    if info.get("CFBundleDisplayName") != DISPLAY_NAME:
        problems.append(f"display name is {info.get('CFBundleDisplayName')}")
    if "CFBundleURLTypes" in info:
        problems.append("upstream's URL scheme is still declared")
    for path in app.rglob("*"):
        rel = path.relative_to(app).as_posix()
        if path.name.startswith(FORBIDDEN_LIBRARIES):
            problems.append(f"forbidden library: {rel}")
        if path.is_file() and path.suffix.lower() in FORBIDDEN_SUFFIXES:
            problems.append(f"forbidden file: {rel}")
    audit_game(app / "game.love")
    if problems:
        fail(f"{app.name} audit:\n  " + "\n  ".join(problems))
    contents = sorted(p.name for p in (app / "Frameworks").iterdir())
    say(f"{app.parent.name}/{app.name}: executable {info.get('CFBundleExecutable')}, "
        f"Frameworks {contents}, bundle id {BUNDLE_ID}")


def package_ipa(app, label):
    ipa = DIST / f"{APP_NAME}-{label}-unsigned.ipa"
    ipa.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory() as work:
        payload = Path(work) / "Payload"
        payload.mkdir()
        run(["cp", "-R", app, payload / app.name])
        run(["zip", "-q", "-r", "-y", ipa, "Payload"], cwd=work)  # -y keeps symbolic links
    say(f"IPA: {ipa} ({ipa.stat().st_size / 1048576:.1f} MiB, sha256 {sha256(ipa)})")
    return ipa


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", help="a release version such as 0.0.4; default: a dev build named by commit")
    parser.add_argument("--logs", type=Path, default=DIST / "logs", help="where build logs go")
    parser.add_argument("--payload-only", type=Path, metavar="OUT.love",
                        help="only export and audit game.love to this path; runs on any system")
    args = parser.parse_args()

    if args.payload_only:
        commit = pack_game(args.payload_only.resolve())
        print(f"game from commit {commit}\n{args.payload_only.resolve()}")
        return
    if sys.platform != "darwin":
        fail("the app builds on macOS with Xcode; use --payload-only elsewhere")
    if args.version and not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        fail(f"{args.version} is not a version like 0.0.4")
    short = subprocess.run(["git", "rev-parse", "--short=10", "HEAD"], cwd=REPO, capture_output=True,
                           text=True, check=True).stdout.strip()
    label = args.version or f"dev-{short}"
    marketing_version = args.version or "0.0.0"
    build_number = os.environ.get("GITHUB_RUN_NUMBER", "1")
    logs = args.logs.resolve()

    fetch_love()
    say("running upstream's scripts/build_ios.sh --package-only (unchanged)")
    run(["bash", REPO / "scripts" / "build_ios.sh", "--package-only"], log=logs / "build_ios-package-only.log")
    # build_ios.sh packed upstream's payload, launcher included; ours replaces it before Xcode copies it
    game_love = BUILD_DIR / "game.love"
    commit = pack_game(game_love)
    shutil.copy2(game_love, LOVE_FILE)
    edit_info_plist()
    replace_icons()

    apps = {}
    for sdk in ("iphonesimulator", "iphoneos"):
        built = xcodebuild(sdk, marketing_version, build_number, logs)
        apps[sdk] = finish_app(built, sdk, game_love, fetch_prism(sdk))
    ipa = package_ipa(apps["iphoneos"], label)
    (DIST / "build-info.txt").write_text(
        f"game commit {commit}\nversion {label} ({marketing_version}, build {build_number})\n"
        f"LÖVE {LOVE_COMMIT}\nlove-apple-dependencies {DEPENDENCIES_COMMIT}\n"
        f"Prism {PRISM_VERSION}\nbundle id {BUNDLE_ID}\n"
        f"simulator app {apps['iphonesimulator']}\ndevice app {apps['iphoneos']}\nipa {ipa}\n", encoding="utf-8")
    print((DIST / "build-info.txt").read_text(encoding="utf-8"))


if __name__ == "__main__":
    main()
