// Native visual check: the Check button is clicked, but no updates are applied.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 900; visible: true
    property int stage: 0
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function capture(item, name, next) {
        stage = -1
        item.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/updates-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(2); return }
            main.stage = next
        })
    }
    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy || main.backend.installedLoading) return
            const page = stack.currentItem
            if (main.stage === 0) {
                if (main.backend.updates.state !== "idle") { Qt.exit(3); return }
                stack.background = main.snapshotBackground.createObject(stack)
                main.showUpdates(); main.stage = 1
            } else if (main.stage === 1) {
                if (main.backend.updates.state !== "idle") { Qt.exit(4); return }
                main.capture(stack, "idle", 2)
            } else if (main.stage === 2) {
                probe.mouseClick(probe.findChild(page, "checkForUpdatesButton")); main.stage = 3
            } else if (main.stage === 3) {
                if (main.backend.updates.state === "checking") return
                console.log("UPDATES_SCAN", JSON.stringify(main.backend.updates))
                main.capture(stack, "list", 4)
            } else if (main.stage === 4) {
                const changed = main.backend.updates.items.find(row => row.permissions.state === "changed")
                if (!changed) { main.stage = 6; return }
                const dialog = probe.findChild(page, "appPermissionsDialog")
                dialog.app = changed; dialog.changes = changed.permissions; dialog.open(); main.stage = 5
            } else if (main.stage === 5) {
                const dialog = probe.findChild(page, "appPermissionsDialog")
                main.capture(dialog.contentItem.parent, "permission-changes", 6)
            } else if (main.stage === 6) {
                const dialog = probe.findChild(page, "appPermissionsDialog"); dialog.close()
                main.width = 720; main.height = 540; main.stage = 7
            } else if (main.stage === 7) main.capture(stack, "narrow", 8)
            else if (main.stage === 8) Qt.quit()
        }
    }
    Timer { interval: 210000; running: true; onTriggered: Qt.exit(6) }
}
