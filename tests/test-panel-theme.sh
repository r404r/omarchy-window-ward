#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
panel=$root/Panel.qml
controller=$root/WardController.qml
model=$root/WardModel.js

grep -Fq 'readonly property color foreground: Color.popups.text' "$panel"
grep -Fq 'WardController { id: wardController }' "$panel"
grep -Fq 'readonly property bool mutationsAllowed: ward.ready && !ward.busy' "$panel"
grep -Fq 'root.controller.show()' "$panel"
grep -Fq 'root.controller.hide()' "$panel"
if grep -Fq 'property var controller:' "$panel"; then
  printf 'Panel must reserve the inherited controller for its show/hide lifecycle.\n' >&2
  exit 1
fi
grep -Fq 'function refresh() {' "$controller"
grep -Fq 'if (root.busy) {' "$controller"
grep -Fq 'root.refreshPending = true' "$controller"
grep -Fq 'function mutate(command) {' "$controller"
grep -Fq 'root.revision += 1' "$controller"
grep -Fq 'requestRevision !== root.revision' "$controller"
grep -Fq 'root.startStatus()' "$controller"
grep -Fq 'operation.signal(15)' "$controller"
grep -Fq 'operation.signal(9)' "$controller"
grep -Fq 'property int operationDeadlineMs: 8000' "$controller"
grep -Fq 'function parseStatus(raw)' "$model"
grep -Fq 'if (typeof raw !== "string" || !raw.trim()) return null' "$model"
grep -Fq 'state.schemaVersion !== 1' "$model"
grep -Fq 'source: root.applicationIcon(modelData)' "$panel"
grep -Fq 'return Quickshell.iconPath("application-x-executable", true)' "$panel"
grep -Fq 'text: ward.ready ? "Protected applications" : "Last known rules (read-only)"' "$panel"
grep -Fq 'text: !ward.ready ? (ward.state === "loading" ? "Checking" : "Unknown")' "$panel"
grep -Fq 'color: ward.ready && root.protectionEnabled' "$panel"
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
grep -Fq 'readonly property int maxStatusOutputChars: 131072' "$controller"
grep -Fq 'function appendStatusOutput(chunk)' "$controller"
grep -Fq 'if (remaining <= 0 || value.length > remaining)' "$controller"
grep -Fq 'if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(candidate)) continue' "$panel"
plain_text_fields=$(grep -Fc 'textFormat: Text.PlainText' "$panel")
if (( plain_text_fields < 3 )); then
  printf 'Application names, matcher details, and errors must use plain-text rendering.\n' >&2
  exit 1
fi

split_parsers=$(grep -Fc 'SplitParser {' "$controller")
if (( split_parsers != 2 )); then
  printf 'The controller must own one bounded child process with stdout and stderr parsers.\n' >&2
  exit 1
fi

split_markers=$(grep -Fc 'splitMarker: ""' "$controller")
if (( split_markers != 2 )); then
  printf 'SplitParser must stream raw chunks rather than buffer an unterminated line.\n' >&2
  exit 1
fi

if grep -Fq 'StdioCollector' "$controller"; then
  printf 'Panel must not retain complete child-process streams.\n' >&2
  exit 1
fi

if grep -Eq '(Stderr|stderr)\.text' "$controller"; then
  printf 'Panel must not render child-process diagnostics.\n' >&2
  exit 1
fi

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
