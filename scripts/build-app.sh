#!/usr/bin/env bash
# Builds TwoDegrees.app (universal: Apple silicon + Intel) with its widget into ./dist.
# The Xcode project is generated from project.yml with XcodeGen, because SwiftPM can't build
# app extensions. (`swift run` still works for quick development of the app alone.)
# Usage: scripts/build-app.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-${VERSION:-0.1.0}}"
VERSION="${VERSION##*v}"  # "v0.1.0" or "two-degrees-v0.1.0" -> "0.1.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="dist/TwoDegrees.app"
WIDGET="$APP/Contents/PlugIns/TwoDegreesWidget.appex"

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --quiet

xcodebuild -project TwoDegrees.xcodeproj -scheme TwoDegrees -configuration Release \
  -derivedDataPath build -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  -quiet build

rm -rf "$APP"
mkdir -p dist
cp -R build/Build/Products/Release/TwoDegrees.app "$APP"

# Icon: 1024px PNG -> .icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Sign inside out: the widget keeps its sandbox entitlements, then the app.
# Uses a Developer ID if one is configured, otherwise ad-hoc (fine for sideloading).
IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi
codesign --force --options runtime "$TIMESTAMP" --entitlements Resources/Widget.entitlements --sign "$IDENTITY" "$WIDGET"
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose "$APP"

echo "Built $APP ($VERSION build $BUILD) with widget"
