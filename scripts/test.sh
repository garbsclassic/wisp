#!/usr/bin/env bash
# Swift Testing ships inside Command Line Tools but isn't on the default search
# path when there's no Xcode.app, so `swift test` alone fails with
# "no such module 'Testing'". These flags point the compiler, the linker, and
# dyld at where CLT actually keeps it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
INTEROP_LIB="$DEVELOPER_DIR/Library/Developer/usr/lib"

if [[ ! -d "$FRAMEWORKS/Testing.framework" ]]; then
    echo "error: Testing.framework not found under $FRAMEWORKS" >&2
    echo "       (xcode-select -p points at $DEVELOPER_DIR)" >&2
    exit 1
fi

exec swift test --package-path "$ROOT_DIR" \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$INTEROP_LIB" \
    "$@"
