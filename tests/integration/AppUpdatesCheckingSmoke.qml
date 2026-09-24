// Production QML and KDE theme, simulated pending check. No network/app changes.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    backend: previewBackend
    QtObject {
        id: previewBackend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property bool busy: true
        property int iconRevision: 0
        property var updates: ({state:"checking", items:[],
            lastUpdated:fluffBackend.updates.lastUpdated, lastChecked:fluffBackend.updates.lastChecked})
        function cancelUpdateCheck() { updates = {state:"cancelled", items:[]}; busy = false }
        function requestInstallInfo(app) {}
    }
    TestCase { id: probe; when: false }
    property int stage: 0
    property bool capturing: false
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function check(value, message) {
        if (!value) { console.error("CHECKING_UI_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    Timer {
        interval: 600; repeat: true; running: true
        onTriggered: {
            if (main.capturing) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            main.check(fluffBackend.updates.state === "idle", "No real update check")
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                main.showUpdates(); main.stage = 1; return
            }
            const page = probe.findChild(stack.get(0), "updatesPage")
            const area = probe.findChild(page, "updatesContentArea")
            const indicator = probe.findChild(page, "updateCheckIndicator")
            const spinner = probe.findChild(page, "updateCheckSpinner")
            main.check(indicator.visible && spinner.running, "Animated checking indicator")
            main.check(Math.abs(indicator.x + indicator.width / 2 - area.width / 2) < 1
                && Math.abs(indicator.y + indicator.height / 2 - area.height / 2) < 1, "Centered as a group")
            main.check(probe.findChild(page, "cancelUpdateCheckButton").enabled, "Cancellation available")
            main.capturing = true
            const name = main.stage === 1 ? "normal" : "compact"
            main.check(stack.grabToImage(function(result) {
                main.check(result.saveToFile(Qt.resolvedUrl("../../target/app-updates-checking-" + name + ".png").toString().replace("file://", "")), "Save screenshot")
                console.log("CHECKING_UI_CAPTURE", name)
                if (main.stage === 2) { console.log("CHECKING_UI_PASS"); Qt.quit(); return }
                main.width = 720; main.height = 520; main.stage = 2; main.capturing = false
            }), "Capture accepted")
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(3) }
}
