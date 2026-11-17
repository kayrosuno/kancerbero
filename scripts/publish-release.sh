#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/version.sh"

REPO="${GITHUB_REPO:-kayrosuno/kancerbero}"
REMOTE="${GITHUB_REMOTE:-github}"
APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"
ZIP="$ROOT/build/updates/Kancerbero-$VERSION.zip"
DMG="$ROOT/build/updates/dmg/Kancerbero-$VERSION.dmg"
TAG="v$BUILD"
ASSETS=("$ZIP" "$DMG")

USE_GH=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    USE_GH=1
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    USE_GH=0
elif command -v gh >/dev/null 2>&1; then
    echo "gh is installed but not authenticated; run: gh auth login" >&2
    echo "or export GITHUB_TOKEN with contents:write for $REPO" >&2
    exit 1
else
    echo "export GITHUB_TOKEN with contents:write for $REPO" >&2
    exit 1
fi
[[ -f "$ZIP" ]] || {
    echo "missing $ZIP; run scripts/package-release.sh first" >&2
    exit 1
}
[[ -f "$DMG" ]] || {
    echo "missing $DMG; run scripts/package-dmg.sh first" >&2
    exit 1
}
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "working tree is not clean; commit your changes before publishing" >&2
    exit 1
fi

HEAD_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    TAGGED_COMMIT="$(git -C "$ROOT" rev-list -n1 "$TAG")"
    if [[ "$TAGGED_COMMIT" != "$HEAD_COMMIT" ]]; then
        echo "tag $TAG already points to $TAGGED_COMMIT, not HEAD $HEAD_COMMIT" >&2
        exit 1
    fi
else
    git -C "$ROOT" tag -a "$TAG" -m "Kancerbero $VERSION ($BUILD)"
fi
git -C "$ROOT" push "$REMOTE" "$TAG"

if [[ "$USE_GH" == "1" ]]; then
    # gh is idempotent: reuse the release and replace the assets on a retry.
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
    else
        gh release create "$TAG" "${ASSETS[@]}" \
            --repo "$REPO" \
            --title "Kancerbero $VERSION ($BUILD)" \
            --notes "Kancerbero $VERSION ($BUILD)"
    fi
    for asset in "${ASSETS[@]}"; do
        asset_url="https://github.com/$REPO/releases/download/$TAG/$(basename "$asset")"
        curl -fsSIL "$asset_url" | grep -q "200"
        echo "release asset: $asset_url"
    done
    exit 0
fi

# Fallback without gh: GitHub rejects a second release for the same tag (422).
# Reuse the existing release and asset so a retry after a partial publish is
# idempotent.
release_json="$(curl -sS \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases/tags/$TAG" || true)"
release_id="$(printf '%s' "$release_json" | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin).get("id", ""))
except Exception:
    print("")
' || true)"

if [[ -z "$release_id" ]]; then
    release_json="$(curl -fsSL -X POST \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases" \
        -d "{\"tag_name\":\"$TAG\",\"name\":\"Kancerbero $VERSION ($BUILD)\",\"draft\":false,\"prerelease\":false}")"
    release_id="$(printf '%s' "$release_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
else
    echo "release already exists: $TAG"
fi

upload_asset() {
    local path="$1"
    local content_type="$2"
    local name
    name="$(basename "$path")"
    local asset_id
    asset_id="$(curl -sS \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/$REPO/releases/$release_id/assets?per_page=100" \
        | python3 -c '
import json, sys
name = sys.argv[1]
try:
    assets = json.load(sys.stdin)
except Exception:
    assets = []
if isinstance(assets, list):
    for asset in assets:
        if asset.get("name") == name:
            print(asset.get("id", ""))
            break
' "$name" || true)"

    if [[ -z "$asset_id" ]]; then
        curl -fsSL -X POST \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github+json" \
            -H "Content-Type: $content_type" \
            --data-binary @"$path" \
            "https://uploads.github.com/repos/$REPO/releases/$release_id/assets?name=$name" >/dev/null
    else
        echo "release asset already exists: $name"
    fi
}

upload_asset "$ZIP" "application/zip"
upload_asset "$DMG" "application/x-apple-diskimage"

for asset in "${ASSETS[@]}"; do
    asset_url="https://github.com/$REPO/releases/download/$TAG/$(basename "$asset")"
    curl -fsSIL "$asset_url" | grep -q "200"
    echo "release asset: $asset_url"
done
