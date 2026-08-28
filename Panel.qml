import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.r404r.window-ward"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property string output: "Loading…"
  readonly property string cliPath: Quickshell.env("HOME") + "/.local/bin/window-ward"
  readonly property bool busy: refresh.running || toggleProtection.running
  function open() { refresh.running = true; root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) { return root.bar && root.bar.switchPanelFrom ? root.bar.switchPanelFrom(root.hostWidget || root, direction) : false }
  Process {
    id: refresh
    command: [root.cliPath, "list"]
    stdout: StdioCollector { id: refreshStdout; waitForEnd: true }
    stderr: StdioCollector { id: refreshStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.output = refreshStdout.text.trim() || "No protected applications"
      else root.output = "Window Ward is unavailable. Run setup or doctor.\n" + refreshStderr.text.trim().slice(0, 240)
    }
  }
  Process {
    id: toggleProtection
    property bool enable: true
    command: [root.cliPath, enable ? "enable" : "disable"]
    stderr: StdioCollector { id: toggleStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) refresh.running = true
      else root.output = "Could not change protection.\n" + toggleStderr.text.trim().slice(0, 240)
    }
  }
  KeyboardPanel {
    id: panel; anchorItem: root.anchorItem; owner: root.hostWidget || root; bar: root.bar; open: root.opened
    focusTarget: keyCatcher; contentWidth: panel.fittedContentWidth(Style.space(360)); contentHeight: panel.fittedContentHeight(content.implicitHeight)
    PanelKeyCatcher {
      id: keyCatcher; anchors.fill: parent; onCloseRequested: root.close(); onTabRequested: function(direction) { root.switchPanel(direction) }
      Column {
        id: content; width: parent.width; spacing: Style.space(10)
        Text { text: "Window Ward"; color: root.barForeground; font.bold: true; font.pixelSize: Style.font.subtitle }
        Text { width: parent.width; text: root.output; color: root.barForeground; wrapMode: Text.WrapAnywhere; font.family: "monospace" }
        Row {
          spacing: Style.space(8)
          Rectangle { width: 100; height: 32; radius: 6; opacity: root.busy ? 0.5 : 1; color: root.barForeground; Text { anchors.centerIn: parent; text: "Enable"; color: Color.background } MouseArea { anchors.fill: parent; enabled: !root.busy; onClicked: { toggleProtection.enable = true; toggleProtection.running = true } } }
          Rectangle { width: 100; height: 32; radius: 6; opacity: root.busy ? 0.5 : 1; color: root.barForeground; Text { anchors.centerIn: parent; text: "Disable"; color: Color.background } MouseArea { anchors.fill: parent; enabled: !root.busy; onClicked: { toggleProtection.enable = false; toggleProtection.running = true } } }
          Rectangle { width: 100; height: 32; radius: 6; opacity: root.busy ? 0.5 : 1; color: root.barForeground; Text { anchors.centerIn: parent; text: "Refresh"; color: Color.background } MouseArea { anchors.fill: parent; enabled: !root.busy; onClicked: refresh.running = true } }
        }
        Text { width: parent.width; text: "Add focused apps from a terminal: window-ward add-focused"; color: root.barForeground; opacity: 0.75; wrapMode: Text.WordWrap }
      }
    }
  }
}
