#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"; printf '%s\n' '-- existing binding' >"$tmp/bindings.lua"
export WINDOW_WARD_TESTING=1 WINDOW_WARD_BIN_DIR="$tmp/bin" WINDOW_WARD_BINDINGS="$tmp/bindings.lua" WINDOW_WARD_CONFIG="$tmp/config.json" XDG_RUNTIME_DIR="$tmp/runtime"
"$root/scripts/setup"; "$root/scripts/setup"
[[ $(grep -c '^-- BEGIN WINDOW WARD' "$tmp/bindings.lua") == 1 ]]
[[ $(find "$tmp" -maxdepth 1 -name 'bindings.lua.window-ward-backup.*' | wc -l) == 1 ]]
[[ -L $tmp/bin/window-ward ]]
"$root/scripts/uninstall"
if grep -q 'WINDOW WARD' "$tmp/bindings.lua"; then exit 1; fi
[[ ! -e $tmp/bin/window-ward ]]; [[ -e $tmp/config.json ]]

printf 'keep me\n' >"$tmp/bin/window-ward"
rm -f "$tmp/config.json"
if "$root/scripts/setup" 2>/dev/null; then exit 1; fi
grep -qx 'keep me' "$tmp/bin/window-ward"
[[ ! -e $tmp/config.json ]]

WINDOW_WARD_BIN_DIR="$tmp/bad\\path"
if "$root/scripts/setup" >/dev/null 2>&1; then exit 1; fi
WINDOW_WARD_BIN_DIR="$tmp/bin"

rm "$tmp/bin/window-ward"; mkdir -p "$tmp/xdg"
export XDG_CONFIG_HOME="$tmp/xdg" WINDOW_WARD_CONFIG=
unset WINDOW_WARD_CONFIG
"$root/scripts/setup"
[[ -e $tmp/xdg/window-ward/config.json ]]
"$root/scripts/uninstall"

rm -f "$tmp/xdg/window-ward/config.json"; mkdir "$tmp/xdg/window-ward/config.json"
before=$(sha256sum "$tmp/bindings.lua")
if "$root/scripts/setup" >/dev/null 2>&1; then exit 1; fi
[[ ! -e $tmp/bin/window-ward ]]
[[ $(sha256sum "$tmp/bindings.lua") == "$before" ]]
rmdir "$tmp/xdg/window-ward/config.json"

"$root/scripts/setup"
sed -i '/hl.unbind/a -- unexpected user content' "$tmp/bindings.lua"
if "$root/scripts/uninstall" >/dev/null 2>&1; then exit 1; fi
[[ -L $tmp/bin/window-ward ]]
grep -q 'unexpected user content' "$tmp/bindings.lua"
printf 'ok\n'
