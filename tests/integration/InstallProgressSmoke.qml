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
    property string testId: "org.gnome.Calculator"

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
            for (const op of (job.operations || [])) {
                const prefix = op.dependency ? "Dependency: " + op.name : "App: " + main.testApp.name
                if (job.status === prefix + "\n" + op.status) {
                    if (op.dependency) main.sawDependency = true
                    else main.sawApp = true
                    // jobsChanged also invalidates the QML bindings. Inspect
                    // the rendered label after those bindings have reevaluated.
                    Qt.callLater(function() {
                        const current = main.jobForApp(main.testApp)
                        if (!current || !current.active) return
                        const stack = main.find(main.contentItem, "navigationStack")
                        const label = main.find(stack.currentItem, "appJobStatus")
                        if (main.check(label && label.visible && label.text === current.status,
                                       "Current component/status did not reach the app page")) {
                            if (!main.sawProgressUi) stack.currentItem.grabToImage(function(result) {
                                result.saveToFile(Qt.resolvedUrl("../../target/install-progress-proof.png").toString().replace("file://", ""))
                            })
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
                if (!main.check(main.sawApp && main.sawProgressUi && (main.sawDependency || !job.operations.some(op => op.dependency)),
                                "Missing per-component progress")) return
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
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/install-history-proof.png").toString().replace("file://", ""))
                    console.info("INSTALL_PROGRESS_ALL_PASS: real component progress, no app-page completion text, recorded installation date in both views, Downloads history retained")
                    Qt.quit()
                })
            }
        }
    }
    Timer {
        interval: 600000; running: true
        onTriggered: main.check(false, "Timeout at " + main.phase)
    }
}
