#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${DEVELOPMENT_TEAM:-AK37TK8X2Y}"

cd "$ROOT"

SIGNING="$ROOT/Config/Signing.local.xcconfig"
if [[ ! -f "$SIGNING" ]]; then
    echo "missing $SIGNING" >&2
    echo "copy Config/Signing.local.xcconfig.example and fill in KANCERBERO_APP_PROFILE" >&2
    echo "and KANCERBERO_FILTER_PROFILE with the Developer ID profile names/UUIDs" >&2
    exit 1
fi

for var in KANCERBERO_APP_PROFILE KANCERBERO_FILTER_PROFILE; do
    if ! grep -Eq "^[[:space:]]*${var}[[:space:]]*=[[:space:]]*[^[:space:]]+" "$SIGNING"; then
        echo "$var is empty in $SIGNING" >&2
        echo "release builds need Developer ID provisioning profiles (see docs/verification.md)" >&2
        exit 1
    fi
done

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "no Developer ID Application identity in the keychain" >&2
    echo "create/download one from the Apple Developer portal; Apple Development" >&2
    echo "and Apple Distribution identities cannot sign a network system extension" >&2
    exit 1
fi

# Signing identity, style and hardened runtime come from Config/Release.xcconfig.
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
    -configuration Release -derivedDataPath build \
    DEVELOPMENT_TEAM="$TEAM" \
    build

APP="$ROOT/build/Build/Products/Release/Kancerbero.app"
EXT="$APP/Contents/Library/SystemExtensions/KancerberoFilter.systemextension"

codesign --verify --deep --strict --verbose=2 "$APP"

if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q "get-task-allow"; then
    echo "release app still carries get-task-allow; it is a development build" >&2
    exit 1
fi

if ! codesign -d --entitlements - "$EXT" 2>/dev/null | grep -q "content-filter-provider-systemextension"; then
    echo "embedded filter extension lacks content-filter-provider-systemextension" >&2
    echo "check Resources/Filter/KancerberoFilter.entitlements and the Developer ID profile" >&2
    exit 1
fi

for bundle in "$APP" "$EXT"; do
    if [[ ! -f "$bundle/Contents/embedded.provisionprofile" ]]; then
        echo "missing embedded.provisionprofile in $bundle" >&2
        exit 1
    fi
done

echo "release app: $APP"
