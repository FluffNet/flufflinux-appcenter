import QtQuick
import QtQuick.Window

Window {
    visible: true
    width: 320
    height: 180
    property string initialUpdates: JSON.stringify(fluffBackend.updates)
    function showUpdates() {
        if (initialUpdates !== JSON.stringify(fluffBackend.updates)) {
            console.error("FAIL: launch action changed update state")
            Qt.exit(1)
            return
        }
        console.log("PASS: legacy update shortcut dispatched without checking for updates")
        Qt.quit()
    }
    Timer { interval: 10000; running: true; onTriggered: Qt.exit(2) }
}
