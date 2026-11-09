"""End-to-end runner for the Crystal randomizer's map (door) shuffle.

Imports Crystal into a disposable identity, installs the mod (without its
tests) into that identity's mods folder, runs tests/maps_e2e_driver.lua once
per level and seed through tests/access/drivers/isolated.lua, prints a summary
and deletes the identity folder.  Silent and isolated; never touches the
default pokemon-love2d identity.

From the repository root:
    python launcher/mods/crystal_randomizer/tests/maps_e2e.py
    python launcher/mods/crystal_randomizer/tests/maps_e2e.py --levels houses --seeds 424242 --keep

Exit status: 0 when every run finished with no FAIL and no MISSING line,
1 otherwise.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

IDENTITY = "pocket-access-maps-e2e"
PROTECTED_IDENTITY = "pokemon-love2d"
LOVE = r"C:\Program Files\LOVE\lovec.exe"
ROM_MARK = "- Crystal Version (USA, Europe) (Rev 1)"
DRIVER = "launcher/mods/crystal_randomizer/tests/maps_e2e_driver.lua"
ISOLATED = "tests/access/drivers/isolated.lua"

HERE = Path(__file__).resolve()
MOD_DIR = HERE.parent.parent                      # launcher/mods/crystal_randomizer
REPO = MOD_DIR.parent.parent.parent               # repository root
ROM_DIR = REPO.parent / "red"


def identity_dir() -> Path:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        sys.exit("APPDATA is not set; cannot find the LOVE save folder")
    path = Path(appdata) / "LOVE" / IDENTITY
    if path.name == PROTECTED_IDENTITY:
        sys.exit("refusing to use the owner's identity")
    return path


def find_rom() -> Path:
    matches = [p for p in ROM_DIR.glob("*") if ROM_MARK in p.name]
    if len(matches) != 1:
        sys.exit(f"expected one ROM containing {ROM_MARK!r} in {ROM_DIR}, found {len(matches)}")
    return matches[0]


def base_env() -> dict:
    env = dict(os.environ)
    env.update({
        "POKEPORT_IDENTITY": IDENTITY,
        "POKEPORT_ACCESS_SILENT": "1",
        "POKEPORT_BACKGROUND": "1",
        "POKEPORT_VERSION": "crystal",
        "POKEPORT_GAME": "crystal",
        "POKEPORT_TOUCH": "0",
    })
    for key in ("POKEPORT_IMPORT_ROM", "POKEPORT_IMPORT_ONLY", "POKEPORT_FORCE_IMPORT", "POKEPORT_DRIVER"):
        env.pop(key, None)
    return env


def run(env: dict, timeout: int):
    """Runs the game from the repository root; returns (exit code or None on timeout, output, seconds)."""
    started = time.time()
    try:
        done = subprocess.run([LOVE, "."], cwd=REPO, env=env, timeout=timeout,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, encoding="utf-8", errors="replace")
        return done.returncode, done.stdout, time.time() - started
    except subprocess.TimeoutExpired as expired:
        out = expired.stdout or ""
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        return None, out, time.time() - started


def import_crystal(timeout: int) -> bool:
    env = base_env()
    env.update({
        "POKEPORT_IMPORT_ROM": str(find_rom()),
        "POKEPORT_IMPORT_ONLY": "1",
        "POKEPORT_FORCE_IMPORT": "1",
    })
    code, out, secs = run(env, timeout)
    print(f"import: exit {code if code is not None else 'TIMEOUT'} in {secs:.0f}s")
    if code != 0:
        print("\n".join(out.splitlines()[-20:]))
    return code == 0


def install_mod(ident: Path):
    target = ident / "mods" / "crystal_randomizer"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(MOD_DIR, target, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    modules = sorted(p.stem for p in (target / "modules").glob("*.lua"))
    print("installed modules:", " ".join(modules))


def driver_run(level: str, seed: str, sample: int, frames: int, timeout: int, verbose: bool) -> dict:
    env = base_env()
    env.update({
        "POKEPORT_DRIVER": ISOLATED,
        "ISOLATED_DRIVER": DRIVER,
        "MAPS_E2E_LEVEL": level,
        "MAPS_E2E_SEED": seed,
        "MAPS_E2E_SAMPLE": str(sample),
        "MAPS_E2E_FRAMES": str(frames),
    })
    code, out, secs = run(env, timeout)
    lines = [line for line in out.splitlines() if line.startswith("[driver]")]
    errors = [line for line in out.splitlines() if line.startswith("driver error")]
    result = {"level": level, "seed": seed, "code": code, "secs": secs, "lines": lines, "errors": errors,
              "done": any(line.split()[1:2] == ["DONE"] for line in lines)}
    for kind in ("PASS", "FAIL", "MISSING", "SKIP"):
        result[kind] = [line for line in lines if line.split()[1:2] == [kind]]
    result["summary"] = next((line for line in lines if line.split()[1:2] == ["SUMMARY"]), None)
    result["canwin"] = next((line for line in lines if " canWin " in line and "RESULT" in line), None)
    status = "TIMEOUT" if code is None else f"exit {code}"
    print(f"\n=== level={level} seed={seed}: {status}, {secs:.0f}s, "
          f"pass {len(result['PASS'])}, fail {len(result['FAIL'])}, "
          f"missing {len(result['MISSING'])}, skip {len(result['SKIP'])}")
    shown = lines if verbose else [l for l in lines if l.split()[1:2] in (["FAIL"], ["MISSING"], ["SKIP"], ["RESULT"], ["SUMMARY"])]
    for line in shown:
        print("  " + line)
    for line in errors:
        print("  " + line)
    # the mod's own log lines about maps (why a placement was or was not made)
    seen = set()
    for line in out.splitlines():
        low = line.lower()
        if not line.startswith("[driver]") and "crystal_randomizer" in low and ("map" in low or "error" in low):
            text = line.strip()[:300]
            if text not in seen:
                seen.add(text)
                print("  modlog: " + text)
    if not result["done"]:
        print("  (the driver did not reach DONE)")
        if not verbose:
            print("  last output:")
            for line in out.splitlines()[-15:]:
                print("    " + line)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--levels", default="houses,caves,full")
    parser.add_argument("--seeds", default="424242,190731")
    parser.add_argument("--sample", type=int, default=3, help="doors walked per town")
    parser.add_argument("--frames", type=int, default=60000, help="driver frame budget per run")
    parser.add_argument("--timeout", type=int, default=900, help="seconds per run")
    parser.add_argument("--keep", action="store_true", help="keep the identity folder afterwards")
    parser.add_argument("--verbose", action="store_true", help="print every driver line")
    args = parser.parse_args()

    if not Path(LOVE).exists():
        sys.exit(f"LOVE not found at {LOVE}")
    ident = identity_dir()
    if ident.exists():
        shutil.rmtree(ident)
    results = []
    try:
        if not import_crystal(300):
            print("import failed; no runs made")
            return 1
        install_mod(ident)
        for level in [l for l in args.levels.split(",") if l]:
            for seed in [s for s in args.seeds.split(",") if s]:
                results.append(driver_run(level, seed, args.sample, args.frames, args.timeout, args.verbose))
    finally:
        if args.keep:
            print(f"\nidentity kept at {ident}")
        elif ident.exists():
            shutil.rmtree(ident, ignore_errors=True)
            print(f"\nidentity folder deleted: {not ident.exists()}")

    print("\n=== summary")
    missing = sorted({" ".join(line.split()[2:3]) for r in results for line in r["MISSING"]})
    if missing:
        print("missing pieces:", ", ".join(missing))
    ok = True
    for r in results:
        status = "TIMEOUT" if r["code"] is None else ("done" if r["done"] else f"exit {r['code']}, not done")
        bad = r["FAIL"] or r["MISSING"] or not r["done"]
        ok = ok and not bad
        print(f"{'FAIL' if bad else 'ok  '} {r['level']:6} seed {r['seed']}: {status}, "
              f"pass {len(r['PASS'])}, fail {len(r['FAIL'])}, missing {len(r['MISSING'])}, "
              f"skip {len(r['SKIP'])}, {r['secs']:.0f}s"
              + (f" | {r['canwin'].split('canWin', 1)[1].strip()}" if r["canwin"] else ""))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
