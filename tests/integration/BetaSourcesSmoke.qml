// Read-only native-themed captures. The empty-source page uses a fake backend;
// no real repositories, installations or user preferences are modified.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    property int stage: 0
    TestCase { id: probe; when: false }
    QtObject {
        id: emptyBackend
        property var jobs: []
        property var review: ({})
        property var repositories: []
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        property string sourcesError: ""
        function refreshSources() {}
    }
    function capture(name, next) {
        stage = -1
        const about = probe.findChild(main, "aboutDialog")
        const add = probe.findChild(main, "addSourceDialog")
        const target = about.visible ? about.contentItem : add && add.visible ? add.contentItem
            : probe.findChild(main, "navigationStack")
        target.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/beta-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(1); return }
            stage = next
        })
    }
    Timer {
        interval: 450; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy || main.installedLoading || main.backend.sourcesBusy) return
            if (main.stage === 0) { main.showAbout(); main.stage = 1 }
            else if (main.stage === 1) {
                if (probe.findChild(main, "aboutVersion").text !== "Version 2026.09 (Beta)") { Qt.exit(2); return }
                main.capture("about", 2)
            } else if (main.stage === 2) {
                probe.findChild(main, "aboutDialog").close(); main.showSettings(); main.stage = 3
            } else if (main.stage === 3) {
                if (!main.backend.repositories.some(row => row.name === "flathub" && row.scope === "merged")) { Qt.exit(3); return }
                main.capture("merged-sources", 4)
            } else if (main.stage === 4) { main.width = 720; main.height = 620; main.stage = 5 }
            else if (main.stage === 5) { main.capture("sources-narrow", 6) }
            else if (main.stage === 6) {
                main.backend = emptyBackend
                probe.findChild(stack.currentItem, "addSourceButton").clicked(); main.stage = 7
            } else if (main.stage === 7) {
                if (!probe.findChild(main, "addDefaultSourcesButton").visible) { Qt.exit(4); return }
                main.capture("add-defaults", 8)
            } else if (main.stage === 8) {
                console.info("BETA_SOURCES_SMOKE_PASS: native version, merged Flathub, narrow Settings, default-source dialog")
                Qt.quit()
            }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(5) }
}
