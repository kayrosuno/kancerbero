#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Debug}"

cd "$ROOT"
source "$ROOT/scripts/lib/version.sh"

./scripts/prepare-build-version.sh
export KANCERBERO_VERSION_PREPARED=1

echo "==> building Kancerbero ($CONFIG)"
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
    -configuration "$CONFIG" -derivedDataPath build build \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= >/dev/null

APP="$ROOT/build/Build/Products/$CONFIG/Kancerbero.app"
kancerbero_read_app_version "$APP"
FILTER_VERSION="$(kancerbero_component_value "$ROOT/Config/ComponentVersions.xcconfig" \
    KANCERBERO_FILTER_MARKETING_VERSION)"
FILTER_BUILD="$(kancerbero_component_value "$ROOT/Config/ComponentVersions.xcconfig" \
    KANCERBERO_FILTER_BUILD_VERSION)"
DAEMON_VERSION="$(kancerbero_component_value "$ROOT/Config/ComponentVersions.xcconfig" \
    KANCERBERO_DAEMON_MARKETING_VERSION)"
DAEMON_BUILD="$(kancerbero_component_value "$ROOT/Config/ComponentVersions.xcconfig" \
    KANCERBERO_DAEMON_BUILD_VERSION)"
kancerbero_require_filter_version "$APP" "$FILTER_VERSION" "$FILTER_BUILD"

for scheme in KancerberoProbe KancerberoDaemon; do
    echo "==> building $scheme ($CONFIG)"
    xcodebuild -project Kancerbero.xcodeproj -scheme "$scheme" \
        -configuration "$CONFIG" -derivedDataPath build build \
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= >/dev/null
done

DAEMON="$ROOT/build/Build/Products/$CONFIG/KancerberoDaemon"
PROBE="$ROOT/build/Build/Products/$CONFIG/KancerberoProbe"

daemon_out="$("$DAEMON" 2>&1 | head -1 || true)"
probe_out="$("$PROBE" version 2>&1 | head -1 || true)"

if [[ "$daemon_out" != *"$VERSION"* || "$daemon_out" != *"$BUILD"* \
    || "$daemon_out" != *"$DAEMON_VERSION"* || "$daemon_out" != *"$DAEMON_BUILD"* ]]; then
    echo "daemon reports '$daemon_out'" >&2
    echo "expected app $VERSION ($BUILD) and daemon $DAEMON_VERSION ($DAEMON_BUILD)" >&2
    exit 1
fi
if [[ "$probe_out" != *"$VERSION"* ]]; then
    echo "probe reports '$probe_out', expected app $VERSION" >&2
    exit 1
fi

echo "products:"
ls -1 "$ROOT/build/Build/Products/$CONFIG"
echo "app: $VERSION ($BUILD) · daemon: $DAEMON_VERSION ($DAEMON_BUILD) · filter: $FILTER_VERSION ($FILTER_BUILD)"
