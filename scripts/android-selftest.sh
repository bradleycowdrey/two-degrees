#!/usr/bin/env bash
# Runs the Android app in the emulator (in CI): photographs the first-launch terms, runs the self-test
# (live data), then photographs a city page at rest and scrolled, and the city list.
# Usage: scripts/android-selftest.sh <apk> <output folder>
set -uo pipefail
APK="$1"; OUT="$2"; mkdir -p "$OUT"
ID=com.bradcowdrey.twodegrees
adb wait-for-device
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb install -r "$APK"
shot() { adb exec-out screencap -p > "$OUT/$1.png"; }
launch() { adb shell am start -W -n $ID/.MainActivity "$@" >/dev/null; }
stop() { adb shell am force-stop $ID; }

# 1. First launch: the terms.
launch; sleep 6; shot android-1-terms; stop

# 2. The self-test, then the main screen.
adb shell run-as $ID rm -f files/report.txt
# Use My Location: allow it, turn location on, and put the emulator in Denver.
adb shell pm grant $ID android.permission.ACCESS_COARSE_LOCATION || true
adb shell cmd location set-location-enabled true || true
adb emu geo fix -104.9847 39.7392 || true
sleep 2; adb emu geo fix -104.9847 39.7392 || true
launch --ez selftest true --ez locate true
for i in $(seq 1 150); do adb shell run-as $ID ls files/report.txt >/dev/null 2>&1 && break; sleep 1; done
sleep 2; shot android-2-main
adb shell run-as $ID cat files/report.txt > "$OUT/report.txt" || echo "FAILED (no report)" > "$OUT/report.txt"
stop

# 3. Scrolled: the 10-day forecast, then the detail tiles. 4. The city list.
launch --ez selftest true --es show days; sleep 9; shot android-3-days; stop
launch --ez selftest true --es show tiles; sleep 9; shot android-4-tiles; stop
launch --es show list; sleep 6; shot android-5-list; stop
adb shell getprop ro.build.version.release > "$OUT/device.txt"
adb shell getprop ro.product.model >> "$OUT/device.txt"
cat "$OUT/report.txt"
