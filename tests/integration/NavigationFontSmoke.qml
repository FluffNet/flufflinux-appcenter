// Real launcher/font/icon integration, fixture data only. No transactions or
// preference writes. Capture multiple window sizes and pointer-dismissal states.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; minimumWidth: 1; minimumHeight: 1
    visible: true
    palette.window: "#202326"; palette.windowText: "#ffffff"; palette.placeholderText: "#a5a9ad"
    property int stage: 0
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    backend: QtObject {
        property var jobs: []
        property var review: ({})
        property var installedApps: Array.from({length:7}, (_, i) => ({
            id:"org.example.Font" + i, name:"Flatpak Builder Flatpak " + i, icon:"application-x-executable",
            installedOrigin:"flathub", installation:"default", installedSize:"319.62 MiB",
            installedVersion:"v0-Flathub", screenshots:[], summary:"", description:"", category:""
        }))
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        property string sourcesError: ""
        property var repositories: [{name:"flathub", title:"Flathub", scope:"user", enabled:true, verified:true, url:"https://dl.flathub.org/repo/"}]
        function refreshSources() {}
    }
    function capture(item, name, next) {
        stage = -1
        item.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/navigation-font-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(1); return }
            stage = next
        })
    }
    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy) return
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                main.selectedCategory = "Installed"; main.stage = 1
            } else if (main.stage === 1) { main.capture(stack, "wide", 2) }
            else if (main.stage === 2) { main.width = 720; main.height = 520; main.stage = 3 }
            else if (main.stage === 3) { main.capture(stack, "compact", 4) }
            else if (main.stage === 4) { main.width = 640; main.height = 360; main.stage = 5 }
            else if (main.stage === 5) { main.capture(stack, "short", 6) }
            else if (main.stage === 6) { main.width = 1180; main.height = 760; main.showSettings(); main.stage = 7 }
            else if (main.stage === 7) { main.capture(stack, "information-icon", 8) }
            else if (main.stage === 8) { probe.findChild(stack.currentItem, "sourceDetailsButton").clicked(); main.stage = 9 }
            else if (main.stage === 9) {
                if (probe.findChild(main, "closeSourceDetailsButton").activeFocus) { Qt.exit(2); return }
                main.capture(probe.findChild(main, "sourceDetailsDialog").contentItem.parent, "information-dialog", 10)
            } else if (main.stage === 10) {
                probe.findChild(main, "closeSourceDetailsButton").clicked()
                main.showCatalog(); main.stage = 11
            } else if (main.stage === 11) { probe.mouseClick(probe.findChild(main, "applicationMenuButton")); main.stage = 12 }
            else if (main.stage === 12) { probe.mouseClick(main.contentItem, main.width - 20, main.height - 20); main.stage = 13 }
            else if (main.stage === 13) {
                if (probe.findChild(main, "applicationMenuButton").activeFocus) { Qt.exit(3); return }
                main.capture(stack, "dismissed-menu", 14)
            } else if (main.stage === 14) { Qt.quit() }
        }
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.exit(100 + main.stage) }
}
