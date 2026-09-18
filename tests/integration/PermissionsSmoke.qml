// Real read-only metadata and icon provider; no app/repository changes.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 900; visible: true
    palette.window: "#202326"; palette.windowText: "#ffffff"
    property int stage: 0
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function capture(item, name, next) {
        stage = -1
        item.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/permissions-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(2); return }
            main.stage = next
        })
    }
    Timer {
        interval: 300; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy || main.backend.installedLoading) return
            const page = stack.currentItem
            const dialog = probe.findChild(page, "appPermissionsDialog")
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                const telegram = main.catalog.find(app => String(app.flatpakRef).indexOf("app/org.telegram.desktop/") === 0 && String(app.flatpakRef).endsWith("/stable"))
                if (!telegram) { Qt.exit(3); return }
                main.openApp(telegram); main.stage = 1
            } else if (main.stage === 1) {
                const flick = probe.findChild(page, "detailsFlickable")
                flick.contentY = Math.max(0, flick.contentHeight - flick.height)
                main.stage = 2
            } else if (main.stage === 2) main.capture(stack, "entry", 3)
            else if (main.stage === 3) { probe.mouseClick(probe.findChild(page, "viewAppPermissionsButton")); main.stage = 4 }
            else if (main.stage === 4 || main.stage === 9) {
                if (main.backend.appPermissions.state === "loading") return
                if (main.backend.appPermissions.state !== "ready") { main.capture(dialog.contentItem.parent, "error", 11); return }
                console.log(JSON.stringify(main.backend.appPermissions))
                main.capture(dialog.contentItem.parent, main.stage === 4 ? "telegram" : "installed", main.stage === 4 ? 5 : 10)
            } else if (main.stage === 5) {
                const scroll = probe.findChild(dialog, "permissionsScroll")
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height); main.stage = 6
            } else if (main.stage === 6) main.capture(dialog.contentItem.parent, "telegram-bottom", 7)
            else if (main.stage === 7) {
                probe.mouseClick(probe.findChild(dialog, "closePermissionsButton"))
                const installed = main.backend.installedApps.find(app => app.id.indexOf("anydesk") >= 0)
                if (!installed) { Qt.exit(5); return }
                main.openApp(installed); main.stage = 8
            } else if (main.stage === 8) { dialog.open(); main.stage = 9 }
            else if (main.stage === 10) {
                dialog.close()
                const system = main.backend.installedApps.find(app => app.id === "org.mozilla.firefox" && app.installation !== "user")
                if (!system) { Qt.exit(7); return }
                main.openApp(system); main.stage = 12
            }
            else if (main.stage === 11) Qt.exit(4)
            else if (main.stage === 12) { dialog.open(); main.stage = 13 }
            else if (main.stage === 13) {
                if (main.backend.appPermissions.state === "loading") return
                if (main.backend.appPermissions.state !== "ready" || !main.backend.appPermissions.installed) { main.capture(dialog.contentItem.parent, "error", 11); return }
                main.capture(dialog.contentItem.parent, "system", 14)
            } else if (main.stage === 14) {
                dialog.close()
                const zeroad = main.catalog.find(app => String(app.flatpakRef).indexOf("app/com.play0ad.zeroad/") === 0)
                if (!zeroad) { Qt.exit(8); return }
                main.openApp(zeroad); main.stage = 15
            } else if (main.stage === 15) { dialog.open(); main.stage = 16 }
            else if (main.stage === 16) {
                if (main.backend.appPermissions.state === "loading") return
                if (main.backend.appPermissions.state !== "ready") { main.capture(dialog.contentItem.parent, "error", 11); return }
                main.capture(dialog.contentItem.parent, "zeroad", 17)
            } else if (main.stage === 17) { main.width = 720; main.height = 540; main.stage = 18 }
            else if (main.stage === 18) main.capture(dialog.contentItem.parent, "narrow", 19)
            else if (main.stage === 19) { dialog.close(); Qt.quit() }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(6) }
}
