#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${1:?usage: set-version.sh <major.minor> (the date/build suffix is generated automatically)}"

if [[ ! "$PREFIX" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "invalid version prefix '$PREFIX' (expected major.minor, e.g. 0.1)" >&2
    exit 1
fi

CONFIG="$ROOT/Config/Version.xcconfig"
cat > "$CONFIG" <<EOF
// App version prefix. The real marketing version and build are generated on
// every build by scripts/prepare-build-version.sh:
//   marketing = <prefix>.<YYMMDD>
//   build     = YYYYMMDDHHMMSS (UTC, strictly increasing)
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

echo "version prefix $PREFIX written to Config/Version.xcconfig"
echo "the next build will use $PREFIX.<YYMMDD> and a timestamp build number"
