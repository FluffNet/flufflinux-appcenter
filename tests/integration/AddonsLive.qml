import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760
    property int stage: 0
    property bool capturePending: false
    property var parentApp: null
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    function capture(name, next) {
        capturePending = true
        const stack = probe.findChild(main, "navigationStack")
        const dialog = probe.findChild(stack.currentItem, "appAddonsDialog")
        const target = dialog && dialog.opened ? dialog.contentItem.parent : stack
        if (!target.grabToImage(function(result) {
            if (!result.saveToFile("/tmp/appcenter-addons-" + name + ".png")) { Qt.exit(10); return }
            console.info("ADDONS_CAPTURE: " + name)
            stage = next; capturePending = false
        })) Qt.exit(11)
    }
    Timer {
        interval: 600; running: true; repeat: true
        onTriggered: {
            if (!main.backend || main.capturePending) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            const page = stack.currentItem
            const dialog = probe.findChild(page, "appAddonsDialog")
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                if (main.backend.installedLoading) return
                main.parentApp = main.backend.installedApps.find(app => app.id === "org.flufflinux.AddonFixture")
                if (!main.parentApp) { Qt.exit(2); return }
                main.openApp(main.parentApp); main.stage = 1
            } else if (main.stage === 1) {
                const scroll = probe.findChild(page, "detailsFlickable")
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
                main.stage = 2
            } else if (main.stage === 2) main.capture("button", 3)
            else if (main.stage === 3) {
                probe.mouseClick(probe.findChild(page, "viewAppAddonsButton")); main.stage = 4
            } else if (main.stage === 4) {
                if (main.backend.appAddons.state === "loading") return
                if (main.backend.appAddons.state !== "ready" || main.backend.appAddons.items.length !== 1) {
                    console.error(JSON.stringify(main.backend.appAddons)); Qt.exit(3); return
                }
                main.capture("dialog", 5)
            } else if (main.stage === 5) {
                const row = probe.findChild(dialog, "addonRows").itemAt(0)
                probe.mouseClick(probe.findChild(row, "addonActionButton")); main.stage = 6
            } else if (main.stage === 6) {
                if (main.backend.busy || main.backend.appAddons.state === "loading") return
                if (!main.backend.appAddons.items[0].installed) { console.error(JSON.stringify(main.backend.jobs)); Qt.exit(4); return }
                main.capture("installed", 7)
            } else if (main.stage === 7) {
                main.palette.window = "#eff0f1"; main.palette.windowText = "#232629"; main.palette.placeholderText = "#606970"
                main.stage = 8
            } else if (main.stage === 8) main.capture("light", 9)
            else if (main.stage === 9) {
                const row = probe.findChild(dialog, "addonRows").itemAt(0)
                probe.mouseClick(probe.findChild(row, "addonActionButton")); main.stage = 10
            } else if (main.stage === 10) {
                if (!main.backend.review.token) return
                if (main.backend.review.message.indexOf("parent app and its data will be kept") < 0) { Qt.exit(5); return }
                main.backend.answerReview(main.backend.review.token, true); main.stage = 11
            } else if (main.stage === 11) {
                if (main.backend.busy || main.backend.appAddons.state === "loading") return
                if (main.backend.appAddons.items[0].installed) { console.error(JSON.stringify(main.backend.jobs)); Qt.exit(6); return }
                if (main.downloadQueue.jobs.some(job => job.action === "uninstall")) { Qt.exit(7); return }
                console.info("PASS: real add-on dialog install/remove, parent-safe confirmation, removals outside Queue, dark/light screenshots")
                Qt.quit()
            }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: { console.error("ADDONS_TIMEOUT stage " + main.stage); Qt.exit(8) } }
}
