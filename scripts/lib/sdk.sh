#!/usr/bin/env bash
# Select the newest installed SDK compatible with Wisp's deployment target and CLT SwiftUI.
set -euo pipefail

sdk_dir="$(xcode-select -p)/SDKs"
if [[ ! -d "$sdk_dir" ]]; then
    echo "error: SDK directory not found: $sdk_dir" >&2
    exit 1
fi
sdk="$(find "$sdk_dir" -maxdepth 1 \( -type d -o -type l \) -name 'MacOSX[0-9]*.sdk' -exec basename {} \; \
    | awk '/^MacOSX[0-9]+(\.[0-9]+)*\.sdk$/ { split($0, parts, /[X.]/); if (parts[2] >= 15 && parts[2] < 27) print }' \
    | sort -V | tail -n 1)"
if [[ -z "$sdk" || ! -d "$sdk_dir/$sdk" ]]; then
    echo "error: no macOS SDK from 15 through 26 found under $sdk_dir" >&2
    exit 1
fi
printf '%s\n' "$sdk_dir/$sdk"
