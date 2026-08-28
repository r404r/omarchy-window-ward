#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
panel=$root/Panel.qml

grep -Fq 'readonly property color foreground: Color.popups.text' "$panel"
grep -Fq 'command: [root.cliPath, "status"]' "$panel"
grep -Fq 'command: [root.cliPath, "add-focused"]' "$panel"
grep -Fq 'command: [root.cliPath, "set-app-enabled", applicationId, enable ? "true" : "false"]' "$panel"
grep -Fq 'command: [root.cliPath, "remove", applicationId]' "$panel"
grep -Fq 'source: root.applicationIcon(modelData)' "$panel"
grep -Fq 'return Quickshell.iconPath("application-x-executable", true)' "$panel"
grep -Fq 'text: "Protected applications"' "$panel"
grep -Fq 'label: "Window protection"' "$panel"
grep -Fq 'text: "Add focused app"' "$panel"
grep -Fq 'ToggleSwitch {' "$panel"
grep -Fq 'interactive: true' "$panel"
grep -Fq 'onToggled: root.setApplicationEnabled(String(modelData.id), !checked)' "$panel"
grep -Fq 'text: root.pendingRemovalId === String(modelData.id) ? "Confirm" : "Remove"' "$panel"
grep -Fq 'interval: 5000' "$panel"
grep -Fq 'readonly property int globalToggleFocusIndex: 1 + root.applications.length * 2' "$panel"
grep -Fq 'hasCursor: root.focusIndex === 1 + index * 2' "$panel"
grep -Fq 'hasCursor: root.focusIndex === 2 + index * 2' "$panel"
grep -Fq 'required property int index' "$panel"
grep -Fq 'applicationList.positionViewAtIndex(currentIndex, ListView.Contain)' "$panel"
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
