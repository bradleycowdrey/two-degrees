#!/usr/bin/env bash
# Archives the Mac app (with its widget) as the Mac App Store variant and uploads it to App Store Connect.
# The Developer ID build (scripts/build-app.sh) is unchanged: this variant only differs by the MAC_APP_STORE
# compilation condition (no self-updater) and the app's sandboxed Resources/AppStore.entitlements, set through
# TWO_DEGREES_APP_ENTITLEMENTS (see project.yml).
#
# Signing is automatic through the App Store Connect API key, as for the iPhone app: the archive is signed for
# development, then the export re-signs it for the Mac App Store, makes the installer package and uploads it.
# Xcode makes or fetches the Apple Distribution and Mac Installer Distribution certificates and the Mac App
# Store profiles itself. The runner's Mac is never registered as a device: -allowProvisioningDeviceRegistration
# is not passed, so the account's Mac device limit isn't used up by throwaway machines.
#
# ARCHIVE_SIGNING=local is the fallback, for an account with no Mac registered or if development signing
# fails: the archive is signed to run locally (ad hoc, entitlements kept) and only the export signs with
# Apple's certificates. It needs no development certificate, profile or device.
#
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, DERIVED_TEAM_ID, VERSION, BUILD, and optionally ARCHIVE_SIGNING
# (development, the default, or local). Runs on macOS with Xcode. Used by .github/workflows/mac-appstore.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_P8:?}" "${DERIVED_TEAM_ID:?}" "${VERSION:?}" "${BUILD:?}"
ARCHIVE_SIGNING="${ARCHIVE_SIGNING:-development}"
TMP="${RUNNER_TEMP:-$(mktemp -d)}"
ARCHIVE="$TMP/TwoDegrees-mac.xcarchive"

# Prints the errors in a log as annotations, then its tail, and fails.
fail_with_log() {
  grep -E "${2:-(error|fatal):}" "$1" | sort -u | head -25 | sed 's/^/::error::/' || true
  tail -40 "$1"
  exit 1
}

KEY="$TMP/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY"
trap 'rm -f "$KEY"' EXIT
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

# project.yml points the app's (and only the app's) CODE_SIGN_ENTITLEMENTS at TWO_DEGREES_APP_ENTITLEMENTS, so
# setting that on the command line leaves the widget's entitlements alone.
grep -q 'TWO_DEGREES_APP_ENTITLEMENTS' project.yml \
  || { echo "::error::project.yml no longer has the TWO_DEGREES_APP_ENTITLEMENTS setting the App Store build sets."; exit 1; }
[[ -f Resources/AppStore.entitlements ]] || { echo "::error::Resources/AppStore.entitlements is missing."; exit 1; }
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --quiet

case "$ARCHIVE_SIGNING" in
  development)
    SIGNING=(DEVELOPMENT_TEAM="$DERIVED_TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" "${AUTH[@]}") ;;
  local)
    SIGNING=(DEVELOPMENT_TEAM="$DERIVED_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" PROVISIONING_PROFILE_SPECIFIER="") ;;
  *)
    echo "::error::ARCHIVE_SIGNING must be development or local, not $ARCHIVE_SIGNING."; exit 1 ;;
esac
echo "Archiving Two Degrees for Mac $VERSION (build $BUILD), archive signed for $ARCHIVE_SIGNING"

LOG="$TMP/mac-archive.log"
xcodebuild -project TwoDegrees.xcodeproj -scheme TwoDegrees -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) MAC_APP_STORE' \
  TWO_DEGREES_APP_ENTITLEMENTS=Resources/AppStore.entitlements \
  "${SIGNING[@]}" archive > "$LOG" 2>&1 || fail_with_log "$LOG"

# Check the archive is the App Store variant before anything is uploaded: the app sandboxed, the widget
# with its own entitlements, and an icon from the asset catalog.
APP="$ARCHIVE/Products/Applications/TwoDegrees.app"
WIDGET="$APP/Contents/PlugIns/TwoDegreesWidget.appex"
[[ -d "$APP" && -d "$WIDGET" ]] || { echo "::error::The archive has no TwoDegrees.app with its widget."; ls -R "$ARCHIVE/Products" | head -20; exit 1; }
APP_ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
WIDGET_ENT="$(codesign -d --entitlements - --xml "$WIDGET" 2>/dev/null || true)"
grep -q "com.apple.security.app-sandbox" <<< "$APP_ENT" \
  || { echo "::error::The archived app isn't sandboxed, so it didn't get Resources/AppStore.entitlements."; exit 1; }
grep -q "com.apple.security.app-sandbox" <<< "$WIDGET_ENT" \
  || { echo "::error::The archived widget lost its sandbox entitlements."; exit 1; }
! grep -q "personal-information.location" <<< "$WIDGET_ENT" \
  || { echo "::error::The archived widget got the app's entitlements instead of Resources/Widget.entitlements."; exit 1; }
[[ -f "$APP/Contents/Resources/AppIcon.icns" || -f "$APP/Contents/Resources/Assets.car" ]] \
  || { echo "::error::The archived app has no icon."; exit 1; }
echo "archive checked: app and widget sandboxed, icon present"

cat > "$TMP/mac-export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$DERIVED_TEAM_ID</string>
</dict></plist>
PLIST
LOG="$TMP/mac-export.log"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$TMP/mac-export.plist" \
  -exportPath "$TMP/mac-export" "${AUTH[@]}" > "$LOG" 2>&1 || fail_with_log "$LOG" "[Ee]rror"

echo "::notice::Uploaded Two Degrees for Mac $VERSION (build $BUILD) to App Store Connect. It shows under the macOS platform once Apple finishes processing it."
