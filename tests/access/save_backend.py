#!/usr/bin/env python3
"""Drives launcher/SaveBackend directly, the way the launcher's save editor does.

Scripted, silent and windowless, so it is safe beside the owner's screen reader.
Always point it at a disposable identity and a scratch save; never at
pokemon-love2d.

  python tests/access/save_backend.py <game> <identity> <script.json> [scratch-save]

The script is a JSON array of requests, for example
  [{"cmd":"model","page":"trainer"},
   {"cmd":"set","page":"trainer","field":"money","value":1234},
   {"cmd":"save"}]
An "open" is sent first.  Each request and the full answer are printed as JSON,
and it exits 1 if any answer says ok=false.  With no scratch-save a temporary
file is used, so the first open reports a new game stub.
"""
import json
import os
import subprocess
import sys
import tempfile

PREFIX = "@@PA "
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LOVE = os.environ.get("POCKET_LOVEC", r"C:\Program Files\LOVE\lovec.exe")


class Backend:
    def __init__(self, identity):
        env = dict(os.environ, POCKET_GAME_DIR=ROOT, POKEPORT_IDENTITY=identity,
                   POKEPORT_ACCESS="0", POKEPORT_PORTMASTER_MANAGED="1")
        self.proc = subprocess.Popen(
            [LOVE, os.path.join(ROOT, "launcher", "SaveBackend")], env=env, cwd=ROOT,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            encoding="utf-8", creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        self.next_id = 0
        self.read()

    def read(self):
        for line in self.proc.stdout:
            if line.startswith(PREFIX):
                return json.loads(line[len(PREFIX):])
        raise RuntimeError("the backend stopped")

    def send(self, request):
        self.next_id += 1
        request = dict(request, id=self.next_id)
        self.proc.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
        self.proc.stdin.flush()
        return self.read()

    def close(self):
        self.proc.stdin.close()
        self.proc.wait(10)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sys.stdout.reconfigure(encoding="utf-8")
    game, identity, script = sys.argv[1:4]
    if identity == "pokemon-love2d":
        print("refusing the owner's real profile")
        return 2
    path = sys.argv[4] if len(sys.argv) > 4 else os.path.join(tempfile.mkdtemp(), "scratch.lua")
    with open(script, encoding="utf-8") as file:
        requests = json.load(file)
    backend = Backend(identity)
    failed = False
    try:
        for request in [{"cmd": "open", "version": game, "path": path}] + requests:
            answer = backend.send(request)
            print(">>", json.dumps(request, ensure_ascii=False))
            print("<<", json.dumps(answer, ensure_ascii=False))
            failed = failed or answer.get("ok") is not True
    finally:
        backend.close()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
