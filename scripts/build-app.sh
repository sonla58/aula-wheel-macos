#!/usr/bin/env bash
# Builds build/AulaWheel.app. Pass --install to copy it to ~/Applications and relaunch it.
#
# macOS ties Accessibility / Input Monitoring grants to the code signature, so the app is signed
# with a stable identity (SIGN_IDENTITY, else the first "Apple Development" certificate).
# Ad-hoc signing works but the permissions must be granted again after every build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product AulaWheel
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/AulaWheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/AulaWheel" "$APP/Contents/MacOS/AulaWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [[ -z "$IDENTITY" ]]; then
    echo "warning: no Apple Development identity found; ad-hoc signing" >&2
    IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x AulaWheel && sleep 1 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/AulaWheel.app"
    cp -R "$APP" "$HOME/Applications/"
    open "$HOME/Applications/AulaWheel.app"
    echo "Installed and launched ~/Applications/AulaWheel.app"
fi
