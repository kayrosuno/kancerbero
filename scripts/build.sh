#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"

cd "$ROOT"
for scheme in Kancerbero KancerberoProbe KancerberoDaemon; do
    echo "==> building $scheme ($CONFIG)"
    xcodebuild -project Kancerbero.xcodeproj -scheme "$scheme" \
        -configuration "$CONFIG" -derivedDataPath build build \
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= >/dev/null
done

echo "products:"
ls -1 "$ROOT/build/Build/Products/$CONFIG"
