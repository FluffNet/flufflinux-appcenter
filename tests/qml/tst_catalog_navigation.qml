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

    function test_full_cards_and_page_scrollbar_data() {
        return [{tag: "wide", width: 1180, height: 760},
                {tag: "short", width: 980, height: 610},
                {tag: "narrow", width: 720, height: 520}]
    }
    function test_full_cards_and_page_scrollbar(data) {
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
        for (const offset of [0, 79, 158, grid.contentHeight - grid.height]) {
            grid.contentY = offset
            waitForRendering(page)
            let visibleCards = 0, clippedCards = 0
            for (let index = 0; index < grid.count; ++index) {
                const card = grid.itemAtIndex(index)
                if (!card) continue
                const fits = card.y >= grid.contentY - 0.5
                          && card.y + card.height <= grid.contentY + grid.height + 0.5
                compare(card.visible, fits)
                compare(card.enabled, fits)
                if (fits) ++visibleCards
                else if (card.y < grid.contentY + grid.height && card.y + card.height > grid.contentY) ++clippedCards
            }
            verify(visibleCards >= grid.columnCount, "At least one complete row must remain visible")
            if (offset === 79) verify(clippedCards > 0, "Test must include a partially clipped row")
        }
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
