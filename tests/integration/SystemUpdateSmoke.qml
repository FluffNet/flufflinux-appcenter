// Opt-in REAL system Firefox update, never part of the automatic test suite.
// Run only after user authorization and preserving the current Firefox release.
// Uses the ordinary desktop user's backend/worker and existing Flatpak helper.
// No passwords, review acceptance, source configuration, or policy changes.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    property int stage: 0
    property var selectedUpdate: null
    property string oldVersion: ""
    TestCase { id: probe; when: false }
    function fail(reason) {
        console.log("SYSTEM_UPDATE_FAIL", reason)
        stage = -1
        backend.cancelAll()
        Qt.exit(1)
    }
    Timer {
        interval: 350; running: main.stage >= 0; repeat: true
        onTriggered: {
            if (!main.backend || main.backend.installedLoading) return
            if (main.backend.review && main.backend.review.token) {
                main.fail("Unexpected confirmation; no automatic approval")
                return
            }
            if (main.stage === 0 && !main.backend.busy) {
                const installed = main.backend.installedApps.find(app => app.id === "org.mozilla.firefox"
                    && app.installation === "system" && app.installedBranch === "stable")
                if (!installed) { main.fail("System Firefox is not installed"); return }
                main.oldVersion = installed.installedVersion
                main.showUpdates(); main.stage = 1
            } else if (main.stage === 1) {
                probe.mouseClick(probe.findChild(main, "checkForUpdatesButton")); main.stage = 2
            } else if (main.stage === 2 && main.backend.updates.state !== "checking") {
                const result = main.backend.updates
                const row = result.items.find(app => app.id === "org.mozilla.firefox"
                    && app.installation === "system" && app.remote === "flathub"
                    && app.flatpakRef === "app/org.mozilla.firefox/x86_64/stable")
                if (result.state !== "ready" || result.error || !row) {
                    main.fail("No successfully checked system Firefox update"); return
                }
                if (row.oldVersion !== main.oldVersion || row.permissions.state !== "unchanged"
                        || row.plan.some(op => op.ref.startsWith("app/") && op.ref !== row.flatpakRef)) {
                    main.fail("Unexpected version, permissions or additional application"); return
                }
                main.selectedUpdate = row
                main.backend.selectAllUpdates(false)
                main.backend.selectUpdate(row.key, true)
                console.log("SYSTEM_UPDATE_START", JSON.stringify({key:row.key, from:row.oldVersion,
                    to:row.newVersion, commit:row.commit, plan:row.plan}))
                probe.mouseClick(probe.findChild(main, "installUpdatesButton")); main.stage = 3
            } else if (main.stage === 3 && !main.backend.busy) {
                const jobs = main.backend.jobs.filter(job => job.action === "update")
                if (jobs.length !== 1 || jobs[0].key !== main.selectedUpdate.key || jobs[0].failed
                        || jobs[0].cancelled || jobs[0].progress !== 1) {
                    main.fail(JSON.stringify(jobs)); return
                }
                const installed = main.backend.installedApps.find(app => app.id === "org.mozilla.firefox"
                    && app.installation === "system")
                if (!installed || installed.installedVersion !== main.selectedUpdate.newVersion
                        || !installed.updatedAt) {
                    main.fail("Installed version or persisted update date did not refresh"); return
                }
                console.log("SYSTEM_UPDATE_PASS", JSON.stringify({from:main.oldVersion,
                    to:installed.installedVersion, updatedAt:installed.updatedAt, installation:installed.installation}))
                main.stage = -1
                Qt.quit()
            }
        }
    }
    Timer { interval: 600000; running: main.stage >= 0; onTriggered: main.fail("Timed out") }
}
