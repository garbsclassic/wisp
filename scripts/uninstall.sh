#!/usr/bin/env bash
# Removes Wisp. Keeps config and window preferences unless --purge is passed.
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
        echo "usage: uninstall.sh [--purge]" \
            "(--purge also removes $CONFIG_DIR and window preferences)" >&2
        exit 2
        ;;
    esac
done

is_running() {
    local query_status=0
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || query_status=$?
    if [[ "$query_status" -gt 1 ]]; then
        echo "error: couldn't check whether $APP_NAME is running; uninstall stopped" >&2
        exit 1
    fi
    return "$query_status"
}

if [[ -d "$DEST" ]]; then
    # Quit first: the unregister call below runs the same binary, and two live
    # copies of an accessory app fighting over one status item is avoidable.
    if is_running; then
        osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
        sleep 1
        if is_running; then
            echo "error: $APP_NAME did not quit; preserve unsaved text before uninstalling" >&2
            exit 1
        fi
    fi

    # Withdraw the login item while the bundle still exists. SMAppService keys
    # the registration to the bundle, so deleting the app first would strand it.
    if ! "$DEST/Contents/MacOS/$APP_NAME" --unregister-login-item; then
        echo "error: couldn't remove Launch at Login; uninstall stopped" >&2
        exit 1
    fi
fi

if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
    echo "Removed $DEST"
else
    echo "No app at $DEST"
fi

if [[ "$PURGE" == "1" ]]; then
    defaults delete dev.garbs.wisp >/dev/null 2>&1 || true
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        echo "Removed $CONFIG_DIR"
    fi
else
    echo "Kept $CONFIG_DIR and window preferences (pass --purge to remove them)"
fi
