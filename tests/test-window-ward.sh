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
"$root/bin/window-ward" set-app-enabled alacritty false
"$root/bin/window-ward" list | grep -q $'alacritty\tfalse\tTerminal'
: >"$tmp/calls"
"$root/bin/window-ward" close
grep -q 'address:0xdef' "$tmp/calls"
"$root/bin/window-ward" set-app-enabled alacritty true
"$root/bin/window-ward" list | grep -q $'alacritty\ttrue\tTerminal'
: >"$tmp/calls"
"$root/bin/window-ward" close
[[ ! -s $tmp/calls ]]
if "$root/bin/window-ward" set-app-enabled missing-app false >/dev/null 2>&1; then exit 1; fi
if "$root/bin/window-ward" set-app-enabled alacritty invalid >/dev/null 2>&1; then exit 1; fi
"$root/bin/window-ward" remove alacritty
if "$root/bin/window-ward" list | grep -q alacritty; then exit 1; fi
if "$root/bin/window-ward" remove alacritty >/dev/null 2>&1; then exit 1; fi

for invalid in \
  '{"schemaVersion":1,"enabled":true,"confirmWindowMs":-1,"protectedApplications":[]}' \
  '{"schemaVersion":1,"enabled":true,"confirmWindowMs":3000,"protectedApplications":[{}]}' \
  '{"schemaVersion":1,"enabled":true,"confirmWindowMs":3000,"protectedApplications":[{"id":"duplicate","name":"One","enabled":true,"mode":"double-press","match":{"class":["one"]}},{"id":"duplicate","name":"Two","enabled":true,"mode":"double-press","match":{"class":["two"]}}]}'; do
  printf '%s\n' "$invalid" >"$tmp/config.json"
  if "$root/bin/window-ward" status >/dev/null 2>&1; then exit 1; fi
done

rm -f "$tmp/config.json"
MOCK_WINDOW_JSON='{"address":"0x111","class":"Alpha App","initialClass":"Alpha App"}' "$root/bin/window-ward" add-focused Alpha &
pid_a=$!
MOCK_WINDOW_JSON='{"address":"0x222","class":"Beta App","initialClass":"Beta App"}' "$root/bin/window-ward" add-focused Beta &
pid_b=$!
wait "$pid_a" "$pid_b"
"$root/bin/window-ward" list | grep -q $'alpha-app\ttrue\tAlpha'
"$root/bin/window-ward" list | grep -q $'beta-app\ttrue\tBeta'
printf 'ok\n'
