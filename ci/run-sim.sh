#!/bin/bash
# Installs the built app in an iPad simulator, takes screenshots of every screen using the demo desk,
# then connects it to the X32 emulator and checks that its changes reach the "console".
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/ci-out}"
SHOTS="$OUT/screenshots"
mkdir -p "$SHOTS"
APP=$(sed -n 's/^APP=//p' "$OUT/app-path.txt")
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
echo "App: $APP ($BUNDLE)"

pick_device() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in data.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        if want in d["name"]:
            best = d["udid"]
print(best or "")
' "$1"
}

IPAD=$(pick_device "iPad Pro 13")
[ -z "$IPAD" ] && IPAD=$(pick_device "iPad Pro")
[ -z "$IPAD" ] && IPAD=$(pick_device "iPad")
IPHONE=$(pick_device "iPhone 16")
[ -z "$IPHONE" ] && IPHONE=$(pick_device "iPhone")
echo "iPad: $IPAD  iPhone: $IPHONE"

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b > /dev/null 2>&1
  xcrun simctl install "$1" "$APP"
}

shot() {
  # shot DEVICE NAME SECONDS ROTATE args...
  local dev="$1" name="$2" wait="$3" rotate="$4"
  shift 4
  xcrun simctl terminate "$dev" "$BUNDLE" > /dev/null 2>&1 || true
  xcrun simctl launch "$dev" "$BUNDLE" -autoLocked NO "$@" > /dev/null
  sleep "$wait"
  xcrun simctl io "$dev" screenshot "$SHOTS/$name.png" > /dev/null 2>&1
  if [ "$rotate" != "0" ]; then
    sips -r "$rotate" "$SHOTS/$name.png" > /dev/null 2>&1 || true
  fi
  echo "screenshot: $name"
}

boot "$IPAD"
# Portrait set (the simulator boots in portrait).
shot "$IPAD" 01-connect 6 0 -autoMode mixer
shot "$IPAD" 02-mixer 8 0 -autoDemo YES -autoMode mixer -autoLayer inputs1
shot "$IPAD" 03-mixer-17-32 8 0 -autoDemo YES -autoMode mixer -autoLayer inputs2
shot "$IPAD" 04-sends-on-fader 8 0 -autoDemo YES -autoMode mixer -autoLayer inputs1 -autoSends 1
shot "$IPAD" 05-dca 8 0 -autoDemo YES -autoMode mixer -autoLayer dca
shot "$IPAD" 06-eq 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-16 -autoTab eq
shot "$IPAD" 07-dynamics 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-1 -autoTab dynamics
shot "$IPAD" 08-input 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-16 -autoTab input
shot "$IPAD" 09-sends 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-16 -autoTab sends
shot "$IPAD" 10-setup 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-16 -autoTab setup
shot "$IPAD" 11-bus-eq 9 0 -autoDemo YES -autoMode mixer -autoDetail bus-1 -autoTab eq
shot "$IPAD" 12-scenes 9 0 -autoDemo YES -autoMode mixer -autoSheet scenes
shot "$IPAD" 13-monitor 10 0 -autoDemo YES -autoMode monitor -autoMonitorBus 1
sleep 5
xcrun simctl io "$IPAD" screenshot "$SHOTS/13b-monitor-later.png" > /dev/null 2>&1
shot "$IPAD" 14-simple 9 0 -autoDemo YES -autoMode simple

# Landscape set: rotate the simulated iPad (Cmd+Right in Simulator). Best effort.
open -a Simulator || true
sleep 3
osascript -e 'tell application "Simulator" to activate' -e 'delay 1' -e 'tell application "System Events" to key code 124 using command down' > "$OUT/rotate.log" 2>&1 || true
sleep 3
shot "$IPAD" 40-landscape-mixer 9 0 -autoDemo YES -autoMode mixer -autoLayer inputs1
shot "$IPAD" 41-landscape-sends 9 0 -autoDemo YES -autoMode mixer -autoLayer inputs1 -autoSends 1
shot "$IPAD" 42-landscape-eq 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-16 -autoTab eq
shot "$IPAD" 43-landscape-dynamics 9 0 -autoDemo YES -autoMode mixer -autoDetail channel-1 -autoTab dynamics
shot "$IPAD" 44-landscape-monitor 10 0 -autoDemo YES -autoMode monitor -autoMonitorBus 1
shot "$IPAD" 45-landscape-simple 9 0 -autoDemo YES -autoMode simple
osascript -e 'tell application "Simulator" to activate' -e 'delay 1' -e 'tell application "System Events" to key code 123 using command down' >> "$OUT/rotate.log" 2>&1 || true
sleep 3

# Integration test against the X32 emulator over real UDP.
EMU="$ROOT/build/X32-Behringer/X32emu"
RESULT=0
if [ -x "$EMU" ]; then
  (cd "$ROOT/build" && "$EMU" -i 127.0.0.1 -v 1 > "$OUT/emulator.log" 2>&1 &)
  sleep 2
  python3 "$ROOT/ci/x32tool.py" seed 127.0.0.1 | tee "$OUT/seed.log"
  shot "$IPAD" 20-emulator-mixer 10 0 -autoHost 127.0.0.1 -autoMode mixer -autoLayer inputs1 -autoScript selftest
  sleep 2
  python3 "$ROOT/ci/x32tool.py" check 127.0.0.1 | tee "$OUT/selftest-check.log"
  RESULT=${PIPESTATUS[0]}
  shot "$IPAD" 21-emulator-eq 9 0 -autoHost 127.0.0.1 -autoMode mixer -autoDetail channel-6 -autoTab eq
  pkill -f X32emu || true
else
  echo "emulator missing; skipped integration test"
fi

if [ -n "$IPHONE" ]; then
  boot "$IPHONE"
  sleep 20
  shot "$IPHONE" 30-iphone-monitor 10 0 -autoDemo YES -autoMode monitor -autoMonitorBus 1
  shot "$IPHONE" 31-iphone-simple 10 0 -autoDemo YES -autoMode simple
  shot "$IPHONE" 32-iphone-connect 10 0 -autoMode mixer
fi

xcrun simctl spawn "$IPAD" log show --last 5m --predicate 'process == "X32Remote" OR process == "X32 Remote"' --style compact > "$OUT/app-log.txt" 2>/dev/null || true
exit $RESULT
