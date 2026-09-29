import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "InstalledSort"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    readonly property var apps: [
        {id: "org.example.A", name: "Alpha", installedAt: "2026-09-17T12:00:00Z", installedBytes: 1073741824, installedSize: "1.00 GiB"},
        {id: "org.example.B", name: "Beta", installedAt: "2025-09-17T12:00:00Z", installedBytes: 524288000, installedSize: "500.00 MiB"},
        {id: "org.example.C", name: "Gamma", installedAt: "invalid", installedSize: "Unavailable"},
        // Same displayed size/date as Alpha, but a different unrounded byte count.
        {id: "org.example.D", name: "Delta", installedAt: "2026-09-17T12:00:00Z", installedBytes: 1073741825, installedSize: "1.00 GiB"},
        {id: "org.example.E", name: "Empty", installedBytes: 0, installedSize: "0.00 MiB"}
    ]
    function page() { return findChild(main, "navigationStack").currentItem }
    function names() { return page().installedMatches.map(app => app.name).join(",") }
    function init() {
        main.requestActivate()
        main.width = 1180
        main.showCatalog()
        tryCompare(findChild(main, "navigationStack"), "busy", false)
        main.installedApps = apps
        main.selectedCategory = "Installed"
        main.searchText = ""
        main.installedError = ""
        main.installedLoading = false
        page().installedSortIndex = 0
        waitForRendering(page())
    }
    function test_orders_data() {
        return [
            {tag: "name-asc", index: 0, expected: "Alpha,Beta,Delta,Empty,Gamma"},
            {tag: "name-desc", index: 1, expected: "Gamma,Empty,Delta,Beta,Alpha"},
            {tag: "date-desc", index: 2, expected: "Alpha,Delta,Beta,Empty,Gamma"},
            {tag: "date-asc", index: 3, expected: "Beta,Alpha,Delta,Empty,Gamma"},
            {tag: "size-desc", index: 4, expected: "Delta,Alpha,Beta,Empty,Gamma"},
            {tag: "size-asc", index: 5, expected: "Empty,Beta,Alpha,Delta,Gamma"}
        ]
    }
    function test_orders(data) {
        page().installedSortIndex = data.index
        compare(names(), data.expected)
        compare(findChild(page(), "installedList").count, apps.length)
        compare(findChild(page(), "installedSort").currentIndex, data.index)
        compare(apps[0].name, "Alpha", "Sorting must not mutate the installed source list")
        compare(apps[3].name, "Delta")
    }
    function test_dropdown_keyboard_and_layout_data() {
        return [{tag: "wide", width: 1180}, {tag: "narrow", width: 720}]
    }
    function test_dropdown_keyboard_and_layout(data) {
        main.width = data.width
        const sort = findChild(page(), "installedSort")
        verify(sort.visible)
        mouseClick(sort)
        tryCompare(sort.popup, "visible", true)
        for (let index = 0; index < 5; ++index) keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        tryCompare(sort.popup, "visible", false)
        compare(page().installedSortIndex, 5)
        compare(names(), "Empty,Beta,Alpha,Delta,Gamma")
        waitForRendering(page())
        verify(sort.mapToItem(page(), sort.width, 0).x <= page().width - 27)
        const title = findChild(page(), "catalogTitleLabel")
        verify(sort.mapToItem(page(), 0, 0).x > title.mapToItem(page(), title.width, 0).x)
        main.selectedCategory = "All Apps"
        verify(!sort.visible)
        main.selectedCategory = "Installed"
        // Home has its own scrolling heading; returning recreates this heading.
        verify(findChild(page(), "installedSort").visible)
        compare(page().installedSortIndex, 5)
    }
    function test_search_and_live_refresh_preserve_order() {
        page().installedSortIndex = 4
        main.searchText = "alpha"
        compare(names(), "Alpha")
        main.searchText = "org.example"
        compare(names(), "Delta,Alpha,Beta,Empty,Gamma")
        main.installedApps = apps.filter(app => app.name !== "Delta")
        compare(names(), "Alpha,Beta,Empty,Gamma")
        compare(page().installedSortIndex, 4)
    }
    function test_empty_results_and_real_errors() {
        main.searchText = "does-not-exist"
        const empty = findChild(page(), "catalogEmptyMessage")
        verify(empty.visible)
        compare(empty.text, "No results.")
        main.installedError = "Unable to read installed apps"
        compare(empty.text, main.installedError)
        main.installedError = ""
        main.installedLoading = true
        verify(!empty.visible)
        main.installedLoading = false
        main.selectedCategory = "All Apps"
        verify(empty.visible)
        compare(empty.text, "No results.")
    }
}
