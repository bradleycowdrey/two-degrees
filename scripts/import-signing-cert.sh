#!/usr/bin/env bash
# CI: imports the Developer ID certificate into a temporary keychain and exports CODESIGN_IDENTITY and
# DERIVED_TEAM_ID to later steps. Needs DEVELOPER_ID_P12 (base64), DEVELOPER_ID_P12_PASSWORD,
# NOTARY_APPLE_ID and NOTARY_PASSWORD.
set -euo pipefail
# A signed app that isn't notarized is still blocked by Gatekeeper: insist on both.
[[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]] || { echo "::error::DEVELOPER_ID_P12 is set but NOTARY_APPLE_ID or NOTARY_PASSWORD is missing"; exit 1; }
KEYCHAIN="$RUNNER_TEMP/build.keychain"
echo "$DEVELOPER_ID_P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p ci "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p ci "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign \
  || { echo "::error::Couldn't import the certificate: check DEVELOPER_ID_P12 is the base64 of the .p12 and DEVELOPER_ID_P12_PASSWORD is its password"; exit 1; }
security set-key-partition-list -S apple-tool:,apple: -s -k ci "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN"
rm -f "$RUNNER_TEMP/cert.p12"
ID="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
[[ -n "$ID" ]] || { echo "::error::The certificate isn't a Developer ID Application certificate"; security find-identity -v -p codesigning "$KEYCHAIN"; exit 1; }
TEAM="${ID##*(}"; TEAM="${TEAM%)}"
echo "Signing as: $ID (team $TEAM)"
echo "CODESIGN_IDENTITY=$ID" >> "$GITHUB_ENV"
echo "DERIVED_TEAM_ID=$TEAM" >> "$GITHUB_ENV"
