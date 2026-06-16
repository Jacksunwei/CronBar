#!/bin/bash
# Builds Resources/AppIcon.icns from the source artwork
# Sources/CronBar/Resources/AppIcon.png (a 1024x1024 transparent PNG).
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Sources/CronBar/Resources/AppIcon.png"
if [ ! -f "$SRC" ]; then
    echo "Missing $SRC" >&2
    exit 1
fi

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET" Resources

gen() { sips -z "$2" "$2" "$SRC" --out "$ICONSET/$1" >/dev/null; }
gen icon_16x16.png 16
gen icon_16x16@2x.png 32
gen icon_32x32.png 32
gen icon_32x32@2x.png 64
gen icon_128x128.png 128
gen icon_128x128@2x.png 256
gen icon_256x256.png 256
gen icon_256x256@2x.png 512
gen icon_512x512.png 512
gen icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Generated Resources/AppIcon.icns from $SRC"
