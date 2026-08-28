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
  function open() { refresh.running = true; root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? close() : open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) { return root.bar && root.bar.switchPanelFrom ? root.bar.switchPanelFrom(root.hostWidget || root, direction) : false }
  Process {
    id: refresh
    command: ["window-ward", "list"]
    stdout: StdioCollector { onStreamFinished: root.output = text.trim() || "No protected applications" }
  }
  Process { id: toggleProtection; property bool enable: true; command: ["window-ward", enable ? "enable" : "disable"]; onExited: refresh.running = true }
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
          Rectangle { width: 100; height: 32; radius: 6; color: root.barForeground; Text { anchors.centerIn: parent; text: "Enable"; color: Color.background } MouseArea { anchors.fill: parent; onClicked: { toggleProtection.enable = true; toggleProtection.running = true } } }
          Rectangle { width: 100; height: 32; radius: 6; color: root.barForeground; Text { anchors.centerIn: parent; text: "Disable"; color: Color.background } MouseArea { anchors.fill: parent; onClicked: { toggleProtection.enable = false; toggleProtection.running = true } } }
          Rectangle { width: 100; height: 32; radius: 6; color: root.barForeground; Text { anchors.centerIn: parent; text: "Refresh"; color: Color.background } MouseArea { anchors.fill: parent; onClicked: refresh.running = true } }
        }
        Text { width: parent.width; text: "Add focused apps from a terminal: window-ward add-focused"; color: root.barForeground; opacity: 0.75; wrapMode: Text.WordWrap }
      }
    }
  }
}
