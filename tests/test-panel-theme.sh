#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
panel=$root/Panel.qml

grep -Fq 'readonly property color popupForeground: Color.popups.text' "$panel"
grep -Fq 'readonly property color popupBackground: Color.popups.background' "$panel"

if grep -Fq 'root.barForeground' "$panel"; then
  printf 'Panel content must use the popup palette, not the bar palette.\n' >&2
  exit 1
fi

for label in 'Google Chrome' 'Enable' 'Disable' 'Refresh'; do
  if [[ $label == 'Google Chrome' ]]; then
    grep -Fq 'command: [root.cliPath, "list"]' "$panel"
  else
    grep -Fq "text: \"$label\"" "$panel"
  fi
done

printf 'ok\n'
