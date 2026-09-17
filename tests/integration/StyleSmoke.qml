// Read-only visual check in the real KDE session. Never starts transactions or
// changes the system theme/font/scaling. Leaves the catalog open for inspection.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visibility: Window.Maximized
    property int stage: 0
    // ApplicationWindow's native content root cannot be grabbed. Give the
    // navigation stack the same background for self-contained page snapshots.
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of (item.children || [])) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function capture(name, next) {
        find(contentItem, "navigationStack").grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/style-" + name + ".png").toString().replace("file://", ""))) {
                console.error("STYLE_FAIL: could not save " + name); Qt.exit(1); return
            }
            next()
        })
    }
    function verifyCatalogViewport() {
        const page = find(contentItem, "navigationStack").currentItem
        const grid = find(page, "catalogGrid")
        const bar = find(page, "catalogPageScrollBar")
        let valid = bar.visible && bar.parent === page.contentItem && bar.y === 0
            && bar.height === page.contentItem.height
            && bar.x + bar.width === page.contentItem.width && bar.contentItem.height >= 43
        let fullCards = 0
        for (let index = 0; index < grid.count; ++index) {
            const card = grid.itemAtIndex(index)
            if (!card) continue
            const fits = card.y >= grid.contentY - 0.5 && card.y + card.height <= grid.contentY + grid.height + 0.5
            valid = valid && card.visible === fits && card.enabled === fits
            if (card.visible) ++fullCards
        }
        if (!valid || fullCards < grid.columnCount) {
            console.error("STYLE_FAIL: full-page scrollbar or whole-card visibility at " + grid.contentY)
            Qt.exit(1); return false
        }
        console.info("STYLE_SCROLL_PASS: offset=" + grid.contentY + " completeCards=" + fullCards)
        return true
    }
    Timer {
        interval: 600; repeat: true; running: main.stage < 10
        onTriggered: {
            if (main.installedLoading) return
            const stack = main.find(main.contentItem, "navigationStack")
            if (stack.busy) return
            if (main.stage === 0) {
                if (!main.verifyCatalogViewport()) return
                stack.background = main.snapshotBackground.createObject(stack)
                const count = main.find(main.contentItem, "catalogCountLabel")
                console.info("STYLE_FONT: " + count.fontInfo.family + " " + count.fontInfo.pixelSize
                             + "px; scale=" + Screen.devicePixelRatio + "; native=" + count.renderType)
                const separator = main.find(main.contentItem, "catalogHeaderSeparator")
                console.info("STYLE_SEAM: window scale=" + separator.pixelRatio + "; thickness=" + separator.thickness)
                main.stage = -1
                main.capture("catalog", function() { main.stage = 1 })
            } else if (main.stage === 1) {
                const count = main.find(main.contentItem, "catalogCountLabel")
                main.stage = -1
                count.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/style-count-native.png").toString().replace("file://", ""))
                    count.renderType = Text.QtRendering
                    main.stage = 2
                })
            } else if (main.stage === 2) {
                const count = main.find(main.contentItem, "catalogCountLabel")
                main.stage = -1
                count.grabToImage(function(result) {
                    result.saveToFile(Qt.resolvedUrl("../../target/style-count-qt.png").toString().replace("file://", ""))
                    count.renderType = Text.NativeRendering
                    main.selectedCategory = "Installed"
                    main.stage = 3
                })
            } else if (main.stage === 3) {
                main.stage = -1
                main.capture("installed", function() {
                    const app = main.catalog.find(item => item.id === "com.play0ad.zeroad")
                    if (!app) { console.error("STYLE_FAIL: missing test catalog entry"); Qt.exit(1); return }
                    main.openApp(app); main.stage = 4
                })
            } else if (main.stage === 4) {
                main.stage = -1
                main.capture("app", function() { main.showDownloads(); main.stage = 5 })
            } else if (main.stage === 5) {
                main.stage = -1
                main.capture("downloads", function() {
                    main.showCatalog(); main.selectedCategory = "All Apps"; main.stage = 6
                })
            } else if (main.stage === 6) {
                main.find(stack.currentItem, "catalogGrid").contentY = 79
                main.stage = 7
            } else if (main.stage === 7) {
                if (!main.verifyCatalogViewport()) return
                main.stage = -1
                main.capture("catalog-scrolled", function() {
                    const grid = main.find(stack.currentItem, "catalogGrid")
                    grid.contentY = grid.contentHeight - grid.height
                    main.stage = 8
                })
            } else if (main.stage === 8) {
                if (!main.verifyCatalogViewport()) return
                main.stage = -1
                main.capture("catalog-bottom", function() {
                    main.find(stack.currentItem, "catalogGrid").positionViewAtBeginning()
                    main.stage = 9
                })
            } else if (main.stage === 9) {
                main.stage = 10
                console.info("STYLE_ALL_PASS: full-page scrollbar, complete cards at top/middle/bottom, Installed, app, Downloads, and native/Qt count snapshots")
            }
        }
    }
}
