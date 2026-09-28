// Read-only startup benchmark. Use an isolated XDG_RUNTIME_DIR for its socket.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visible: false
    catalogStats: null
    catalogPreferences: null
    property bool reportedFrame: false
    property bool reportedCatalog: false
    property int catalogFrames: 0
    TestCase { id: probe; when: false }
    Component.onCompleted: showMaximized()
    onSearchTextChanged: {
        if (searchText === "telegram") { console.log("STARTUP_CLI_SEARCH_RECEIVED"); finish.interval = 300 }
    }
    onFrameSwapped: {
        if (!reportedFrame) { reportedFrame = true; console.log("STARTUP_FIRST_FRAME") }
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (!main.reportedFrame || main.catalog.length === 0 || main.reportedCatalog) return
            // CatalogChanged can precede the render-thread polish pass. Check
            // the settled, actually rendered header rather than that interim frame.
            if (++main.catalogFrames < 5) return
            main.reportedCatalog = true
            const grid = probe.findChild(main, "catalogGrid")
            const heading = probe.findChild(main, "recommendedHeading")
            console.log("STARTUP_CATALOG", main.catalog.length, "maximized", main.visibility === Window.Maximized,
                "atTop", grid.atYBeginning, "headingY", heading.mapToItem(grid, 0, 0).y,
                "anchor", grid.startupTopAnchor, "intent", grid.scrollIntent)
            if (main.visibility !== Window.Maximized || !grid.atYBeginning
                    || heading.mapToItem(grid, 0, 0).y < 0) Qt.exit(1)
            finish.start()
        }
    }
    Timer { id: finish; interval: 5000; onTriggered: Qt.quit() }
    Timer { interval: 20000; running: true; onTriggered: Qt.exit(2) }
}
