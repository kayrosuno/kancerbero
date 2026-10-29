#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM="${DEVELOPMENT_TEAM:-AK37TK8X2Y}"

cd "$ROOT"

SIGNING="$ROOT/Config/Signing.local.xcconfig"
if [[ ! -f "$SIGNING" ]]; then
    echo "missing $SIGNING" >&2
    echo "copy Config/Signing.local.xcconfig.example and fill in KANCERBERO_APP_PROFILE" >&2
    echo "and KANCERBERO_FILTER_PROFILE with the Developer ID profile names/UUIDs" >&2
    exit 1
fi

for var in KANCERBERO_APP_PROFILE KANCERBERO_FILTER_PROFILE; do
    if ! grep -Eq "^[[:space:]]*${var}[[:space:]]*=[[:space:]]*[^[:space:]]+" "$SIGNING"; then
        echo "$var is empty in $SIGNING" >&2
        echo "release builds need Developer ID provisioning profiles (see docs/verification.md)" >&2
        exit 1
    fi
done

identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ "$identities" != *"Developer ID Application"* ]]; then
    echo "no Developer ID Application identity in the keychain" >&2
    echo "create one from Xcode > Settings > Accounts > Manage Certificates (+)," >&2
    echo "then regenerate the Developer ID provisioning profiles for it" >&2
    exit 1
fi

# Xcode rewrites CODE_SIGN_IDENTITY/CODE_SIGN_STYLE in the target settings when
# Signing & Capabilities is touched, which silently downgrades Release to Apple
# Development and makes notarization fail. Verify the resolved settings first.
target_settings() {
    xcodebuild -project Kancerbero.xcodeproj -target "$1" \
        -configuration Release -showBuildSettings 2>/dev/null || true
}

setting_value() {
    local settings="$1" key="$2"
    awk -v key="$key" '
        $1 == key { sub(/^[[:space:]]*[^=]*= /, ""); print; exit }
    ' <<<"$settings"
}

require_setting() {
    local target="$1" key="$2" expected="$3" value
    value="$(setting_value "$(target_settings "$target")" "$key")"
    if [[ "$value" != "$expected" ]]; then
        echo "$target Release: $key is '${value:-<unset>}', expected '$expected'" >&2
        echo "remove the Release overrides from project.pbxproj (Xcode re-adds them" >&2
        echo "when you edit Signing & Capabilities); see docs/verification.md" >&2
        exit 1
    fi
}

require_empty_setting() {
    local target="$1" key="$2" value
    value="$(setting_value "$(target_settings "$target")" "$key")"
    value="${value%\"}"
    value="${value#\"}"
    if [[ -n "$value" ]]; then
        echo "$target Release: $key is '$value', expected empty" >&2
        echo "the daemon must not have an App ID or team; see docs/verification.md" >&2
        exit 1
    fi
}

# The identity may be the literal "Developer ID Application" or a certificate
# fingerprint pinned in Signing.local when several Developer ID identities exist.
require_developer_id_identity() {
    local target="$1" value
    value="$(setting_value "$(target_settings "$target")" CODE_SIGN_IDENTITY)"
    if [[ "$value" != "Developer ID Application" && ! "$value" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        echo "$target Release: CODE_SIGN_IDENTITY is '${value:-<unset>}', expected a Developer ID identity" >&2
        exit 1
    fi
}

require_developer_id_identity Kancerbero
require_developer_id_identity KancerberoFilter
require_developer_id_identity KancerberoDaemon
require_setting Kancerbero CODE_SIGN_STYLE Manual
require_setting KancerberoFilter CODE_SIGN_STYLE Manual
require_setting Kancerbero DEVELOPMENT_TEAM "$TEAM"
require_setting KancerberoFilter DEVELOPMENT_TEAM "$TEAM"
require_empty_setting KancerberoDaemon DEVELOPMENT_TEAM

for target in Kancerbero KancerberoFilter; do
    value="$(setting_value "$(target_settings "$target")" PROVISIONING_PROFILE_SPECIFIER)"
    if [[ -z "$value" ]]; then
        echo "$target Release: no PROVISIONING_PROFILE_SPECIFIER resolved" >&2
        echo "check KANCERBERO_APP_PROFILE / KANCERBERO_FILTER_PROFILE in $SIGNING" >&2
        exit 1
    fi
done

# Signing identity, style and hardened runtime come from the xcconfigs.
# Do not pass DEVELOPMENT_TEAM on the command line: command-line settings
# override every target and would make Xcode derive an App ID (and therefore a
# restricted application-identifier entitlement) for the daemon tool.
xcodebuild -project Kancerbero.xcodeproj -scheme Kancerbero \
    -configuration Release -derivedDataPath build \
    build

APP="$ROOT/build/Build/Products/Release/Kancerbero.app"
EXT="$APP/Contents/Library/SystemExtensions/uno.kayros.kancerbero.filter.systemextension"
DAEMON="$APP/Contents/Library/LaunchDaemons/KancerberoDaemon"
PRODUCT_DAEMON="$ROOT/build/Build/Products/Release/KancerberoDaemon"

codesign --verify --deep --strict --verbose=2 "$APP"

signature_info() { codesign -dvvv "$1" 2>&1 || true; }
entitlements_of() { codesign -d --entitlements - --xml "$1" 2>/dev/null || true; }

if [[ ! -d "$EXT" ]]; then
    echo "missing system extension at $EXT" >&2
    exit 1
fi

for binary in "$APP" "$EXT" "$DAEMON"; do
    if [[ "$(signature_info "$binary")" != *"Authority=Developer ID Application"* ]]; then
        echo "$binary is not signed with a Developer ID Application certificate" >&2
        exit 1
    fi
done

# The daemon is a bare tool, so it cannot claim a restricted entitlement
# without an embedded provisioning profile (TN3125). If it does, AMFI kills the
# launchd job at spawn with "Launch Constraint Violation" while BTM/Login Items
# still reports the item as enabled. It must be signed with no entitlements at
# all: keep Resources/Daemon/KancerberoDaemon.entitlements empty and keep
# PRODUCT_BUNDLE_IDENTIFIER/DEVELOPMENT_TEAM off the KancerberoDaemon target.
for daemon in "$PRODUCT_DAEMON" "$DAEMON"; do
    if [[ ! -f "$daemon" ]]; then
        echo "missing daemon binary at $daemon" >&2
        exit 1
    fi
    if [[ "$(signature_info "$daemon")" != *"runtime"* ]]; then
        echo "$daemon is not built with the hardened runtime" >&2
        exit 1
    fi
    daemon_entitlements="$(entitlements_of "$daemon")"
    daemon_entitlements_json=""
    if [[ -n "${daemon_entitlements//[[:space:]]/}" ]]; then
        daemon_entitlements_json="$(
            printf '%s' "$daemon_entitlements" | plutil -convert json -o - -- - 2>/dev/null || true
        )"
    fi
    if [[ -n "$daemon_entitlements_json" && "$daemon_entitlements_json" != "{}" ]]; then
        echo "$daemon has entitlements; the daemon must be signed with none:" >&2
        printf '%s\n' "$daemon_entitlements" >&2
        echo "keep Resources/Daemon/KancerberoDaemon.entitlements empty and remove" >&2
        echo "PRODUCT_BUNDLE_IDENTIFIER/DEVELOPMENT_TEAM from the daemon target" >&2
        exit 1
    fi
    if [[ -f "$daemon/Contents/embedded.provisionprofile" ]]; then
        echo "$daemon carries a provisioning profile; a bare tool cannot use one" >&2
        exit 1
    fi
done

# The launch constraint that ServiceManagement attaches to the job comes from
# the host app's designated requirement. Sign the daemon with the app's signing
# identifier (Config/KancerberoDaemon.xcconfig sets -i), otherwise launchd
# kills it at spawn with "Launch Constraint Violation".
for daemon in "$PRODUCT_DAEMON" "$DAEMON"; do
    daemon_identifier="$(signature_info "$daemon" | sed -n 's/^Identifier=//p' | head -1)"
    if [[ "$daemon_identifier" != "uno.kayros.kancerbero" ]]; then
        echo "$daemon signing identifier is '${daemon_identifier:-<unset>}', expected 'uno.kayros.kancerbero'" >&2
        echo "check OTHER_CODE_SIGN_FLAGS = -i uno.kayros.kancerbero on the daemon target" >&2
        exit 1
    fi
done

if [[ "$(entitlements_of "$APP")" == *"get-task-allow"* ]]; then
    echo "release app still carries get-task-allow; it is a development build" >&2
    exit 1
fi

for key in com.apple.application-identifier \
           com.apple.developer.networking.networkextension \
           com.apple.developer.system-extension.install \
           com.apple.security.application-groups; do
    if [[ "$(entitlements_of "$APP")" != *"$key"* ]]; then
        echo "release app is missing expected entitlement $key" >&2
        exit 1
    fi
done

for key in content-filter-provider-systemextension \
           com.apple.security.app-sandbox \
           com.apple.application-identifier; do
    if [[ "$(entitlements_of "$EXT")" != *"$key"* ]]; then
        echo "embedded filter extension is missing expected entitlement $key" >&2
        echo "check Resources/Filter/KancerberoFilter.entitlements and the Developer ID profile" >&2
        exit 1
    fi
done

if [[ "$(entitlements_of "$EXT")" == *"get-task-allow"* ]]; then
    echo "release extension still carries get-task-allow; it is a development build" >&2
    exit 1
fi

for bundle in "$APP" "$EXT"; do
    if [[ ! -f "$bundle/Contents/embedded.provisionprofile" ]]; then
        echo "missing embedded.provisionprofile in $bundle" >&2
        exit 1
    fi
done

echo "release app: $APP"
