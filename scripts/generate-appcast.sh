#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/version.sh"

APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"

UPDATES="$ROOT/build/updates"
SPARKLE_BIN="${SPARKLE_BIN:-$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
ACCOUNT="${SPARKLE_ACCOUNT:-kancerbero-ed25519}"
APPCAST="$UPDATES/appcast.xml"
ZIP="$UPDATES/Kancerbero-$VERSION.zip"
TAG="v$BUILD"
REPO="${GITHUB_REPO:-kayrosuno/kancerbero}"
FEED="${SPARKLE_FEED_URL:-https://${REPO%%/*}.github.io/${REPO##*/}/appcast.xml}"

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

# Keep the previous feed so old versions stay available. generate_appcast
# reuses an existing appcast in the archives directory.
curl -fsSL "$FEED" -o "$APPCAST" 2>/dev/null || true

# Refuse to publish an item that is not newer than what clients may already
# have seen. This also catches stale local tags or a clock that went backwards.
if [[ -s "$APPCAST" ]] && xmllint --noout "$APPCAST" 2>/dev/null; then
    feed_max="$(python3 - "$APPCAST" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
try:
    root = ET.parse(sys.argv[1]).getroot()
except Exception:
    sys.exit(0)
values = []
for item in root.findall("./channel/item"):
    value = item.findtext("sparkle:version", namespaces=ns)
    if value and value.isdigit():
        values.append(int(value))
if values:
    print(max(values))
PY
)"
    if [[ -n "$feed_max" ]] && (( 10#$BUILD <= feed_max )); then
        echo "build $BUILD is not greater than the newest item in $FEED ($feed_max)" >&2
        echo "check the clock or fetch the release tags before publishing" >&2
        exit 1
    fi
fi

"$SPARKLE_BIN/generate_appcast" \
    --account "$ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --link "https://github.com/$REPO/releases/tag/$TAG" \
    --embed-release-notes \
    --maximum-deltas 0 \
    --maximum-versions 3 \
    -o "$APPCAST" \
    "$UPDATES"

xmllint --noout "$APPCAST"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST"
grep -q "Kancerbero-$VERSION.zip" "$APPCAST"
grep -q "sparkle:edSignature" "$APPCAST"
"$SPARKLE_BIN/sign_update" --account "$ACCOUNT" --verify "$APPCAST" >/dev/null

echo "appcast: $APPCAST ($VERSION/$BUILD)"
