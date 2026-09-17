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
    property bool sawAppProgressImage: false
    property bool sawDownloadStage: false
    property bool sawInstallStage: false
    property bool sawAppInstallStage: false
    property string testId: "org.gnome.Calculator"
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
        if (condition) return true
        failed = true
        if (backend) backend.cancelAll()
        console.error("INSTALL_PROGRESS_FAIL: " + message)
        Qt.exit(1)
        return false
    }
    Connections {
        target: main.backend
        function onJobsChanged() {
            if (!main.testApp) return
            const job = main.jobForApp(main.testApp)
            if (!job || !job.active) return
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
                        const download = main.find(stack.currentItem, "downloadPhaseProgress")
                        const install = main.find(stack.currentItem, "installPhaseProgress")
                        if (!main.check(download && install && install.visible
                                        && Math.abs(download.value - current.downloadProgress) < 0.0001
                                        && Math.abs(install.value - current.installProgress) < 0.0001,
                                        "Separate progress bars do not match the real backend")) return
                        if (current.phase === "download" && !main.sawDownloadStage) {
                            main.sawDownloadStage = true
                            console.info("DOWNLOAD_STAGE_PASS: " + current.downloadProgress + ", installed=" + current.installCompleted + "/" + current.installTotal)
                            stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/download-stage-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (current.phase === "install" && !main.sawInstallStage) {
                            if (!main.check(install.activeStep && current.installCompleted < current.installTotal,
                                            "Download completion incorrectly finished installation")) return
                            main.sawInstallStage = true
                            console.info("INSTALL_STAGE_PASS: " + current.downloadProgress + ", installed=" + current.installCompleted + "/" + current.installTotal)
                            stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/install-stage-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (current.phase === "install" && current.currentRef.startsWith("app/") && !main.sawAppInstallStage) {
                            main.sawAppInstallStage = true
                            console.info("APP_DEPLOY_STAGE_PASS: download=" + current.downloadProgress + ", installed=" + current.installCompleted + "/" + current.installTotal)
                            stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/install-app-stage-proof.png").toString().replace("file://", ""))
                            })
                        }
                        if (main.check(label && label.visible && label.text === current.status,
                                       "Current component/status did not reach the app page")) {
                            if (!main.sawProgressUi) stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/install-progress-proof.png").toString().replace("file://", ""))
                            })
                            if (!main.sawAppProgressImage && current.currentRef.startsWith("app/")
                                    && (current.status === "Installing…" || current.status.startsWith("Downloading…"))) {
                                main.sawAppProgressImage = true
                                console.info("INSTALL_STATUS_PASS: " + current.status)
                                stack.currentItem.grabToImage(function(result) {
                                    result.saveToFile(Qt.resolvedUrl("../../target/install-app-progress-proof.png").toString().replace("file://", ""))
                                })
                            }
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
                main.openApp(main.testApp)
                main.phase = "install"
            } else if (main.phase === "install") {
                main.phase = "waiting"
                main.find(stack.currentItem, "installAppButton").clicked()
            } else if (main.phase === "waiting" && !main.backend.busy) {
                const job = main.jobForApp(main.testApp)
                if (!main.check(job && !job.failed && job.progress === 1 && main.findInstalled(main.testApp),
                                "Real installation did not finish successfully")) return
                if (!main.check(main.sawApp && main.sawProgressUi && main.sawAppProgressImage && (main.sawDependency || !job.operations.some(op => op.dependency)),
                                "Missing per-component progress")) return
                if (!main.check(main.sawDownloadStage && main.sawInstallStage && main.sawAppInstallStage
                                && job.installCompleted === job.installTotal && job.downloadProgress === 1,
                                "Missing separate real download/install stages")) return
                if (!main.check(!main.find(stack.currentItem, "appJobStatus").visible
                                && !main.find(stack.currentItem, "appInstallProgress").visible
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
