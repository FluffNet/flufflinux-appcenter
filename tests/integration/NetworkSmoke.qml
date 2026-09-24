// Real KDE rendering and catalog, simulated connection states only. This never
// disconnects the VM, starts an update check, or changes installed applications.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    networkStatus: previewNetwork
    QtObject { id: previewNetwork; property string state: "offline"; property bool ready: true }
    TestCase { id: probe; when: false }
    property int index: 0
    property bool prepared: false
    property bool capturing: false
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    readonly property var scenes: [
        {state:"offline", category:"All Apps", name:"offline-home"},
        {state:"offline", category:"Internet", name:"offline-category"},
        {state:"local", category:"All Apps", name:"lan-home"},
        {state:"limited", category:"All Apps", name:"limited-home"},
        {state:"portal", category:"All Apps", name:"portal-home"},
        {state:"limited", category:"Updates", name:"limited-updates"},
        {state:"offline", category:"Updates", name:"offline-updates"},
        {state:"online", category:"All Apps", name:"online-home"}
    ]
    function check(value, message) {
        if (!value) { console.error("NETWORK_UI_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    Timer {
        interval: 650; running: true; repeat: true
        onTriggered: {
            if (main.capturing || main.backend.installedLoading) return
            main.check(main.backend.updates.state === "idle", "No automatic update checks")
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            const page = stack.get(0), scene = main.scenes[main.index]
            if (!main.prepared) {
                if (!stack.background) stack.background = main.snapshotBackground.createObject(stack)
                // To show connection loss while Updates is already open.
                if (scene.category === "Updates") {
                    previewNetwork.state = "online"
                    main.showUpdates()
                } else page.openCategory(scene.category)
                previewNetwork.state = scene.state
                probe.findChild(page, "catalogGrid").positionViewAtBeginning()
                main.prepared = true
                return
            }
            if (main.catalogStats.state === "loading") return
            const offline = scene.state === "offline", updates = scene.category === "Updates"
            main.check(probe.findChild(page, "updatesButton").enabled === !offline, "Updates disabled only offline")
            main.check(probe.findChild(page, "catalogOfflineMessage").visible === (offline && !updates), "Offline replacement")
            main.check(probe.findChild(page, "catalogNetworkNote").visible === main.networkAdvisory, "Advisory note")
            if (offline && !updates) {
                const icon = probe.findChild(probe.findChild(page, "catalogOfflineMessage"), "networkWarningIcon")
                main.check(icon.status === Image.Ready, "KDE warning icon loaded")
            }
            if (updates) main.check(probe.findChild(page, "checkForUpdatesButton").enabled === !offline, "Check action availability")
            main.capturing = true
            const accepted = stack.grabToImage(function(result) {
                const filename = Qt.resolvedUrl("../../target/network-" + scene.name + ".png").toString().replace("file://", "")
                main.check(result.saveToFile(filename), "Save screenshot " + scene.name)
                console.log("NETWORK_CAPTURE", scene.name)
                main.index++; main.prepared = false; main.capturing = false
                if (main.index === main.scenes.length) { console.log("NETWORK_UI_PASS", "eight states captured; no app update checks"); Qt.quit() }
            })
            main.check(accepted, "Screenshot item has a QML rendering context")
        }
    }
    Timer { interval: 180000; running: true; onTriggered: { console.error("NETWORK_UI_TIMEOUT"); Qt.exit(3) } }
}
