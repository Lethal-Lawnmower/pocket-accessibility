#!/usr/bin/env bash
# Smoke test of the simulator app that launcher/ios/build_ipa.py built, without any ROM.
#
#   bash launcher/ios/simulator_smoke.sh [seconds]      (macOS with Xcode; default 75 s)
#
# Creates a throwaway iPhone simulator, installs dist/ios/iphonesimulator/PocketAccessibility.app
# and launches it twice, with POKEPORT_ACCESS_TRACE=1, watching its output (docs/access/ios.md,
# "What the smoke test checks"):
#
#   1. "launcher" (25 s): the app opens on our native launcher ("[pocket-launcher] shown (1)")
#      and no game starts: no "[pocket-launcher] starting", no "[access] speech ready".
#   2. "refusal" (the given seconds): POCKET_LAUNCHER_AUTOSTART=red makes the launcher start Red
#      once, without an import, as Play would.  With no ROM the game starts, opens Prism
#      ("[access] speech ready: <backend>", "Pocket Accessibility ready."), refuses
#      ("[access] start refused: ..."), and LÖVE's restart brings the launcher back in the same
#      process ("[pocket-launcher] shown (2)") showing the reason ("refusal shown:").
#
# Both runs must end with the app still running, no Lua error, no crash report and no uncaught
# exception.  Logs go to dist/ios/logs/.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP="$ROOT/dist/ios/iphonesimulator/PocketAccessibility.app"
BUNDLE_ID="com.pocketaccessibility.app"
EXECUTABLE="PocketAccessibility"   # build_ipa.py names the product and executable
LOGS="$ROOT/dist/ios/logs"
SECONDS_TO_WATCH="${1:-75}"
mkdir -p "$LOGS"

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

PROBLEMS=()

# run_app <label> <seconds> [NAME=value ...]: launches the app with those variables, watches it,
# and leaves its console, unified log and combined log in $LOGS/<label>-*.log.  Sets ALIVE and
# CRASHES.  SIMCTL_CHILD_ variables reach the app's environment without the prefix.  Speech is not
# silenced: nobody listens to a CI simulator, and a real call into Prism is part of the test.
run_app() {
  local label="$1" seconds="$2"
  shift 2
  local console="$LOGS/$label-console.log" system_log="$LOGS/$label-system.log"
  local started
  started="$(date '+%Y-%m-%d %H:%M:%S')"
  local child_env=(SIMCTL_CHILD_POKEPORT_ACCESS_TRACE=1 SIMCTL_CHILD_POKEPORT_IDENTITY=pocket-access-ci)
  local pair
  for pair in "$@"; do child_env+=("SIMCTL_CHILD_$pair"); done
  env "${child_env[@]}" \
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE_ID" \
    >"$console" 2>&1 &
  local launcher_pid=$!

  # Wait while the app runs; the launch command returns when the app exits.
  local _
  for _ in $(seq "$seconds"); do
    kill -0 "$launcher_pid" 2>/dev/null || break
    sleep 1
  done
  ALIVE=no
  if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -F "$BUNDLE_ID" >/dev/null; then
    ALIVE=yes
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  kill "$launcher_pid" 2>/dev/null || true
  wait "$launcher_pid" 2>/dev/null || true

  # print() and NSLog may reach the console, the unified log, or both: search both.
  xcrun simctl spawn "$UDID" log show --style compact --start "$started" \
    --predicate "process == \"$EXECUTABLE\"" >"$system_log" 2>&1 || true
  CRASHES="$(find "$HOME/Library/Logs/DiagnosticReports" -newermt "$started" \
    \( -name "$EXECUTABLE*.ips" -o -name "$EXECUTABLE*.crash" \) 2>/dev/null || true)"
  local report
  for report in $CRASHES; do cp "$report" "$LOGS/" 2>/dev/null || true; done
  cat "$console" "$system_log" >"$LOGS/$label-combined.log"
  CURRENT="$LOGS/$label-combined.log"
  CURRENT_CONSOLE="$console"
}

# The first line of the current run's logs holding the text, from its tag on.
first() { grep -m 1 -F "$1" "$CURRENT" | sed -E 's/^.*(\[(access|pocket-launcher)\])/\1/' ; }

# Problems every run must be free of.
check_health() {
  local label="$1"
  # LÖVE's error handler prints "Error: <file>.lua:<line>: ..." and a traceback; system
  # frameworks also log to this process, so a bare "Error:" is not enough.
  LUA_ERROR="$(grep -m 3 -E 'Error: (\[string |[^ ]+\.lua:[0-9]+)|stack traceback' "$CURRENT" || true)"
  EXCEPTION="$(grep -m 3 -E 'Terminating app due to uncaught exception|EXC_BAD_ACCESS|EXC_CRASH' "$CURRENT_CONSOLE" || true)"
  UNAVAILABLE_BRIDGE="$(first '[access] ios launcher unavailable:')"
  echo "app still running at the end: $ALIVE"
  echo "Lua error:              ${LUA_ERROR:-none}"
  echo "crash reports:          ${CRASHES:-none}"
  echo "uncaught exception:     ${EXCEPTION:-none}"
  [ -n "$UNAVAILABLE_BRIDGE" ] && echo "launcher bridge:        $UNAVAILABLE_BRIDGE"
  [ -z "$LUA_ERROR" ] || PROBLEMS+=("$label: a Lua error was printed")
  [ -z "$CRASHES" ] || PROBLEMS+=("$label: a crash report was written")
  [ -z "$EXCEPTION" ] || PROBLEMS+=("$label: the app raised an uncaught exception")
  [ -z "$UNAVAILABLE_BRIDGE" ] || PROBLEMS+=("$label: Lua could not reach the launcher ($UNAVAILABLE_BRIDGE)")
  [ "$ALIVE" = yes ] || PROBLEMS+=("$label: the app was not running at the end")
}

# ------------------------------------------------------------------ 1. the launcher comes first
run_app launcher 25
SHOWN="$(first '[pocket-launcher] shown (1)')"
STARTED_GAME="$(first '[pocket-launcher] starting')"
EARLY_SPEECH="$(first '[access] speech ready:')"
WAITING="$(first '[access] ios launcher: waiting for a game')"
echo
echo "================ 1. the app opens on the launcher ================"
echo "Lua asked for the launcher:  ${WAITING:-NO}"
echo "launcher shown:              ${SHOWN:-NO}"
echo "games listed:                $(first '[pocket-launcher] games listed:' || true)"
echo "a game started:              ${STARTED_GAME:-no (expected)}"
echo "game speech started:         ${EARLY_SPEECH:-no (expected)}"
check_health launcher
[ -n "$SHOWN" ] || PROBLEMS+=("launcher: no '[pocket-launcher] shown (1)': our launcher did not appear")
[ -z "$STARTED_GAME" ] || PROBLEMS+=("launcher: a game started without anyone choosing one")
[ -z "$EARLY_SPEECH" ] || PROBLEMS+=("launcher: the game's speech started before a game was chosen")
echo "first 40 lines of the app's console:"
head -n 40 "$CURRENT_CONSOLE"

# ------------------------------------------------------------------ 2. a refused start comes back
run_app refusal "$SECONDS_TO_WATCH" POCKET_LAUNCHER_AUTOSTART=red
AUTOSTART="$(first '[pocket-launcher] autostart red')"
STARTING="$(first '[pocket-launcher] starting red')"
SPEECH="$(first '[access] speech ready:')"
SPEECH_UNAVAILABLE="$(first '[access] speech unavailable:')"
SAID="$(first '[access] say!: Pocket Accessibility ready.')"
SPEECH_FAILED="$(first '[access] speech failed:')"
REFUSED="$(first '[access] start refused:')"
BACK="$(first '[pocket-launcher] shown (2)')"
REASON="$(first '[pocket-launcher] refusal shown:')"
MARKED="$(first '[pocket-launcher] game screen marked for direct touch')"
echo
echo "================ 2. a refused start returns to the launcher ================"
echo "autostart:                   ${AUTOSTART:-NO}"
echo "game started:                ${STARTING:-NO}"
echo "game screen marked:          ${MARKED:-no (reported only)}"
echo "Prism started:               ${SPEECH:-NO}"
[ -n "$SPEECH_UNAVAILABLE" ] && echo "Prism failure:               $SPEECH_UNAVAILABLE"
echo "startup announcement:        ${SAID:-NO}"
[ -n "$SPEECH_FAILED" ] && echo "speech call failed:          $SPEECH_FAILED (reported, not a failure on a simulator)"
echo "start refused (no ROM):      ${REFUSED:-NO}"
echo "launcher shown again:        ${BACK:-NO}"
echo "refusal shown:               ${REASON:-NO}"
check_health refusal
[ -n "$AUTOSTART" ] || PROBLEMS+=("refusal: the launcher did not take POCKET_LAUNCHER_AUTOSTART")
[ -n "$STARTING" ] || PROBLEMS+=("refusal: the launcher did not start Red")
[ -n "$SPEECH" ] || PROBLEMS+=("refusal: no '[access] speech ready:' line: the game or our layer did not start, or Prism did not load")
[ -n "$SAID" ] || PROBLEMS+=("refusal: no 'Pocket Accessibility ready.' announcement in the trace")
[ -n "$REFUSED" ] || PROBLEMS+=("refusal: the game did not refuse to start without a ROM")
[ -n "$BACK" ] || PROBLEMS+=("refusal: the launcher did not come back after the refusal")
[ -n "$REASON" ] || PROBLEMS+=("refusal: the launcher did not show the game's reason")
STARTS="$(grep -c -F '[pocket-launcher] starting red' "$CURRENT_CONSOLE" || true)"
echo "game starts in the console:  ${STARTS:-0} (the launcher must not loop)"
echo "first 80 lines of the app's console:"
head -n 80 "$CURRENT_CONSOLE"

echo "=========================================================================="
if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  for problem in "${PROBLEMS[@]}"; do echo "::error::$problem"; done
  exit 1
fi
echo "PASS: the app opened on the launcher, Red started and refused without a ROM, Prism loaded" \
  "(${SPEECH#*speech ready: }), and the launcher came back without a crash."
