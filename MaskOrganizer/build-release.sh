#!/usr/bin/env bash
# Build, sign, notarize, and staple a release DMG of Mask EX Voice Manager.
#
# Prerequisites (one-time setup):
#   1. Apple Developer ID Application cert installed in keychain.
#   2. App-specific password stored in keychain via:
#        xcrun notarytool store-credentials "MaskEXNotarize" \
#            --apple-id "you@example.com" \
#            --team-id  "NHQ24QB25V" \
#            --password "xxxx-xxxx-xxxx-xxxx"
#   3. ../dmg-background.png exists at the repo root.
#   4. ../dmg-settings.py exists at the repo root.
#
# Output: ../dist/Mask-EX-Voice-Manager-<version>.dmg (signed + notarized + stapled)

set -euo pipefail

# ─── configuration ──────────────────────────────────────────────────
# SHA-1 of the Developer ID Application cert. Two certs share the same
# human-readable name (renewal), so the readable form is ambiguous;
# use the hash to pin the exact cert.
DEVELOPER_ID="E1FB1FB3D9559FA8A38BD65001F87C7E8964E6E1"
TEAM_ID="NHQ24QB25V"
NOTARY_PROFILE="MaskEXNotarize"

APP_DISPLAY_NAME="Mask EX Voice Manager"
APP_FILE_NAME="${APP_DISPLAY_NAME}.app"
EXEC_NAME="MaskOrganizer"      # CFBundleExecutable; binary name inside MacOS/
VERSION="0.1"

cd "$(dirname "$0")"

REPO_ROOT="$(cd .. && pwd)"
DIST_DIR="$REPO_ROOT/dist"
APP_DIR="$DIST_DIR/$APP_FILE_NAME"
DMG_NAME="Mask-EX-Voice-Manager-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# ─── 0. sanity checks ───────────────────────────────────────────────
[ -f "$REPO_ROOT/dmg-background.png" ] \
    || { echo "✗ missing $REPO_ROOT/dmg-background.png"; exit 1; }
[ -f "$REPO_ROOT/dmg-settings.py" ] \
    || { echo "✗ missing $REPO_ROOT/dmg-settings.py"; exit 1; }
security find-identity -v -p codesigning | grep -q "$TEAM_ID" \
    || { echo "✗ Developer ID cert for team $TEAM_ID not found in keychain"; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || { echo "✗ notarytool profile '$NOTARY_PROFILE' not set up. See header comment."; exit 1; }
command -v dmgbuild >/dev/null \
    || { echo "✗ dmgbuild not installed. Run: pip3 install dmgbuild"; exit 1; }

echo "→ release build"
swift build -c release

# ─── 1. assemble the .app ───────────────────────────────────────────
echo "→ assembling $APP_FILE_NAME"
rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp ".build/release/$EXEC_NAME" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "Bundle/Info.plist"        "$APP_DIR/Contents/Info.plist"
cp "Bundle/AppIcon.icns"      "$APP_DIR/Contents/Resources/AppIcon.icns"

# ─── 2. sign the .app (hardened runtime, secure timestamp) ──────────
echo "→ signing .app with Developer ID"
codesign --force --options runtime --timestamp \
    --entitlements Bundle/entitlements.plist \
    --sign "$DEVELOPER_ID" \
    "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

# ─── 3. build the styled DMG ────────────────────────────────────────
echo "→ building DMG"
cd "$REPO_ROOT"
# dmgbuild needs the .app at the location dmg-settings.py expects.
# Our settings file points at dist-dmg/<APP_FILE_NAME>; stage it there.
rm -rf dist-dmg
mkdir -p dist-dmg
cp -R "$APP_DIR" "dist-dmg/$APP_FILE_NAME"

dmgbuild -s dmg-settings.py "$APP_DISPLAY_NAME" "$DMG_PATH"

# ─── 4. sign the DMG ────────────────────────────────────────────────
echo "→ signing DMG"
codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

# ─── 5. notarize (uploads & waits) ──────────────────────────────────
echo "→ submitting to Apple notary service (this takes 2–10 min)"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# ─── 6. staple ─────────────────────────────────────────────────────
echo "→ stapling notarization ticket"
xcrun stapler staple "$APP_DIR"
xcrun stapler staple "$DMG_PATH"

# ─── 7. set the DMG file icon ───────────────────────────────────────
echo "→ setting DMG file icon"
python3 - <<PY
import Cocoa, os
dmg  = "$DMG_PATH"
icns = os.path.join("$REPO_ROOT", "MaskOrganizer", "Bundle", "AppIcon.icns")
img  = Cocoa.NSImage.alloc().initWithContentsOfFile_(icns)
ok = Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(img, dmg, 0)
print("  icon:", "set" if ok else "failed")
PY

# ─── 8. verify final assessment ─────────────────────────────────────
echo "→ verifying with spctl"
spctl --assess --type execute --verbose=2 "$APP_DIR" || true
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" || true

echo
echo "✓ done: $DMG_PATH"
