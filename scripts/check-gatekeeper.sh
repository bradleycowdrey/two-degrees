#!/usr/bin/env bash
# CI: what a Mac checks when the app is opened. Developer ID, notarized, ticket stapled to the app,
# and the widget signed by the same team. The DMG must be signed; its own notarization is submitted
# without waiting (see make-dmg.sh), so its Gatekeeper check is informational.
set -euo pipefail
APP=dist/TwoDegrees.app
DMG="$(ls dist/TwoDegrees-*.dmg)"
spctl -a -vv -t exec "$APP" 2>&1 | tee "$RUNNER_TEMP/gk.txt"
grep -q "source=Notarized Developer ID" "$RUNNER_TEMP/gk.txt" || { echo "::error::Gatekeeper doesn't accept the app as notarized"; exit 1; }
xcrun stapler validate "$APP"
codesign --verify --strict "$DMG"
codesign -dv "$DMG" 2>&1 | grep -q '^Authority=Developer ID Application' || { echo "::error::The DMG isn't signed with the Developer ID"; exit 1; }
spctl -a -vv -t open --context context:primary-signature "$DMG" || echo "(DMG notarization still with Apple)"
APP_TEAM="$(codesign -dv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
WIDGET_TEAM="$(codesign -dv "$APP/Contents/PlugIns/TwoDegreesWidget.appex" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
echo "app team $APP_TEAM, widget team $WIDGET_TEAM"
[[ -n "$APP_TEAM" && "$APP_TEAM" == "$WIDGET_TEAM" ]] || { echo "::error::The app and its widget aren't signed by the same team"; exit 1; }
