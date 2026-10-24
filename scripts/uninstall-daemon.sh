#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "run with sudo: sudo $0" >&2
    exit 1
fi

LABEL="uno.kayros.kancerbero.daemon"
launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist"
rm -f "/Library/PrivilegedHelperTools/$LABEL"
echo "removed $LABEL"
