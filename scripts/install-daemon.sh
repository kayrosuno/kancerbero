#!/bin/bash
set -euo pipefail

# Development install of the privileged daemon. Requires sudo.
# Production uses SMAppService.daemon with a Developer ID signature instead.

if [ "$(id -u)" -ne 0 ]; then
    echo "run with sudo: sudo $0" >&2
    exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"
SOURCE="$ROOT/build/Build/Products/$CONFIG/KancerberoDaemon"
TARGET="/Library/PrivilegedHelperTools/uno.kayros.kancerbero.daemon"
PLIST_SRC="$ROOT/Resources/LaunchDaemons/uno.kayros.kancerbero.daemon.legacy.plist"
PLIST_DST="/Library/LaunchDaemons/uno.kayros.kancerbero.daemon.plist"
LOG_DIR="/Library/Logs/Kancerbero"
LABEL="uno.kayros.kancerbero.daemon"

if [ ! -x "$SOURCE" ]; then
    echo "missing $SOURCE; run scripts/build.sh first" >&2
    exit 1
fi

install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -d -o root -g wheel -m 755 "$LOG_DIR"
install -o root -g wheel -m 755 "$SOURCE" "$TARGET"

if ! codesign --verify --strict "$TARGET" >/dev/null 2>&1; then
    codesign --force --sign - "$TARGET"
fi

install -o root -g wheel -m 644 "$PLIST_SRC" "$PLIST_DST"

launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DST"
launchctl kickstart -k "system/$LABEL"

echo "installed $LABEL"
echo "logs: $LOG_DIR"
launchctl print "system/$LABEL" | sed -n '1,25p'
