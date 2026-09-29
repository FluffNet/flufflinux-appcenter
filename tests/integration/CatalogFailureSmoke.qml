// Production backend and UI. The runner isolates Flatpak data and simulates
// NM state on a private bus; a refusing proxy blocks the real Flathub pull.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1280; height: 850; visible: true
    catalogStats: null
    catalogPreferences: null
    TestCase { id: probe; when: false }
    property bool capturing: false
    property int readyFrames: 0
    property Component backdrop: Rectangle { color: main.backgroundColor }
    function check(value, text) {
        if (!value) { console.error("CAPTURE_FAIL", text); Qt.exit(1); throw new Error(text) }
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (!main.networkReady || main.capturing) return
            const offline = main.networkOffline
            if (!offline && main.backend.catalogLoading) return
            if (++main.readyFrames < 4) return
            main.check(main.catalog.length === 0, "No old list displayed")
            main.check(main.backend.jobs.length === 0, "Source refresh is not an install/update notification job")
            main.check(main.backend.updates.state === "idle", "No app update check")
            main.check(!main.backend.sourcesBusy, "No active refresh at capture")
            if (!offline) {
                main.check(main.networkState === "local", "LAN connection remains allowed")
                main.check(main.backend.catalogSourcesUnavailable, "Actual worker failure reaches UI")
                main.check(main.backend.sourcesError.toLowerCase().indexOf("flathub") >= 0, "Failure names Flathub")
                console.log("REAL_SOURCE_ERROR", main.backend.sourcesError)
            }
            const stack = probe.findChild(main, "navigationStack")
            if (!stack.background) stack.background = main.backdrop.createObject(stack)
            const updates = probe.findChild(stack, "updatesButton")
            main.check(updates.enabled === !offline, "Only fully offline disables App Updates")
            main.capturing = true
            stack.grabToImage(function(result) {
                const name = offline ? "cache-fully-offline.png" : "cache-lan-source-failure.png"
                main.check(result.saveToFile(Qt.resolvedUrl("../../target/" + name).toString().replace("file://", "")), "Save capture")
                console.log("CATALOG_FAILURE_CAPTURE", name)
                Qt.quit()
            })
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(2) }
}
