import QtQuick
import QtQuick.Controls as QtControls
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
  property var applications: []
  property bool protectionEnabled: false
  property int focusIndex: 0
  property string errorText: ""

  readonly property string cliPath: Quickshell.env("HOME") + "/.local/bin/window-ward"
  readonly property bool busy: statusProcess.running || toggleProcess.running || addProcess.running
  readonly property color foreground: Color.popups.text
  readonly property color mutedForeground: Qt.darker(foreground, 1.45)
  readonly property color accent: Color.accent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
    root.focusIndex = 0
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }
  function closeForPopoutSwitch() { root.close() }
  function switchPanel(direction) {
    return root.bar && root.bar.switchPanelFrom
      ? root.bar.switchPanelFrom(root.hostWidget || root, direction)
      : false
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function setProtection(enabled) {
    if (root.busy) return
    root.errorText = ""
    toggleProcess.enable = enabled
    toggleProcess.running = true
  }

  function moveFocus(delta) {
    root.focusIndex = (root.focusIndex + (delta > 0 ? 1 : -1) + 3) % 3
  }

  function activateFocused() {
    if (root.focusIndex === 0) root.refresh()
    else if (root.focusIndex === 1) root.setProtection(!root.protectionEnabled)
    else root.addFocusedApplication()
  }

  function addFocusedApplication() {
    if (root.busy) return
    root.errorText = ""
    addProcess.running = true
  }

  function matchingClasses(application) {
    if (!application || !application.match || !(application.match.class instanceof Array)) return []
    return application.match.class
  }

  Process {
    id: statusProcess
    command: [root.cliPath, "status"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var state = JSON.parse(text || "{}")
          root.protectionEnabled = state.enabled === true
          root.applications = state.protectedApplications instanceof Array ? state.protectedApplications : []
          root.errorText = ""
        } catch (error) {
          root.errorText = "Could not read Window Ward status."
        }
      }
    }

    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.errorText = statusStderr.text.trim() || "Window Ward is unavailable. Run setup or doctor."
    }
  }

  Process {
    id: toggleProcess
    property bool enable: true
    command: [root.cliPath, enable ? "enable" : "disable"]

    stderr: StdioCollector {
      id: toggleStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh()
      else root.errorText = toggleStderr.text.trim() || "Could not change protection."
    }
  }

  Process {
    id: addProcess
    command: [root.cliPath, "add-focused"]

    stderr: StdioCollector {
      id: addStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh()
      else root.errorText = addStderr.text.trim() || "Could not add the focused application."
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveFocus(dy) }
      onActivateRequested: root.activateFocused()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(10)

          Image {
            width: Style.space(30)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            source: Quickshell.iconPath("security-high-symbolic", true)
            fillMode: Image.PreserveAspectFit
            smooth: true
          }

          Column {
            width: parent.width - refreshButton.width - parent.spacing * 2 - Style.space(30)
            spacing: Style.space(2)

            Row {
              spacing: Style.space(8)

              Text {
                text: "Window Ward"
                color: root.foreground
                font.family: root.fontFamily
                font.bold: true
                font.pixelSize: Style.font.title
              }

              Rectangle {
                width: statusLabel.implicitWidth + Style.space(14)
                height: Style.space(22)
                radius: Style.cornerRadius
                color: root.protectionEnabled
                  ? Util.alpha(root.accent, 0.18)
                  : Util.alpha(root.foreground, 0.08)

                Text {
                  id: statusLabel
                  anchors.centerIn: parent
                  text: root.protectionEnabled ? "Enabled" : "Paused"
                  color: root.protectionEnabled ? root.accent : root.mutedForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Text {
              text: root.protectionEnabled
                ? "Double-press close protection"
                : "Close protection is paused"
              width: parent.width
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Button {
            id: refreshButton
            width: Style.space(86)
            text: root.busy ? "Checking…" : "Refresh"
            tooltipText: "Refresh rules (R)"
            bordered: false
            focusable: true
            hasCursor: root.focusIndex === 0
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.refresh()
            onHovered: function(hovered) { if (hovered) root.focusIndex = 0 }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(Color.popups.border, 0.28)
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: sectionTitle
            text: "Protected applications"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Rectangle {
            width: countLabel.implicitWidth + Style.space(12)
            height: Style.space(22)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.08)

            Text {
              id: countLabel
              anchors.centerIn: parent
              text: String(root.applications.length)
              color: root.mutedForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        ListView {
          id: applicationList
          width: parent.width
          height: root.applications.length === 0
            ? emptyState.implicitHeight
            : Math.min(contentHeight, Style.space(260))
          spacing: Style.space(10)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          QtControls.ScrollBar.vertical: QtControls.ScrollBar {
            policy: QtControls.ScrollBar.AsNeeded
          }
          model: root.applications

          delegate: Column {
            required property var modelData
            width: applicationList.width
            height: implicitHeight
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(10)

              Image {
                width: Style.space(38)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                source: Quickshell.iconPath(modelData.id || "application-x-executable", true)
                fillMode: Image.PreserveAspectFit
                smooth: true
              }

              Column {
                width: parent.width - enabledSwitch.width - parent.spacing * 2 - Style.space(38)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: String(modelData.name || modelData.id || "Unnamed application")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.matchingClasses(modelData).length + " matching classes"
                  color: root.mutedForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              ToggleSwitch {
                id: enabledSwitch
                checked: modelData.enabled === true
                interactive: false
                foreground: root.foreground
                accent: root.accent
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              width: parent.width
              leftPadding: Style.space(48)
              text: root.matchingClasses(modelData).join("  ·  ")
              color: root.mutedForeground
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        Text {
          id: emptyState
          visible: root.applications.length === 0 && root.errorText === ""
          width: parent.width
          text: root.busy ? "Checking protected applications…" : "No protected applications"
          color: root.mutedForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.errorText !== ""
          width: parent.width
          text: root.errorText
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(Color.popups.border, 0.28)
        }

        Row {
          width: parent.width
          spacing: Style.space(10)

          Toggle {
            width: parent.width - addButton.width - parent.spacing
            label: "Window protection"
            description: root.protectionEnabled
              ? "Enabled for all listed applications"
              : "Paused for all listed applications"
            checked: root.protectionEnabled
            hasCursor: root.focusIndex === 1
            enabled: !root.busy
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.setProtection(!root.protectionEnabled)
            onHovered: function(hovered) { if (hovered) root.focusIndex = 1 }
          }

          Button {
            id: addButton
            width: Style.space(126)
            height: parent.children[0].height
            text: "Add focused app"
            tooltipText: "Protect the currently focused application"
            bordered: false
            focusable: true
            hasCursor: root.focusIndex === 2
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.addFocusedApplication()
            onHovered: function(hovered) { if (hovered) root.focusIndex = 2 }
          }
        }
      }
    }
  }
}
