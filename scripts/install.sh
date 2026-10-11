#!/usr/bin/env bash
# Builds Wisp and installs it to /Applications.
#
# Installing to a stable path matters for Launch at Login: the login item is
# recorded against the bundle's location, so running from dist/ means moving or
# rebuilding the tree can orphan it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Wisp"
DEST_DIR="${WISP_INSTALL_DIR:-/Applications}"
DEST="$DEST_DIR/${APP_NAME}.app"

"$ROOT_DIR/scripts/build.sh"

is_running() {
  local query_status=0
  pgrep -x "$APP_NAME" >/dev/null 2>&1 || query_status=$?
  if [[ "$query_status" -gt 1 ]]; then
    echo "error: couldn't check whether $APP_NAME is running; installation stopped" >&2
    exit 1
  fi
  return "$query_status"
}

# Quit every running copy, wherever it was launched from — one started out of
# dist/ keeps its old executable mapped and would carry on running the
# pre-rebuild code — and relaunch from the install location afterwards.
WAS_RUNNING=0
if is_running; then
  WAS_RUNNING=1
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  sleep 1
  if is_running; then
    echo "error: $APP_NAME did not quit; preserve unsaved text before installing" >&2
    exit 1
  fi
fi

if [[ -d "$DEST" ]]; then
  echo "Replacing existing $DEST"
  rm -rf "$DEST"
fi

cp -R "$ROOT_DIR/dist/${APP_NAME}.app" "$DEST"

/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
  -f "$DEST"

echo "Installed $DEST"

if [[ "$WAS_RUNNING" == "1" ]]; then
  open "$DEST"
  echo "Restarted $APP_NAME."
else
  echo
  echo "Next:"
  echo "  open \"$DEST\""
fi
