#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
panel=$root/Panel.qml

grep -Fq 'readonly property color foreground: Color.popups.text' "$panel"
grep -Fq 'command: [root.cliPath, "status"]' "$panel"
grep -Fq 'command: [root.cliPath, "add-focused"]' "$panel"
grep -Fq 'source: Quickshell.iconPath(modelData.id || "application-x-executable", true)' "$panel"
grep -Fq 'text: "Protected applications"' "$panel"
grep -Fq 'label: "Window protection"' "$panel"
grep -Fq 'text: "Add focused app"' "$panel"
grep -Fq 'ToggleSwitch {' "$panel"
grep -Fq 'Toggle {' "$panel"
grep -Fq 'Button {' "$panel"
grep -Fq 'ListView {' "$panel"
grep -Fq 'QtControls.ScrollBar.vertical: QtControls.ScrollBar {' "$panel"

if grep -Fq 'blocked: root.busy' "$panel"; then
  printf 'Busy work must not block Escape or panel navigation.\n' >&2
  exit 1
fi

if grep -Fq 'root.barForeground' "$panel"; then
  printf 'Panel content must use the popup palette, not the bar palette.\n' >&2
  exit 1
fi

grep -Fq 'text: root.busy ? "Checking…" : "Refresh"' "$panel"

printf 'ok\n'
