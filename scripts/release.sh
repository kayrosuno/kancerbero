#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: release.sh <marketing> <build> [--publish]}"
BUILD="${2:?usage: release.sh <marketing> <build> [--publish]}"
PUBLISH="${3:-}"

cd "$ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "working tree is not clean; commit or stash before releasing" >&2
    exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
current_version="$(awk -F' *= *' '$1 == "KANCERBERO_MARKETING_VERSION" { print $2 }' Config/Version.xcconfig)"
current_build="$(awk -F' *= *' '$1 == "KANCERBERO_BUILD_VERSION" { print $2 }' Config/Version.xcconfig)"
if [[ "$current_version" != "$VERSION" || "$current_build" != "$BUILD" ]]; then
    ./scripts/set-version.sh "$VERSION" "$BUILD"
    git add Config/Version.xcconfig
    git commit -m "Release $VERSION ($BUILD)"
    git push github "$BRANCH"
else
    echo "version already set to $VERSION ($BUILD); reusing the commit"
fi

./scripts/build-release.sh
./scripts/notarize.sh
./scripts/package-release.sh
./scripts/generate-appcast.sh

if [[ "$PUBLISH" == "--publish" ]]; then
    : "${GITHUB_TOKEN:?export GITHUB_TOKEN with contents:write}"
    ./scripts/publish-release.sh
    ./scripts/publish-appcast.sh
    ./scripts/verify-release.sh
else
    echo "artifacts ready in build/updates; rerun with --publish to publish"
fi
