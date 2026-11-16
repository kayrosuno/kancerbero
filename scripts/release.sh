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

if [[ "$PUBLISH" == "--publish" ]]; then
    # Fail before the build/notarize steps if the release cannot be published.
    if ! command -v gh >/dev/null 2>&1 && [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "publishing requires gh (run: gh auth login) or GITHUB_TOKEN" >&2
        exit 1
    fi
    if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1 \
        && [[ -z "${GITHUB_TOKEN:-}" ]]; then
        echo "gh is installed but not authenticated; run: gh auth login" >&2
        echo "or export GITHUB_TOKEN with contents:write" >&2
        exit 1
    fi

    if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
        :
    else
        upstream="${GITHUB_REMOTE:-github}/main"
        if ! git rev-parse -q --verify "refs/remotes/$upstream" >/dev/null; then
            echo "no upstream configured and refs/remotes/$upstream does not exist;" >&2
            echo "fetch the remote or set an upstream before publishing" >&2
            exit 1
        fi
    fi
    if ! git merge-base --is-ancestor HEAD "$upstream"; then
        echo "HEAD is not pushed to $upstream; push before publishing" >&2
        exit 1
    fi
fi

./scripts/build-release.sh
./scripts/notarize.sh
./scripts/package-release.sh
./scripts/generate-appcast.sh

source "$ROOT/scripts/lib/version.sh"
APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"

echo "release artifacts: Kancerbero $VERSION ($BUILD)"
echo "  zip: build/updates/Kancerbero-$VERSION.zip"

if [[ "$PUBLISH" == "--publish" ]]; then
    ./scripts/publish-release.sh
    ./scripts/publish-appcast.sh
    ./scripts/verify-release.sh
else
    echo "artifacts ready in build/updates; rerun with --publish to publish"
fi
