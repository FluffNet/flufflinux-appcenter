// VM-only, destructive: removes the Calculator created by InstallProgressSmoke.
// Run in a NEW App Center process so no earlier size lookup masks the regression.
// The runner must ensure Calculator and its data were absent before installing it.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1240; height: 820
    property string testId: "org.gnome.Calculator"
    property string priorAppId: ""
    property bool keepOpen: false
    property string phase: "start"
    property var testApp: null
    property bool failed: false
    property double openedAt: 0
    property double sizesRefreshedAt: 0

    function find(item, name) {
        if (!item) return null
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
        backend.cancelAll()
        console.error("UNINSTALL_SIZES_FAIL: " + message)
        Qt.exit(1)
        return false
    }
    function checkRemovalUi(confirmed) {
        const stack = find(main.contentItem, "navigationStack")
        const job = jobForApp(testApp)
        return check(job && job.removalConfirmed === confirmed
                     && find(stack.currentItem, "appInstallProgress").visible === confirmed
                     && !find(stack.currentItem, "cancelAppButton").visible
                     && (confirmed || find(stack.currentItem, "appJobStatus").text === "Waiting for confirmation"),
                     "Uninstall must show only waiting text before Yes, then progress without Cancel")
    }
    Connections {
        target: main.backend
        function onInstallSizesChanged() {
            if (main.phase === "removing") main.sizesRefreshedAt = Date.now()
        }
    }
    Timer {
        interval: 16; repeat: true; running: !main.failed && main.phase !== "done"
        onTriggered: {
            if (main.installedLoading) return
            const stack = main.find(main.contentItem, "navigationStack")
            if (stack.busy) return
            if (main.phase === "start") {
                main.testApp = main.installedApps.find(app => app.id === main.testId && app.installation === "user")
                if (!main.check(!!main.testApp, "Test-created user Calculator is missing")) return
                if (!main.check(Object.keys(main.backend.installSizes).length === 0, "Test requires a fresh process")) return
                if (main.priorAppId) {
                    const prior = main.catalog.find(app => app.id === main.priorAppId)
                    if (!main.check(!!prior && !main.findInstalled(prior), "Prior test app must be uninstalled")) return
                    main.openApp(prior)
                    main.phase = "open"
                } else main.phase = "open"
            } else if (main.phase === "open") {
                main.openedAt = Date.now()
                main.openApp(main.testApp)
                main.phase = "cancel"
            } else if (main.phase === "cancel") {
                const elapsed = Date.now() - main.openedAt
                if (!main.check(elapsed < 500, "Installed app took " + elapsed + " ms to open")) return
                console.info("UNINSTALL_SIZES_OPEN: " + elapsed + " ms")
                main.find(stack.currentItem, "uninstallAppButton").clicked()
                main.phase = "decline"
            } else if (main.phase === "decline" && main.backend.review.removing) {
                if (!main.checkRemovalUi(false)) return
                main.backend.answerReview(main.backend.review.token, false)
                if (!main.checkRemovalUi(false)) return
                main.phase = "cancelled"
            } else if (main.phase === "cancelled" && !main.backend.busy) {
                if (!main.check(!!main.findInstalled(main.testApp)
                                && !main.find(stack.currentItem, "installSizeDetails").visible,
                                "Declining uninstall changed the installed view")) return
                main.find(stack.currentItem, "uninstallAppButton").clicked()
                main.phase = "approve"
            } else if (main.phase === "approve" && main.backend.review.removing) {
                if (!main.checkRemovalUi(false)) return
                main.phase = "removing"
                main.backend.answerReview(main.backend.review.token, true)
                if (!main.checkRemovalUi(true)) return
                console.info("UNINSTALL_CONFIRMATION_PASS: no bar/cancel before Yes; progress without Cancel after Yes")
                stack.currentItem.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/uninstall-confirmed-proof.png").toString().replace("file://", ""))
                })
            } else if (main.phase === "removing" && !main.backend.busy) {
                if (!main.check(!main.findInstalled(main.testApp), "Test app was not removed")) return
                const sizes = main.backend.installSizes[main.testId] || ({})
                const appLabel = main.find(stack.currentItem, "appDownloadSize")
                const totalLabel = main.find(stack.currentItem, "totalDownloadSize")
                console.info("UNINSTALL_SIZES_RESULT: " + JSON.stringify(sizes) + " labels=" + appLabel.text + "/" + totalLabel.text)
                main.phase = "capture"
                stack.currentItem.grabToImage(function(result) {
                    const filename = Qt.resolvedUrl("../../target/uninstall-sizes-proof.png").toString().replace("file://", "")
                    if (!main.check(result.saveToFile(filename), "Cannot save post-uninstall screenshot")) return
                    if (!main.check(sizes.state === "ready" && !!sizes.appSize && !!sizes.totalSize
                                    && main.sizesRefreshedAt > 0 && appLabel.visible && appLabel.text === sizes.appSize
                                    && totalLabel.text === sizes.totalSize
                                    && totalLabel.visible === (sizes.appSize !== sizes.totalSize),
                                    "Sizes were not ready when the uninstalled page appeared")) return
                    if (!main.check(main.find(stack.currentItem, "installAppButton").visible
                                    && !main.find(stack.currentItem, "appJobStatus").visible
                                    && main.downloadQueue.jobs.length === 0,
                                    "Uninstall left status/history or incorrect buttons")) return
                    console.info("UNINSTALL_SIZES_ALL_PASS: fresh session, declined removal, real uninstall, immediate sizes without reopening; prior=" + main.priorAppId)
                    main.phase = "done"
                    if (!main.keepOpen) Qt.quit()
                })
            }
        }
    }
    Timer {
        interval: 60000; running: main.phase !== "done"
        onTriggered: main.check(false, "Timeout at " + main.phase)
    }
}
