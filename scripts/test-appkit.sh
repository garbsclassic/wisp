#!/usr/bin/env bash
# Exercises the production frame controller across separate processes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/wisp-frame-check-XXXXXXXX)"
TEST_UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
export WISP_FRAME_TEST_ROOT="$TEST_ROOT"
export WISP_FRAME_TEST_BUNDLE_ID="dev.garbs.wisp.frame-check.$TEST_UUID"
export XDG_CONFIG_HOME="$TEST_ROOT/xdg"

cleanup() {
    defaults delete "$WISP_FRAME_TEST_BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

DEVELOPER_DIR="$(xcode-select -p)"
SDK_DIR="$DEVELOPER_DIR/SDKs"
if [[ -n "${WISP_SDKROOT:-}" ]]; then
    TEST_SDK="$WISP_SDKROOT"
else
    TEST_SDK="$(find "$SDK_DIR" -maxdepth 1 -name 'MacOSX[0-9]*.sdk' -exec basename {} \; \
        | sort -V | awk -F'[X.]' '$2 < 27' | tail -n 1)"
    [[ -n "$TEST_SDK" ]] && TEST_SDK="$SDK_DIR/$TEST_SDK"
fi
if [[ -z "$TEST_SDK" || ! -d "$TEST_SDK" ]]; then
    echo "error: set WISP_SDKROOT to an installed macOS SDK" >&2
    exit 1
fi

TEST_TARGET="$(uname -m)-apple-macosx13.0"
TEST_APP="$TEST_ROOT/FramePersistenceCheck.app"
TEST_BINARY="$TEST_APP/Contents/MacOS/FramePersistenceCheck"
mkdir -p "$TEST_APP/Contents/MacOS" "$XDG_CONFIG_HOME"
cat > "$TEST_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$WISP_FRAME_TEST_BUNDLE_ID</string>
<key>CFBundleExecutable</key><string>FramePersistenceCheck</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

xcrun swiftc -sdk "$TEST_SDK" -target "$TEST_TARGET" -swift-version 6 \
    -parse-as-library -emit-module -emit-library -static -module-name WispCore \
    "$ROOT_DIR"/Sources/WispCore/*.swift \
    -o "$TEST_ROOT/libWispCore.a" -emit-module-path "$TEST_ROOT/WispCore.swiftmodule"
xcrun swiftc -sdk "$TEST_SDK" -target "$TEST_TARGET" -swift-version 6 \
    -parse-as-library -I "$TEST_ROOT" -L "$TEST_ROOT" -lWispCore \
    "$ROOT_DIR/Sources/Wisp/PanelFrameController.swift" \
    "$ROOT_DIR/Tests/AppKit/FramePersistenceCheck.swift" -o "$TEST_BINARY"

echo "Requires a logged-in session with a display arranged above the primary display."
"$TEST_BINARY" save
"$TEST_BINARY" restore
