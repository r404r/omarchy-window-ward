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
  property string pendingRemovalId: ""
  property string statusOutput: ""
  property bool statusOutputOverflow: false
  property bool statusFinishing: false
  property int statusGeneration: 0

  // The panel is a trust boundary: the CLI, its configuration, and Hyprland
  // can all ultimately provide this data. Keep its retained state deliberately
  // small even when a broken or replaced command writes without stopping.
  // The CLI accepts a 64 KiB config, then normalizes optional match fields
  // before serializing status. 128 KiB accepts every valid normalized status
  // with margin while still bounding retained panel memory.
  readonly property int maxStatusOutputChars: 131072
  readonly property int maxApplications: 128
  readonly property int maxMatchersPerApplication: 32
  readonly property int maxApplicationIdChars: 128
  readonly property int maxApplicationNameChars: 256
  readonly property int maxMatcherChars: 256

  readonly property string cliPath: Quickshell.env("HOME") + "/.local/bin/window-ward"
  readonly property bool busy: statusProcess.running || statusFinishing || toggleProcess.running || addProcess.running
    || applicationToggleProcess.running || removeProcess.running
  readonly property color foreground: Color.popups.text
  readonly property color mutedForeground: Qt.darker(foreground, 1.45)
  readonly property color accent: Color.accent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property int globalToggleFocusIndex: 1 + root.applications.length * 2
  readonly property int addFocusIndex: root.globalToggleFocusIndex + 1
  readonly property int focusTargetCount: root.addFocusIndex + 1

  function open() {
    root.controller.show()
    root.focusIndex = 0
    root.pendingRemovalId = ""
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
    root.pendingRemovalId = ""
    removalConfirmationTimer.stop()
    if (!statusProcess.running && !root.statusFinishing) {
      root.statusGeneration += 1
      root.statusOutput = ""
      root.statusOutputOverflow = false
      statusProcess.requestGeneration = root.statusGeneration
      statusProcess.running = true
    }
  }

  function setProtection(enabled) {
    if (root.busy) return
    root.errorText = ""
    toggleProcess.enable = enabled
    toggleProcess.running = true
  }

  function moveFocus(delta) {
    root.focusIndex = (root.focusIndex + (delta > 0 ? 1 : -1) + root.focusTargetCount)
      % root.focusTargetCount
  }

  function activateFocused() {
    if (root.focusIndex === 0) {
      root.refresh()
      return
    }
    if (root.focusIndex < root.globalToggleFocusIndex) {
      var applicationIndex = Math.floor((root.focusIndex - 1) / 2)
      var application = root.applications[applicationIndex]
      if (!application) return
      if ((root.focusIndex - 1) % 2 === 0)
        root.setApplicationEnabled(String(application.id), application.enabled !== true)
      else
        root.requestApplicationRemoval(String(application.id))
      return
    }
    if (root.focusIndex === root.globalToggleFocusIndex)
      root.setProtection(!root.protectionEnabled)
    else
      root.addFocusedApplication()
  }

  function addFocusedApplication() {
    if (root.busy) return
    root.errorText = ""
    addProcess.running = true
  }

  function setApplicationEnabled(applicationId, enabled) {
    if (root.busy || !applicationId) return
    root.errorText = ""
    root.pendingRemovalId = ""
    applicationToggleProcess.applicationId = applicationId
    applicationToggleProcess.enable = enabled
    applicationToggleProcess.running = true
  }

  function requestApplicationRemoval(applicationId) {
    if (root.busy || !applicationId) return
    if (root.pendingRemovalId !== applicationId) {
      root.pendingRemovalId = applicationId
      removalConfirmationTimer.restart()
      return
    }
    removalConfirmationTimer.stop()
    root.errorText = ""
    removeProcess.applicationId = applicationId
    removeProcess.running = true
  }

  function matchingClasses(application) {
    if (!application || !application.match || !(application.match.class instanceof Array)) return []
    return application.match.class
  }

  function boundedDisplayText(value, maximumLength) {
    var text = String(value === undefined || value === null ? "" : value)
      .replace(/[\u0000-\u001f\u007f]/g, " ")
    return text.length > maximumLength ? text.slice(0, maximumLength - 1) + "…" : text
  }

  function sanitizedMatcherList(values) {
    if (!(values instanceof Array)) return []
    var result = []
    for (var index = 0; index < values.length && result.length < root.maxMatchersPerApplication; index++) {
      var matcher = root.boundedDisplayText(values[index], root.maxMatcherChars)
      if (matcher.length > 0) result.push(matcher)
    }
    return result
  }

  function sanitizedApplications(values) {
    if (!(values instanceof Array)) return []
    var result = []
    for (var index = 0; index < values.length && result.length < root.maxApplications; index++) {
      var application = values[index]
      if (!application || typeof application !== "object") continue
      var id = String(application.id === undefined || application.id === null ? "" : application.id)
      if (!id || id.length > root.maxApplicationIdChars || /[\u0000-\u001f\u007f]/.test(id)) continue
      var match = application.match && typeof application.match === "object" ? application.match : {}
      result.push({
        id: id,
        name: root.boundedDisplayText(application.name || id, root.maxApplicationNameChars),
        enabled: application.enabled === true,
        match: {
          class: root.sanitizedMatcherList(match.class),
          initialClass: root.sanitizedMatcherList(match.initialClass)
        }
      })
    }
    return result
  }

  function appendStatusOutput(chunk) {
    if (root.statusOutputOverflow) return
    var value = String(chunk)
    var remaining = root.maxStatusOutputChars - root.statusOutput.length
    if (remaining <= 0 || value.length > remaining) {
      root.statusOutputOverflow = true
      return
    }
    root.statusOutput += value
  }

  function finishStatus(exitCode, generation) {
    if (generation !== root.statusGeneration) return
    root.statusFinishing = false
    if (exitCode !== 0) {
      root.errorText = "Window Ward is unavailable. Run setup or doctor."
      return
    }
    if (root.statusOutputOverflow) {
      root.errorText = "Window Ward status was too large to display safely."
      return
    }
    try {
      var state = JSON.parse(root.statusOutput || "{}")
      root.protectionEnabled = state.enabled === true
      root.applications = root.sanitizedApplications(state.protectedApplications)
      root.focusIndex = Math.min(root.focusIndex, 2 + root.applications.length * 2)
      root.errorText = ""
    } catch (error) {
      root.errorText = "Could not read Window Ward status."
    }
  }

  function applicationIcon(application) {
    var candidates = [String((application && application.id) || "")]
      .concat(root.matchingClasses(application))
    if (application && application.match && application.match.initialClass instanceof Array)
      candidates = candidates.concat(application.match.initialClass)
    for (var index = 0; index < candidates.length; index++) {
      var candidate = String(candidates[index] || "")
      // iconPath accepts more than icon-theme names. Only hand it a compact
      // icon-theme identifier, never an application-controlled path or URL.
      if (!/^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(candidate)) continue
      var themed = Quickshell.iconPath(candidate, true)
      if (themed.length > 0) return themed
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  Timer {
    id: removalConfirmationTimer
    interval: 5000
    onTriggered: root.pendingRemovalId = ""
  }

  Process {
    id: statusProcess
    property int requestGeneration: 0
    command: [root.cliPath, "status"]

    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) { root.appendStatusOutput(chunk) }
    }

    stderr: SplitParser {
      splitMarker: ""
      // Deliberately consume without retaining diagnostics from a child process.
      onRead: function(chunk) {}
    }

    onExited: function(exitCode) {
      var generation = requestGeneration
      root.statusFinishing = true
      Qt.callLater(function() { root.finishStatus(exitCode, generation) })
    }
  }

  Process {
    id: toggleProcess
    property bool enable: true
    command: [root.cliPath, enable ? "enable" : "disable"]

    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {}
    }

    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh()
      else root.errorText = "Could not change protection."
    }
  }

  Process {
    id: addProcess
    command: [root.cliPath, "add-focused"]

    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {}
    }

    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh()
      else root.errorText = "Could not add the focused application."
    }
  }

  Process {
    id: applicationToggleProcess
    property string applicationId: ""
    property bool enable: true
    command: [root.cliPath, "set-app-enabled", applicationId, enable ? "true" : "false"]

    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {}
    }

    onExited: function(exitCode) {
      if (exitCode === 0) root.refresh()
      else root.errorText = "Could not change this application."
    }
  }

  Process {
    id: removeProcess
    property string applicationId: ""
    command: [root.cliPath, "remove", applicationId]

    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {}
    }

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.pendingRemovalId = ""
        root.refresh()
      } else {
        root.pendingRemovalId = ""
        root.errorText = "Could not remove this application."
      }
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
          currentIndex: root.focusIndex > 0 && root.focusIndex < root.globalToggleFocusIndex
            ? Math.floor((root.focusIndex - 1) / 2)
            : -1
          onCurrentIndexChanged: {
            if (currentIndex >= 0)
              Qt.callLater(function() { applicationList.positionViewAtIndex(currentIndex, ListView.Contain) })
          }
          QtControls.ScrollBar.vertical: QtControls.ScrollBar {
            policy: QtControls.ScrollBar.AsNeeded
          }
          model: root.applications

          delegate: Column {
            required property var modelData
            required property int index
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
                source: root.applicationIcon(modelData)
                fillMode: Image.PreserveAspectFit
                smooth: true
              }

              Column {
                width: parent.width - enabledSwitch.width - removeButton.width
                  - parent.spacing * 3 - Style.space(38)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: String(modelData.name || modelData.id || "Unnamed application")
                  textFormat: Text.PlainText
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
                interactive: true
                busy: root.busy
                hasCursor: root.focusIndex === 1 + index * 2
                foreground: root.foreground
                accent: root.accent
                anchors.verticalCenter: parent.verticalCenter
                onToggled: root.setApplicationEnabled(String(modelData.id), !checked)
                onHovered: function(hovered) { if (hovered) root.focusIndex = 1 + index * 2 }
              }

              Button {
                id: removeButton
                width: Style.space(root.pendingRemovalId === String(modelData.id) ? 82 : 70)
                text: root.pendingRemovalId === String(modelData.id) ? "Confirm" : "Remove"
                tooltipText: root.pendingRemovalId === String(modelData.id)
                  ? "Click again to remove this rule"
                  : "Remove this application from protection"
                bordered: root.pendingRemovalId === String(modelData.id)
                focusable: true
                hasCursor: root.focusIndex === 2 + index * 2
                enabled: !root.busy
                foreground: Color.urgent
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.requestApplicationRemoval(String(modelData.id))
                onHovered: function(hovered) { if (hovered) root.focusIndex = 2 + index * 2 }
              }
            }

            Text {
              width: parent.width
              leftPadding: Style.space(48)
              text: root.matchingClasses(modelData).join("  ·  ")
              textFormat: Text.PlainText
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
          textFormat: Text.PlainText
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
            hasCursor: root.focusIndex === root.globalToggleFocusIndex
            enabled: !root.busy
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.setProtection(!root.protectionEnabled)
            onHovered: function(hovered) { if (hovered) root.focusIndex = root.globalToggleFocusIndex }
          }

          Button {
            id: addButton
            width: Style.space(126)
            height: parent.children[0].height
            text: "Add focused app"
            tooltipText: "Protect the currently focused application"
            bordered: false
            focusable: true
            hasCursor: root.focusIndex === root.addFocusIndex
            enabled: !root.busy
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.addFocusedApplication()
            onHovered: function(hovered) { if (hovered) root.focusIndex = root.addFocusIndex }
          }
        }
      }
    }
  }
}
