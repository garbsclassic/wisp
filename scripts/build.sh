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

# CommandLineTools' default SDK (MacOSX.sdk) reimplements @State as a macro whose plugin
# (SwiftUIMacros) ships only with Xcode, so `swift build` fails with "plugin for module
# 'SwiftUIMacros' not found". Pin to the newest SDK that predates that change via $SDKROOT, not
# `-Xswiftc -sdk`, since SwiftPM derives its own `-sdk` for the build plan which takes priority.
SDK_DIR="$(xcode-select -p)/SDKs"
export SDKROOT="${WISP_SDKROOT:-$SDK_DIR/MacOSX26.5.sdk}"
if [[ ! -d "$SDKROOT" ]]; then
    echo "error: SDK not found at $SDKROOT" >&2
    echo "       set WISP_SDKROOT to an SDK under $SDK_DIR that predates the SwiftUIMacros plugin requirement" >&2
    exit 1
fi

swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR"
BINARY="$(swift build -c "$CONFIGURATION" --package-path "$ROOT_DIR" --show-bin-path)/${APP_NAME}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
# The config's JSON Schema. The app copies it into ~/.config/wisp at launch so
# editors validate wisp.jsonc offline; the bundle is the source of truth.
cp "$ROOT_DIR/Resources/wisp.schema.json" "$APP_BUNDLE/Contents/Resources/wisp.schema.json"

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
