#!/usr/bin/env bash
# Removes Wisp. Keeps your config unless --purge is passed.
set -euo pipefail

APP_NAME="Wisp"
DEST_DIR="${WISP_INSTALL_DIR:-/Applications}"
DEST="$DEST_DIR/${APP_NAME}.app"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wisp"
PURGE=0

for arg in "$@"; do
    case "$arg" in
    --purge) PURGE=1 ;;
    *)
        echo "usage: uninstall.sh [--purge]   (--purge also removes $CONFIG_DIR)" >&2
        exit 2
        ;;
    esac
done

if [[ -d "$DEST" ]]; then
    # Quit first: the unregister call below runs the same binary, and two live
    # copies of an accessory app fighting over one status item is avoidable.
    if pgrep -f "$DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
        pkill -f "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true
        sleep 1
    fi

    # Withdraw the login item while the bundle still exists. SMAppService keys
    # the registration to the bundle, so deleting the app first would strand it.
    "$DEST/Contents/MacOS/$APP_NAME" --unregister-login-item || true
fi

if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
    echo "Removed $DEST"
else
    echo "No app at $DEST"
fi

if [[ "$PURGE" == "1" ]]; then
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        echo "Removed $CONFIG_DIR"
    fi
else
    echo "Kept $CONFIG_DIR (pass --purge to remove it)"
fi
