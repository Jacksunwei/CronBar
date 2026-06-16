#!/bin/bash
# Dev loop: kill any running CronBar, rebuild, and launch the fresh build.
# Press Ctrl+C to quit the running app.
set -euo pipefail
cd "$(dirname "$0")/.."

# Kill running instances (match exact binary paths so we never kill this shell).
pkill -f '.build/debug/CronBar'            2>/dev/null || true
pkill -f '.build/release/CronBar'          2>/dev/null || true
pkill -f 'CronBar.app/Contents/MacOS/CronBar' 2>/dev/null || true

swift build
echo "Launching CronBar (Ctrl+C to quit)..."
exec ./.build/debug/CronBar
