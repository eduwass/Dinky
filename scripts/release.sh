#!/usr/bin/env bash
# Tests, packages, tags and publishes a GitHub release from a clean, pushed main.
# Usage: scripts/release.sh 0.1.0   (run again to retry a failed release)
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/release.sh X.Y.Z}"
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y.Z' >&2; exit 1; }
tag="v$version"
repo=mikker/Dinky

[[ "$(git branch --show-current)" == main ]] || { echo 'Release from main' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit your changes first' >&2; exit 1; }
git fetch -q origin main
head="$(git rev-parse HEAD)"
[[ "$head" == "$(git rev-parse origin/main)" ]] || { echo 'Push or pull main first' >&2; exit 1; }
if git rev-parse --verify -q "$tag" >/dev/null; then
  [[ "$head" == "$(git rev-list -n 1 "$tag")" ]] || { echo "Tag $tag points to another commit" >&2; exit 1; }
fi
latest="$(gh release view -R "$repo" --json tagName --jq .tagName 2>/dev/null || true)"
if [[ -n "$latest" ]]; then
  python3 - "$tag" "$latest" <<'PY'
import sys
v = lambda s: tuple(int(x) for x in s.removeprefix('v').split('.'))
if v(sys.argv[1]) <= v(sys.argv[2]): raise SystemExit(f'{sys.argv[1]} is not newer than the latest release {sys.argv[2]}')
PY
fi
if [[ "$(gh release view "$tag" -R "$repo" --json isDraft --jq .isDraft 2>/dev/null || true)" == false ]]; then
  echo "$tag is already published" >&2; exit 1
fi

swift test
scripts/package-release.sh "$version"
[[ "$head" == "$(git rev-parse HEAD)" && -z "$(git status --porcelain)" ]] || { echo 'Source changed during packaging; retry' >&2; exit 1; }

git rev-parse --verify -q "$tag" >/dev/null || git tag -a "$tag" -m "Release $version"
git push origin "$tag"
gh release view "$tag" -R "$repo" >/dev/null 2>&1 \
  || gh release create "$tag" -R "$repo" --verify-tag --draft --title "dinky $version" --generate-notes
gh release upload "$tag" -R "$repo" dist/dinky.app.zip dist/appcast.xml --clobber
gh release edit "$tag" -R "$repo" --draft=false --latest
echo "==> https://github.com/$repo/releases/tag/$tag"
