import QtQuick

// Use APPCENTER_PROFILE_SHUTDOWN_IMAGES=1. Real image workers contact only
// the fixture's loopback server; package operations remain simulated.
UpdateProfile {
    id: main
    property int turns: 0
    property int navigationTurns: 40
    property int readyImages: 0
    property int pendingImages: 0
    property double imageWaitStarted: 0
    property bool finishing: false
    function finishWithError(message) {
        finishing = true
        console.error(message, turns, readyImages, pendingImages)
        Qt.exit(1)
    }
    Connections {
        target: main.backend
        function onScreenshotFilesChanged() {
            const files = main.backend.screenshotFiles
            main.pendingImages += Object.keys(files).filter(key => files[key].state === "loading").length
        }
    }
    Timer {
        interval: 260; repeat: true; running: main.phase === 3 && !main.finishing
        onTriggered: {
            const nav = main.stack()
            if (nav.busy) return
            if (!main.backend.busy) { main.finishWithError("SHUTDOWN_UPDATES_FINISHED_EARLY"); return }
            if (nav.currentItem.objectName === "downloadsPage") {
                main.openApp(main.catalog[Math.floor(main.turns / 2) % main.expectedJobs])
                main.imageWaitStarted = Date.now()
            } else {
                const files = main.backend.screenshotFiles
                main.readyImages += Object.keys(files).filter(key => files[key].state === "ready").length
                // Whole-library instrumentation can make the first worker
                // slower than this navigation timer. Actually exercise a
                // decoded image before claiming preview/shutdown coverage.
                if (!main.readyImages) {
                    if (Date.now() - main.imageWaitStarted > 60000)
                        main.finishWithError("SHUTDOWN_IMAGE_LOAD_TIMEOUT")
                    return
                }
                nav.currentItem.openScreenshot(0)
                nav.currentItem.previewZoom = 2
                nav.currentItem.panPreviewBy(50, 20)
                if (main.turns >= main.navigationTurns - 1) {
                    if (!main.readyImages || !main.pendingImages) {
                        main.finishWithError("SHUTDOWN_IMAGES_NOT_EXERCISED"); return
                    }
                    // Start uncached transfers and quit before their bodies
                    // finish, while the preview and Queue are still alive.
                    main.backend.requestScreenshots([String(main.catalog[0].screenshots[0]) + "?exit=1"])
                    if (!Object.keys(main.backend.screenshotFiles).some(key => main.backend.screenshotFiles[key].state === "loading")) {
                        main.finishWithError("SHUTDOWN_IMAGE_NOT_PENDING"); return
                    }
                    console.log("SHUTDOWN_OVERLAP_PASS", main.turns + 1, main.readyImages, main.pendingImages, main.backendJobs.length)
                    main.finishing = true
                    stop(); Qt.quit(); return
                }
                nav.currentItem.screenshotPreviewDialog.close()
                main.goBack()
            }
            ++main.turns
        }
    }
}
