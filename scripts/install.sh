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

WAS_RUNNING=0
if [[ -d "$DEST" ]]; then
  if pgrep -f "$DEST/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    WAS_RUNNING=1
    # Quit the running copy first, or the replace lands under a live process.
    osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
    pkill -f "$DEST/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 1
  fi
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
