import QtQuick
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Installed"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    function test_installed_navigation_and_information() {
        main.installedApps = [{id: "org.example.Offline", name: "Offline app", icon: "",
            summary: "An installed app without catalog metadata", description: "Installed locally",
            category: "", license: "", homepage: "", developer: "", screenshots: [],
            installedSize: "125 MB", installedOrigin: "local", installation: "user",
            installedBranch: "stable", installedArch: "x86_64"}]
        const stack = findChild(main, "navigationStack")
        const catalog = stack.currentItem
        main.searchText = "unrelated"
        waitForRendering(catalog)
        mouseClick(findChild(catalog, "installedButton"))
        compare(stack.depth, 1)
        tryCompare(main, "searchText", "")
        compare(main.selectedCategory, "Installed")
        const list = findChild(catalog, "installedList")
        tryCompare(list, "count", 1)
        verify(list.visible)
        verify(findChild(catalog, "searchField").visible)
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const row = list.itemAtIndex(0)
        compare(findChild(row, "uninstallButton").enabled, false)
        mouseClick(row, 90, 30)
        tryCompare(stack, "busy", false)
        compare(stack.depth, 2)
        compare(main.selectedApp.id, "org.example.Offline")
        main.showCatalog()
        tryCompare(stack, "busy", false)
        compare(stack.currentItem, catalog)
        compare(main.selectedCategory, "Installed")
        verify(list.visible)
        catalog.openCategory("All Apps")
        verify(!list.visible)
    }
}
