// Real backend/worker test on the development VM. Does not remove any apps.
// Refuses pre-installed test apps; immediately cancels each install request.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1240; height: 820
    property string phase: "start"
    property bool failed: false
    property var testApp: null
    property int firstIndex: -1
    property string testId: "org.gnome.Calculator"
    property bool waitForPayload: false
    property double cancelledAt: 0

    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of (item.children || [])) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function check(condition, message) {
        if (failed) return false
        if (condition) return true
        failed = true
        if (backend) backend.cancelAll()
        console.error("CANCEL_UI_FAIL: " + message)
        Qt.exit(1)
        return false
    }
    function cancelActive() {
        const stack = find(main.contentItem, "navigationStack")
        cancelledAt = Date.now()
        find(stack.currentItem, "cancelAppButton").clicked()
        if (!check(backend.jobs.length === 0 && jobForApp(testApp) === null,
                   "Cancel did not immediately hide the active job")) return
        console.info("CANCEL_IMMEDIATE_PASS: no public job after click")
        phase = "wait"
    }
    function verifyFinished() {
        const stack = find(main.contentItem, "navigationStack")
        return check(!main.findInstalled(main.testApp), "Cancelled request installed the test app")
            && check(main.backend.jobs.length === 0, "Cancellation leaked into public job history")
            && check(main.jobForApp(main.testApp) === null, "App still has a cancelled status")
            && check(find(stack.currentItem, "installAppButton").visible, "Install did not return")
            && check(!find(stack.currentItem, "appJobStatus").visible, "Cancelled text still visible")
            && check(!main.downloadQueue.buttonVisible, "Cancelled history kept the Downloads button")
    }
    Timer {
        interval: 30; repeat: true; running: !main.failed
        onTriggered: {
            if (main.installedLoading) return
            const stack = main.find(main.contentItem, "navigationStack")
            if (main.phase === "start") {
                main.testApp = main.catalog.find(app => app.id === main.testId)
                const queuedApp = main.catalog.find(app => app.id === "io.github.mezoahmedii.Picker")
                if (!main.check(!!main.testApp && !!queuedApp && !main.findInstalled(main.testApp)
                                && !main.findInstalled(queuedApp), "Refusing missing/pre-installed test apps")) return
                main.openApp(main.testApp)
                main.backend.installApp(main.testApp)
                main.firstIndex = main.backend.jobs[0].index
                main.backend.installApp(queuedApp)
                if (!main.check(main.backend.jobs.length === 2, "Expected active and queued jobs")) return
                main.backend.cancelJob(main.backend.jobs[1].index)
                if (!main.check(main.backend.jobs.length === 1 && main.backend.jobs[0].index === main.firstIndex,
                                "Queued cancellation was not hidden or changed the running index")) return
                if (main.waitForPayload) main.phase = "downloading"
                else main.cancelActive()
            } else if (main.phase === "downloading") {
                const job = main.jobForApp(main.testApp)
                if (!main.check(job && job.active, "Test app finished/failed before cancellation")) return
                const op = (job.operations || []).find(item => item.ref === job.currentRef && !item.dependency)
                if (!op || op.phase !== "download" || op.receivedBytes < 65536) return
                console.info("CANCEL_LIVE_DOWNLOAD: received=" + op.receivedBytes)
                main.cancelActive()
            } else if (main.phase === "wait" && !main.backend.busy && !stack.busy) {
                if (!main.verifyFinished()) return
                if (!main.check(Date.now() - main.cancelledAt < 2000,
                                "Cancellation/worker cleanup took more than two seconds")) return
                console.info("CANCEL_STOPPED_PASS: worker stopped and caches refreshed in " + (Date.now() - main.cancelledAt) + " ms")
                console.info("CANCEL_UI_PASS: active and queued cancellations absent; Install restored")
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/cancel-app-proof.png").toString().replace("file://", ""))
                    main.showDownloads()
                    main.phase = "downloads"
                })
            } else if (main.phase === "downloads" && !stack.busy) {
                if (!main.check(main.find(stack.currentItem, "downloadJobs").count === 0, "Cancelled rows still in Downloads")) return
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/cancel-downloads-proof.png").toString().replace("file://", ""))
                    main.goBack()
                    main.phase = "retry"
                })
            } else if (main.phase === "retry" && !stack.busy) {
                main.backend.installApp(main.testApp)
                const job = main.backend.jobs[0]
                if (!main.check(main.backend.jobs.length === 1 && job.index > main.firstIndex,
                                "Retry reused an old cancellation or corrupted job indices")) return
                main.backend.cancelJob(job.index)
                main.phase = "retry-wait"
            } else if (main.phase === "retry-wait" && !main.backend.busy) {
                if (!main.verifyFinished()) return
                console.info("CANCEL_UI_ALL_PASS: real worker cancelled, empty Downloads, retry and stable indices; no test app installed")
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 60000; running: true
        onTriggered: main.check(false, "Timeout at " + main.phase)
    }
}
