// Real KDE rendering and recorded dates. No update checks or app mutations.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    property int stage: 0
    property bool capturing: false
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function check(value, message) {
        if (!value) { console.error("APP_UPDATES_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (main.capturing || main.backend.installedLoading) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            main.check(main.backend.updates.state === "idle", "No automatic app update check")
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                main.showUpdates(); main.stage = 1; return
            }
            const page = probe.findChild(stack.get(0), "updatesPage")
            const search = probe.findChild(stack.get(0), "searchField"), menu = probe.findChild(stack.get(0), "applicationMenuButton")
            main.check(Math.abs(search.x + search.width + 10 - menu.x) < 1, "Search first, menu second")
            main.check(Math.abs(menu.x + menu.width - menu.parent.width + 24) < 1, "Menu right margin")
            const title = probe.findChild(page, "appUpdatesTitle"), check = probe.findChild(page, "checkForUpdatesButton")
            main.check(title.text === "App Updates", "Page title")
            main.check(probe.findChild(stack.get(0), "updatesButton").text === "App Updates", "Sidebar label")
            main.check(check.text === "Check for App Updates", "Check button")
            main.check(probe.findChild(page, "updateDates").text.indexOf("Apps were last updated:") === 0, "Recorded date label")
            main.check(probe.findChild(page, "updateDates").text.indexOf("Last checked") < 0, "No last-checked line")
            main.check(!probe.findChild(page, "updatesEmpty").visible, "No redundant center instruction")
            main.check(title.contentWidth <= title.width + 1, "Title fits")
            const t = title.mapToItem(page, 0, 0), c = check.mapToItem(page, 0, 0)
            main.check(c.x >= t.x + title.width || c.y >= t.y + title.height, "Title and button do not overlap")
            main.capturing = true
            const name = main.stage === 1 ? "normal" : "compact"
            main.check(stack.grabToImage(function(result) {
                main.check(result.saveToFile(Qt.resolvedUrl("../../target/app-updates-" + name + ".png").toString().replace("file://", "")), "Save screenshot")
                console.log("APP_UPDATES_CAPTURE", name)
                if (main.stage === 2) { console.log("APP_UPDATES_PASS"); Qt.quit(); return }
                main.width = 720; main.height = 520; main.stage = 2; main.capturing = false
            }), "Screenshot capture")
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(3) }
}
