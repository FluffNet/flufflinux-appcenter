// Real Rust manager and Qt property transport; isolated simulated workers.
import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as App

App.Main {
    id: main
    width: 1180; height: 900; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state:"online", ready:true})
    property int phase: 0
    property int completed: 0
    property int progressSamples: 0
    property int queuedSamples: 0
    property int afterRemovalSamples: 0
    property int plannedSamples: 0
    property bool captured: false
    property bool captureDone: false
    property var originalRows: []
    property var originalPlans: []
    property var captureArea: null
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    function check(value, message) {
        if (!value) { console.error("UPDATE_ROWS_FAIL", message); Qt.exit(1); throw new Error(message) }
    }
    function updatesPage() {
        return probe.findChild(probe.findChild(main,"navigationStack").get(0), "updatesPage")
    }
    Timer {
        interval: 60000; running: true
        onTriggered: { console.error("UPDATE_ROWS_TIMEOUT", main.phase); Qt.exit(1) }
    }
    Timer {
        interval: 16; repeat: true; running: true
        onTriggered: {
            if (main.phase === 0) {
                if (main.catalogLoading || main.installedLoading || main.backend.busy || !main.catalog.length) return
                main.showUpdates(); main.backend.checkForUpdates(); main.phase = 1
                main.captureArea = probe.findChild(main, "navigationStack")
                main.captureArea.background = main.snapshotBackground.createObject(main.captureArea)
            } else if (main.phase === 1) {
                if (main.backend.updateStatus.state !== "ready" || main.backend.busy) return
                main.check(main.updateItems.length >= 4, "At least four real QVariant update rows")
                const lastKey = main.updateItems[main.updateItems.length - 1].key
                main.backend.selectUpdate(lastKey, false)
                main.backend.selectUpdate(lastKey, true)
                main.originalRows = main.updateItems.slice()
                main.originalPlans = main.updateItems.map(row => JSON.stringify(row.plan))
                main.backend.installSelectedUpdates(); main.phase = 2
            } else if (main.phase === 2) {
                const page = main.updatesPage()
                main.check(!probe.findChild(page, "updateSelectionControls").visible || !page.updating,
                           "Selection summary hidden during updates")
                const finished = main.backendJobs.filter(job => !job.active && !job.failed).length
                main.completed = Math.max(main.completed, finished)
                // QVariant-backed nested values must remain snapshots even as
                // the native sequence loses rows at its beginning and middle.
                for (let i = 0; i < main.originalRows.length; ++i) {
                    main.check(JSON.stringify(main.originalRows[i].plan) === main.originalPlans[i],
                               "Retained plan changed at original row " + i + " after " + finished + " completions")
                }
                for (const row of main.updateItems) {
                    const job = page.jobFor(row)
                    main.check(!!job, "Missing queued/progress job for " + row.key)
                    if (job.active && job.queued) ++main.queuedSamples
                    if (job.active && !job.queued) {
                        ++main.progressSamples
                        if (finished) ++main.afterRemovalSamples
                        if (job.operations && job.operations.length) ++main.plannedSamples
                    }
                }
                const downloading = main.updateItems.some(row => {
                    const job = page.jobFor(row)
                    return job && job.active && !job.queued && job.hasDownload && job.phase === "download"
                })
                if (finished && downloading && !main.captured) {
                    main.captured = true
                    main.check(main.captureArea.grabToImage(function(result) {
                        const filename = Qt.resolvedUrl("../target/update-progress-fixed-" + Qt.locale().name + ".png").toString().replace("file://", "")
                        main.check(result.saveToFile(filename), "Save progress after first completion")
                        main.captureDone = true
                    }), "Capture progress after first completion")
                }
                if (!main.backend.busy) {
                    if (!main.captureDone) return
                    main.check(main.completed === main.originalRows.length, "Every queued app completed")
                    main.check(main.updateItems.length === 0, "Completed rows removed")
                    main.check(main.progressSamples > 0 && main.queuedSamples > 0, "Active and queued jobs observed")
                    main.check(main.plannedSamples > 0, "Resolved operations reach the page progress display")
                    main.check(main.afterRemovalSamples > 0, "Progress survives the first completion")
                    console.info("UPDATE_ROWS_PASS", main.completed, main.progressSamples, main.queuedSamples, main.afterRemovalSamples, main.plannedSamples)
                    main.phase = 3; Qt.quit()
                }
            }
        }
    }
}
