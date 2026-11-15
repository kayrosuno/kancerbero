#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release/Kancerbero.app"
VERSION="$(awk -F' *= *' '$1 == "KANCERBERO_MARKETING_VERSION" { print $2 }' \
    "$ROOT/Config/Version.xcconfig")"
OUT="$ROOT/build/updates"
ZIP="$OUT/Kancerbero-$VERSION.zip"

if [[ ! -d "$APP" ]]; then
    echo "missing Release app: $APP" >&2
    echo "run scripts/build-release.sh and scripts/notarize.sh first" >&2
    exit 1
fi

mkdir -p "$OUT"
rm -f "$ZIP"

# The distribution archive is created AFTER stapling: the notarization ticket
# lives inside the .app and must be present in the zip users download.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Verify the archive exactly as the user will see it.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ditto -x -k "$ZIP" "$TMP"
codesign --verify --deep --strict --verbose=2 "$TMP/Kancerbero.app"
xcrun stapler validate "$TMP/Kancerbero.app"
spctl -a -vvv -t exec "$TMP/Kancerbero.app"

echo "distribution archive: $ZIP"
