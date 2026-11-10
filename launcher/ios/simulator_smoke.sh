#!/usr/bin/env bash
# Smoke test of the simulator app that launcher/ios/build_ipa.py built, without any ROM.
#
#   bash launcher/ios/simulator_smoke.sh [seconds]      (macOS with Xcode; default 75 s)
#
# Creates a throwaway iPhone simulator, installs dist/ios/iphonesimulator/PocketAccessibility.app,
# launches it with POKEPORT_ACCESS_TRACE=1 and watches its output.  Without a ROM and without
# our iOS launcher (not built yet), the expected run is: the Lua game starts, our layer opens
# Prism ("[access] speech ready: <backend>") and says "Pocket Accessibility ready.", then
# src/access/PackagedBuild.lua refuses to open upstream's launcher and quits
# ("[access] start refused: ...").  Staying alive instead also passes.  A Lua error, a crash
# report, or no speech line fails.  Logs go to dist/ios/logs/.  See docs/access/ios.md.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/dist/ios/iphonesimulator/PocketAccessibility.app"
BUNDLE_ID="com.pocketaccessibility.app"
EXECUTABLE="love"   # LÖVE's product name; the app folder is renamed, the executable is not
LOGS="$ROOT/dist/ios/logs"
SECONDS_TO_WATCH="${1:-75}"
mkdir -p "$LOGS"
CONSOLE="$LOGS/app-console.log"
SYSTEM_LOG="$LOGS/app-system.log"

[ -d "$APP" ] || { echo "::error::no simulator app at $APP; run launcher/ios/build_ipa.py first"; exit 1; }

# The newest available iOS runtime, and the newest iPhone it supports.
read -r RUNTIME DEVICE_TYPE < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"]
            if r.get("platform") == "iOS" and r.get("isAvailable")]
if not runtimes:
    sys.exit("no available iOS simulator runtime")
runtime = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])
phones = [d for d in runtime.get("supportedDeviceTypes", []) if d.get("productFamily") == "iPhone"]
if not phones:
    sys.exit("the runtime supports no iPhone")
print(runtime["identifier"], phones[-1]["identifier"])
')
[ -n "${RUNTIME:-}" ] || { echo "::error::could not choose a simulator runtime"; exit 1; }
echo "runtime: $RUNTIME"
echo "device type: $DEVICE_TYPE"

UDID="$(xcrun simctl create pocket-access-smoke "$DEVICE_TYPE" "$RUNTIME")"
cleanup() {
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP" || { echo "::error::simctl install failed"; exit 1; }

STARTED="$(date '+%Y-%m-%d %H:%M:%S')"
# SIMCTL_CHILD_ variables reach the app's environment without the prefix.  Speech is not
# silenced: nobody listens to a CI simulator, and a real call into Prism is part of the test.
SIMCTL_CHILD_POKEPORT_ACCESS_TRACE=1 \
SIMCTL_CHILD_POKEPORT_IDENTITY=pocket-access-ci \
  xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE_ID" \
  >"$CONSOLE" 2>&1 &
LAUNCHER_PID=$!

# Wait while the app runs; the launch command returns when the app exits.
for _ in $(seq "$SECONDS_TO_WATCH"); do
  kill -0 "$LAUNCHER_PID" 2>/dev/null || break
  sleep 1
done
ALIVE=no
if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -F "$BUNDLE_ID" >/dev/null; then
  ALIVE=yes
fi
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
kill "$LAUNCHER_PID" 2>/dev/null || true
wait "$LAUNCHER_PID" 2>/dev/null || true

# LÖVE may send print() to the console, to the unified log, or both: search both.
xcrun simctl spawn "$UDID" log show --style compact --start "$STARTED" \
  --predicate "process == \"$EXECUTABLE\"" >"$SYSTEM_LOG" 2>&1 || true
CRASHES="$(find "$HOME/Library/Logs/DiagnosticReports" -newermt "$STARTED" \
  \( -name "$EXECUTABLE*.ips" -o -name "$EXECUTABLE*.crash" \) 2>/dev/null || true)"
for report in $CRASHES; do cp "$report" "$LOGS/" 2>/dev/null || true; done

ALL="$LOGS/app-combined.log"
cat "$CONSOLE" "$SYSTEM_LOG" >"$ALL"
first() { grep -m 1 -F "$1" "$ALL" | sed -E 's/^.*(\[access\])/\1/' ; }

SPEECH="$(first '[access] speech ready:')"
UNAVAILABLE="$(first '[access] speech unavailable:')"
SAID="$(first '[access] say!: Pocket Accessibility ready.')"
SPEECH_FAILED="$(first '[access] speech failed:')"
REFUSED="$(first '[access] start refused:')"
# LÖVE's error handler prints "Error: <file>.lua:<line>: ..." and a traceback; system
# frameworks also log to this process, so a bare "Error:" is not enough.
LUA_ERROR="$(grep -m 3 -E 'Error: (\[string |[^ ]+\.lua:[0-9]+)|stack traceback' "$ALL" || true)"
EXCEPTION="$(grep -m 3 -E 'Terminating app due to uncaught exception|EXC_BAD_ACCESS|EXC_CRASH' "$CONSOLE" || true)"

echo
echo "================ iOS simulator smoke test ================"
echo "watched for:            up to $SECONDS_TO_WATCH s"
echo "console lines:          $(wc -l <"$CONSOLE" | tr -d ' ')   unified log lines: $(wc -l <"$SYSTEM_LOG" | tr -d ' ')"
echo "Prism started:          ${SPEECH:-NO}"
[ -n "$UNAVAILABLE" ] && echo "Prism failure:          $UNAVAILABLE"
echo "startup announcement:   ${SAID:-NO}"
[ -n "$SPEECH_FAILED" ] && echo "speech call failed:     $SPEECH_FAILED (reported, not a failure on a simulator)"
echo "start refused (expected without our iOS launcher): ${REFUSED:-no}"
echo "app still running at the end: $ALIVE"
echo "Lua error:              ${LUA_ERROR:-none}"
echo "crash reports:          ${CRASHES:-none}"
echo "uncaught exception:     ${EXCEPTION:-none}"
echo "=========================================================="
echo "first 60 lines of the app's console:"
head -n 60 "$CONSOLE"

PROBLEMS=()
[ -n "$SPEECH" ] || PROBLEMS+=("no '[access] speech ready:' line: the game or our layer did not start, or Prism did not load")
[ -n "$SAID" ] || PROBLEMS+=("no 'Pocket Accessibility ready.' announcement in the trace")
[ -z "$LUA_ERROR" ] || PROBLEMS+=("a Lua error was printed")
[ -z "$CRASHES" ] || PROBLEMS+=("a crash report was written")
[ -z "$EXCEPTION" ] || PROBLEMS+=("the app raised an uncaught exception")
[ "$ALIVE" = yes ] || [ -n "$REFUSED" ] || PROBLEMS+=("the app ended without the expected start refusal")

if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  for problem in "${PROBLEMS[@]}"; do echo "::error::$problem"; done
  exit 1
fi
echo "PASS: the game started, Prism loaded (${SPEECH#*speech ready: }), and the app did not crash."
