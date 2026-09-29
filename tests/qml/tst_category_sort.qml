import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "CategorySorting"
    when: main.visible
    AppCenter.Main { id: main; catalogStats: stats; catalogPreferences: preferences }
    QtObject { id: preferences; property string homeSort: "release-asc" }
    QtObject {
        id: stats
        property var counts: ({})
        property string state: "ready"
        property int requests: 0
        function loadPopularity() { requests++ }
    }
    function page() { return findChild(main, "navigationStack").get(0) }
    function names() { return page().visibleApps.map(app => app.name).join(",") }
    function app(id, name, category, date) {
        return {id:id, name:name, category:category, summary:"Category test", icon:"", description:"Test",
            screenshots:[], sources:[], homepage:"", license:"MIT", developer:"Test", version:"1.0",
            sourceUrl:"https://dl.flathub.org/repo/", flatpakRef:"app/" + id + "/x86_64/stable",
            releaseDate:date, searchName:name.toLowerCase(), searchSummary:"test", searchDescription:"test",
            searchMetadata:id, searchHaystack:name.toLowerCase() + " test"}
    }
    function catalog(category) {
        return [app("org.example.Beta", "Beta", category, "2026-09-01"),
            app("org.example.Alpha", "Alpha", category, "2026-09-24"),
            app("org.example.Unknown", "Unknown", category, "bad"),
            app("org.example.Zero", "Zero", category, "2020-01-01"),
            app("org.example.Outside", "Outside", category === "Games" ? "Office" : "Games", "2026-09-25")]
    }
    function selectCategory(category) {
        page().openCategory(category)
        waitForPolish(page()); wait(10)
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.showCatalog(); tryCompare(findChild(main, "navigationStack"), "busy", false)
        main.width = 1180; main.height = 760
        main.searchText = ""; main.selectedCategory = "All Apps"
        page().catalogSortIndex = 5
        stats.counts = {"org.example.Alpha":5, "org.example.Beta":10, "org.example.Zero":0}
        stats.state = "ready"; stats.requests = 0
        main.catalog = catalog("Utilities")
    }
    function test_all_category_orders_data() {
        const rows = []
        for (const category of page().categories.slice(1)) {
            for (const order of [
                {index:0, expected:"Alpha,Beta,Unknown,Zero"},
                {index:1, expected:"Zero,Unknown,Beta,Alpha"},
                {index:2, expected:"Beta,Alpha,Zero,Unknown"},
                {index:3, expected:"Zero,Alpha,Beta,Unknown"},
                {index:4, expected:"Alpha,Beta,Zero,Unknown"},
                {index:5, expected:"Zero,Beta,Alpha,Unknown"}])
                rows.push({tag:category.name + "-" + order.index, category:category.name,
                    index:order.index, expected:order.expected})
        }
        return rows
    }
    function test_all_category_orders(data) {
        main.catalog = catalog(data.category)
        selectCategory(data.category)
        const sort = findChild(page(), "catalogSort")
        verify(sort && sort.visible)
        compare(sort.currentIndex, 0)
        compare(sort.count, 6)
        sort.activated(data.index)
        compare(sort.currentIndex, data.index)
        compare(names(), data.expected)
        compare(main.catalog[0].name, "Beta", "Do not mutate the underlying catalog")
        compare(page().catalogSortIndex, 5)
        compare(preferences.homeSort, "release-asc", "Never save category sorts over Home's choice")
    }
    function test_switching_categories_resets_only_category_sort() {
        selectCategory("Utilities")
        page().setCatalogSort(1)
        compare(names(), "Zero,Unknown,Beta,Alpha")
        selectCategory("Games")
        compare(page().categorySortIndex, 0)
        page().setCatalogSort(4)
        selectCategory("Utilities")
        compare(page().categorySortIndex, 0)
        compare(names(), "Alpha,Beta,Unknown,Zero")
        selectCategory("All Apps")
        compare(findChild(page(), "catalogSort").currentIndex, 5)
        compare(preferences.homeSort, "release-asc")
    }
    function test_category_popularity_loads_and_keeps_recommendations() {
        main.catalog = catalog("Utilities").concat([app("com.discordapp.Discord", "Discord", "Utilities", "")])
        selectCategory("Utilities")
        compare(stats.requests, 0, "A-Z categories need no popularity request")
        page().setCatalogSort(2)
        compare(stats.requests, 1)
        verify(page().visibleApps.some(app => app.id === "com.discordapp.Discord"))
        stats.counts = {"com.discordapp.Discord":100, "org.example.Alpha":10, "org.example.Beta":5}
        compare(page().visibleApps[0].name, "Discord", "New statistics reorder the current category")
        page().setCatalogSort(3)
        verify(page().visibleApps.some(app => app.id === "com.discordapp.Discord"))
        stats.counts = {}; stats.state = "unavailable"
        compare(names(), "Alpha,Beta,Discord,Unknown,Zero")
        verify(findChild(page(), "catalogSortDescription").visible)
        verify(findChild(page(), "catalogSortDescription").text.indexOf("unavailable") >= 0)
        page().setCatalogSort(4)
        verify(findChild(page(), "catalogSortDescription").text.indexOf("release date") >= 0)
    }
    function test_search_installed_updates_remain_independent() {
        selectCategory("Utilities"); page().setCatalogSort(3)
        main.searchText = "alpha"
        compare(names(), "Alpha")
        verify(!findChild(page(), "catalogSort").visible)
        verify(findChild(page(), "searchCategoryFilter").visible)
        verify(!findChild(page(), "catalogSortDescription").visible)
        selectCategory("Installed")
        verify(findChild(page(), "installedSort").visible)
        verify(!findChild(page(), "catalogSort").visible)
        compare(page().installedSortIndex, 0)
        selectCategory("Updates")
        verify(!findChild(page(), "catalogSort").visible)
        compare(page().catalogSortIndex, 5)
        compare(preferences.homeSort, "release-asc")
    }
    function test_popularity_loading_has_no_message_data() {
        const rows = []
        for (const category of ["All Apps", "Utilities"])
            for (const cached of [false, true])
                for (const order of [2, 3])
                    rows.push({tag:category + "-" + cached + "-" + order,
                        category:category, cached:cached, order:order})
        return rows
    }
    function test_popularity_loading_has_no_message(data) {
        selectCategory(data.category)
        if (!data.cached) stats.counts = {}
        stats.state = "loading"
        page().setCatalogSort(data.order)
        waitForPolish(page())
        verify(findChild(page(), "catalogSort").visible)
        compare(page().sortDescription, "")
        verify(!findChild(page(), "catalogSortDescription").visible)
        compare(page().visibleApps[0].name, !data.cached ? "Alpha" : data.order === 2 ? "Beta" : "Zero")

        stats.counts = {"org.example.Alpha":100, "org.example.Beta":5, "org.example.Zero":0}
        stats.state = "ready"
        compare(page().visibleApps[0].name, data.order === 2 ? "Alpha" : "Zero")
        compare(findChild(page(), "catalogSort").currentIndex, data.order)
        verify(!findChild(page(), "catalogSortDescription").visible)
    }
    function test_details_back_preserves_active_visit() {
        selectCategory("Utilities"); page().setCatalogSort(1)
        main.openApp(main.catalog[0])
        tryCompare(findChild(main, "navigationStack"), "busy", false)
        main.goBack()
        tryCompare(findChild(main, "navigationStack"), "busy", false)
        compare(page().categorySortIndex, 1, "Returning from details resumes the same category visit")
        compare(preferences.homeSort, "release-asc")
    }
    function test_layout_data() {
        return [{tag:"narrow", width:720, height:520}, {tag:"wide", width:1400, height:1000},
            {tag:"short", width:1180, height:520}]
    }
    function test_layout(data) {
        main.width = data.width; main.height = data.height
        selectCategory("Audio & Video"); page().setCatalogSort(4)
        waitForPolish(page())
        const sort = findChild(page(), "catalogSort"), grid = findChild(page(), "catalogGrid")
        verify(sort.visible && sort.width >= 210)
        verify(sort.mapToItem(page(), 0, 0).x >= 0)
        verify(sort.mapToItem(page(), sort.width, 0).x <= page().width - 20)
        verify(sort.mapToItem(page(), 0, sort.height).y <= grid.mapToItem(page(), 0, 0).y)
        verify(grid.height >= 100, "Leave space for apps below the category heading")
    }
}
