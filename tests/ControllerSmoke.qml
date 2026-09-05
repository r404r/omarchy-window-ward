import QtQuick
import Quickshell
import "." as WindowWard

ShellRoot {
  id: root
  property int stage: 0
  property bool finished: false

  function fail(message) {
    console.error("controller smoke failed: " + message)
    Qt.exit(1)
  }
  function pass() {
    if (finished) return
    finished = true
    console.log("controller smoke: ok")
    Qt.exit(0)
  }

  WindowWard.WardController {
    id: ward
    cliPath: Quickshell.env("WINDOW_WARD_TEST_CLI")
    operationDeadlineMs: 100
    terminationGraceMs: 50
  }

  Component.onCompleted: ward.refresh()

  Timer {
    interval: 10
    repeat: true
    running: !root.finished
    onTriggered: {
      if (root.stage === 0 && ward.ready) {
        if (!ward.setProtection(false)) root.fail("initial mutation was rejected")
        ward.refresh() // Must queue, not race a status read with the write.
        root.stage = 1
      } else if (root.stage === 1 && ward.ready && !ward.protectionEnabled) {
        ward.refresh() // Fake CLI returns empty stdout for this request.
        root.stage = 2
      } else if (root.stage === 2 && !ward.ready && ward.errorText === "Could not read Window Ward status.") {
        ward.refresh() // Fake CLI blocks; the owned deadline must terminate it.
        root.stage = 3
      } else if (root.stage === 3 && !ward.busy && !ward.ready && ward.errorText === "Window Ward did not respond in time.") {
        ward.cliPath = Quickshell.env("WINDOW_WARD_TEST_CLI") + "-missing"
        ward.refresh()
        root.stage = 4
      } else if (root.stage === 4 && !ward.busy && !ward.ready && ward.errorText === "Window Ward is unavailable. Run setup or doctor.") {
        root.pass()
      }
    }
  }

  Timer {
    interval: 2000
    running: !root.finished
    onTriggered: root.fail("timed out waiting for controller state")
  }
}
