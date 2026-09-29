// Read-only capture of the real installed Firefox row. No app/config changes.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1480; height: 900; visible: true
    catalogStats: null
    catalogPreferences: null
    palette.window: "#202326"; palette.windowText: "#ffffff"; palette.placeholderText: "#a5a9ad"
    property int stage: 0
    property Component backdrop: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    function check(value, message) {
        if (!value) { console.error("INSTALLED_SPACING_FAIL", message); Qt.exit(1); throw new Error(message) }
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (main.stage < 0 || main.catalogLoading || main.installedLoading) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            if (main.stage === 0) {
                stack.background = main.backdrop.createObject(stack)
                main.selectedCategory = "Installed"
                main.searchText = "Firefox"
                main.stage = 1
                return
            }
            const list = probe.findChild(stack.currentItem, "installedList")
            const row = list.itemAtIndex(0)
            if (!row) return
            main.check(row.app.name === "Firefox", "Expected the actual installed Firefox")
            main.check(row.topPadding === 12 && row.bottomPadding === 12, "Tighter vertical padding")
            main.check(row.leftPadding === 16 && row.rightPadding === 16, "Horizontal padding unchanged")
            main.stage = -1
            row.grabToImage(function(result) {
                main.check(result.saveToFile(Qt.resolvedUrl("../../target/installed-row-tighter.png").toString().replace("file://", "")), "Save row image")
                stack.grabToImage(function(page) {
                    main.check(page.saveToFile(Qt.resolvedUrl("../../target/installed-page-tighter.png").toString().replace("file://", "")), "Save page image")
                    console.log("INSTALLED_SPACING_CAPTURE", row.app.name, row.app.installedVersion,
                                "height", row.height, "contentHeight", row.contentItem.implicitHeight)
                    Qt.quit()
                })
            })
        }
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.exit(2) }
}
