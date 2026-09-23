// Opt-in real-desktop recovery check. May add the official system Flathub
// source through Polkit; never installs or updates applications.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    property int stage: 0
    TestCase { id: probe; when: false }
    Timer {
        interval: 350; running: true; repeat: true
        onTriggered: {
            if (!main.backend || main.backend.installedLoading) return
            if (main.stage === 0 && !main.backend.busy) {
                main.showUpdates(); main.stage = 1
            } else if (main.stage === 1) {
                probe.mouseClick(probe.findChild(main, "checkForUpdatesButton")); main.stage = 2
            } else if (main.stage === 2 && main.backend.updates.state !== "checking") {
                const result = main.backend.updates
                const sources = main.backend.repositories.map(source => ({
                    name:source.name, scope:source.scope, hasUser:source.hasUser, hasSystem:source.hasSystem,
                    members:(source.members || []).map(member => ({name:member.name, scope:member.scope, url:member.url}))
                }))
                console.log("SYSTEM_SOURCE_RESULT", JSON.stringify({state:result.state, skipped:result.skipped,
                    error:result.error, sources:sources,
                    updates:result.items.map(row => ({id:row.id, installation:row.installation, remote:row.remote}))}))
                main.stage = 3
                Qt.exit(sources.some(source => source.name === "flathub" && source.hasSystem && source.hasUser) ? 0 : 5)
            }
        }
    }
    Timer { interval: 210000; running: true; onTriggered: Qt.exit(6) }
}
