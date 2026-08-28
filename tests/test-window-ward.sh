#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"
cat >"$tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == activewindow ]]; then printf '%s\n' "${MOCK_WINDOW_JSON}"; else printf '%s\n' "$*" >>"${MOCK_CALLS}"; fi
EOF
cat >"$tmp/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${MOCK_NOTIFICATIONS}"
EOF
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" WINDOW_WARD_CONFIG="$tmp/config.json" MOCK_CALLS="$tmp/calls" MOCK_NOTIFICATIONS="$tmp/notifications"
export MOCK_WINDOW_JSON='{"address":"0xabc","class":"google-chrome","initialClass":"google-chrome"}'
"$root/bin/window-ward" status >/dev/null
"$root/bin/window-ward" close; [[ ! -e $tmp/calls ]]
"$root/bin/window-ward" close; grep -q 'address:0xabc' "$tmp/calls"
: >"$tmp/calls"; export MOCK_WINDOW_JSON='{"address":"0xaaa","class":"chrome-example-pwa","initialClass":"chrome-example-pwa"}'
"$root/bin/window-ward" close; [[ ! -s $tmp/calls ]]
export MOCK_WINDOW_JSON='{"address":"0xaab","class":"chrome-example-pwa","initialClass":"chrome-example-pwa"}'
"$root/bin/window-ward" close; [[ ! -s $tmp/calls ]]
: >"$tmp/calls"; export MOCK_WINDOW_JSON='{"address":"0xdef","class":"Alacritty","initialClass":"Alacritty"}'
"$root/bin/window-ward" close; grep -q 'address:0xdef' "$tmp/calls"
"$root/bin/window-ward" add-focused Terminal; "$root/bin/window-ward" list | grep -q $'alacritty\ttrue\tTerminal'
"$root/bin/window-ward" remove alacritty; ! "$root/bin/window-ward" list | grep -q alacritty
printf 'ok\n'
