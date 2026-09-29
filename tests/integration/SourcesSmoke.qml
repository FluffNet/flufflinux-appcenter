// Read-only visual fixture with native icons. Source listing and installed
// metadata are real; the alternate app source is synthetic. Never mutates a
// repository or starts an install/removal transaction.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    property int stage: 0
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of (item.children || [])) { const found = find(child, name); if (found) return found }
        return null
    }
    function capture(name, next) {
        stage = -1
        find(contentItem, "navigationStack").grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/sources-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(1); return }
            stage = next
        })
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            const stack = main.find(main.contentItem, "navigationStack")
            if (main.stage < 0 || stack.busy || main.installedLoading || main.backend.sourcesBusy) return
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                main.stage = 1
            } else if (main.stage === 1) {
                main.capture("menu", 2)
            } else if (main.stage === 2) {
                main.showSettings(); main.stage = 3
            } else if (main.stage === 3) {
                main.capture("settings", 4)
            } else if (main.stage === 4) {
                main.width = 720; main.height = 620; main.stage = 5
            } else if (main.stage === 5) {
                main.capture("settings-narrow", 6)
            } else if (main.stage === 6) {
                main.width = 1180; main.height = 760
                const app = main.catalog.find(item => item.id === "com.play0ad.zeroad")
                if (!app) { console.error("SOURCES_SMOKE_FAIL: catalog missing"); Qt.exit(1); return }
                const beta = Object.assign({}, app, {sources:[], remote:"flathub-beta", version:"Preview", flatpakRef:"app/com.play0ad.zeroad/x86_64/beta"})
                main.openApp(Object.assign({}, app, {sources:[app,beta]})); main.stage = 7
            } else if (main.stage === 7) {
                main.stage = 8
            } else if (main.stage === 8) {
                main.capture("picker", 9)
            } else if (main.stage === 9) {
                main.showCatalog(); main.selectedCategory = "Installed"; main.stage = 10
            } else if (main.stage === 10) {
                main.capture("installed", 11)
            } else if (main.stage === 11) {
                console.info("SOURCES_SMOKE_PASS: menu, Settings at two widths, source chooser, installed origins")
                Qt.quit()
            }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: { console.error("SOURCES_SMOKE_FAIL: timeout"); Qt.exit(1) } }
}
