import QtQuick
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
