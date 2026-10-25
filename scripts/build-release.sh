#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${DEVELOPMENT_TEAM:-AK37TK8X2Y}"

cd "$ROOT"
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
    -configuration Release -derivedDataPath build \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

APP="$ROOT/build/Build/Products/Release/Kancerbero.app"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "release app: $APP"
