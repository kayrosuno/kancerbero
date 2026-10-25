#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release/Kancerbero.app"
PROFILE="${NOTARY_PROFILE:-kancerbero-notary}"
ZIP="$(mktemp -d)/Kancerbero.zip"

if [[ ! -d "$APP" ]]; then
    echo "missing Release app: $APP" >&2
    echo "run scripts/build-release.sh first" >&2
    exit 1
fi

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"
echo "notarized app: $APP"
