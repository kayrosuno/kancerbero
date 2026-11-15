#!/bin/bash
set -euo pipefail

FEED="https://kayrosuno.github.io/kancerbero/appcast.xml"
VERSION="${1:-$(awk -F' *= *' '$1 == "KANCERBERO_MARKETING_VERSION" { print $2 }' \
    "$(cd "$(dirname "$0")/.." && pwd)/Config/Version.xcconfig")}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# GitHub Pages can take a minute or two to deploy a new appcast.
for _ in $(seq 1 12); do
    if curl -fsSL "$FEED" -o "$TMP/appcast.xml" 2>/dev/null \
        && grep -q "sparkle:shortVersionString>$VERSION<" "$TMP/appcast.xml"; then
        break
    fi
    sleep 15
done
curl -fsSL "$FEED" -o "$TMP/appcast.xml"
xmllint --noout "$TMP/appcast.xml"
grep -q "sparkle:shortVersionString>$VERSION<" "$TMP/appcast.xml"
grep -q "sparkle:edSignature" "$TMP/appcast.xml"

enclosure="$(python3 - "$TMP/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(sys.argv[1]).getroot()
for item in root.findall("./channel/item"):
    version = item.findtext("sparkle:shortVersionString", namespaces=ns)
    if version:
        enc = item.find("enclosure")
        if enc is not None:
            print(enc.get("url", ""))
PY
)"
if [[ -z "$enclosure" ]]; then
    echo "no enclosure found in $FEED" >&2
    exit 1
fi
curl -fsSIL "$enclosure" | grep -q "200"

echo "feed OK: $FEED"
echo "asset OK: $enclosure"
