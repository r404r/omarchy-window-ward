#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"; printf '%s\n' '-- existing binding' >"$tmp/bindings.lua"
export WINDOW_WARD_BIN_DIR="$tmp/bin" WINDOW_WARD_BINDINGS="$tmp/bindings.lua" WINDOW_WARD_CONFIG="$tmp/config.json" XDG_RUNTIME_DIR="$tmp/runtime"
"$root/scripts/setup"; "$root/scripts/setup"
[[ $(grep -c '^-- BEGIN WINDOW WARD' "$tmp/bindings.lua") == 1 ]]
[[ $(find "$tmp" -maxdepth 1 -name 'bindings.lua.window-ward-backup.*' | wc -l) == 1 ]]
[[ -L $tmp/bin/window-ward ]]
"$root/scripts/uninstall"
! grep -q 'WINDOW WARD' "$tmp/bindings.lua"; [[ ! -e $tmp/bin/window-ward ]]; [[ -e $tmp/config.json ]]
printf 'ok\n'
