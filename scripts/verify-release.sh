#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/version.sh"

APP="$(kancerbero_require_release_app "$ROOT")"
kancerbero_read_app_version "$APP"

REPO="${GITHUB_REPO:-kayrosuno/kancerbero}"
FEED="${SPARKLE_FEED_URL:-https://${REPO%%/*}.github.io/${REPO##*/}/appcast.xml}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# GitHub Pages can take a minute or two to deploy a new appcast. Match BOTH the
# app version and the app build: several builds can share the same day.
for _ in $(seq 1 12); do
    if curl -fsSL "$FEED" -o "$TMP/appcast.xml" 2>/dev/null \
        && grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$TMP/appcast.xml" \
        && grep -q "<sparkle:version>$BUILD</sparkle:version>" "$TMP/appcast.xml"; then
        break
    fi
    sleep 15
done

curl -fsSL "$FEED" -o "$TMP/appcast.xml"
xmllint --noout "$TMP/appcast.xml"
grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$TMP/appcast.xml"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$TMP/appcast.xml"
grep -q "sparkle:edSignature" "$TMP/appcast.xml"

enclosure="$(python3 - "$TMP/appcast.xml" "$BUILD" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
build = sys.argv[2]
root = ET.parse(sys.argv[1]).getroot()
for item in root.findall("./channel/item"):
    if item.findtext("sparkle:version", namespaces=ns) == build:
        enc = item.find("enclosure")
        if enc is not None:
            print(enc.get("url", ""))
            break
PY
)"

if [[ -z "$enclosure" ]]; then
    echo "no enclosure found for build $BUILD in $FEED" >&2
    exit 1
fi
case "$enclosure" in
    *"$VERSION.zip") ;;
    *)
        echo "enclosure does not contain $VERSION.zip: $enclosure" >&2
        exit 1
        ;;
esac
curl -fsSIL "$enclosure" | grep -q "200"

echo "feed OK: $FEED"
echo "asset OK: $enclosure"
