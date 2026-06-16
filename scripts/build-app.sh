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
if [ -d ".build/$CONFIG/CronBar_CronBar.bundle" ]; then
    cp -R ".build/$CONFIG/CronBar_CronBar.bundle" "$APP/Contents/Resources/"
fi

# Ad-hoc code signature so macOS is happy to launch it locally.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Run it with:  open $APP"
