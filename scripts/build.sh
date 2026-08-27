#!/usr/bin/env bash
# Assembles Wisp.app by hand. SwiftPM only produces a bare executable, so the
# bundle layout, Info.plist and signature are done here instead of by Xcode.
set -euo pipefail

APP_NAME="Wisp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
CONFIGURATION="${WISP_CONFIGURATION:-release}"
# Ad-hoc ("-") by default. Point this at a self-signed code-signing identity
# from Keychain Access to keep a stable code identity across rebuilds — see
# the signing note in README.md.
SIGN_IDENTITY="${WISP_SIGN_IDENTITY:--}"

swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR"
BINARY="$(swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR" --show-bin-path)/${APP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# App icon. Source art lives at Resources/AppIcon.png (1024x1024, pre-shaped
# as a squircle). The compiled .icns is cached in .build/, so a rebuild only
# re-runs sips/iconutil when the source PNG actually changes, not every time
# dist/ gets wiped below. Requires Info.plist to set CFBundleIconFile=AppIcon
# (no extension) — sips/iconutil ship with the OS, no Xcode needed.
ICON_SRC="$ROOT_DIR/Resources/AppIcon.png"
ICON_CACHE="$ROOT_DIR/.build/AppIcon.icns"

if [[ -f "$ICON_SRC" ]]; then
    if [[ ! -f "$ICON_CACHE" || "$ICON_SRC" -nt "$ICON_CACHE" ]]; then
        ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
        mkdir -p "$ICONSET_DIR"
        for size in 16 32 128 256 512; do
            sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
            double=$((size * 2))
            sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
        done
        mkdir -p "$(dirname "$ICON_CACHE")"
        iconutil -c icns "$ICONSET_DIR" -o "$ICON_CACHE"
        rm -rf "$(dirname "$ICONSET_DIR")"
    fi
    cp "$ICON_CACHE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
else
    echo "warning: $ICON_SRC not found, building without an app icon" >&2
fi

codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

# Re-announce the rebuilt bundle so Launch Services and the Login Items list
# pick up the new binary instead of a stale registration.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
