#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/version.sh"

PROFILE="${NOTARY_PROFILE:-kancerbero-notary}"
DEFAULT_IDENTITY="642A9BD5DBAEA0622E387D1C6620428C31E0E127"
SIGN_ID="${KANCERBERO_DMG_SIGN_IDENTITY:-$DEFAULT_IDENTITY}"
DEV="${KANCERBERO_DMG_DEV:-0}"
SKIP_LAYOUT="${KANCERBERO_DMG_SKIP_LAYOUT:-0}"
BACKGROUND="$ROOT/Resources/DMG/background.png"
OUT_DIR="$ROOT/build/updates/dmg"

usage() {
    echo "usage: package-dmg.sh" >&2
    echo "env: NOTARY_PROFILE, KANCERBERO_DMG_SIGN_IDENTITY, KANCERBERO_DMG_DEV=1," >&2
    echo "     KANCERBERO_DMG_SKIP_LAYOUT=1 (headless testing; no Finder background)" >&2
}

die() {
    echo "package-dmg: $*" >&2
    exit 1
}

if [[ $# -ne 0 ]]; then
    usage
    exit 2
fi

APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"

COMPONENTS="$ROOT/Config/ComponentVersions.xcconfig"
FILTER_MARKETING="$(kancerbero_component_value "$COMPONENTS" KANCERBERO_FILTER_MARKETING_VERSION)"
FILTER_BUILD="$(kancerbero_component_value "$COMPONENTS" KANCERBERO_FILTER_BUILD_VERSION)"
kancerbero_require_filter_version "$APP" "$FILTER_MARKETING" "$FILTER_BUILD"

for tool in hdiutil osascript codesign ditto sips shasum security xcrun lipo python3; do
    command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done

[[ -f "$BACKGROUND" ]] || die "missing background: $BACKGROUND"

sips_value() {
    sips -g "$1" "$BACKGROUND" 2>/dev/null | awk -v key="$1" '$1 == key ":" { print int($2) }'
}
[[ "$(sips_value pixelWidth)" == "1320" ]] || die "background must be 1320 px wide"
[[ "$(sips_value pixelHeight)" == "896" ]] || die "background must be 896 px tall"
[[ "$(sips_value dpiWidth)" == "144" ]] || die "background must be 144 DPI"
[[ "$(sips_value dpiHeight)" == "144" ]] || die "background must be 144 DPI"

codesign --verify --deep --strict --verbose=2 "$APP"
app_signature="$(codesign -dvvv "$APP" 2>&1 || true)"
[[ "$app_signature" == *"Authority=Developer ID Application"* ]] \
    || die "app is not signed with Developer ID"
[[ "$app_signature" == *"TeamIdentifier=AK37TK8X2Y"* ]] \
    || die "app is not signed by team AK37TK8X2Y"

if [[ "$DEV" == "1" ]]; then
    echo "warning: KANCERBERO_DMG_DEV=1; notarization and stapling are skipped" >&2
else
    xcrun stapler validate "$APP" >/dev/null \
        || die "app is not notarized/stapled; run ./scripts/notarize.sh first"
    spctl -a -vvv -t exec "$APP" >/dev/null 2>&1 \
        || die "app fails Gatekeeper assessment; notarize it first"
fi

[[ "$SIGN_ID" =~ ^[0-9A-Fa-f]{40}$ ]] \
    || die "signing identity must be a 40-hex fingerprint"
security find-identity -v -p codesigning | grep -qi "$SIGN_ID" \
    || die "signing identity $SIGN_ID is not in the keychain"
if [[ -f "$ROOT/Config/Signing.local.xcconfig" ]]; then
    configured="$(awk -F' *= *' '$1 == "CODE_SIGN_IDENTITY" { print $2; exit }' \
        "$ROOT/Config/Signing.local.xcconfig")"
    [[ -z "$configured" || "$configured" == "$SIGN_ID" ]] \
        || die "signing identity does not match Config/Signing.local.xcconfig ($configured)"
fi

if [[ "$DEV" != "1" ]]; then
    if ! history_out="$(xcrun notarytool history --keychain-profile "$PROFILE" \
            --output-format json 2>&1)"; then
        printf '%s\n' "$history_out" >&2
        die "notary profile '$PROFILE' is missing or unusable. Create it with:
  xcrun notarytool store-credentials $PROFILE \\
    --apple-id '<Apple ID>' --team-id AK37TK8X2Y --password '<app-specific password>'"
    fi
fi

VOLNAME="Kancerbero $VERSION"
[[ ! -e "/Volumes/$VOLNAME" ]] \
    || die "volume '$VOLNAME' is already mounted; eject it and rerun"

DEV_SUFFIX=""
if [[ "$DEV" == "1" ]]; then
    DEV_SUFFIX="-dev"
fi
FINAL="$OUT_DIR/Kancerbero-$VERSION$DEV_SUFFIX.dmg"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kancerbero-dmg.XXXXXX")"
STAGE="$WORK/stage"
MOUNT="/Volumes/$VOLNAME"
VERIFY_MNT="$WORK/verify"
RW="$WORK/Kancerbero-rw.dmg"
TMP_DMG="$OUT_DIR/.Kancerbero-$VERSION.$$.dmg"
MNT_DEV=""
VERIFY_DEV=""

cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "$VERIFY_DEV" ]]; then
        hdiutil detach "$VERIFY_DEV" >/dev/null 2>&1 \
            || hdiutil detach "$VERIFY_MNT" -force >/dev/null 2>&1 || true
    elif [[ -d "$VERIFY_MNT" ]]; then
        hdiutil detach "$VERIFY_MNT" -force >/dev/null 2>&1 || true
    fi
    if [[ -n "$MNT_DEV" ]]; then
        hdiutil detach "$MNT_DEV" >/dev/null 2>&1 \
            || hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    elif [[ -d "$MOUNT" ]]; then
        hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK"
    if [[ -n "$TMP_DMG" ]]; then
        rm -f "$TMP_DMG" || true
    fi
    exit "$status"
}
trap cleanup EXIT

mkdir -p "$STAGE/.background" "$VERIFY_MNT" "$OUT_DIR"
rm -f "$TMP_DMG"

ditto "$APP" "$STAGE/Kancerbero.app"
ln -s /Applications "$STAGE/Applications"
ditto "$BACKGROUND" "$STAGE/.background/background.png"

codesign --verify --deep --strict --verbose=2 "$STAGE/Kancerbero.app"
[[ "$(readlink "$STAGE/Applications")" == "/Applications" ]] \
    || die "staged Applications link is wrong"
if [[ "$DEV" != "1" ]]; then
    xcrun stapler validate "$STAGE/Kancerbero.app" >/dev/null \
        || die "staged app lost its notarization ticket"
fi

stage_kb="$(du -sk "$STAGE" | awk '{print $1}')"
rw_kb=$((stage_kb + 131072))
if ((rw_kb < 262144)); then
    rw_kb=262144
fi

hdiutil create -srcfolder "$STAGE" -size "${rw_kb}k" -fs APFS \
    -volname "$VOLNAME" -format UDRW -ov "$RW"

attach_out="$(hdiutil attach -nobrowse -readwrite -noautoopen "$RW")"
MNT_DEV="$(printf '%s\n' "$attach_out" | awk '/^\/dev\/disk/ { print $1; exit }')"
[[ -n "$MNT_DEV" ]] || die "could not determine the attached device"
[[ -d "$MOUNT" ]] || die "image did not mount at $MOUNT"

[[ -d "$MOUNT/Kancerbero.app" ]] || die "app is missing from the read-write image"
[[ "$(readlink "$MOUNT/Applications")" == "/Applications" ]] \
    || die "Applications link is missing from the read-write image"
[[ -f "$MOUNT/.background/background.png" ]] \
    || die "background is missing from the read-write image"
sync

if [[ "$SKIP_LAYOUT" == "1" ]]; then
    echo "warning: KANCERBERO_DMG_SKIP_LAYOUT=1; the Finder layout will not be set" >&2
else
    cat >"$WORK/layout.applescript" <<'APPLESCRIPT'
on run argv
    set diskName to item 1 of argv
    set winX to (item 2 of argv) as integer
    set winY to (item 3 of argv) as integer
    set winW to (item 4 of argv) as integer
    set winH to (item 5 of argv) as integer
    set appX to (item 6 of argv) as integer
    set appY to (item 7 of argv) as integer
    set appsX to (item 8 of argv) as integer
    set appsY to (item 9 of argv) as integer
    set iconSize to (item 10 of argv) as integer
    set textSize to (item 11 of argv) as integer
    set bottomRightX to winX + winW
    set bottomRightY to winY + winH

    tell application "Finder"
        with timeout of 120 seconds
            tell disk diskName
                open
                tell container window
                    set current view to icon view
                    set toolbar visible to false
                    set statusbar visible to false
                    set the bounds to {winX, winY, bottomRightX, bottomRightY}
                    set position of every item to {bottomRightX + 100, 100}
                end tell

                set opts to the icon view options of container window
                tell opts
                    set arrangement to not arranged
                    set icon size to iconSize
                    set text size to textSize
                end tell
                set background picture of opts to file ".background:background.png"

                set position of item "Kancerbero.app" to {appX, appY}
                set position of item "Applications" to {appsX, appsY}

                close
                open
                delay 1
                tell container window
                    set the bounds to {winX, winY, bottomRightX - 10, bottomRightY - 10}
                end tell
                delay 1
                tell container window
                    set the bounds to {winX, winY, bottomRightX, bottomRightY}
                end tell
                delay 1
            end tell
        end timeout
    end tell
end run
APPLESCRIPT

WIN_X=200
WIN_Y=120
WIN_W=660
WIN_H=420
APP_X=165
APP_Y=180
APPS_X=495
APPS_Y=180
ICON_SIZE=128
TEXT_SIZE=13

layout_ok=0
for attempt in 1 2 3; do
    if osascript "$WORK/layout.applescript" \
        "$VOLNAME" "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H" \
        "$APP_X" "$APP_Y" "$APPS_X" "$APPS_Y" \
        "$ICON_SIZE" "$TEXT_SIZE" 2>"$WORK/layout.err"; then
        layout_ok=1
        break
    fi
    layout_error="$(cat "$WORK/layout.err")"
    case "$layout_error" in
        *-1743*|*"Not authorized"*)
            echo "package-dmg: Finder automation permission denied." >&2
            echo "Allow your terminal/IDE to control Finder in System Settings >" >&2
            echo "Privacy & Security > Automation, then rerun." >&2
            open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation" \
                >/dev/null 2>&1 || true
            exit 1
            ;;
    esac
    open -a Finder >/dev/null 2>&1 || true
    sleep 1
done
if [[ "$layout_ok" != "1" ]]; then
    cat "$WORK/layout.err" >&2
    die "could not configure the Finder layout"
fi

for _ in $(seq 1 60); do
    [[ -s "$MOUNT/.DS_Store" ]] && break
    sleep 0.5
done
[[ -s "$MOUNT/.DS_Store" ]] \
    || die "Finder did not write .DS_Store; the layout would be lost"
fi
sync

for _ in 1 2 3 4 5; do
    if hdiutil detach "$MNT_DEV" >/dev/null 2>&1; then
        MNT_DEV=""
        break
    fi
    sleep 1
done
if [[ -n "$MNT_DEV" ]]; then
    hdiutil detach "$MNT_DEV" -force >/dev/null 2>&1 \
        || die "could not detach $MNT_DEV"
    MNT_DEV=""
fi

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$TMP_DMG"
hdiutil verify "$TMP_DMG" >/dev/null

codesign --force --timestamp --sign "$SIGN_ID" "$TMP_DMG"
codesign --verify --verbose=2 "$TMP_DMG"

if [[ "$DEV" != "1" ]]; then
    submit_json="$(xcrun notarytool submit "$TMP_DMG" \
        --keychain-profile "$PROFILE" --wait --timeout 30m --output-format json)"
    submission_status="$(printf '%s' "$submit_json" | python3 -c \
        'import json,sys; print(json.load(sys.stdin).get("status",""))')"
    submission_id="$(printf '%s' "$submit_json" | python3 -c \
        'import json,sys; print(json.load(sys.stdin).get("id",""))')"
    if [[ "$submission_status" != "Accepted" ]]; then
        xcrun notarytool log "$submission_id" --keychain-profile "$PROFILE" >&2 || true
        die "DMG notarization failed with status '$submission_status'"
    fi

    xcrun stapler staple "$TMP_DMG"
    xcrun stapler validate "$TMP_DMG"
    codesign --verify --verbose=2 "$TMP_DMG"
    spctl --assess --type open --context context:primary-signature -vvv "$TMP_DMG"
else
    echo "warning: development DMG is signed but not notarized or stapled;" >&2
    echo "warning: do not distribute $FINAL" >&2
fi

verify_out="$(hdiutil attach -nobrowse -readonly -noautoopen \
    -mountpoint "$VERIFY_MNT" "$TMP_DMG")"
VERIFY_DEV="$(printf '%s\n' "$verify_out" | awk '/^\/dev\/disk/ { print $1; exit }')"
[[ -n "$VERIFY_DEV" ]] || die "could not mount the final DMG"

[[ -d "$VERIFY_MNT/Kancerbero.app" ]] || die "app is missing from the DMG"
[[ "$(readlink "$VERIFY_MNT/Applications")" == "/Applications" ]] \
    || die "Applications link is missing from the DMG"
[[ -f "$VERIFY_MNT/.background/background.png" ]] \
    || die "background is missing from the DMG"
if [[ "$SKIP_LAYOUT" != "1" ]]; then
    [[ -s "$VERIFY_MNT/.DS_Store" ]] \
        || die ".DS_Store is missing from the DMG"
fi

codesign --verify --deep --strict --verbose=2 "$VERIFY_MNT/Kancerbero.app"
if [[ "$DEV" != "1" ]]; then
    xcrun stapler validate "$VERIFY_MNT/Kancerbero.app" >/dev/null
    spctl -a -vvv -t exec "$VERIFY_MNT/Kancerbero.app" >/dev/null 2>&1
fi

built_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$VERIFY_MNT/Kancerbero.app/Contents/Info.plist")"
built_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$VERIFY_MNT/Kancerbero.app/Contents/Info.plist")"
[[ "$built_version" == "$VERSION" ]] || die "DMG app version is '$built_version', expected '$VERSION'"
[[ "$built_build" == "$BUILD" ]] || die "DMG app build is '$built_build', expected '$BUILD'"

hdiutil detach "$VERIFY_DEV" >/dev/null
VERIFY_DEV=""

mv -f "$TMP_DMG" "$FINAL"
TMP_DMG=""

echo "DMG:      $FINAL"
echo "Version:  $VERSION ($BUILD)"
echo "Arch:     $(lipo -archs "$APP/Contents/MacOS/Kancerbero")"
echo "SHA-256:  $(shasum -a 256 "$FINAL" | awk '{print $1}')"
if [[ "$SKIP_LAYOUT" == "1" ]]; then
    echo "warning: created without the Finder layout; rerun without" >&2
    echo "warning: KANCERBERO_DMG_SKIP_LAYOUT after granting Automation." >&2
fi
