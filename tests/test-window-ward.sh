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
export PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" WINDOW_WARD_TESTING=1 WINDOW_WARD_CONFIG="$tmp/config.json" WINDOW_WARD_STATE="$tmp/state" MOCK_CALLS="$tmp/calls" MOCK_NOTIFICATIONS="$tmp/notifications"
export MOCK_WINDOW_JSON='{"address":"0xabc","class":"google-chrome","initialClass":"google-chrome"}'
"$root/bin/window-ward" status >/dev/null
[[ $("$root/bin/window-ward" status | wc -c) -le 65536 ]]
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
  '{"schemaVersion":1,"enabled":true,"confirmWindowMs":3000,"protectedApplications":[{"id":"spaces","name":"Spaces","enabled":true,"mode":"double-press","match":{"class":["   "]}}]}' \
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

# Files, locks, state and command output are all bounded and never followed through symlinks.
victim="$tmp/victim"; printf 'do not change\n' >"$victim"
rm -f "$tmp/config.json"; ln -s "$victim" "$tmp/config.json"
if "$root/bin/window-ward" status >/dev/null 2>&1; then exit 1; fi
grep -qx 'do not change' "$victim"
rm "$tmp/config.json"; "$root/bin/window-ward" status >/dev/null
rm -f "$tmp/config.json.lock"; ln -s "$victim" "$tmp/config.json.lock"
if "$root/bin/window-ward" status >/dev/null 2>&1; then exit 1; fi
grep -qx 'do not change' "$victim"
rm "$tmp/config.json.lock"

mkdir "$tmp/real-parent"; ln -s "$tmp/real-parent" "$tmp/linked-parent"
WINDOW_WARD_CONFIG="$tmp/linked-parent/config.json" "$root/bin/window-ward" status >/dev/null 2>&1 && exit 1
rm "$tmp/linked-parent"; rmdir "$tmp/real-parent"

printf '%*s' 65537 '' >"$tmp/config.json"
if "$root/bin/window-ward" status >/dev/null 2>&1; then exit 1; fi
rm "$tmp/config.json"; "$root/bin/window-ward" status >/dev/null
printf '%*s' 257 '' >"$tmp/state"
if "$root/bin/window-ward" close >/dev/null 2>&1; then exit 1; fi
rm "$tmp/state"; ln -s "$victim" "$tmp/state"
if "$root/bin/window-ward" close >/dev/null 2>&1; then exit 1; fi
grep -qx 'do not change' "$victim"
rm "$tmp/state"

mkdir "$tmp/real-runtime"; ln -s "$tmp/real-runtime" "$tmp/linked-runtime"
WINDOW_WARD_STATE="$tmp/linked-runtime/state" "$root/bin/window-ward" close >/dev/null 2>&1 && exit 1
rm "$tmp/linked-runtime"; rmdir "$tmp/real-runtime"

cat >"$tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == activewindow ]]; then head -c 32769 /dev/zero; else printf '%s\n' "$*" >>"${MOCK_CALLS}"; fi
EOF
chmod +x "$tmp/bin/hyprctl"
if "$root/bin/window-ward" add-focused TooMuch >/dev/null 2>&1; then exit 1; fi

cat >"$tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == activewindow ]]; then
  sleep 30 & echo $! >"${MOCK_CHILD_PID}"
  head -c 32769 /dev/zero
else
  printf '%s\n' "$*" >>"${MOCK_CALLS}"
fi
EOF
chmod +x "$tmp/bin/hyprctl"
export MOCK_CHILD_PID="$tmp/child-pid"
if "$root/bin/window-ward" add-focused TooMuch >/dev/null 2>&1; then exit 1; fi
child_pid=$(cat "$tmp/child-pid")
for _ in {1..20}; do kill -0 "$child_pid" 2>/dev/null || break; sleep 0.05; done
if kill -0 "$child_pid" 2>/dev/null; then exit 1; fi

# A failed notification must also kill descendants in its dedicated process group.
cat >"$tmp/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
if [[ $1 == activewindow ]]; then printf '%s\n' "${MOCK_WINDOW_JSON}"; else printf '%s\n' "$*" >>"${MOCK_CALLS}"; fi
EOF
cat >"$tmp/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
sleep 30 & echo $! >"${MOCK_NOTIFY_CHILD}"
exit 1
EOF
chmod +x "$tmp/bin/hyprctl" "$tmp/bin/omarchy"
export MOCK_WINDOW_JSON='{"address":"0xddd","class":"google-chrome","initialClass":"google-chrome"}' MOCK_NOTIFY_CHILD="$tmp/notify-child"
rm -f "$tmp/state"
"$root/bin/window-ward" close
notify_child=$(cat "$tmp/notify-child")
for _ in {1..20}; do kill -0 "$notify_child" 2>/dev/null || break; sleep 0.05; done
if kill -0 "$notify_child" 2>/dev/null; then exit 1; fi

# The public CLI does not honour test-only executable and path overrides.
WINDOW_WARD_TESTING=0 WINDOW_WARD_CONFIG="$victim" "$root/bin/window-ward" help >/dev/null
printf 'ok\n'
