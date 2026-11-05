#!/usr/bin/env python3
"""Builds the zip-ready Windows folder for a Pocket Accessibility release.

    python launcher/package_release.py --version 0.0.1 --dotnet self-contained --out <new folder outside the repository>

It also writes PocketAccessibility-<version>-windows-x64.zip beside that folder: the one asset a
release needs, under the name PocketUpdater looks for.

What goes in is decided here and nowhere else (docs/access/launcher.md, "Packaged
release"): the game comes from `git archive HEAD`, so only committed files can be
packaged, never ROMs, saves, caches or logs; only LÖVE and Prism come from outside
the repository.  The last step audits the finished folder and fails the build if
anything forbidden is in it.  It uploads nothing.

Standard library only.  Needs git, the .NET 10 SDK, LÖVE 11.5 and a Prism release.
"""
import argparse
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path, PurePosixPath

REPO = Path(__file__).resolve().parents[1]
CREATE_NO_WINDOW = 0x08000000  # never put a window or a console on the player's screen

# What the game folder is made of, as paths in the repository.
GAME_PATHS = [
    "main.lua", "conf.lua", "LICENSE.MD", "README.md", "AIDisclosure.md",
    "src", "assets", "data", "tools/save-editor", "launcher",
]
# mods/ is not packaged: no mod is bundled (decision 42), and upstream's examples
# hold sprites derived from ROMs (mods/example_mew_starter).
GAME_GLOBS = ["tools/rom_manifest*.json"]

# Upstream's proprietary launcher: License Term 2, listed in LICENSE.MD.
TERM2_FILES = {
    "src/import/LauncherView.lua", "src/import/LauncherSettings.lua", "src/import/OnlinePanel.lua",
    "src/import/CartLabelArt.lua", "src/import/CartShape.lua", "src/mods/LauncherMods.lua",
    # Holds launcher interface code too. PackagedImporter.lua replaces its import logic.
    "src/import/RomImporter.lua",
}
TERM2_DIRS = ["assets/launcher/", "assets/labels/"]

# Not on the Term 2 list by name, but they are that launcher's screens: useless
# without it, and some may count as "later versions" of listed files.
LAUNCHER_ONLY_FILES = {
    "src/import/BoxPanel.lua", "src/import/BoxUI.lua", "src/import/BoxTools.lua", "src/import/BoxDetails.lua",
    "src/import/BoxOrganizer.lua", "src/import/ShowcaseEditor.lua",
    "src/import/LauncherSplash.lua", "src/import/LauncherThemeVideo.lua",
}
LAUNCHER_ONLY_DIRS = ["src/import/online/"]

# Modules a kept file may name although their file is left out, and why.
STAND_INS = {
    "src.import.RomImporter": "PackagedBuild preloads PackagedImporter",
    "src.mods.LauncherMods": "PackagedBuild preloads a stand-in",
    "src.import.LauncherSplash": "PackagedBuild preloads a stand-in",
    "src.import.BoxPanel": "main.lua, only after the bootGame hook has refused the start",
    "service": "launcher/SaveBackend/service.lua, on the require path AndroidSaveBackend sets",
}

# Upstream's project marks (License Term 3), which the game does not draw;
# assets/logo/pokemon_logo.png is the one TitleState uses.
UNUSED_MARKS = {f"assets/logo/{name}" for name in
                ("bcg.png", "bcg.webp", "gen1recomp_cover.png", "logo.png", "minilogo.png")}

# Development files inside the kept folders.
DROP_SUFFIXES = {".py", ".sh", ".psd"}

LOVE_FILES = ["love.exe", "lovec.exe", "love.dll", "lua51.dll", "SDL2.dll", "OpenAL32.dll",
              "mpg123.dll", "msvcp120.dll", "msvcr120.dll"]

# Never in the finished folder, whatever else changes.
FORBIDDEN_SUFFIXES = {".gb", ".gbc", ".gba", ".sav", ".srm", ".rtc", ".log", ".love", ".zip", ".pdb"}
FORBIDDEN_NAMES = {"tolk.dll", "portable.txt", "rom-cache.complete", "launcher-window.cfg"}
FORBIDDEN_PARTS = [("data", "generated"), ("assets", "generated"), ("red",), ("asset_packs",), ("save",), (".git",)]


def fail(message):
    sys.exit("PACKAGE FAILED: " + message)


def say(message):
    print(message, flush=True)


def run(*command, cwd=REPO):
    return subprocess.run(command, cwd=cwd, check=True, capture_output=True,
                          creationflags=CREATE_NO_WINDOW).stdout


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main_checkout():
    """The checkout holding git-ignored local-deps; a worktree has none of its own."""
    common = Path(run("git", "rev-parse", "--path-format=absolute", "--git-common-dir").decode().strip())
    return common.parent


def left_out(path):
    """Why a repository path stays out of the game folder, or None."""
    if path in TERM2_FILES or any(path.startswith(d) for d in TERM2_DIRS):
        return "Term 2"
    if path in LAUNCHER_ONLY_FILES or any(path.startswith(d) for d in LAUNCHER_ONLY_DIRS):
        return "launcher only"
    if path in UNUSED_MARKS:
        return "unused marks"
    if PurePosixPath(path).suffix.lower() in DROP_SUFFIXES and not path.startswith("launcher/"):
        return "development file"
    return None


def export_game(game_dir):
    """Copies the committed game files; returns the commit and what was left out."""
    commit = run("git", "rev-parse", "HEAD").decode().strip()
    if run("git", "status", "--porcelain", "--", *GAME_PATHS).strip():
        say("WARNING: uncommitted changes are not in the package; it holds commit " + commit)
    paths = list(GAME_PATHS)
    tracked = run("git", "ls-tree", "-r", "--name-only", "HEAD", "tools/").decode().splitlines()
    for pattern in GAME_GLOBS:
        paths += [p for p in tracked if PurePosixPath(p).match(pattern)]
    archive = run("git", "archive", "--format=tar", "HEAD", "--", *paths)
    excluded = {}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            why = left_out(member.name)
            if why:
                excluded.setdefault(why, []).append(member.name)
                continue
            target = game_dir / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tar.extractfile(member).read())
    return commit, excluded


def copy_love(love_source, love_dir, licenses):
    version = subprocess.run([str(love_source / "lovec.exe"), "--version"], capture_output=True,
                             creationflags=CREATE_NO_WINDOW).stdout.decode(errors="replace")
    if not version.startswith("LOVE 11.5"):
        fail(f"{love_source} is not LÖVE 11.5: {version.strip()!r}")
    love_dir.mkdir(parents=True)
    for name in LOVE_FILES:
        shutil.copy2(love_source / name, love_dir / name)
    license_text = love_source / "license.txt"
    if not license_text.is_file():
        fail(f"LÖVE's license text is not at {license_text}")
    shutil.copy2(license_text, licenses / "LOVE-license.txt")
    return version.strip()


def copy_prism(prism_dll, prism_release, game_dir, licenses):
    """Prism's DLL, and its licenses from the release the DLL came from."""
    if not prism_dll.is_file():
        fail(f"prism.dll is not at {prism_dll}")
    released = prism_release / "dynamic" / "release" / "bin" / "prism.dll"
    for needed in (released, prism_release / "NOTICE", prism_release / "LICENSES" / "prism"):
        if not needed.exists():
            fail(f"Prism's license files are not on disk: {needed} is missing")
    if sha256(released) != sha256(prism_dll):
        fail(f"{prism_dll} differs from {released}, so that release's licenses may not apply")
    target = game_dir / "local-deps" / "prism"
    target.mkdir(parents=True)
    shutil.copy2(prism_dll, target / "prism.dll")
    shutil.copytree(prism_release / "LICENSES", licenses / "Prism" / "LICENSES")
    shutil.copy2(prism_release / "NOTICE", licenses / "Prism" / "NOTICE")
    return prism_release.name


def publish_program(name, out, self_contained):
    """One of our two programs, as one executable beside game and love."""
    scratch = out.parent / (out.name + "-publish")
    shutil.rmtree(scratch, ignore_errors=True)
    command = ["dotnet", "publish", str(REPO / "launcher" / name), "-c", "Release", "-r", "win-x64",
               "-o", str(scratch), "--nologo", "-p:PublishSingleFile=true", "-p:DebugType=none",
               f"-p:PathMap={REPO}=."]  # no local paths or .pdb in the program
    if self_contained:
        command += ["--self-contained", "true", "-p:IncludeNativeLibrariesForSelfExtract=true",
                    "-p:EnableCompressionInSingleFile=true"]
    else:
        command += ["--self-contained", "false"]
    run(*command)
    shutil.copy2(scratch / f"{name}.exe", out / f"{name}.exe")
    shutil.rmtree(scratch)


def publish_launcher(out, licenses, self_contained):
    """The launcher and the updater that replaces it."""
    # ReadyCheck, SaveBackend and ModBackend are found in game/launcher (GamePaths.cs).
    publish_program("PocketLauncher", out, self_contained)
    publish_program("PocketUpdater", out, self_contained)
    if self_contained:
        # The texts published with the runtime packs that were built in, not the
        # SDK install's own LICENSE.txt, which is a different document.
        assets = (REPO / "launcher" / "PocketLauncher" / "obj" / "project.assets.json").read_text(encoding="utf-8")
        version = re.search(r'"Microsoft\.NETCore\.App\.Runtime\.win-x64",\s*"version": "\[([\d.]+),', assets).group(1)
        pack = Path.home() / ".nuget" / "packages" / "microsoft.netcore.app.runtime.win-x64" / version
        for source, name in ((pack / "LICENSE.TXT", "dotNET-LICENSE.txt"),
                             (pack / "THIRD-PARTY-NOTICES.TXT", "dotNET-THIRD-PARTY-NOTICES.txt")):
            if not source.is_file():
                fail(f".NET's license text is not at {source}")
            shutil.copy2(source, licenses / name)


def copy_notices(out, game_dir, licenses):
    """The license texts THIRD-PARTY-NOTICES.txt names."""
    shutil.copy2(game_dir / "launcher" / "THIRD-PARTY-NOTICES.txt", out / "THIRD-PARTY-NOTICES.txt")
    for name in ("CC-BY-4.0.txt", "CC0-1.0.txt"):
        (licenses / name).write_bytes(run("git", "show", f"HEAD:scripts/portmaster/licenses/{name}"))
    # Lucide's own license text for the lock icon; only this file is taken from that folder.
    (licenses / "Lucide-LICENSE.txt").write_bytes(run("git", "show", "HEAD:assets/launcher/lucide/LICENSE"))
    notices = licenses / "asset-notices"
    notices.mkdir()
    for folder in ("fonts/plainpixel", "skins/gba_purple", "skins/gb_anim", "skins/tv_crt", "touch", "game3"):
        shutil.copy2(game_dir / "assets" / folder / "README.md", notices / (folder.replace("/", "-") + ".md"))


def write_notes(out, game_dir, commit, love_version, prism_name, licenses, self_contained, version):
    (out / "version.txt").write_text(version + "\n", encoding="utf-8")
    (game_dir / "pocket-access-package.txt").write_text(
        f"Packaged by launcher/package_release.py from commit {commit}.\n"
        "src/access/PackagedBuild.lua reads this file's presence: no upstream launcher here.\n", encoding="utf-8")
    shutil.copy2(game_dir / "LICENSE.MD", licenses / "Pocket-Accessibility-LICENSE.txt")
    shutil.copy2(game_dir / "src" / "import" / "gen5" / "ANIMAENGINE_LICENSE", licenses / "AnimaEngine-LICENSE.txt")
    (out / "README.txt").write_text(f"""Pocket Accessibility

Screen reader accessibility for the Pokémon recompilation games.
Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp).
This is an unofficial fork, not affiliated with or endorsed by that project, Nintendo,
Game Freak or The Pokémon Company. You supply your own cartridge dumps; no game data is included.

To play: unzip this folder anywhere, open PocketLauncher.exe, choose Import ROM to import
your cartridge dump, then Play. {"Nothing else needs installing." if self_contained else "This build needs the .NET 10 Desktop Runtime for Windows x64 from Microsoft."}

Feedback, help and bug reports: https://discord.gg/8NNev6PsB6

Saves and imported data are kept in %APPDATA%\\LOVE\\pokemon-love2d, not in this folder,
so deleting or replacing this folder does not touch them.

License: GNU General Public License version 3 with upstream's Section 7 terms (licenses folder).
Source: the Lua source is the game folder; the launcher's source is game\\launcher.
The same source is at https://github.com/Lethal-Lawnmower/pocket-accessibility, commit {commit}.
Upstream's proprietary launcher files (License Term 2) are not in this package.

Contents
  PocketLauncher.exe  the launcher
  PocketUpdater.exe   installs newer releases from GitHub; the launcher's Check for updates opens it
  version.txt         this release's version
  game                the game's source, and Prism in game\\local-deps\\prism
  love                {love_version}, unmodified (zlib license)
  licenses            license texts for everything above; see THIRD-PARTY-NOTICES.txt
Speech through Prism ({prism_name}, MPL-2.0; source: https://github.com/ethindp/prism).
""", encoding="utf-8")


REQUIRE = re.compile(r"""require\s*\(?\s*["']((?:src|tools)[\w.\-]*)["']""")


def missing_requires(game_dir):
    """Every require of a module that is not in the folder and has no stand-in."""
    missing = {}
    for lua in game_dir.rglob("*.lua"):
        rel = lua.relative_to(game_dir).as_posix()
        if rel.startswith(("launcher/", "mods/")):
            continue
        for name in REQUIRE.findall(lua.read_text(encoding="utf-8", errors="replace")):
            # a name ending in . or _ is the start of a computed one
            if name in STAND_INS or name.endswith((".", "_")):
                continue
            base = game_dir / Path(*name.split("."))
            if not (base.with_suffix(".lua").is_file() or (base / "init.lua").is_file()):
                missing.setdefault(name, []).append(rel)
    return missing


def audit(out, game_dir, excluded):
    problems = []
    for path in out.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(out)
        parts = tuple(p.lower() for p in rel.parts)
        posix = rel.as_posix()
        in_game = posix[5:] if posix.startswith("game/") else None
        if path.suffix.lower() in FORBIDDEN_SUFFIXES or path.name.lower() in FORBIDDEN_NAMES:
            problems.append(f"forbidden file: {posix}")
        for forbidden in FORBIDDEN_PARTS:
            if any(parts[i:i + len(forbidden)] == forbidden for i in range(len(parts))):
                problems.append(f"forbidden folder: {posix}")
        if in_game is not None and in_game in TERM2_FILES | LAUNCHER_ONLY_FILES:
            problems.append(f"launcher file: {posix}")
        if in_game is not None and any(in_game.startswith(d) for d in TERM2_DIRS + LAUNCHER_ONLY_DIRS):
            problems.append(f"launcher file: {posix}")
        if path.suffix.lower() in {".exe", ".dll"} and posix not in {"PocketLauncher.exe", "PocketUpdater.exe"} \
                and posix != "game/local-deps/prism/prism.dll" \
                and not (parts[0] == "love" and rel.name in LOVE_FILES):
            problems.append(f"unexpected program file: {posix}")
    for name, users in sorted(missing_requires(game_dir).items()):
        problems.append(f"require of a missing module: {name}, from {', '.join(users[:4])}")
    if problems:
        fail("the audit found:\n  " + "\n  ".join(problems))
    say("audit passed: no ROMs, saves, caches, logs or launcher files; every require resolves")
    for why, files in sorted(excluded.items()):
        say(f"left out, {why}: {len(files)} files")


def folder_size(path):
    return sum(f.stat().st_size for f in Path(path).rglob("*") if f.is_file())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version", required=True, help="this release's version, such as 0.0.1; the tag is v<version>")
    parser.add_argument("--out", required=True, type=Path, help="folder to create; must not exist, outside the repository")
    parser.add_argument("--love", type=Path, default=Path(r"C:\Program Files\LOVE"), help="LÖVE 11.5 install folder")
    parser.add_argument("--prism-dll", type=Path, help="default: local-deps/prism/prism.dll in the main checkout")
    parser.add_argument("--prism-release", type=Path, help="the unpacked Prism release the DLL came from, for its "
                        "licenses; default: ../local-deps/prism-v0.17.3-windows-x64 beside the main checkout")
    parser.add_argument("--dotnet", required=True, choices=["self-contained", "runtime-required"],
                        help="self-contained builds .NET into the launcher; runtime-required leaves it out, "
                        "and players must install the .NET 10 Desktop Runtime (launcher.md has the trade-offs)")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        fail(f"{args.version} is not a version like 0.0.1")

    out = args.out.resolve()
    if out.exists():
        fail(f"{out} already exists; choose a new folder")
    if out == REPO or REPO in out.parents or main_checkout() in out.parents:
        fail("the package must be built outside the repository")
    checkout = main_checkout()
    prism_dll = (args.prism_dll or checkout / "local-deps" / "prism" / "prism.dll").resolve()
    prism_release = (args.prism_release or checkout.parent / "local-deps" / "prism-v0.17.3-windows-x64").resolve()

    game_dir, licenses = out / "game", out / "licenses"
    game_dir.mkdir(parents=True)
    licenses.mkdir()
    say("exporting the game from git")
    commit, excluded = export_game(game_dir)
    say("copying LÖVE and Prism")
    love_version = copy_love(args.love.resolve(), out / "love", licenses)
    prism_name = copy_prism(prism_dll, prism_release, game_dir, licenses)
    self_contained = args.dotnet == "self-contained"
    say(f"publishing the launcher ({args.dotnet})")
    publish_launcher(out, licenses, self_contained)
    copy_notices(out, game_dir, licenses)
    write_notes(out, game_dir, commit, love_version, prism_name, licenses, self_contained, args.version)
    audit(out, game_dir, excluded)
    say(f"commit {commit}")
    for part in ("PocketLauncher.exe", "PocketUpdater.exe", "love", "game", "licenses"):
        target = out / part
        size = target.stat().st_size if target.is_file() else folder_size(target)
        say(f"  {part}: {size / 1048576:.1f} MiB")
    say(f"total {folder_size(out) / 1048576:.1f} MiB in {out}")
    zip_path = out.parent / f"PocketAccessibility-{args.version}-windows-x64.zip"
    if zip_path.exists():
        fail(f"{zip_path} already exists")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(p for p in out.rglob("*") if p.is_file()):
            archive.write(path, f"PocketAccessibility-{args.version}/{path.relative_to(out).as_posix()}")
    say(f"zip {zip_path}: {zip_path.stat().st_size / 1048576:.1f} MiB, sha256 {sha256(zip_path)}")


if __name__ == "__main__":
    main()
