// Real catalog/native icon provider, simulated queue only. No transactions.
import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as App

App.Main {
    id: main
    width: 1180; height: 800; visible: true
    backend: mock
    catalogPreferences: null
    catalogStats: null
    // Mock connectivity only. No update check or transaction is invoked.
    networkStatus: ({state: "online", ready: true})
    property int tick: 0
    property var queueItems: []
    property double lastTick: 0
    property double longestPause: 0
    property int cycles: 1
    property int completedCycles: 0
    QtObject {
        id: mock
        property var catalog: fluffBackend.catalog
        property bool catalogLoading: fluffBackend.catalogLoading
        property var installedApps: fluffBackend.installedApps
        property bool installedLoading: fluffBackend.installedLoading
        property string installedError: ""
        property int iconRevision: 0
        property var jobs: []
        property var review: ({})
        property var updates: ({state: "ready", items: []})
        property bool busy: false
        property var installSizes: fluffBackend.installSizes
        property var appPermissions: ({state: "idle", groups: []})
        property var appAddons: ({state: "idle", items: []})
        signal appOpened(var app)
        signal inputError(string message)
        function requestInstallInfo(app) { fluffBackend.requestInstallInfo(app) }
        function requestAppPermissions(app) { return 1 }
        function cancelAppPermissions(token) {}
    }
    TestCase { id: probe; when: false }
    function stack() { return probe.findChild(main, "navigationStack") }
    Timer {
        interval: 20; repeat: true; running: true
        onTriggered: {
            if (!main.catalog.length || mock.catalogLoading || mock.installedLoading) return
            const now = Date.now()
            if (main.lastTick) main.longestPause = Math.max(main.longestPause, now - main.lastTick)
            main.lastTick = now
            if (main.tick === 0) {
                for (let index = 0; index < 200; ++index) {
                    const app = main.catalog[index % main.catalog.length]
                    const plan = []
                    for (let part = 0; part < 12; ++part)
                        plan.push({ref: "runtime/org.example.Shared" + part + "/x86_64/stable",
                            commit: "0123456789abcdef".repeat(4), downloadBytes: 100000000,
                            progress: 0.5, downloadProgress: 0.5, receivedBytes: 50000000})
                    main.queueItems.push(Object.assign({}, app, {index: index, key: "test:" + index,
                        action: "update", active: true, queued: index > 0, selected: true,
                        installation: "user", remote: "flathub", plan: plan, operations: plan,
                        permissions: {state: "unchanged", groups: []},
                        queuePosition: index + 1, queueTotal: 200, progress: 0.5}))
                }
                mock.jobs = main.queueItems.slice()
                mock.updates = {state: "ready", items: main.queueItems.slice()}
                mock.busy = true
                main.showUpdates()
                if (main.selectedCategory !== "Updates") {
                    console.error("MEMORY_UPDATES_NAVIGATION_FAILED")
                    Qt.exit(1)
                    return
                }
                console.log("MEMORY_PHASE updates", main.catalog.length)
            } else if (main.tick === 250) {
                main.showDownloads()
                console.log("MEMORY_PHASE queue")
            } else if (main.tick === 500) {
                main.openApp(main.catalog[0])
                console.log("MEMORY_PHASE details")
            } else if (main.tick === 750) {
                main.showDownloads()
                mock.jobs = main.queueItems.map(job => Object.assign({}, job, {active: false, progress: 1}))
                mock.busy = false
                console.log("MEMORY_PHASE completed")
            } else if (main.tick === 1000) {
                main.showCatalog()
                mock.jobs = []; mock.updates = {state: "ready", items: []}
                main.queueItems = []
                console.log("MEMORY_PHASE cleared")
            } else if (main.tick >= 2000) {
                ++main.completedCycles
                console.log("MEMORY_CYCLE", main.completedCycles)
                if (main.completedCycles < main.cycles) {
                    main.tick = 0
                    return
                }
                console.log("MEMORY_RESULT", JSON.stringify({longestPauseMs: main.longestPause,
                    passed: main.longestPause < 1000}))
                Qt.exit(main.longestPause < 1000 ? 0 : 1)
                return
            }
            if (main.tick === 375)
                stack().currentItem.grabToImage(function(frame) {
                    if (!frame.saveToFile("target/queue-memory-200.png")) console.error("MEMORY_CAPTURE_FAILED")
                })
            if (main.tick > 0 && main.tick < 750) {
                const jobs = main.queueItems.slice()
                jobs[0] = Object.assign({}, jobs[0], {progress: (main.tick % 100) / 100})
                mock.jobs = jobs
            }
            const view = probe.findChild(stack().currentItem, "downloadJobs")
            if (view && main.tick % 50 === 0 && view.count) {
                if (view.positionViewAtIndex) {
                    view.positionViewAtIndex(main.tick % 100 === 0 ? 199 : 0, ListView.Beginning)
                } else {
                    // The pre-virtualization baseline used a Repeater in a Flickable.
                    let scroll = view.parent
                    while (scroll && typeof scroll.contentY !== "number") scroll = scroll.parent
                    if (scroll) scroll.contentY = main.tick % 100 === 0
                        ? Math.max(0, scroll.contentHeight - scroll.height) : 0
                }
            }
            ++main.tick
        }
    }
}
