#!/usr/bin/env bash
# Builds build/AulaWheel.app. Pass --install to copy it to ~/Applications and relaunch it.
# Set ARCHS (e.g. "arm64 x86_64") for a universal binary; the default is this Mac's architecture.
#
# macOS ties Accessibility / Input Monitoring grants to the code signature, so the app is signed
# with a stable identity: SIGN_IDENTITY, else the release certificate pinned in scripts/release-cert.sha1
# (if it is in your keychain), else the first "Apple Development" certificate.
# Ad-hoc signing works but the permissions must be granted again after every build.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
for arch in ${ARCHS:-}; do ARCH_FLAGS+=(--arch "$arch"); done

swift build -c release --product AulaWheel ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/AulaWheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/AulaWheel" "$APP/Contents/MacOS/AulaWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

RELEASE_IDENTITY="$(tr -d '[:space:]' 2>/dev/null < scripts/release-cert.sha1 || true)"
# Self-signed, so it is only listed without -v.
if [[ -z "$RELEASE_IDENTITY" || "$(security find-identity -p codesigning)" != *"$RELEASE_IDENTITY"* ]]; then
    RELEASE_IDENTITY=""
fi
DEV_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
IDENTITY="${SIGN_IDENTITY:-${RELEASE_IDENTITY:-$DEV_IDENTITY}}"
if [[ -z "$IDENTITY" ]]; then
    echo "warning: no signing identity found; ad-hoc signing (permissions must be granted again after every build)" >&2
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
