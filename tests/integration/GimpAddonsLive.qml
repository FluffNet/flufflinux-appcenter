// Real Flathub catalog and installed GIMP. Installs only its compatible Fourier
// add-on when absent; never launches GIMP or removes any app/plugin/data.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760
    property int stage: 0
    property bool capturing: false
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    function check(ok, message) {
        if (!ok) { console.error("GIMP_ADDONS_FAIL: " + message); Qt.exit(2); throw new Error(message) }
    }
    function capture(item, name, next) {
        capturing = true
        check(item.grabToImage(function(result) {
            main.check(result.saveToFile("/tmp/appcenter-gimp-addons-" + name + ".png"), "Save " + name)
            console.info("GIMP_ADDONS_CAPTURE: " + name)
            main.stage = next; main.capturing = false
        }), "Capture " + name)
    }
    Timer {
        interval: 650; running: true; repeat: true
        onTriggered: {
            if (main.capturing || !main.backend || main.backend.installedLoading) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            const page = stack.currentItem
            const dialog = probe.findChild(page, "appAddonsDialog")
            if (main.stage === 0) {
                const app = main.backend.installedApps.find(app => app.id === "org.gimp.GIMP" && app.installation === "user")
                main.check(!!app, "GIMP must already be installed for this demonstration")
                stack.background = main.snapshotBackground.createObject(stack)
                main.openApp(app); main.stage = 1
            } else if (main.stage === 1) {
                const scroll = probe.findChild(page, "detailsFlickable")
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height); main.stage = 2
            } else if (main.stage === 2) main.capture(stack, "button", 3)
            else if (main.stage === 3) {
                probe.mouseClick(probe.findChild(page, "viewAppAddonsButton")); main.stage = 4
            } else if (main.stage === 4) {
                if (main.backend.appAddons.state === "loading") return
                main.check(main.backend.appAddons.state === "ready", JSON.stringify(main.backend.appAddons))
                const rows = main.backend.appAddons.items
                const index = rows.findIndex(row => row.id === "org.gimp.GIMP.Plugin.Fourier")
                main.check(index >= 0, "A compatible Fourier add-on is available")
                const row = rows[index]
                main.check(row.available && row.installation === "user", "Fourier comes from GIMP's user source")
                console.info("GIMP_ADDONS_REAL_ROWS: " + JSON.stringify(rows.map(row => ({name:row.name, ref:row.flatpakRef, installed:row.installed}))))
                if (!row.installed) {
                    const item = probe.findChild(dialog, "addonRows").itemAt(index)
                    const button = probe.findChild(item, "addonActionButton")
                    main.check(button.downloadArrow, "Use app page's install arrow")
                    probe.mouseClick(button)
                }
                main.stage = 5
            } else if (main.stage === 5) {
                if (main.backend.busy || main.backend.appAddons.state === "loading") return
                main.check(dialog.opened && main.backend.appAddons.state === "ready", "Dialog remains open after install")
                const index = main.backend.appAddons.items.findIndex(row => row.id === "org.gimp.GIMP.Plugin.Fourier")
                main.check(main.backend.appAddons.items[index].installed, "Fourier installation succeeded")
                const button = probe.findChild(probe.findChild(dialog, "addonRows").itemAt(index), "addonActionButton")
                main.check(button.icon.source.toString().endsWith("/trash-red.svg"), "Use app page's uninstall icon")
                main.capture(dialog.contentItem.parent, "dark", 6)
            } else if (main.stage === 6) {
                main.palette.window = "#eff0f1"; main.palette.windowText = "#232629"; main.palette.placeholderText = "#606970"
                main.stage = 7
            } else if (main.stage === 7) main.capture(dialog.contentItem.parent, "light", 8)
            else if (main.stage === 8) {
                console.info("PASS: real GIMP add-ons, Fourier installed through dialog, shared install/remove icons, dark/light screenshots")
                Qt.quit()
            }
        }
    }
    Timer { interval: 120000; running: true; onTriggered: { console.error("GIMP_ADDONS_TIMEOUT: " + main.stage); Qt.exit(3) } }
}
