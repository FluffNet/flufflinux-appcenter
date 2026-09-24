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
                // A normal check need not publish sources when no recovery is
                // necessary. Load them explicitly before checking the grouping.
                main.backend.refreshSources(); main.stage = 1
            } else if (main.stage === 1 && !main.backend.sourcesBusy) {
                main.showUpdates(); main.stage = 2
            } else if (main.stage === 2) {
                probe.mouseClick(probe.findChild(main, "checkForUpdatesButton")); main.stage = 3
            } else if (main.stage === 3 && main.backend.updates.state !== "checking") {
                const result = main.backend.updates
                const sources = main.backend.repositories.map(source => ({
                    name:source.name, scope:source.scope, hasUser:source.hasUser, hasSystem:source.hasSystem,
                    members:(source.members || []).map(member => ({name:member.name, scope:member.scope, url:member.url}))
                }))
                console.log("SYSTEM_SOURCE_RESULT", JSON.stringify({state:result.state, skipped:result.skipped,
                    error:result.error, sources:sources,
                    updates:result.items.map(row => ({id:row.id, installation:row.installation, remote:row.remote}))}))
                const passed = result.state === "ready" && !result.error && !(result.skipped || []).length
                    && sources.some(source => source.name === "flathub" && source.hasSystem && source.hasUser)
                console.log(passed ? "SYSTEM_SOURCE_PASS" : "SYSTEM_SOURCE_FAIL")
                main.stage = 4
                Qt.exit(passed ? 0 : 5)
            }
        }
    }
    Timer { interval: 210000; running: true; onTriggered: Qt.exit(6) }
}
