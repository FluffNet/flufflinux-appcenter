// Real transactions in a temporary Flatpak installation, never user apps.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    catalogStats: null
    catalogPreferences: null
    property bool started: false
    property bool closedForQueue: false
    property bool reopenedFrame: false
    function findItem(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const match = findItem(child, name)
            if (match) return match
        }
        return null
    }
    onFrameSwapped: {
        if (!visible || !closedForQueue || reopenedFrame) return
        reopenedFrame = true
        const message = findItem(contentItem, "catalogEmptyMessage")
        console.log("QUEUE_CACHE_REOPEN_FRAME", "apps", catalog.length,
                    "loaded", catalogLoaded, "emptyMessage", message ? message.visible : "missing")
        closeAgain.start()
    }
    Timer {
        id: closeAgain
        interval: 400
        onTriggered: { main.close(); console.log("QUEUE_CACHE_CLOSED_AGAIN") }
    }
    Connections {
        target: main.backend
        function onInputError(message) { console.error("QUEUE_CACHE_FAIL", message); Qt.exit(3) }
        function onJobsChanged() {
            if (!main.started) return
            const jobs = main.backend.jobs
            if (jobs.some(job => job.failed)) { console.error("QUEUE_CACHE_FAIL", JSON.stringify(jobs)); Qt.exit(4); return }
            if (!main.closedForQueue && jobs.some(job => job.active && !job.queued)) {
                main.closedForQueue = true
                main.close()
                console.log("QUEUE_CACHE_CLOSED")
            }
            if (jobs.length === 2 && jobs.every(job => !job.active)) console.log("QUEUE_CACHE_COMPLETE")
        }
    }
    Timer {
        interval: 100; repeat: true; running: !main.started
        onTriggered: {
            if (main.catalogLoading || main.backend.installedLoading) return
            const apps = main.catalog.filter(app => app.id.startsWith("org.example.QueueCache.App"))
            if (apps.length !== 2) { console.error("QUEUE_CACHE_FAIL", "missing apps"); Qt.exit(2); return }
            main.started = true
            console.log("QUEUE_CACHE_STARTED")
            apps.forEach(app => main.backend.installApp(app))
        }
    }
}
