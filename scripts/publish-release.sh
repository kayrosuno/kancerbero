#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${GITHUB_REPO:-kayrosuno/kancerbero}"
VERSION="$(awk -F' *= *' '$1 == "KANCERBERO_MARKETING_VERSION" { print $2 }' \
    "$ROOT/Config/Version.xcconfig")"
ZIP="$ROOT/build/updates/Kancerbero-$VERSION.zip"
TAG="v$VERSION"

: "${GITHUB_TOKEN:?export GITHUB_TOKEN with contents:write for $REPO}"
if [[ ! -f "$ZIP" ]]; then
    echo "missing $ZIP; run scripts/package-release.sh first" >&2
    exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "working tree is not clean; commit the version bump before publishing" >&2
    exit 1
fi
if ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    git -C "$ROOT" tag -a "$TAG" -m "Kancerbero $VERSION"
fi
git -C "$ROOT" push github "$TAG"

release_json="$(curl -fsSL -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"Kancerbero $VERSION\",\"draft\":false,\"prerelease\":false}")"
release_id="$(printf '%s' "$release_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"

curl -fsSL -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Content-Type: application/zip" \
    --data-binary @"$ZIP" \
    "https://uploads.github.com/repos/$REPO/releases/$release_id/assets?name=$(basename "$ZIP")" >/dev/null

asset_url="https://github.com/$REPO/releases/download/$TAG/$(basename "$ZIP")"
curl -fsSIL "$asset_url" | grep -q "200"
echo "release asset: $asset_url"
