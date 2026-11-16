#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${1:?usage: set-version.sh <major.minor> (the date/build suffix is generated automatically)}"

if [[ ! "$PREFIX" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "invalid version prefix '$PREFIX' (expected major.minor, e.g. 0.1)" >&2
    exit 1
fi

CONFIG="$ROOT/Config/Version.xcconfig"

if [[ -f "$CONFIG" ]] && grep -Eq '^[[:space:]]*KANCERBERO_VERSION_PREFIX[[:space:]]*=' "$CONFIG"; then
    # Edit only the prefix line so any other change to the file is preserved.
    TMP="$(mktemp "$ROOT/Config/.Version.xcconfig.XXXXXX")"
    trap 'rm -f "$TMP"' EXIT
    awk -v prefix="$PREFIX" '
        /^[[:space:]]*KANCERBERO_VERSION_PREFIX[[:space:]]*=/ {
            print "KANCERBERO_VERSION_PREFIX = " prefix
            next
        }
        { print }
    ' "$CONFIG" >"$TMP"
    chmod 0644 "$TMP"
    mv -f "$TMP" "$CONFIG"
    trap - EXIT
else
    cat > "$CONFIG" <<EOF
// App version prefix. The real marketing version and build are generated on
// every build by scripts/prepare-build-version.sh:
//   marketing = <prefix>.<build>
//   build     = YYMMDDHHMM (UTC, strictly increasing)
// The last version component is exactly the build.
// Change the prefix with scripts/set-version.sh (<major.minor>).
KANCERBERO_VERSION_PREFIX = $PREFIX

// Fallbacks used only when the generated xcconfig does not exist (a target-only
// build without the scheme pre-action, or a broken generator).
KANCERBERO_MARKETING_VERSION = \$(KANCERBERO_VERSION_PREFIX).0
KANCERBERO_BUILD_VERSION = 0

// Generated before every build; keep this include after the fallbacks so the
// generated values win.
#include? "../build/Generated/Version.xcconfig"

// Recorded daemon/filter identities. They change only when the corresponding
// component sources or marketing versions change.
#include "ComponentVersions.xcconfig"
EOF
fi

echo "version prefix $PREFIX written to Config/Version.xcconfig"
echo "the next build will use $PREFIX.<build> and the same build number as its last component"
