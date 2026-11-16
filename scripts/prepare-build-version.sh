#!/bin/bash
set -euo pipefail

# A wrapper script may have prepared the version before invoking xcodebuild;
# the scheme pre-action then only needs to keep the existing values.
if [[ "${KANCERBERO_VERSION_PREPARED:-}" == "1" ]]; then
    exit 0
fi

if [[ -n "${SRCROOT:-}" && -f "$SRCROOT/Config/Version.xcconfig" ]]; then
    ROOT="$SRCROOT"
else
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

source "$ROOT/scripts/lib/version.sh"

VERSION_FILE="$ROOT/Config/Version.xcconfig"
COMPONENT_FILE="$ROOT/Config/ComponentVersions.xcconfig"
OUT_DIR="$ROOT/build/Generated"
APP_XCCONFIG="$OUT_DIR/Version.xcconfig"
APP_PLIST="$OUT_DIR/Version.plist"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "prepare-build-version: missing $VERSION_FILE" >&2
    exit 1
fi

PREFIX="$(awk -F' *= *' '$1 == "KANCERBERO_VERSION_PREFIX" { print $2; exit }' \
    "$VERSION_FILE" 2>/dev/null || true)"
PREFIX="${PREFIX:-0.1}"
if [[ ! "$PREFIX" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "prepare-build-version: invalid KANCERBERO_VERSION_PREFIX '$PREFIX'" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

# One clock read; the marketing patch is the final build number, so it must be
# assigned after the monotonic floor is applied below.
read -r BUILD <<<"$(date -u +%y%m%d%H%M)"

# The app build must never go backwards. The previous generated state and the
# release tags are the floor.
PREVIOUS_BUILD=""
if [[ -f "$APP_PLIST" ]]; then
    PREVIOUS_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :build' "$APP_PLIST" 2>/dev/null || true)"
fi
PREVIOUS_BUILD="$(kancerbero_normalize_build "$PREVIOUS_BUILD")"
TAG_BUILD="$(kancerbero_last_tag_build "$ROOT")"
FLOOR="$PREVIOUS_BUILD"
if [[ -n "$TAG_BUILD" && ( -z "$FLOOR" || "$TAG_BUILD" -gt "$FLOOR" ) ]]; then
    FLOOR="$TAG_BUILD"
fi
if [[ -n "$FLOOR" && "$BUILD" -le "$FLOOR" ]]; then
    BUILD=$((10#$FLOOR + 1))
fi
if [[ ! "$BUILD" =~ ^[0-9]{10}$ ]]; then
    echo "prepare-build-version: generated build '$BUILD' is not 10 digits" >&2
    exit 1
fi

# The last version component is exactly the build.
MARKETING="$PREFIX.$BUILD"

component_value() {
    kancerbero_component_value "$COMPONENT_FILE" "$1"
}

hash_paths() {
    (
        cd "$ROOT"
        local path missing=()
        for path in "$@"; do
            [[ -e "$path" ]] || missing+=("$path")
        done
        if (( ${#missing[@]} )); then
            printf 'hash_paths: missing hashed path: %s\n' "${missing[@]}" >&2
            return 1
        fi
        find "$@" -type f -print \
            | LC_ALL=C sort \
            | while IFS= read -r file; do
                printf '%s\n' "$file"
                shasum -a 256 "$file" | awk '{ print $1 }'
            done \
            | shasum -a 256 | awk '{ print $1 }'
    )
}

DAEMON_PREFIX="$(component_value KANCERBERO_DAEMON_VERSION_PREFIX)"
DAEMON_PREFIX="${DAEMON_PREFIX:-0.2}"
DAEMON_BUILD="$(component_value KANCERBERO_DAEMON_BUILD_VERSION)"
DAEMON_BUILD="$(kancerbero_normalize_build "${DAEMON_BUILD:-0}")"
DAEMON_HASH_PREVIOUS="$(component_value KANCERBERO_DAEMON_SOURCE_HASH)"

FILTER_PREFIX="$(component_value KANCERBERO_FILTER_VERSION_PREFIX)"
FILTER_PREFIX="${FILTER_PREFIX:-0.2}"
FILTER_BUILD="$(component_value KANCERBERO_FILTER_BUILD_VERSION)"
FILTER_BUILD="$(kancerbero_normalize_build "${FILTER_BUILD:-0}")"
FILTER_HASH_PREVIOUS="$(component_value KANCERBERO_FILTER_SOURCE_HASH)"

for prefix in "$DAEMON_PREFIX" "$FILTER_PREFIX"; do
    if [[ ! "$prefix" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "prepare-build-version: invalid component version prefix '$prefix'" >&2
        exit 1
    fi
done

DAEMON_PATHS=(
    Sources/KancerberoDaemon
    Sources/KancerberoCore
    Sources/KancerberoC
    Resources/Daemon
    Resources/LaunchDaemons
    Config/KancerberoDaemon.xcconfig
    Config/KancerberoCore.xcconfig
    Config/KancerberoC.xcconfig
    Config/Base.xcconfig
)
FILTER_PATHS=(
    Sources/KancerberoFilter
    Sources/KancerberoFilterContract
    Resources/Filter
    Config/KancerberoFilter.xcconfig
    Config/KancerberoFilterContract.xcconfig
    Config/Base.xcconfig
)

# Source-only hashes: the derived marketing/build must not feed back into the
# bump decision, or every build would change the hash and bump again.
DAEMON_HASH="$(hash_paths "${DAEMON_PATHS[@]}")"
FILTER_HASH="$(hash_paths "${FILTER_PATHS[@]}")"

# A missing recorded state counts as a change: the identity plumbing in this
# version must replace any component installed from an older build.
if [[ ! -f "$COMPONENT_FILE" || -z "$DAEMON_HASH_PREVIOUS" ]]; then
    DAEMON_BUILD="$BUILD"
elif [[ "$DAEMON_HASH" != "$DAEMON_HASH_PREVIOUS" ]]; then
    if [[ "$BUILD" -le "$DAEMON_BUILD" ]]; then
        DAEMON_BUILD=$((DAEMON_BUILD + 1))
    else
        DAEMON_BUILD="$BUILD"
    fi
fi

if [[ ! -f "$COMPONENT_FILE" || -z "$FILTER_HASH_PREVIOUS" ]]; then
    FILTER_BUILD="$BUILD"
elif [[ "$FILTER_HASH" != "$FILTER_HASH_PREVIOUS" ]]; then
    if [[ "$BUILD" -le "$FILTER_BUILD" ]]; then
        FILTER_BUILD=$((FILTER_BUILD + 1))
    else
        FILTER_BUILD="$BUILD"
    fi
fi

TMP_XCCONFIG="$(mktemp "$OUT_DIR/.Version.xcconfig.XXXXXX")"
TMP_PLIST="$(mktemp "$OUT_DIR/.Version.plist.XXXXXX")"
TMP_COMPONENTS="$(mktemp "$ROOT/Config/.ComponentVersions.XXXXXX")"
trap 'rm -f "$TMP_XCCONFIG" "$TMP_PLIST" "$TMP_COMPONENTS"' EXIT

cat >"$TMP_XCCONFIG" <<EOF
// Generated by scripts/prepare-build-version.sh. Do not edit.
KANCERBERO_MARKETING_VERSION = $MARKETING
KANCERBERO_BUILD_VERSION = $BUILD
EOF

cat >"$TMP_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>marketing</key>
	<string>$MARKETING</string>
	<key>build</key>
	<string>$BUILD</string>
	<key>prefix</key>
	<string>$PREFIX</string>
</dict>
</plist>
EOF

cat >"$TMP_COMPONENTS" <<EOF
// Recorded component identities. Regenerated by scripts/prepare-build-version.sh
// only when the component sources change. The marketing patch is the build.
KANCERBERO_DAEMON_VERSION_PREFIX = $DAEMON_PREFIX
KANCERBERO_DAEMON_BUILD_VERSION = $DAEMON_BUILD
KANCERBERO_DAEMON_SOURCE_HASH = $DAEMON_HASH
KANCERBERO_FILTER_VERSION_PREFIX = $FILTER_PREFIX
KANCERBERO_FILTER_BUILD_VERSION = $FILTER_BUILD
KANCERBERO_FILTER_SOURCE_HASH = $FILTER_HASH
KANCERBERO_DAEMON_MARKETING_VERSION = $DAEMON_PREFIX.$DAEMON_BUILD
KANCERBERO_FILTER_MARKETING_VERSION = $FILTER_PREFIX.$FILTER_BUILD
EOF

plutil -lint "$TMP_PLIST" >/dev/null
chmod 0644 "$TMP_XCCONFIG" "$TMP_PLIST" "$TMP_COMPONENTS"
mv -f "$TMP_XCCONFIG" "$APP_XCCONFIG"
mv -f "$TMP_PLIST" "$APP_PLIST"
if [[ -f "$COMPONENT_FILE" ]] && cmp -s "$TMP_COMPONENTS" "$COMPONENT_FILE"; then
    rm -f "$TMP_COMPONENTS"
else
    mv -f "$TMP_COMPONENTS" "$COMPONENT_FILE"
fi
trap - EXIT

echo "prepare-build-version: app $MARKETING ($BUILD), daemon $DAEMON_PREFIX.$DAEMON_BUILD ($DAEMON_BUILD), filter $FILTER_PREFIX.$FILTER_BUILD ($FILTER_BUILD)"
