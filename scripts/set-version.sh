#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: set-version.sh <marketing> [build]}"
BUILD="${2:-$(date +%Y%m%d)01}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "invalid marketing version '$VERSION' (expected X.Y.Z)" >&2
    exit 1
fi
if [[ ! "$BUILD" =~ ^[0-9]+$ ]]; then
    echo "invalid build '$BUILD' (expected an integer)" >&2
    exit 1
fi

prev_tag="$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
if [[ -n "$prev_tag" ]]; then
    prev_build="$(git -C "$ROOT" show "$prev_tag:Config/Version.xcconfig" 2>/dev/null \
        | awk -F' *= *' '$1 == "KANCERBERO_BUILD_VERSION" { print $2 }')"
    if [[ -n "$prev_build" && "$BUILD" -le "$prev_build" ]]; then
        echo "build $BUILD must be greater than $prev_tag ($prev_build)" >&2
        exit 1
    fi
fi

cat > "$ROOT/Config/Version.xcconfig" <<EOF
// Single source of truth for the app, daemon and filter versions.
// Bump with scripts/set-version.sh; do not edit by hand.
// MARKETING_VERSION must be semver; CURRENT_PROJECT_VERSION must be a strictly
// increasing integer (Sparkle compares it and sysextd uses it to stage a new
// system extension).
KANCERBERO_MARKETING_VERSION = $VERSION
KANCERBERO_BUILD_VERSION = $BUILD
EOF

echo "version $VERSION ($BUILD) written to Config/Version.xcconfig"
echo "commit and push the bump before publishing the release"
