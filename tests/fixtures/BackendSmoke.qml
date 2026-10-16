import QtQuick
import "../../qml" as App

// Real backend, read-only navigation. Does not enqueue operations or refresh
// sources; run with its own runtime directory to avoid the desktop's instance.
App.Main {
    id: window
    width: 1400; height: 950
    catalogStats: null
    property int step: 0
    property string captureName: "home"
    // Item captures omit the window's sibling backdrop. Include the identical
    // native-palette background so transparent pixels are not rendered black.
    property Component backdrop: Rectangle { color: window.backgroundColor }
    function stackItem(parent) {
        if (parent.objectName === "navigationStack") return parent
        for (const child of parent.children || []) {
            const found = stackItem(child)
            if (found) return found
        }
        return null
    }
    Timer {
        interval: 45000; running: true
        onTriggered: { console.error("RUST_SMOKE: timed out"); Qt.exit(1) }
    }
    Timer {
        id: ready
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (window.catalogLoading || window.installedLoading) return
            stop()
            if (!window.catalog.length) {
                console.error("RUST_SMOKE: no local applications found"); Qt.exit(1); return
            }
            console.warn("RUST_SMOKE: catalog", window.catalog.length, "installed", window.installedApps.length)
            const stack = window.stackItem(window.contentItem)
            stack.background = window.backdrop.createObject(stack)
            capture.start()
        }
    }
    Timer {
        id: capture
        interval: 600
        onTriggered: window.stackItem(window.contentItem).grabToImage(function(result) {
            const path = Qt.resolvedUrl("../../target/rust-smoke-" + window.captureName + ".png").toString().replace("file://", "")
            if (!result.saveToFile(path)) { console.error("RUST_SMOKE: capture failed"); Qt.exit(1); return }
            console.warn("RUST_SMOKE:", window.captureName, "captured")
            window.step++
            if (window.step === 1) { window.showUpdates(); window.captureName = "updates" }
            else if (window.step === 2) { window.showDownloads(); window.captureName = "queue" }
            else { Qt.quit(); return }
            capture.start()
        })
    }
}
