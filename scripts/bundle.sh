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

codesign --force $SIGN_FLAGS --sign "$IDENTITY" "$APP"
echo "built $APP ($CONFIG, $VERSION build $BUILD)"
