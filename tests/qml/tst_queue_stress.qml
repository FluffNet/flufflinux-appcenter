import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    id: testCase
    name: "QueueStress"
    when: main.visible
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property var installSizes: ({})
        signal appOpened(var app)
        signal inputError(string message)
    }
    AppCenter.Main { id: main; backend: backend; visible: true; width: 1180; height: 800 }
    property double lastBeat: 0
    property double longestPause: 0
    Timer {
        interval: 16; repeat: true; running: true
        onTriggered: {
            const now = Date.now()
            if (testCase.lastBeat) testCase.longestPause = Math.max(testCase.longestPause, now - testCase.lastBeat)
            testCase.lastBeat = now
        }
    }
    function test_two_hundred_items() {
        const jobs = []
        for (let i = 0; i < 200; ++i) {
            const operations = []
            for (let j = 0; j < 12; ++j)
                operations.push({ref: "runtime/org.example.Runtime" + j + "/x86_64/stable",
                    commit: "0123456789abcdef".repeat(4), downloadBytes: 100000000,
                    receivedBytes: 50000000, downloadProgress: 0.5, progress: 0.5})
            jobs.push({id: "org.example.App" + i, name: "Application " + i, index: i,
                icon: Qt.resolvedUrl("../../assets/flufflinux-appcenter.svg").toString(),
                action: "update", active: true, queued: i > 0, progress: 0.5,
                queuePosition: i + 1, queueTotal: 200, operations: operations,
                hasDownload: true, downloadedSize: "50 MiB", downloadTotalSize: "100 MiB",
                downloadSpeed: "1 MiB/s"})
        }
        backend.jobs = jobs
        main.showDownloads()
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const view = findChild(page, "downloadJobs")
        compare(view.count, 200)
        wait(100)
        let liveCards = 0
        for (let index = 0; index < view.count; ++index)
            if (view.itemAtIndex(index)) ++liveCards
        verify(liveCards < 20, "Offscreen queue cards must stay uninstantiated: " + liveCards)
        longestPause = 0; lastBeat = Date.now()
        const started = Date.now()
        for (let tick = 0; tick < 1000; ++tick) {
            const snapshot = jobs.slice()
            snapshot[0] = Object.assign({}, jobs[0], {progress: (tick % 100) / 100})
            backend.jobs = snapshot
            // Sweep both ends while progress arrives, then retain completed history.
            if (view.positionViewAtIndex && tick % 25 === 0)
                view.positionViewAtIndex(tick % 50 === 0 ? 199 : 0, ListView.Beginning)
            wait(5)
        }
        console.log("QUEUE_STRESS", JSON.stringify({items: 200, updates: 1000,
            elapsedMs: Date.now() - started, longestPauseMs: longestPause}))
        verify(longestPause < 1000, "The event loop must never stall for a second: " + longestPause)
        backend.jobs = jobs.map(job => Object.assign({}, job, {active: false, progress: 1}))
        wait(500)
        for (let cycle = 0; cycle < 10; ++cycle) {
            main.showCatalog(); tryCompare(stack, "busy", false)
            main.showDownloads(); tryCompare(stack, "busy", false)
        }
        backend.jobs = []
        wait(500)
        compare(findChild(stack.currentItem, "downloadJobs").count, 0)
    }
}
