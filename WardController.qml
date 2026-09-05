import QtQuick
import Quickshell
import Quickshell.Io
import "WardModel.js" as WardModel

Item {
  id: root

  property string cliPath: Quickshell.env("HOME") + "/.local/bin/window-ward"
  property bool ready: false
  property bool busy: operation.running || finishing
  property string state: "stale" // loading | ready | stale | error
  property string errorText: ""
  property bool protectionEnabled: false
  property var applications: []
  property int revision: 0
  property bool refreshPending: false
  property bool finishing: false
  property string operationKind: ""
  property int operationRevision: 0
  property int operationSerial: 0
  property string statusOutput: ""
  property bool statusOutputOverflow: false
  property bool timedOut: false
  property string postRefreshMessage: ""

  readonly property int maxStatusOutputChars: 131072
  property int operationDeadlineMs: 8000
  property int terminationGraceMs: 500

  function markUntrusted(message, nextState) {
    root.ready = false
    root.state = nextState || "error"
    root.errorText = message
  }

  function refresh() {
    if (root.busy) {
      root.refreshPending = true
      return false
    }
    root.startStatus()
    return true
  }

  function mutate(command) {
    if (!root.ready || root.busy || !(command instanceof Array) || command.length === 0) return false
    root.revision += 1
    root.ready = false
    root.state = "loading"
    root.errorText = ""
    root.startOperation("mutation", command, root.revision)
    return true
  }

  function setProtection(enabled) {
    return root.mutate([enabled ? "enable" : "disable"])
  }

  function addFocusedApplication() {
    return root.mutate(["add-focused"])
  }

  function setApplicationEnabled(applicationId, enabled) {
    if (!applicationId) return false
    return root.mutate(["set-app-enabled", String(applicationId), enabled ? "true" : "false"])
  }

  function removeApplication(applicationId) {
    if (!applicationId) return false
    return root.mutate(["remove", String(applicationId)])
  }

  function startStatus() {
    root.ready = false
    root.state = "loading"
    root.errorText = ""
    root.startOperation("status", ["status"], root.revision)
  }

  function startOperation(kind, arguments, requestRevision) {
    root.operationKind = kind
    root.operationRevision = requestRevision
    root.operationSerial += 1
    root.statusOutput = ""
    root.statusOutputOverflow = false
    root.timedOut = false
    operation.command = [root.cliPath].concat(arguments)
    operation.running = true
    operationDeadline.restart()
  }

  function appendStatusOutput(chunk) {
    if (root.operationKind !== "status" || root.statusOutputOverflow) return
    var value = String(chunk)
    var remaining = root.maxStatusOutputChars - root.statusOutput.length
    if (remaining <= 0 || value.length > remaining) {
      root.statusOutputOverflow = true
      return
    }
    root.statusOutput += value
  }

  function finishOperation(exitCode, serial, kind, requestRevision, wasTimedOut) {
    if (serial !== root.operationSerial) return
    root.finishing = false
    if (wasTimedOut) {
      root.markUntrusted("Window Ward did not respond in time.")
    } else if (kind === "mutation") {
      if (exitCode !== 0) root.postRefreshMessage = "Could not change Window Ward protection."
      root.refreshPending = true
    } else if (exitCode !== 0) {
      root.markUntrusted("Window Ward is unavailable. Run setup or doctor.")
    } else if (root.statusOutputOverflow) {
      root.markUntrusted("Window Ward status was too large to display safely.")
    } else if (requestRevision !== root.revision) {
      root.markUntrusted("Window Ward status changed while loading.", "stale")
      root.refreshPending = true
    } else {
      var status = WardModel.parseStatus(root.statusOutput)
      if (status === null) {
        root.markUntrusted("Could not read Window Ward status.")
      } else {
        root.protectionEnabled = status.enabled
        root.applications = status.applications
        root.ready = true
        root.state = "ready"
        root.errorText = root.postRefreshMessage
        root.postRefreshMessage = ""
      }
    }
    if (root.refreshPending) {
      root.refreshPending = false
      root.startStatus()
    }
  }

  function terminateOwned() {
    if (!operation.running) {
      // Quickshell reports an exec failure as a non-running Process and may not
      // emit exited(). The deadline is also the bounded recovery path for it.
      root.markUntrusted("Window Ward is unavailable. Run setup or doctor.")
      root.finishing = false
      return
    }
    root.timedOut = true
    root.markUntrusted("Window Ward did not respond in time.")
    // Process.signal addresses only this controller's direct CLI child. Do not
    // guess at descendant process groups here; the CLI owns and bounds them.
    operation.signal(15)
    terminationGrace.restart()
  }

  function cancelOwned() {
    operationDeadline.stop()
    terminationGrace.stop()
    if (operation.running) {
      root.timedOut = true
      operation.signal(15)
      terminationGrace.restart()
    }
  }

  Timer {
    id: operationDeadline
    interval: root.operationDeadlineMs
    repeat: false
    onTriggered: root.terminateOwned()
  }
  Timer {
    id: terminationGrace
    interval: root.terminationGraceMs
    repeat: false
    onTriggered: { if (operation.running) operation.signal(9) }
  }
  Process {
    id: operation
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) { root.appendStatusOutput(chunk) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {}
    }
    onExited: function(exitCode) {
      var serial = root.operationSerial
      var kind = root.operationKind
      var requestRevision = root.operationRevision
      var wasTimedOut = root.timedOut
      operationDeadline.stop()
      terminationGrace.stop()
      root.finishing = true
      Qt.callLater(function() { root.finishOperation(exitCode, serial, kind, requestRevision, wasTimedOut) })
    }
  }
  Component.onDestruction: root.cancelOwned()
}
