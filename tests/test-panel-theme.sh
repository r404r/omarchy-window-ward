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
grep -Fq 'readonly property int maxStatusOutputChars: 131072' "$panel"
grep -Fq 'readonly property int maxApplications: 128' "$panel"
grep -Fq 'readonly property int maxMatchersPerApplication: 32' "$panel"
grep -Fq 'readonly property int maxApplicationIdChars: 128' "$panel"
grep -Fq 'readonly property int maxApplicationNameChars: 256' "$panel"
grep -Fq 'readonly property int maxMatcherChars: 256' "$panel"
grep -Fq 'function appendStatusOutput(chunk)' "$panel"
grep -Fq 'if (remaining <= 0 || value.length > remaining)' "$panel"
grep -Fq 'function sanitizedApplications(values)' "$panel"
grep -Fq 'property bool statusFinishing: false' "$panel"
grep -Fq 'if (!statusProcess.running && !root.statusFinishing)' "$panel"
grep -Fq 'if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(candidate)) continue' "$panel"
plain_text_fields=$(grep -Fc 'textFormat: Text.PlainText' "$panel")
if (( plain_text_fields < 3 )); then
  printf 'Application names, matcher details, and errors must use plain-text rendering.\n' >&2
  exit 1
fi

split_parsers=$(grep -Fc 'SplitParser {' "$panel")
if (( split_parsers < 6 )); then
  printf 'Every child-process stream must use bounded SplitParser handling.\n' >&2
  exit 1
fi

split_markers=$(grep -Fc 'splitMarker: ""' "$panel")
if (( split_markers < 6 )); then
  printf 'SplitParser must stream raw chunks rather than buffer an unterminated line.\n' >&2
  exit 1
fi

if grep -Fq 'StdioCollector' "$panel"; then
  printf 'Panel must not retain complete child-process streams.\n' >&2
  exit 1
fi

if grep -Eq '(Stderr|stderr)\.text' "$panel"; then
  printf 'Panel must not render child-process diagnostics.\n' >&2
  exit 1
fi

# A config may omit an optional matcher field. The CLI normalizes it before
# status serialization, so model a near-64 KiB valid input and ensure the QML
# cap still accepts the larger normalized output.
python3 - <<'PY'
import json

limit = 64 * 1024
apps = [
    {
        "id": f"app-{index}",
        "name": "n",
        "enabled": True,
        "mode": "double-press",
        "match": {"class": ["class"]},
    }
    for index in range(128)
]
config = {"schemaVersion": 1, "enabled": True, "confirmWindowMs": 3000, "protectedApplications": apps}

def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode() + b"\n"

# Fill legal names first, then legal class patterns, stopping at the on-disk
# config limit. Deliberately leave initialClass absent for normalization.
for app in apps:
    candidate = "n" * 256
    old = app["name"]
    app["name"] = candidate
    if len(encoded(config)) > limit:
        app["name"] = old
        break
for app in apps:
    while len(app["match"]["class"]) < 32:
        app["match"]["class"].append("c" * 256)
        if len(encoded(config)) > limit:
            app["match"]["class"].pop()
            break

raw = encoded(config)
assert len(raw) <= limit and len(raw) > 60000, len(raw)
normalized = json.loads(raw)
for app in normalized["protectedApplications"]:
    app["match"].setdefault("initialClass", [])
status = encoded(normalized)
assert len(status) <= 131072, len(status)
PY

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
