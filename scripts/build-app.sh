#!/bin/bash
# Builds CronBar.app (a double-clickable, menu-bar app bundle) from the SPM
# executable, embedding Info.plist and the generated app icon.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="CronBar.app"
CONFIG="release"

# Ensure the icon exists.
if [ ! -f Resources/AppIcon.icns ]; then
    echo "Icon missing; generating..."
    ./scripts/make-icon.sh
fi

echo "Building (${CONFIG})..."
swift build -c "$CONFIG"
BIN=".build/$CONFIG/CronBar"

echo "Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CronBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Bundle the SPM resource bundle (contains AppIcon.png) so Bundle.module
# resolves at runtime inside the .app.
BUNDLE_SRC=""
if [ -d ".build/$CONFIG/CronBar_CronBar.bundle" ]; then
    BUNDLE_SRC=".build/$CONFIG/CronBar_CronBar.bundle"
else
    # Try to find the bundle dynamically inside the .build folder
    FOUND_BUNDLE=$(find .build -name "CronBar_CronBar.bundle" -type d | head -n 1)
    if [ -n "$FOUND_BUNDLE" ]; then
        BUNDLE_SRC="$FOUND_BUNDLE"
    fi
fi

if [ -n "$BUNDLE_SRC" ]; then
    cp -R "$BUNDLE_SRC" "$APP/Contents/Resources/"
    echo "Bundled resources from: $BUNDLE_SRC"
else
    echo "Warning: CronBar_CronBar.bundle not found!"
fi

# Code signing. Set CODESIGN_IDENTITY to a "Developer ID Application: ..."
# identity to produce a distributable (hardened-runtime, timestamped) signature;
# otherwise an ad-hoc signature is used for local runs.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$APP" >/dev/null 2>&1 || true
    echo "Signed ad-hoc."
else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
fi

echo "Built $APP"
echo "Run it with:  open $APP"
