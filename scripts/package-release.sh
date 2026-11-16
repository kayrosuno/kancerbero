#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/version.sh"

APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"
COMPONENTS="$ROOT/Config/ComponentVersions.xcconfig"
FILTER_MARKETING="$(kancerbero_component_value "$COMPONENTS" KANCERBERO_FILTER_MARKETING_VERSION)"
FILTER_BUILD="$(kancerbero_component_value "$COMPONENTS" KANCERBERO_FILTER_BUILD_VERSION)"
kancerbero_require_filter_version "$APP" "$FILTER_MARKETING" "$FILTER_BUILD"

OUT="$ROOT/build/updates"
ZIP="$OUT/Kancerbero-$VERSION-$BUILD.zip"

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
