// Real source loading with a private profile supplied by the Python runner.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1480; height: 900; visible: true
    catalogStats: null
    catalogPreferences: null
    property bool lightTheme: false
    palette.window: lightTheme ? "#eff0f1" : "#202326"
    palette.windowText: lightTheme ? "#202326" : "#ffffff"
    palette.placeholderText: lightTheme ? "#68757e" : "#a5a9ad"
    property int lastProgress: 0
    property bool firstFrame: false
    property bool readyFrame: false
    property bool capturing: false
    property bool capturedSource: false
    property bool capturedParse: false
    property Component backdrop: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    function check(value, message) {
        if (!value) { console.error("CATALOG_PROGRESS_FAIL", message); Qt.exit(1); throw new Error(message) }
    }
    onCatalogProgressChanged: {
        check(catalogProgress >= lastProgress, "Progress moved backwards")
        check(catalogProgress < 100 || !catalogLoading, "Completion while still loading")
        lastProgress = catalogProgress
        console.log("CATALOG_PROGRESS", catalogProgress)
    }
    onFrameSwapped: {
        if (!firstFrame) {
            firstFrame = true
            console.log("CATALOG_FIRST_FRAME", "apps", catalog.length, "loading", catalogLoading)
        }
        if (!readyFrame && catalog.length > 0 && !catalogLoading) {
            readyFrame = true
            console.log("CATALOG_READY_FRAME", "apps", catalog.length, "progress", catalogProgress)
        }
    }
    function capture(stage, done) {
        capturing = true
        const stack = probe.findChild(main, "navigationStack")
        if (!stack.background) stack.background = backdrop.createObject(stack)
        const path = Qt.resolvedUrl("../../target/loading-" + (lightTheme ? "light-" : "dark-") + stage + ".png").toString().replace("file://", "")
        stack.grabToImage(function(result) {
            check(result.saveToFile(path), "Could not save screenshot")
            console.log("CATALOG_SCREENSHOT", path)
            capturing = false
            if (done) done()
        })
    }
    Timer {
        interval: 16; running: true; repeat: true
        onTriggered: {
            main.check(!main.catalogSourcesUnavailable, "Source load failed: " + main.backend.sourcesError)
            if (main.capturing || !main.firstFrame) return
            const label = probe.findChild(main, "catalogEmptyMessage")
            if (main.catalogLoading) {
                main.check(label.visible && label.font.bold && label.color === main.textColor, "Loading styling")
                main.check(label.text === "Loading... " + main.catalogProgress + "%", "Exact loading label")
                if (!main.capturedSource && main.catalogProgress >= 35 && main.catalogProgress < 70) {
                    main.capturedSource = true
                    main.capture("sources")
                } else if (!main.capturedParse && main.catalogProgress >= 70 && main.catalogProgress < 100) {
                    main.capturedParse = true
                    main.capture("preparing")
                }
            } else if (main.readyFrame) {
                main.check(!label.visible && main.catalogProgress === 100, "Loading text must disappear")
                main.capture("ready", function() { Qt.quit() })
            }
        }
    }
    Timer { interval: 240000; running: true; onTriggered: Qt.exit(2) }
}
