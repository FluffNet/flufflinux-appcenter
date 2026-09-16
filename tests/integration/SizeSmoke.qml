// Run with the real App Center executable, not qmltestrunner's mock backend:
// FLUFF_APP_CENTER_QML="$PWD/tests/integration/SizeSmoke.qml" target/release/flufflinux-appcenter
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1240; height: 820
    property var ids: ["com.play0ad.zeroad", "com.onepassword.OnePassword",
                       "io.github.mezoahmedii.Picker", "org.kde.krita", "org.gnome.Calculator",
                       "com.discordapp.Discord"]
    property int testIndex: 0
    property double started: 0
    property string phase: "start"
    property bool failed: false

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
        failed = true
        console.error("SIZE_UI_FAIL: " + message)
        Qt.exit(1)
        return false
    }
    Timer {
        interval: 16; repeat: true; running: !main.failed
        onTriggered: {
            if (main.installedLoading) return
            if (main.phase === "start") {
                if (!main.check(main.backend && typeof main.backend.requestInstallInfo === "function",
                                "Executable is missing the size API; interface and executable do not match")) return
                const app = main.catalog.find(item => item.id === main.ids[main.testIndex])
                if (!main.check(!!app && !main.findInstalled(app), "Missing/already installed test app")) return
                // App IDs avoid ambiguous names such as the many Calculators.
                main.searchText = app.id
                main.phase = "click"
            } else if (main.phase === "click") {
                const grid = main.find(main.contentItem, "catalogGrid")
                const card = grid ? grid.itemAtIndex(0) : null
                if (!card || card.app.id !== main.ids[main.testIndex]) return
                main.started = Date.now()
                card.clicked()
                main.phase = "visible"
            } else if (main.phase === "visible") {
                const stack = main.find(main.contentItem, "navigationStack")
                if (stack.busy) return
                const appLabel = main.find(stack.currentItem, "appDownloadSize")
                const totalLabel = main.find(stack.currentItem, "totalDownloadSize")
                const sizes = main.backend.installSizes[main.ids[main.testIndex]] || ({})
                const elapsed = Date.now() - main.started
                if (!main.check(sizes.state === "ready" && appLabel && totalLabel
                                && appLabel.visible && totalLabel.visible === (sizes.appBytes !== sizes.totalBytes)
                                && appLabel.text === sizes.appSize && totalLabel.text === sizes.totalSize,
                                "The actual page did not display both real sizes: " + JSON.stringify(sizes))) return
                if (!main.check(elapsed < 500, "Click-to-visible took " + elapsed + " ms")) return
                console.info("SIZE_UI_PASS: " + main.ids[main.testIndex] + " " + elapsed + " ms " + JSON.stringify(sizes))
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    const filename = Qt.resolvedUrl("../../target/size-proof-" + main.ids[main.testIndex] + ".png").toString().replace("file://", "")
                    if (!main.check(result.saveToFile(filename), "Could not save screenshot")) return
                    main.showCatalog()
                    main.phase = "return"
                })
            } else if (main.phase === "return") {
                const stack = main.find(main.contentItem, "navigationStack")
                if (stack.busy) return
                if (++main.testIndex === main.ids.length) {
                    console.info("SIZE_UI_ALL_PASS")
                    Qt.quit()
                } else main.phase = "start"
            }
        }
    }
    Timer {
        interval: 20000; running: true
        onTriggered: main.check(false, "Real-application UI test timed out at " + main.phase + ": " + main.ids[main.testIndex])
    }
}
