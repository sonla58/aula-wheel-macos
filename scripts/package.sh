#!/usr/bin/env bash
# Packages build/AulaWheel.app (from scripts/build-app.sh) into a zip and a drag-to-Applications DMG,
# named after the app's version: build/AulaWheel-<version>.zip and build/AulaWheel-<version>.dmg.
# The in-app updater looks for the zip by exactly this name on the release tagged v<version>.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/AulaWheel.app"
[[ -d "$APP" ]] || { echo "error: $APP not found; run scripts/build-app.sh first" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"

ZIP="build/AulaWheel-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

DMG="build/AulaWheel-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "AulaWheel $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

echo "Packaged $ZIP and $DMG"
