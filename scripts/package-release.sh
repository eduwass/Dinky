#!/usr/bin/env bash
# Builds, signs with Developer ID, notarizes and staples dinky.app, and zips it into dist/.
# Usage: scripts/package-release.sh 0.1.0
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/package-release.sh X.Y.Z}"
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y.Z' >&2; exit 1; }
profile="${NOTARYTOOL_PROFILE:-TunaNotary}"
identity="${DEVELOPER_ID_APPLICATION:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}"
[[ -n "$identity" ]] || { echo 'No Developer ID Application identity; set DEVELOPER_ID_APPLICATION' >&2; exit 1; }
build="$(( $(git rev-list --count HEAD) + 100 ))"

echo "==> Building and signing dinky.app $version ($build) with $identity"
VERSION="$version" BUILD="$build" IDENTITY="$identity" SIGN_FLAGS="--options runtime --timestamp" scripts/bundle.sh
codesign --verify --strict --verbose=1 build/dinky.app

mkdir -p dist
rm -f dist/dinky.app.zip
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==> Notarizing with profile $profile"
ditto -c -k --sequesterRsrc --keepParent build/dinky.app "$tmp/dinky.zip"
xcrun notarytool submit "$tmp/dinky.zip" --keychain-profile "$profile" --wait
xcrun stapler staple build/dinky.app
spctl --assess --type execute --verbose=1 build/dinky.app

ditto -c -k --sequesterRsrc --keepParent build/dinky.app dist/dinky.app.zip
echo "==> dist/dinky.app.zip ($(du -h dist/dinky.app.zip | cut -f1)), version $version build $build"
