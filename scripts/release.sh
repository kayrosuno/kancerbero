#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISH="${1:-}"

if [[ -n "$PUBLISH" && "$PUBLISH" != "--publish" ]]; then
    echo "release.sh no longer takes a version/build; they are generated automatically" >&2
    echo "usage: release.sh [--publish]" >&2
    exit 2
fi

cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "working tree is not clean; commit or stash before releasing" >&2
    exit 1
fi

./scripts/build-release.sh
./scripts/notarize.sh
./scripts/package-release.sh
./scripts/generate-appcast.sh

source "$ROOT/scripts/lib/version.sh"
APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"

echo "release artifacts: Kancerbero $VERSION ($BUILD)"
echo "  zip: build/updates/Kancerbero-$VERSION-$BUILD.zip"

if [[ "$PUBLISH" == "--publish" ]]; then
    : "${GITHUB_TOKEN:?export GITHUB_TOKEN with contents:write}"

    if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
        if ! git merge-base --is-ancestor HEAD "$upstream"; then
            echo "HEAD is not pushed to $upstream; push before publishing" >&2
            exit 1
        fi
    else
        echo "warning: no upstream branch; the release tag will still be pushed" >&2
    fi

    ./scripts/publish-release.sh
    ./scripts/publish-appcast.sh
    ./scripts/verify-release.sh
else
    echo "artifacts ready in build/updates; rerun with --publish to publish"
fi
