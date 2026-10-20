#!/usr/bin/env bash
# Exercises uninstall safety using disposable files and mocked macOS commands.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
export WISP_INSTALL_DIR="$FIXTURE/apps"
export XDG_CONFIG_HOME="$FIXTURE/config"
export TEST_LOG="$FIXTURE/commands.log"
export TEST_RUNNING="$FIXTURE/running"
mkdir -p "$FIXTURE/bin"

cat > "$FIXTURE/bin/pgrep" <<'MOCK'
#!/usr/bin/env bash
echo "pgrep $*" >> "$TEST_LOG"
exit "$(cat "$TEST_RUNNING")"
MOCK
cat > "$FIXTURE/bin/osascript" <<'MOCK'
#!/usr/bin/env bash
echo osascript >> "$TEST_LOG"
echo "$TEST_AFTER_QUIT" > "$TEST_RUNNING"
MOCK
cat > "$FIXTURE/bin/pkill" <<'MOCK'
#!/usr/bin/env bash
echo pkill >> "$TEST_LOG"
exit 1
MOCK
cat > "$FIXTURE/bin/defaults" <<'MOCK'
#!/usr/bin/env bash
echo defaults >> "$TEST_LOG"
MOCK
cat > "$FIXTURE/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$FIXTURE/bin/"*
export PATH="$FIXTURE/bin:$PATH"

prepare() {
    mkdir -p "$WISP_INSTALL_DIR/Wisp.app/Contents/MacOS" "$XDG_CONFIG_HOME/wisp"
    echo keep > "$XDG_CONFIG_HOME/wisp/config.json"
    : > "$TEST_LOG"
    cat > "$WISP_INSTALL_DIR/Wisp.app/Contents/MacOS/Wisp" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == --unregister-login-item ]] || exit 99
echo unregister >> "$TEST_LOG"
exit "$TEST_UNREGISTER_STATUS"
MOCK
    chmod +x "$WISP_INSTALL_DIR/Wisp.app/Contents/MacOS/Wisp"
    export TEST_UNREGISTER_STATUS=0 TEST_AFTER_QUIT=1
}

expect_aborted() {
    if bash "$ROOT_DIR/scripts/uninstall.sh" --purge > "$FIXTURE/output" 2>&1; then
        echo "error: uninstall unexpectedly succeeded" >&2
        exit 1
    fi
    [[ -d "$WISP_INSTALL_DIR/Wisp.app" ]]
    [[ "$(cat "$XDG_CONFIG_HOME/wisp/config.json")" == keep ]]
    if grep -Eq '^(pkill|defaults)$' "$TEST_LOG"; then
        echo "error: uninstall killed the app or deleted preferences" >&2
        exit 1
    fi
}

prepare
echo 0 > "$TEST_RUNNING"
export TEST_AFTER_QUIT=0
expect_aborted
! grep -Eq '^unregister$' "$TEST_LOG"

prepare
echo 2 > "$TEST_RUNNING"
expect_aborted
! grep -Eq '^(osascript|unregister)$' "$TEST_LOG"

prepare
echo 0 > "$TEST_RUNNING"
export TEST_AFTER_QUIT=2
expect_aborted
! grep -Eq '^unregister$' "$TEST_LOG"

prepare
echo 1 > "$TEST_RUNNING"
export TEST_UNREGISTER_STATUS=1
expect_aborted

prepare
echo 0 > "$TEST_RUNNING"
bash "$ROOT_DIR/scripts/uninstall.sh" > "$FIXTURE/output" 2>&1
[[ ! -e "$WISP_INSTALL_DIR/Wisp.app" ]]
[[ -f "$XDG_CONFIG_HOME/wisp/config.json" ]]
! grep -Eq '^(pkill|defaults)$' "$TEST_LOG"
grep -Eq '^unregister$' "$TEST_LOG"
echo "Uninstall safety checks passed."
