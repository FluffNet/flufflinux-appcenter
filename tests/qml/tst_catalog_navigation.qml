import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    id: testCase
    name: "CatalogNavigation"
    when: mainWindow.visible

    readonly property var testCatalog: {
        const apps = []
        for (let index = 0; index < 80; ++index) {
            const name = "Application " + index
            apps.push({
                id: "org.fluff.Application" + index,
                name: name,
                summary: "Catalog navigation test",
                description: "A test application",
                icon: "",
                category: "Utilities",
                developer: "FluffNet",
                license: "MIT",
                homepage: "",
                screenshots: [],
                searchName: name.toLowerCase(),
                searchSummary: "catalog navigation test",
                searchDescription: "a test application",
                searchMetadata: "fluffnet utilities",
                searchHaystack: (name + " catalog navigation test "
                                + "a test application fluffnet utilities").toLowerCase()
            })
        }
        return apps
    }

    AppCenter.Main {
        id: mainWindow
        visible: true
        catalog: testCase.testCatalog
    }

    function test_adaptive_cards_and_continuous_scroll_data() {
        return [{tag: "wide", width: 1180, height: 760},
                {tag: "short", width: 980, height: 610},
                {tag: "narrow", width: 720, height: 520},
                {tag: "tall", width: 1180, height: 1000}]
    }
    function test_adaptive_cards_and_continuous_scroll(data) {
        mainWindow.width = data.width
        mainWindow.height = data.height
        const stack = findChild(mainWindow, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const grid = findChild(page, "catalogGrid")
        const bar = findChild(page, "catalogPageScrollBar")
        waitForRendering(page)
        verify(bar.visible)
        compare(bar.policy, ScrollBar.AlwaysOn)
        compare(bar.parent, page.contentItem)
        compare(bar.y, 0)
        compare(bar.height, page.contentItem.height)
        compare(bar.x + bar.width, page.contentItem.width)
        verify(bar.height > grid.height, "Scrollbar must extend above the category grid")
        verify(bar.contentItem.height >= 43, "Thumb must remain easy to see and drag")
        verify(bar.contentItem.color !== mainWindow.borderColor)
        compare(grid.snapMode, GridView.NoSnap)
        verify(grid.cellHeight >= 158, "Cards must not shrink below their readable minimum")
        fuzzyCompare(grid.rowCount * grid.cellHeight, grid.height, 0.5,
                     "Rows should share the spare viewport height")
        for (const offset of [0, 79, grid.cellHeight, grid.contentHeight - grid.height]) {
            grid.contentY = offset
            waitForRendering(page)
            let visibleCards = 0, clippedCards = 0
            for (let index = 0; index < grid.count; ++index) {
                const card = grid.itemAtIndex(index)
                if (!card) continue
                compare(card.height, grid.cellHeight - 16)
                compare(card.width, grid.cellWidth - 16)
                const intersects = card.y < grid.contentY + grid.height
                                && card.y + card.height > grid.contentY
                if (!intersects) continue
                verify(card.visible, "Partially visible cards must not disappear while scrolling")
                verify(card.enabled, "Visible parts of cards must remain interactive")
                ++visibleCards
                const fits = card.y >= grid.contentY - 0.5
                          && card.y + card.height <= grid.contentY + grid.height + 0.5
                if (!fits) ++clippedCards
            }
            verify(visibleCards >= grid.columnCount, "Catalog must remain populated")
            if (offset === 0) {
                compare(visibleCards, grid.rowCount * grid.columnCount)
                compare(clippedCards, 0)
            }
            if (offset === 79) {
                verify(clippedCards > 0, "Test must include a partially clipped row")
                verify(visibleCards > grid.rowCount * grid.columnCount,
                       "Keep both edge rows visible during continuous scrolling")
            }
        }
        const lastCard = grid.itemAtIndex(grid.count - 1)
        verify(lastCard && lastCard.visible, "The final application must remain reachable")
        grid.contentY = 0
        waitForRendering(page)
        const naturalScroll = findChild(page, "catalogNaturalScroll")
        naturalScroll.scrollDown(100)
        tryCompare(grid, "contentY", 100)
        naturalScroll.scrollDown(10)
        tryCompare(grid, "contentY", 110)
        grid.contentY = 0
        waitForRendering(page)
        mousePress(bar, bar.width / 2, bar.contentItem.y + bar.contentItem.height / 2)
        mouseMove(bar, bar.width / 2, bar.height * 0.65, 50)
        mouseRelease(bar, bar.width / 2, bar.height * 0.65)
        verify(grid.contentY > 0, "Dragging the page scrollbar must scroll the catalog")
        grid.contentY = 0
        mainWindow.width = 1180
        mainWindow.height = 760
    }

    function test_touch_drag_scrollbar() {
        mainWindow.requestActivate()
        const page = findChild(mainWindow, "navigationStack").currentItem
        const grid = findChild(page, "catalogGrid")
        const bar = findChild(page, "catalogPageScrollBar")
        grid.contentY = 0
        waitForRendering(page)
        const x = bar.width / 2
        const startY = bar.contentItem.y + bar.contentItem.height / 2
        const drag = touchEvent(bar)
        drag.press(0, bar, x, startY).commit()
        verify(bar.interactive, "Breeze must not disable this scrollbar when touch input begins")
        for (let step = 1; step <= 8; ++step)
            drag.move(0, bar, x, startY + step * 30).commit()
        verify(grid.contentY > grid.height, "Holding and dragging the thumb must scroll with a touchscreen")
        drag.release(0, bar, x, startY + 240).commit()
        grid.contentY = 0
    }
    function test_back_restores_the_exact_catalog_item_position() {
        const navigation = findChild(mainWindow, "navigationStack")
        verify(navigation !== null)
        tryCompare(navigation, "depth", 1)
        tryCompare(navigation, "busy", false)

        const originalCatalogPage = navigation.currentItem
        const catalogGrid = findChild(originalCatalogPage, "catalogGrid")
        verify(catalogGrid !== null)
        tryCompare(catalogGrid, "count", testCase.testCatalog.length)
        tryVerify(function() {
            return catalogGrid.contentHeight > catalogGrid.height + 700
        })

        catalogGrid.contentY = 640
        compare(catalogGrid.contentY, 640)
        mainWindow.openApp(testCase.testCatalog[40])
        tryCompare(navigation, "depth", 2)
        tryCompare(navigation, "busy", false)

        mainWindow.showCatalog()
        tryCompare(navigation, "depth", 1)
        tryCompare(navigation, "busy", false)
        compare(navigation.currentItem, originalCatalogPage)
        compare(catalogGrid.contentY, 640)
    }
}
