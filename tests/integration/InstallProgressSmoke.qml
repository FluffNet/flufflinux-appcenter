// VM-only real-backend test. Installs the absent Calculator test app for this
// run; it never removes apps. The runner must clean up its test installation.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1240; height: 820
    property string phase: "start"
    property var testApp: null
    property bool failed: false
    property bool sawApp: false
    property bool sawDependency: false
    property bool sawProgressUi: false
    property bool sawDownloadStage: false
    property bool sawDownloadSpeed: false
    property bool sawInstallStage: false
    property bool sawAppInstallStage: false
    property string testId: "org.gnome.Calculator"
    property string sourceFile: ""
    property bool expectNoDownload: false
    property string proofPrefix: "unified"
    property real previousProgress: 0
    property bool keepOpen: false

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
        console.error("INSTALL_PROGRESS_FAIL: " + message)
        Qt.exit(1)
        return false
    }
    Connections {
        target: main.backend
        function onReviewChanged() {
            const review = main.backend.review
            if (!review.token || !main.sourceFile) return
            // Only approve the explicit test bundle, never an unknown remote
            // or an uninstall prompt. Production trust prompts stay intact.
            if (!main.check(review.kind === "bundle" && review.message.endsWith(main.sourceFile.replace("file://", "")),
                            "Unexpected source trust request during bundle test")) return
            const token = review.token
            Qt.callLater(function() { main.backend.answerReview(token, true) })
        }
        function onJobsChanged() {
            if (main.failed || !main.testApp) return
            const job = main.jobForApp(main.testApp)
            if (!job || !job.active) return
            if (!main.check(job.progress >= main.previousProgress && job.progress < 1,
                            "Overall progress moved backwards or completed before the result")) return
            main.previousProgress = job.progress
            if (!main.check((job.receivedBytes || 0) <= (job.downloadTotalBytes || 0),
                            "Received bytes exceed the transaction download total")) return
            if (main.expectNoDownload && !main.check(!job.hasDownload && !job.receivedBytes && !job.downloadTotalBytes,
                                                    "Local-only bundle unexpectedly counted network bytes")) return
            if (!main.check(job.icon === main.testApp.icon, "Active download lost its catalog icon")) return
            for (const op of (job.operations || [])) {
                if (!main.check(!/delta parts|loose fetched|objects fetched/.test(op.status),
                                "Internal transfer diagnostics leaked into an operation")) return
                const prefix = op.dependency ? "Dependency: " + op.name + "\n" : ""
                if (job.currentRef === op.ref) {
                    if (!main.check(job.status === prefix + op.status,
                                    "Unexpected/repeated app name in progress status: " + job.status)) return
                    if (op.dependency) main.sawDependency = true
                    else main.sawApp = true
                    // jobsChanged also invalidates the QML bindings. Inspect
                    // the rendered label after those bindings have reevaluated.
                    Qt.callLater(function() {
                        const current = main.jobForApp(main.testApp)
                        if (!current || !current.active) return
                        const stack = main.find(main.contentItem, "navigationStack")
                        const label = main.find(stack.currentItem, "appJobStatus")
                        const bar = main.find(stack.currentItem, "overallInstallProgress")
                        const bytes = main.find(stack.currentItem, "downloadBytesLabel")
                        const count = main.find(stack.currentItem, "completedOperationsLabel")
                        const percentage = main.find(stack.currentItem, "overallPercentageLabel")
                        if (!main.check(bar && bar.visible && !bar.indeterminate
                                        && Math.abs(bar.value - current.progress) < 0.0001
                                        && !count && bytes.color === main.textColor && percentage.color === main.textColor
                                        && bytes.visible === (current.hasDownload && !current.downloadComplete)
                                        && (!bytes.visible || bytes.text === current.downloadedSize + " / " + current.downloadTotalSize + " (" + current.downloadSpeed + ")")
                                        && percentage.text === Math.floor(current.progress * 100 + 0.000001) + "%"
                                        && !main.find(stack.currentItem, "downloadPhaseProgress")
                                        && !main.find(stack.currentItem, "installPhaseProgress"),
                                        "Unified progress/bytes do not match the real backend: " + JSON.stringify({
                                            value: bar.value, expected: current.progress, countPresent: !!count,
                                            bytesVisible: bytes.visible, hasDownload: current.hasDownload, downloadComplete: current.downloadComplete,
                                            bytesText: bytes.text, speed: current.downloadSpeed, percentage: percentage.text}))) return
                        if (current.phase === "download" && !main.sawDownloadStage) {
                            main.sawDownloadStage = true
                            console.info("DOWNLOAD_STAGE_PASS: " + percentage.text + ", " + bytes.text)
                            stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/" + main.proofPrefix + "-download-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (bytes.visible && parseFloat(current.downloadSpeed.replace(",", ".")) > 0 && !main.sawDownloadSpeed) {
                            main.sawDownloadSpeed = true
                            console.info("DOWNLOAD_SPEED_PASS: " + bytes.text + ", above bar and left aligned")
                            stack.currentItem.grabToImage(function(result) {
                                const bytesTop = bytes.mapToItem(bar, 0, 0)
                                const percentageTop = percentage.mapToItem(bar, 0, 0)
                                if (!main.check(bytesTop.y + bytes.height <= 0 && bytes.horizontalAlignment === Text.AlignLeft
                                                && Math.abs(bytesTop.x) <= 1
                                                && percentageTop.y + percentage.height <= 0
                                                && Math.abs(percentageTop.x + percentage.width - bar.width) <= 1,
                                                "Download info and percentage are not above the left/right bar edges")) return
                                result.saveToFile(Qt.resolvedUrl("../../target/" + main.proofPrefix + "-speed-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (current.phase === "install" && !main.sawInstallStage) {
                            if (!main.check(current.progress < 1 && current.installCompleted < current.installTotal,
                                            "Download completion incorrectly finished installation")) return
                            main.sawInstallStage = true
                            console.info("INSTALL_STAGE_PASS: " + percentage.text + ", " + bytes.text + ", bytesVisible=" + bytes.visible)
                            stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/" + main.proofPrefix + "-install-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (current.phase === "install" && current.currentRef.startsWith("app/") && !main.sawAppInstallStage) {
                            main.sawAppInstallStage = true
                            if (!main.sourceFile && !main.check(current.receivedBytes === current.downloadTotalBytes,
                                                               "All pulls finished but received/total bytes still differ")) return
                            if (!main.sourceFile && !main.check(current.downloadComplete && !bytes.visible,
                                                               "Download bytes/speed remain after every pull finished")) return
                            console.info("APP_DEPLOY_STAGE_PASS: " + percentage.text + ", bytesVisible=" + bytes.visible)
                            stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/" + main.proofPrefix + "-app-install-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (main.check(label && !label.visible,
                                       "Redundant component/status text remains on the app page")) {
                            main.sawProgressUi = true
                        }
                    })
                }
            }
        }
    }
    Timer {
        interval: 30; repeat: true; running: !main.failed
        onTriggered: {
            if (main.installedLoading) return
            const stack = main.find(main.contentItem, "navigationStack")
            if (stack.busy) return
            if (main.phase === "start") {
                main.testApp = main.catalog.find(app => app.id === main.testId)
                if (!main.check(!!main.testApp && !main.findInstalled(main.testApp),
                                "Refusing missing/pre-installed test app")) return
                if (main.sourceFile) {
                    main.backend.openSource(main.sourceFile)
                    main.phase = "source"
                } else {
                    main.openApp(main.testApp)
                    main.phase = "install"
                }
            } else if (main.phase === "source" && !main.backend.busy) {
                if (!main.check(stack.currentItem.app && stack.currentItem.app.id === main.testId,
                                "Local source did not open the app page")) return
                main.previousProgress = 0
                main.phase = "install"
            } else if (main.phase === "install") {
                main.phase = "waiting"
                main.find(stack.currentItem, "installAppButton").clicked()
            } else if (main.phase === "waiting" && !main.backend.busy) {
                const job = main.jobForApp(main.testApp)
                if (!main.check(job && !job.failed && job.progress === 1 && main.findInstalled(main.testApp),
                                "Real installation did not finish successfully")) return
                if (!main.check(main.sawApp && main.sawProgressUi && (main.sawDependency || !job.operations.some(op => op.dependency)),
                                "Missing per-component progress")) return
                if (!main.check((main.sawDownloadStage || !job.hasDownload) && main.sawInstallStage && main.sawAppInstallStage
                                && job.installCompleted === job.installTotal && job.downloadProgress === 1,
                                "Missing real download/install stages in the unified bar")) return
                if (!main.check(!main.find(stack.currentItem, "appJobStatus").visible
                                && !main.find(stack.currentItem, "appInstallProgress").visible
                                && main.find(stack.currentItem, "openAppButton").visible
                                && main.find(stack.currentItem, "uninstallAppButton").visible,
                                "Completion still leaves status/progress instead of installed actions")) return
                const installed = main.findInstalled(main.testApp)
                if (!main.check(!!installed.installedAt && !!installed.installedDate
                                && main.find(stack.currentItem, "appInstalledDateValue").text === installed.installedDate,
                                "Successful installation did not record/display its date")) return
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/install-complete-proof.png").toString().replace("file://", ""))
                    main.showCatalog()
                    main.selectedCategory = "Installed"
                    main.phase = "installed"
                })
            } else if (main.phase === "installed") {
                const list = main.find(stack.currentItem, "installedList")
                let row = null
                for (let i = 0; i < list.count; ++i) {
                    const item = list.itemAtIndex(i)
                    if (item && item.app.id === main.testApp.id) row = item
                }
                if (!main.check(row && main.find(row, "installedDateValue").visible,
                                "Installed list did not show recorded date")) return
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/install-date-proof.png").toString().replace("file://", ""))
                    main.showDownloads()
                    main.phase = "downloads"
                })
            } else if (main.phase === "downloads") {
                if (!main.check(main.find(stack.currentItem, "downloadJobs").count === 1
                                && main.downloadQueue.jobs[0].status === "Complete",
                                "Successful installation disappeared from Downloads")) return
                const icon = main.find(stack.currentItem, "downloadAppIcon")
                if (!main.check(!!icon && !icon.loadFailed && icon.status !== Image.Error,
                                "Downloads artwork failed to load")) return
                if (icon.status !== Image.Ready) return
                if (!main.check(icon.source.toString() === main.iconSource(main.testApp.icon)
                                && main.downloadQueue.jobs[0].icon === main.testApp.icon,
                                "Completed download did not retain the app's actual icon")) return
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/install-history-proof.png").toString().replace("file://", ""))
                    console.info("INSTALL_PROGRESS_ALL_PASS: real component progress, no app-page completion text, recorded installation date in both views, Downloads history and loaded app icon retained")
                    main.phase = "done"
                    if (!main.keepOpen) Qt.quit()
                })
            }
        }
    }
    Timer {
        interval: 600000; running: main.phase !== "done"
        onTriggered: main.check(false, "Timeout at " + main.phase)
    }
}
