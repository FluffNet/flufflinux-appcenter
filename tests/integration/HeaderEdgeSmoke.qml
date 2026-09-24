// Render the real KDE header, open menu and scrollbar. No app mutations.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    property int stage: 0
    property bool capturing: false
    Item { id: captureRoot; anchors.fill: parent }
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function check(value, message) {
        if (!value) { console.error("HEADER_EDGE_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (main.capturing || main.backend.installedLoading) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            main.check(main.backend.updates.state === "idle", "No automatic update checks")
            const page = stack.get(0)
            const button = probe.findChild(page, "applicationMenuButton")
            const menu = probe.findChild(page, "applicationMenu")
            if (main.stage === 0 || main.stage === 2) {
                if (main.stage === 0) {
                    stack.background = main.snapshotBackground.createObject(stack)
                    // Capture the page and popup together under a QML-owned item.
                    stack.parent = captureRoot
                    main.Overlay.overlay.parent = captureRoot
                }
                probe.mouseMove(button, button.width / 2, button.height / 2)
                probe.mouseClick(button)
                main.stage++; return
            }
            if (!menu.opened) return
            const search = probe.findChild(page, "searchField")
            const bar = probe.findChild(page, "catalogPageScrollBar")
            const right = button.mapToItem(main.contentItem, button.width, 0).x
            main.check(Math.abs(main.width - right - 8) < 1, "8px actual window gap")
            main.check(Math.abs(search.x + search.width + 10 - button.x) < 1, "Search follows menu")
            main.check(bar.visible, "Visible catalogue scrollbar")
            main.check(right > bar.mapToItem(main.contentItem, 0, 0).x, "Button overlaps scrollbar column")
            main.check(Math.abs(menu.x + menu.width - button.width) < 1, "Dropdown right alignment")
            const grid = probe.findChild(page, "catalogGrid")
            const common = probe.findChild(page, "recommendedGrid")
            const title = probe.findChild(page, "catalogTitleLabel")
            const sort = probe.findChild(page, "catalogSort")
            const headingTop = Math.min(title.mapToItem(grid, 0, 0).y, sort.mapToItem(grid, 0, 0).y)
            main.check(Math.abs(headingTop - common.mapToItem(grid, 0, common.height).y
                       - (grid.height < 500 ? 12 : 16)) < 1, "Common Apps to All Apps spacing")
            main.capturing = true
            const name = main.stage === 1 ? "normal" : "compact"
            main.check(captureRoot.grabToImage(function(result) {
                main.check(result.saveToFile(Qt.resolvedUrl("../../target/header-edge-" + name + ".png").toString().replace("file://", "")), "Save screenshot")
                console.log("HEADER_EDGE_CAPTURE", name)
                if (main.stage === 3) { console.log("HEADER_EDGE_PASS"); Qt.quit(); return }
                menu.close(); main.width = 720; main.height = 520
                main.stage = 2; main.capturing = false
            }), "Screenshot capture")
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(3) }
}
