// Native executable/icon provider with fake source/job data and read-only
// installed metadata. Run with a separate XDG_RUNTIME_DIR, at 100% and 150%.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 900; visible: true
    palette.window: "#202326"
    palette.windowText: "#ffffff"
    palette.placeholderText: "#a5a9ad"
    property int stage: 0
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    backend: fixture
    TestCase { id: probe; when: false }
    QtObject {
        id: fixture
        property var jobs: []
        property var review: ({})
        property var installedApps: fluffBackend.installedApps
        property bool installedLoading: fluffBackend.installedLoading
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        property string sourceInputStatus: ""
        property string sourcesError: ""
        property var repositories: [
            {name:"flathub", title:"Flathub", scope:"user", enabled:true, verified:true, url:"https://dl.flathub.org/repo/"},
            {name:"testing", title:"Testing", scope:"user", enabled:false, verified:true, url:"https://example.org/repo/"},
            {name:"system", title:"System source", scope:"default", enabled:true, verified:true, url:"https://example.org/system/"}
        ]
        function refreshSources() {}
    }
    function capture(item, name, next) {
        stage = -1
        item.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/source-ui-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(1); return }
            stage = next
        })
    }
    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy || fixture.installedLoading) return
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                probe.mouseClick(probe.findChild(main, "applicationMenuButton")); main.stage = 13
            }
            else if (main.stage === 13) { main.capture(probe.findChild(main, "applicationMenu").contentItem.parent, "menu", 14) }
            else if (main.stage === 14) { probe.findChild(main, "applicationMenu").close(); main.showSettings(); main.stage = 1 }
            else if (main.stage === 1) { main.capture(stack, "checkboxes", 2) }
            else if (main.stage === 2) { probe.findChild(stack.currentItem, "sourceDetailsButton").clicked(); main.stage = 3 }
            else if (main.stage === 3) { main.capture(probe.findChild(main, "sourceDetailsDialog").contentItem.parent, "details", 4) }
            else if (main.stage === 4) {
                probe.findChild(main, "closeSourceDetailsButton").clicked()
                fixture.sourceInputStatus = "Checking software source…"; fixture.busy = true; main.stage = 11
            } else if (main.stage === 5) { main.capture(probe.findChild(main, "addSourceDialog").contentItem.parent, "add", 6) }
            else if (main.stage === 6) {
                probe.findChild(main, "cancelAddSourceButton").clicked()
                main.showCatalog(); main.selectedCategory = "Installed"; main.stage = 7
            } else if (main.stage === 7) { main.capture(stack, "installed", 8) }
            else if (main.stage === 8) {
                fixture.jobs = [{index:0, id:"org.example.Local", name:"Local Flatpak", active:true,
                    queued:true, progress:0, action:"source", status:"Pending…", operations:[]}]
                main.showDownloads(); main.stage = 9
            } else if (main.stage === 9) { main.capture(stack, "queue", 10) }
            else if (main.stage === 10) { Qt.quit() }
            else if (main.stage === 11) { main.capture(stack, "checking", 12) }
            else if (main.stage === 12) {
                fixture.sourceInputStatus = ""; fixture.busy = false
                probe.findChild(main, "addSourceButton").clicked(); main.stage = 5
            }
        }
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.exit(5) }
}
