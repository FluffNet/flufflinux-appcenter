// Read-only real-backend artwork/version check. No install/remove operations.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visibility: Window.Maximized
    property var ids: ["com.play0ad.zeroad", "com.sweetscape.ZeroOneZeroEditor", "com.onepassword.OnePassword", "com.discordapp.Discord"]
    property int index: 0
    property string phase: "open"
    property bool failed: false
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of (item.children || [])) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function check(condition, message) {
        if (condition) return true
        failed = true; console.error("METADATA_FAIL: " + message); Qt.exit(1); return false
    }
    Timer {
        interval: 100; repeat: true; running: !main.failed && main.phase !== "done"
        onTriggered: {
            if (main.installedLoading) return
            const stack = main.find(main.contentItem, "navigationStack")
            if (stack.busy) return
            if (main.phase === "open") {
                const app = main.catalog.find(item => item.id === main.ids[main.index])
                if (!main.check(!!app && !!app.version, "Missing app/version " + main.ids[main.index])) return
                if (!main.check(app.icon.indexOf("/active/icons/") >= 0, "Unstable artwork path " + app.icon)) return
                stack.background = main.snapshotBackground.createObject(stack)
                main.openApp(app); main.phase = "verify"
            } else if (main.phase === "verify") {
                const app = main.selectedApp
                const logo = main.find(stack.currentItem, "appHeroIcon")
                if (logo.status === Image.Loading) return
                if (!main.check(logo.status === Image.Ready && !logo.loadFailed && logo.paintedWidth > 0, "Missing actual artwork " + app.id)) return
                if (!main.check(main.find(stack.currentItem, "appDeveloper").text === app.developer, "Developer prefix retained")) return
                if (!main.findInstalled(app)) {
                    const version = main.find(stack.currentItem, "appAvailableVersion")
                    const size = main.find(stack.currentItem, "appDownloadSize")
                    if (!main.check(version.visible && version.text === app.version, "Wrong version")) return
                    if (!main.check(version.mapToItem(stack.currentItem, 0, 0).y > size.mapToItem(stack.currentItem, 0, 0).y, "Version not below size")) return
                    const info = main.find(stack.currentItem, "appHeroText")
                    const details = main.find(stack.currentItem, "installSizeDetails")
                    if (!main.check(details.mapToItem(stack.currentItem, 0, 0).y >= info.mapToItem(stack.currentItem, 0, info.height).y, "Details not beneath developer")) return
                }
                const buttons = main.find(stack.currentItem, "appActionButtons")
                const info = main.find(stack.currentItem, "appHeroText")
                if (!main.check(buttons.mapToItem(stack.currentItem, 0, 0).x >= info.mapToItem(stack.currentItem, info.width, 0).x, "Actions not on the right")) return
                const card = main.find(stack.currentItem, "appHeroCard")
                const leftInset = logo.mapToItem(card, 0, 0).x
                const rightInset = card.width - buttons.mapToItem(card, buttons.width, 0).x
                if (!main.check(Math.abs(leftInset - rightInset) < 1, "Unequal icon/button outer spacing")) return
                for (const name of ["installAppButton", "openAppButton", "uninstallAppButton"]) {
                    const button = main.find(stack.currentItem, name)
                    if (button.visible && !main.check(button.width >= 176 && button.height >= 56, "Small touch target: " + name)) return
                }
                console.info("METADATA_PASS: " + app.id + " version=" + app.version + " artwork=" + logo.source)
                main.phase = "capture"
                stack.grabToImage(function(result) {
                    if (!main.check(result.saveToFile(Qt.resolvedUrl("../../target/metadata-" + app.id + ".png").toString().replace("file://", "")), "Capture failed")) return
                    main.showCatalog(); main.phase = ++main.index < main.ids.length ? "open" : "fallback"
                })
            } else if (main.phase === "fallback") {
                const app = main.catalog.find(item => item.id === main.ids[0])
                main.openApp(Object.assign({}, app, {icon: "file:///nonexistent/appcenter-metadata-test.png"}))
                main.phase = "verifyFallback"
            } else if (main.phase === "verifyFallback") {
                const logo = main.find(stack.currentItem, "appHeroIcon")
                if (logo.status === Image.Loading) return
                if (!main.check(logo.loadFailed && logo.status === Image.Ready, "Themed fallback not rendered")) return
                main.openApp(main.catalog.find(item => item.id === main.ids[0]))
                main.phase = "restored"
            } else if (main.phase === "restored") {
                const logo = main.find(stack.currentItem, "appHeroIcon")
                if (logo.status === Image.Loading) return
                if (!main.check(logo.status === Image.Ready && !logo.loadFailed, "Artwork failed to recover")) return
                main.phase = "done"
                console.info("METADATA_ALL_PASS: four apps, real versions/logos, themed fallback and recovery")
            }
        }
    }
    Timer { interval: 30000; running: main.phase !== "done"; onTriggered: main.check(false, "Timed out at " + main.phase) }
}
