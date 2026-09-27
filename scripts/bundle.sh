#!/usr/bin/env bash
# Builds build/dinky.app and signs it with a stable identity, so the Accessibility grant survives rebuilds.
# Usage: scripts/bundle.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"
IDENTITY="${IDENTITY:-Apple Development: Mikkel Malmberg (VAW8MWER4W)}"
SIGN_FLAGS="${SIGN_FLAGS:-}"  # release packaging adds --options runtime --timestamp
CONFIG=release
[[ "${1:-}" == "--debug" ]] && CONFIG=debug

swift build -c "$CONFIG"

APP=build/dinky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c "$CONFIG" --show-bin-path)/dinky" "$APP/Contents/MacOS/dinky"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"

# The app icon, from Resources/icon.png (1024 x 1024).
if [[ -f Resources/icon.png ]]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET" "$APP/Contents/Resources"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/icon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Resources/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  plutil -replace CFBundleIconFile -string "AppIcon" "$APP/Contents/Info.plist"
fi

# Sparkle.framework from the resolved SwiftPM artifact; the linker rpath finds it here.
SPARKLE_SRC="$(find .build/artifacts -maxdepth 6 -path '*macos-arm64_x86_64/Sparkle.framework' | head -1)"
[[ -n "$SPARKLE_SRC" ]] || { echo 'Sparkle.framework not found in .build/artifacts' >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

# Sign inside out: Sparkle's helpers, the framework, then the app.
sign() { codesign --force $SIGN_FLAGS --sign "$IDENTITY" "$1"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in XPCServices/Downloader.xpc XPCServices/Installer.xpc Updater.app Autoupdate Sparkle; do
  sign "$SPARKLE/Versions/Current/$item"
done
sign "$SPARKLE"
sign "$APP"
echo "built $APP ($CONFIG, $VERSION build $BUILD)"
