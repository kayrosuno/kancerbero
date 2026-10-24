#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${1:-/Users/alejandro/CODE/Iconos/kancerbero/kancerbero_1024x1024.png}"
ASSETS="$ROOT/Sources/Kancerbero/Assets.xcassets"
ICONSET="$ASSETS/AppIcon.appiconset"

if ! command -v sips >/dev/null 2>&1; then
    echo "error: sips not found" >&2
    exit 1
fi
if [ ! -r "$SOURCE" ]; then
    echo "error: cannot read source image: $SOURCE" >&2
    exit 1
fi

WIDTH="$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/{print $2}')"
HEIGHT="$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/{print $2}')"
if [ "$WIDTH" != "$HEIGHT" ]; then
    echo "warning: source is not square (${WIDTH}x${HEIGHT}); icons will be stretched" >&2
fi
if [ "$WIDTH" -lt 1024 ] || [ "$HEIGHT" -lt 1024 ]; then
    echo "warning: source is smaller than 1024x1024; the largest icon will be upscaled" >&2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kancerbero-icon.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

MASTER="$TMP/master_1024.png"
sips -z 1024 1024 "$SOURCE" --out "$MASTER" >/dev/null

mkdir -p "$ICONSET"

cat > "$ASSETS/Contents.json" <<'JSON'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

generate() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$filename" >/dev/null
}

generate 16  "icon_16x16.png"
generate 32  "icon_16x16@2x.png"
generate 32  "icon_32x32.png"
generate 64  "icon_32x32@2x.png"
generate 128 "icon_128x128.png"
generate 256 "icon_128x128@2x.png"
generate 256 "icon_256x256.png"
generate 512 "icon_256x256@2x.png"
generate 512 "icon_512x512.png"
generate 1024 "icon_512x512@2x.png"

echo "source:      $SOURCE (${WIDTH}x${HEIGHT})"
echo "icon set:    $ICONSET"
for filename in \
    icon_16x16.png icon_16x16@2x.png \
    icon_32x32.png icon_32x32@2x.png \
    icon_128x128.png icon_128x128@2x.png \
    icon_256x256.png icon_256x256@2x.png \
    icon_512x512.png icon_512x512@2x.png
do
    dimensions="$(sips -g pixelWidth -g pixelHeight "$ICONSET/$filename" \
        | awk '/pixelWidth|pixelHeight/{printf "%s%s", sep, $2; sep="x"}')"
    printf '  %-24s %s\n' "$filename" "$dimensions"
done
