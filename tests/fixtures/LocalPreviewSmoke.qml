// Real local-file handler and backend. The driver supplies isolated Flatpak paths.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as App

App.Main {
    id: main
    width: 1400; height: 1050
    catalogStats: null
    catalogPreferences: null
    networkStatus: null
    palette.window: "#202326"
    palette.windowText: "white"
    property int stage: 0
    property int imageWait: 0
    property bool capturing: false
    property bool backed: false
    property Component backdrop: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    Connections {
        target: main.backend
        function onInputError(message) { console.error("LOCAL_PREVIEW_ERROR", message); Qt.exit(1) }
    }
    Timer { interval: 110000; running: true; onTriggered: { console.error("LOCAL_PREVIEW timeout"); Qt.exit(1) } }
    Timer {
        interval: 200; running: true; repeat: true
        onTriggered: {
            if (main.capturing || !main.selectedApp || !main.selectedApp.localSource) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            if (!main.backed) { stack.background = main.backdrop.createObject(stack); main.backed = true }
            if (main.stage === 2 && probe.findChild(stack.currentItem, "appPermissionsDialog").visible) return
            if (main.stage === 0) {
                const app = main.selectedApp
                if (!app.name || !app.description || !app.localSource) {
                    console.error("LOCAL_PREVIEW incomplete", JSON.stringify(app)); Qt.exit(1); return
                }
                const icon = probe.findChild(main, "appHeroIcon")
                const list = probe.findChild(main, "screenshotList")
                const first = list.itemAtIndex(0)
                const image = first && first.contentItem.children[0]
                if (!icon || icon.status !== Image.Ready || (app.screenshots.length && (!image || image.status !== Image.Ready))) {
                    if (++main.imageWait > 250) { console.error("LOCAL_PREVIEW artwork failed to load"); Qt.exit(1) }
                    return
                }
                const note = probe.findChild(stack.currentItem, "localSourceNote")
                if (!note || !note.visible) { console.error("LOCAL_PREVIEW source note missing"); Qt.exit(1); return }
                const size = probe.findChild(stack.currentItem, "appDownloadSize")
                if (!size || size.text === "Unavailable") { console.error("LOCAL_PREVIEW app size missing"); Qt.exit(1); return }
                const total = probe.findChild(stack.currentItem, "totalDownloadSize")
                if (!total || total.text === "Unavailable") { console.error("LOCAL_PREVIEW dependency total missing"); Qt.exit(1); return }
                if (!probe.findChild(stack.currentItem, "installAppButton").enabled) return
            }
            if (main.stage === 1 || main.stage === 3) {
                const dialog = probe.findChild(stack.currentItem, "appPermissionsDialog")
                if (!dialog.opened || main.backend.appPermissions.state !== "ready") {
                    if (++main.imageWait % 25 === 0) console.log("LOCAL_PREVIEW waiting", main.stage, dialog.opened, JSON.stringify(main.backend.appPermissions), dialog.requestToken)
                    return
                }
            }
            main.capturing = true
            capture.start()
        }
    }
    Timer {
        id: capture
        interval: 500
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            const dialog = probe.findChild(stack.currentItem, "appPermissionsDialog")
            const target = main.stage === 1 || main.stage === 3 ? dialog.contentItem.parent : stack
            if (!target.grabToImage(function(result) {
                const names = ["details-dark", "permissions-dark", "details-light", "permissions-light"]
                const path = Qt.resolvedUrl("../../target/local-preview-" + main.selectedApp.id + "-" + names[main.stage] + ".png").toString().replace("file://", "")
                if (!result.saveToFile(path)) { console.error("LOCAL_PREVIEW capture failed"); Qt.exit(1); return }
                console.log("LOCAL_PREVIEW captured", names[main.stage])
                if (main.stage === 0 || main.stage === 2) {
                    probe.findChild(stack.currentItem, "viewAppPermissionsButton").clicked()
                } else if (main.stage === 1) {
                    dialog.close()
                    main.palette.window = "#eff0f1"; main.palette.windowText = "#202326"
                } else { Qt.quit(); return }
                main.stage++
                main.capturing = false
            })) { console.error("LOCAL_PREVIEW capture could not start"); Qt.exit(1) }
        }
    }
}
