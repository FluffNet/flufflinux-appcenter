// Opt-in disposable-VM test. Both apps must be absent. Installs/removes only
// 2048, starts then cancels a 0 A.D. download, and preserves pre-existing apps.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    property string phase: "start"
    property var removalApp: null
    property var downloadApp: null
    property double startedAt: Date.now()
    property double receivedBeforeRemoval: 0
    function fail(message) {
        console.error("PARALLEL_LIVE_FAIL: " + message)
        phase = "failed"
        backend.cancelAll()
    }
    Timer {
        interval: 30; repeat: true; running: main.phase !== "done" && main.phase !== "failed"
        onTriggered: {
            if (Date.now() - main.startedAt > 300000) { main.fail("Timed out"); return }
            if (main.installedLoading) return
            const stack = main.contentItem.children.find(item => item.objectName === "navigationStack")
            if (stack && stack.busy) return
            if (main.phase === "start") {
                main.removalApp = main.catalog.find(app => app.id === "net.zdechov.app.x2048")
                main.downloadApp = main.catalog.find(app => app.id === "com.play0ad.zeroad")
                if (!main.removalApp || !main.downloadApp || main.findInstalled(main.removalApp) || main.findInstalled(main.downloadApp)) {
                    main.fail("Both test apps must be in the catalog and absent before the test"); return
                }
                main.openApp(main.removalApp)
                main.installApp(main.removalApp)
                main.phase = "install-test-app"
            } else if (main.phase === "install-test-app" && !main.backend.busy) {
                if (!main.findInstalled(main.removalApp)) { main.fail("2048 did not install"); return }
                main.installApp(main.downloadApp)
                main.phase = "download"
            } else if (main.phase === "download") {
                const job = main.jobForApp(main.downloadApp)
                if (job && job.failed) { main.fail("Test download failed: " + job.error); return }
                if (job && !job.active) { main.fail("Download finished too quickly to test overlap"); return }
                if (!job || !job.active || !(job.receivedBytes > 0)) return
                main.receivedBeforeRemoval = job.receivedBytes
                main.openApp(main.removalApp)
                main.uninstallApp(main.findInstalled(main.removalApp))
                main.phase = "confirm"
            } else if (main.phase === "confirm") {
                const review = main.backend.review
                if (!review.token) return
                if (!review.removing || review.appId !== main.removalApp.id) { main.fail("Unexpected confirmation"); return }
                const download = main.jobForApp(main.downloadApp)
                if (!download || !download.active) { main.fail("Download ended before removal confirmation"); return }
                main.backend.answerReview(review.token, true)
                console.info("PARALLEL_LIVE_CONFIRMED: removal approved while download is active")
                main.phase = "remove"
            } else if (main.phase === "remove") {
                const removal = main.jobForApp(main.removalApp)
                const download = main.jobForApp(main.downloadApp)
                if (removal && removal.failed) { main.fail("Removal failed: " + removal.error); return }
                if (!removal || removal.active || main.findInstalled(main.removalApp)) return
                if (!download || !download.active || download.receivedBytes <= main.receivedBeforeRemoval) {
                    main.fail("Download did not continue during removal"); return
                }
                console.info("PARALLEL_LIVE_OVERLAP: 2048 removed while 0 A.D. download continued from "
                             + main.receivedBeforeRemoval + " to " + download.receivedBytes + " bytes")
                main.backend.cancelJob(download.index)
                main.phase = "cancel"
            } else if (main.phase === "cancel" && !main.backend.busy) {
                if (main.findInstalled(main.removalApp) || main.findInstalled(main.downloadApp)
                    || main.jobForApp(main.downloadApp)) { main.fail("Test apps or cancelled job remained"); return }
                console.info("PARALLEL_LIVE_PASS: real concurrent download/removal, installed refresh, isolated cancellation")
                main.phase = "done"
                main.showCatalog()
            }
        }
    }
}
