import QtQuick
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Installed"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    function test_installation_date_only_when_recorded() {
        const app = {id: "org.example.Dated", name: "Dated app", icon: "", summary: "", description: "",
            category: "", license: "", homepage: "", developer: "", screenshots: [],
            installedSize: "10 MB", installedVersion: "1.0", installation: "user",
            installedBranch: "stable", installedArch: "x86_64"}
        const stack = findChild(main, "navigationStack")
        main.showCatalog(); tryCompare(stack, "busy", false)
        main.selectedCategory = "Installed"
        main.installedApps = [app]
        const list = findChild(stack.currentItem, "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        verify(!findChild(list.itemAtIndex(0), "installedDateCaption").visible)
        verify(!findChild(list.itemAtIndex(0), "installedDateValue").visible)
        compare(findChild(list.itemAtIndex(0), "installedUpdatedDateValue").text, "Not recorded")
        main.openApp(app); tryCompare(stack, "busy", false)
        verify(!findChild(stack.currentItem, "appInstalledDateCaption").visible)
        verify(!findChild(stack.currentItem, "appInstalledDateValue").visible)
        main.installedApps = [Object.assign({}, app, {installedDate: "16 September 2026", updatedDate: "23 September 2026"})]
        compare(findChild(stack.currentItem, "appInstalledDateValue").text, "16 September 2026")
        verify(findChild(stack.currentItem, "appInstalledDateCaption").visible)
        verify(findChild(stack.currentItem, "appInstalledDateValue").visible)
        compare(findChild(stack.currentItem, "appUpdatedDateValue").text, "Last updated: 23 September 2026")
        main.showCatalog(); tryCompare(stack, "busy", false)
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const date = findChild(list.itemAtIndex(0), "installedDateValue")
        verify(date.visible && date.font.bold)
        compare(date.text, "16 September 2026")
        compare(findChild(list.itemAtIndex(0), "installedUpdatedDateValue").text, "23 September 2026")
        const formerlyInstalled = main.installedApps[0]
        main.installedApps = []
        compare(main.detailsFor(formerlyInstalled).installedDate, undefined)
        compare(main.detailsFor(formerlyInstalled).updatedDate, undefined)
        main.selectedCategory = "All Apps"
    }
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
