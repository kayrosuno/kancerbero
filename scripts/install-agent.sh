#!/bin/bash
set -euo pipefail

# User-scoped LaunchAgent used for development. It runs as the current user,
# so it can only inspect that user's processes, but it exercises the exact
# XPC path without requiring sudo. The root LaunchDaemon is installed by
# install-daemon.sh.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"
BIN="$ROOT/build/Build/Products/$CONFIG/KancerberoDaemon"
LABEL="uno.kayros.kancerbero.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs/Kancerbero"

if [ ! -x "$BIN" ]; then
    echo "missing $BIN; run scripts/build.sh first" >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
        <string>--daemon</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>uno.kayros.kancerbero.daemon</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/agent.out.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/agent.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "installed $LABEL"
echo "logs: $LOG_DIR"
launchctl print "gui/$(id -u)/$LABEL" | sed -n '1,25p'
