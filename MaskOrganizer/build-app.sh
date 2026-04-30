#!/usr/bin/env bash
# Build a clickable MaskOrganizer.app bundle.
#
# SwiftPM produces a bare executable; macOS GUI apps need the .app/Contents/...
# layout to register a Dock icon, get window focus, and persist across launches.
# This script wraps the SwiftPM-built binary into that layout.
#
# Usage:
#   ./build-app.sh           # debug build (default)
#   ./build-app.sh release   # release build
#
# Output: ./MaskOrganizer.app — drag to /Applications or double-click in place.

set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="MaskOrganizer"
APP_DIR="$APP_NAME.app"
INFO_PLIST="Bundle/Info.plist"

cd "$(dirname "$0")"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$APP_NAME"
[ -x "$BIN_PATH" ] || { echo "missing binary at $BIN_PATH"; exit 1; }

echo "→ packaging $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# App icon: copy the .icns into Contents/Resources/ so Info.plist's
# CFBundleIconFile=AppIcon resolves.
if [ -f "Bundle/AppIcon.icns" ]; then
    cp "Bundle/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign so macOS doesn't complain about an unsigned binary.
codesign --force --sign - --deep "$APP_DIR" 2>/dev/null || true

echo "✓ $APP_DIR built"
echo "→ launch with:  open $APP_DIR"
