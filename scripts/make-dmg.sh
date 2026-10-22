#!/usr/bin/env bash
# Packages dist/TwoDegrees.app into dist/TwoDegrees-<version>.dmg: a branded installer window with
# the app and an Applications shortcut side by side.
# Notarizes it when NOTARY_APPLE_ID / NOTARY_PASSWORD / NOTARY_TEAM_ID are set.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
VERSION="${VERSION##*v}"  # "v0.1.0" or "two-degrees-v0.1.0" -> "0.1.0"
DMG="dist/TwoDegrees-$VERSION.dmg"
WORK="$(mktemp -d)"
rm -f "$DMG"

NOTARIZE=false
if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then NOTARIZE=true; fi

# Submit to Apple's notary service and wait. Anything but "Accepted" stops the release, with
# Apple's log of what it rejected.
notarize() {
  local out status id
  out="$(xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" --wait --timeout 3h --output-format json)" || true
  echo "$out"
  status="$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("status", ""))
except Exception: print("")')"
  id="$(printf '%s' "$out" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("id", ""))
except Exception: print("")')"
  if [[ "$status" != "Accepted" ]]; then
    echo "::error::Notarization of $(basename "$1") was not accepted (status: ${status:-none})"
    [[ -n "$id" ]] && xcrun notarytool log "$id" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" || true
    exit 1
  fi
}

# Notarize and staple the app itself first, so it carries its own ticket: an app the updater
# copies out of the DMG opens without needing to ask Apple online. APP_NOTARIZED=1 means the release
# workflow already did this (finish-release.yml, once Apple accepted the app).
if $NOTARIZE && [[ "${APP_NOTARIZED:-}" != "1" ]]; then
  ditto -c -k --keepParent dist/TwoDegrees.app "$WORK/TwoDegrees.zip"
  notarize "$WORK/TwoDegrees.zip"
  xcrun stapler staple dist/TwoDegrees.app
fi

# Styled installer window (branded background, fixed layout, no toolbar) via dmgbuild,
# which writes Finder's .DS_Store directly instead of scripting Finder.
styled() {
  python3 -m venv "$WORK/venv" >/dev/null
  "$WORK/venv/bin/pip" install --quiet "dmgbuild>=1.6,<2"
  tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png \
    -out "$WORK/background.tiff" >/dev/null
  "$WORK/venv/bin/dmgbuild" -s scripts/dmg-settings.py \
    -D app=dist/TwoDegrees.app \
    -D background="$WORK/background.tiff" \
    -D icon=dist/TwoDegrees.app/Contents/Resources/AppIcon.icns \
    "Two Degrees" "$DMG"
}

# Plain fallback so a release still ships if the styled build ever fails.
plain() {
  mkdir -p "$WORK/stage"
  cp -R dist/TwoDegrees.app "$WORK/stage/"
  ln -s /Applications "$WORK/stage/Applications"
  hdiutil create -volname "Two Degrees" -srcfolder "$WORK/stage" -ov -format UDZO "$DMG"
}

if ! styled; then
  echo "::warning::Styled DMG failed; packaging a plain DMG instead."
  rm -f "$DMG"
  plain
fi

if [[ -n "${CODESIGN_IDENTITY:-}" && "${CODESIGN_IDENTITY}" != "-" ]]; then
  codesign --sign "$CODESIGN_IDENTITY" --timestamp "$DMG"
fi

# The DMG is submitted too, but not waited for: Apple has taken more than three hours to review it
# while the app inside cleared in under one. The app carries its own stapled ticket, which is what
# Gatekeeper checks when it's opened; the DMG's ticket follows online once Apple finishes.
if $NOTARIZE; then
  xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" --output-format json \
    || echo "::warning::Couldn't submit the DMG for notarization; the app inside is notarized and stapled"
fi

shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Packaged $DMG"
