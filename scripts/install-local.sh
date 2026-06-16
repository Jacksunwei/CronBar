#!/bin/bash
# Build CronBar from source and install it to /Applications.
# If Homebrew currently manages cronbar, it is uninstalled first to avoid
# desyncing Homebrew's view of /Applications/CronBar.app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/CronBar.app"

# Remove a Homebrew-managed copy if present.
if command -v brew >/dev/null 2>&1 && brew list --cask cronbar >/dev/null 2>&1; then
    echo "Removing Homebrew-managed cronbar (to avoid desync)..."
    brew uninstall --cask cronbar
fi

# Build the app bundle.
./scripts/build-app.sh

# Quit any running instance so it can be replaced and relaunched fresh.
pkill -f 'CronBar.app/Contents/MacOS/CronBar' 2>/dev/null || true

# Install into /Applications.
rm -rf "$APP"
cp -R CronBar.app "$APP"

echo "Installed $APP"
open "$APP"
