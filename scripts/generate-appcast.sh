#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(awk -F' *= *' '$1 == "KANCERBERO_MARKETING_VERSION" { print $2 }' \
    "$ROOT/Config/Version.xcconfig")"
BUILD="$(awk -F' *= *' '$1 == "KANCERBERO_BUILD_VERSION" { print $2 }' \
    "$ROOT/Config/Version.xcconfig")"
UPDATES="$ROOT/build/updates"
SPARKLE_BIN="${SPARKLE_BIN:-$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="${SPARKLE_ACCOUNT:-kancerbero-ed25519}"
APPCAST="$UPDATES/appcast.xml"
ZIP="$UPDATES/Kancerbero-$VERSION.zip"
FEED="https://kayrosuno.github.io/kancerbero/appcast.xml"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "generate_appcast not found at $SPARKLE_BIN" >&2
    echo "run: xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero -resolvePackageDependencies -derivedDataPath build" >&2
    exit 1
fi
if [[ ! -f "$ZIP" ]]; then
    echo "missing distribution archive: $ZIP" >&2
    echo "run scripts/package-release.sh first" >&2
    exit 1
fi

# Keep the previous feed so old versions stay available. The new item gets the
# current release tag as its download prefix.
curl -fsSL "$FEED" -o "$APPCAST" 2>/dev/null || true

"$SPARKLE_BIN/generate_appcast" \
    --account "$ACCOUNT" \
    --download-url-prefix "https://github.com/kayrosuno/kancerbero/releases/download/v$VERSION/" \
    --link "https://github.com/kayrosuno/kancerbero/releases/tag/v$VERSION" \
    --embed-release-notes \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    -o "$APPCAST" \
    "$UPDATES"

xmllint --noout "$APPCAST"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST"
grep -q "Kancerbero-$VERSION.zip" "$APPCAST"
grep -q "sparkle:edSignature" "$APPCAST"

# generate_appcast already embeds the feed signature. SURequireSignedFeed makes
# the app reject a feed whose signature is missing or invalid.
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$APPCAST" >/dev/null

echo "appcast: $APPCAST"
