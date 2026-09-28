#!/usr/bin/env bash
# Tests, packages, tags and publishes a GitHub release from a clean, pushed main, then updates the cask in
# mikker/homebrew-tap. Usage: scripts/release.sh 0.3   (run again to retry a failed release or tap update)
# Versions are X.Y, bumped by 0.1 each release.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?Usage: scripts/release.sh X.Y}"
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+$ ]] || { echo 'Expected version X.Y' >&2; exit 1; }
tag="v$version"
repo=mikker/Dinky

# Puts dist/dinky.rb into the tap through a temporary clone, so a local tap checkout is left alone.
update_tap() (
  local checkout
  checkout="$(mktemp -d "${TMPDIR:-/tmp}/dinky-tap.XXXXXX")"
  trap 'rm -rf "$checkout"' EXIT
  git clone --quiet --depth 1 git@github.com:mikker/homebrew-tap.git "$checkout"
  cp dist/dinky.rb "$checkout/Casks/dinky.rb"
  git -C "$checkout" add Casks/dinky.rb
  if ! git -C "$checkout" diff --cached --quiet; then
    git -C "$checkout" commit -q -m "Update dinky to $version"
    git -C "$checkout" push -q
  fi
  echo "==> tap: dinky $version"
)

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
# A published release only gets its tap update retried; its archive is never replaced.
if [[ "$(gh release view "$tag" -R "$repo" --json isDraft --jq .isDraft 2>/dev/null || true)" == false ]]; then
  [[ "$latest" == "$tag" ]] || { echo "$tag is already published and is not the latest release" >&2; exit 1; }
  mkdir -p dist
  gh release download "$tag" -R "$repo" -p dinky.rb -D dist --clobber
  update_tap
  exit 0
fi

swift test
scripts/package-release.sh "$version"
[[ "$head" == "$(git rev-parse HEAD)" && -z "$(git status --porcelain)" ]] || { echo 'Source changed during packaging; retry' >&2; exit 1; }

git rev-parse --verify -q "$tag" >/dev/null || git tag -a "$tag" -m "Release $version"
git push origin "$tag"
gh release view "$tag" -R "$repo" >/dev/null 2>&1 \
  || gh release create "$tag" -R "$repo" --verify-tag --draft --title "dinky $version" --generate-notes
gh release upload "$tag" -R "$repo" dist/dinky.app.zip dist/appcast.xml dist/dinky.rb --clobber
gh release edit "$tag" -R "$repo" --draft=false --latest
echo "==> https://github.com/$repo/releases/tag/$tag"
update_tap
