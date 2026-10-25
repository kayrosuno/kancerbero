#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release/Kancerbero.app"
DEST="${1:-/Applications/Kancerbero.app}"

if [[ ! -d "$APP" ]]; then
    echo "missing Release app: $APP" >&2
    echo "run scripts/build-release.sh first" >&2
    exit 1
fi

rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "installed: $DEST"
