// Driven by test_source_picker.py on a private bus. Uses the real source dialog
// and real Qt/KDE portal integration, but cannot add a source or install an app.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visible: true
    backend: fixture
    property int stage: 0
    property string acceptedPath: ""
    TestCase { id: probe; when: false }
    QtObject {
        id: fixture
        property var repositories: []
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        property string sourcesError: ""
        function refreshSources() {}
        function openSource(source) { Qt.exit(9) }
    }
    Timer {
        interval: 150; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            if (main.stage === 0) { main.showSettings(); main.stage = 1; return }
            const page = stack.currentItem
            const dialog = probe.findChild(page, "addSourceDialog")
            const picker = probe.findChild(page, "sourceFileDialog")
            const input = probe.findChild(page, "sourceInput")
            if (main.stage === 1) {
                probe.findChild(page, "addSourceButton").clicked(); main.stage = 2
            } else if (main.stage === 2 && dialog.opened) {
                probe.findChild(page, "chooseSourceFileButton").clicked(); main.stage = 3
            } else if (main.stage === 3 && !picker.visible) {
                if (!input.text.startsWith("file:///") || !decodeURI(input.text).endsWith("/source picker fixture.flatpakrepo")) { Qt.exit(22); return }
                main.acceptedPath = input.text
                probe.findChild(page, "chooseSourceFileButton").clicked(); main.stage = 4
            } else if (main.stage === 4 && !picker.visible) {
                if (input.text !== main.acceptedPath) { Qt.exit(3); return }
                if (main.downloadQueue.jobs.length) { Qt.exit(4); return }
                probe.findChild(page, "cancelAddSourceButton").clicked()
                Qt.quit()
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: Qt.exit(5) }
}
