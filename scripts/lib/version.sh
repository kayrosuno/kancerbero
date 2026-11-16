#!/bin/bash
# Shared version helpers for the release scripts. Source this file.

kancerbero_release_app() {
    printf '%s\n' "${1:?repository root}/build/Build/Products/Release/Kancerbero.app"
}

kancerbero_require_release_app() {
    local app
    app="$(kancerbero_release_app "$1")"
    if [[ ! -d "$app" ]]; then
        echo "missing Release app: $app" >&2
        echo "run scripts/build-release.sh and scripts/notarize.sh first" >&2
        return 1
    fi
    printf '%s\n' "$app"
}

# Sets VERSION and BUILD from the built app's Info.plist. The built artifact is
# authoritative: the generated xcconfig may belong to a different build.
kancerbero_read_app_version() {
    local app="${1:?app path}"
    local plist="$app/Contents/Info.plist"
    local version build
    if [[ ! -f "$plist" ]]; then
        echo "missing $plist; run scripts/build-release.sh first" >&2
        return 1
    fi
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
    build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "invalid CFBundleShortVersionString '$version' in $plist" >&2
        return 1
    fi
    if [[ ! "$build" =~ ^[0-9]{14}$ ]]; then
        echo "invalid CFBundleVersion '$build' in $plist (expected YYYYMMDDHHMMSS)" >&2
        return 1
    fi
    VERSION="$version"
    BUILD="$build"
}

kancerbero_require_filter_version() {
    local app="${1:?app path}"
    local version="${2:?version}"
    local build="${3:?build}"
    local plist="$app/Contents/Library/SystemExtensions/uno.kayros.kancerbero.filter.systemextension/Contents/Info.plist"
    local fv fb
    if [[ ! -f "$plist" ]]; then
        echo "missing filter Info.plist: $plist" >&2
        return 1
    fi
    fv="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
    fb="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)"
    if [[ "$fv" != "$version" || "$fb" != "$build" ]]; then
        echo "filter version is $fv ($fb), expected $version ($build)" >&2
        return 1
    fi
}

kancerbero_component_value() {
    local file="${1:?component file}"
    local key="${2:?key}"
    awk -F' *= *' -v key="$key" '$1 == key { print $2; exit }' "$file" 2>/dev/null || true
}
