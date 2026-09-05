#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fixture_xdg=$tmp/xdg
mkdir -p "$fixture_xdg/runtime" "$fixture_xdg/cache" "$fixture_xdg/data" "$fixture_xdg/state"
# Keep Quickshell's test state entirely below this fixture. Do not change HOME:
# the controller receives the fake CLI path explicitly below.
export XDG_RUNTIME_DIR=$fixture_xdg/runtime
export XDG_CACHE_HOME=$fixture_xdg/cache
export XDG_DATA_HOME=$fixture_xdg/data
export XDG_STATE_HOME=$fixture_xdg/state
# This test has no windows. Force Qt's headless platform unless a caller has
# deliberately supplied a different one for diagnostics.
: "${QT_QPA_PLATFORM:=offscreen}"
export QT_QPA_PLATFORM
fake_cli=$tmp/window-ward
log=$tmp/calls
qml=$tmp/qml
mkdir -p "$qml"
cp "$root/WardController.qml" "$root/WardModel.js" "$root/tests/ControllerSmoke.qml" "$qml/"
mv "$qml/ControllerSmoke.qml" "$qml/shell.qml"

cat >"$fake_cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$WINDOW_WARD_TEST_LOG"
case "$1" in
  status)
    count_file=${WINDOW_WARD_TEST_LOG}.count
    count=0; [[ -f $count_file ]] && count=$(<"$count_file")
    count=$((count + 1)); printf '%s' "$count" >"$count_file"
    case "$count" in
      1) printf '%s\n' '{"schemaVersion":1,"enabled":true,"confirmWindowMs":3000,"protectedApplications":[]}' ;;
      2) printf '%s\n' '{"schemaVersion":1,"enabled":false,"confirmWindowMs":3000,"protectedApplications":[]}' ;;
      3) : ;;
      *) trap '' TERM; exec sleep 5 ;;
    esac
    ;;
  disable) : ;;
  *) exit 64 ;;
esac
EOF
chmod 0700 "$fake_cli"

WINDOW_WARD_TEST_CLI=$fake_cli WINDOW_WARD_TEST_LOG=$log \
  qs -c "$qml"

expected=$'status\ndisable\nstatus\nstatus\nstatus'
[[ $(<"$log") == "$expected" ]]
printf 'ok\n'
