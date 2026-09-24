import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "HomeCatalog"
    when: main.visible
    AppCenter.Main { id: main; catalogStats: stats; catalogPreferences: preferences }
    QtObject { id: preferences; property string homeSort: "popularity-desc" }
    QtObject {
        id: stats
        property var counts: ({"org.example.Alpha":5, "org.example.Beta":10, "org.example.Zero":0})
        property string state: "ready"
        property int requests: 0
        function loadPopularity() { requests++ }
    }
    function app(id, name, size, date) {
        return {id:id, name:name, summary:"Home test", category:"Utilities", icon:"", description:"Test app",
            screenshots:[], sources:[], homepage:"", license:"MIT", developer:"Test", version:"1.0",
            sourceUrl:"https://dl.flathub.org/repo/", flatpakRef:"app/" + id + "/x86_64/stable",
            downloadBytes:size, releaseDate:date, searchName:name.toLowerCase(), searchSummary:"test",
            searchDescription:"test", searchMetadata:id, searchHaystack:name.toLowerCase() + " test"}
    }
    function page() { return findChild(main, "navigationStack").get(0) }
    function names() { return page().visibleApps.map(app => app.name).join(",") }
    function initTestCase() {
        compare(page().catalogSortIndex, 2, "Home defaults to popularity")
        compare(page().installedSortIndex, 0, "Installed still defaults to A–Z")
        verify(stats.requests >= 1, "Home requests popularity presentation data")
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.showCatalog(); tryCompare(findChild(main, "navigationStack"), "busy", false)
        main.width = 1180; main.height = 760
        main.searchText = ""; main.selectedCategory = "All Apps"
        stats.state = "ready"; stats.requests = 0
        stats.counts = {"org.example.Alpha":5, "org.example.Beta":10, "org.example.Zero":0}
        main.catalog = [app("org.example.Beta", "Beta", 900, "2026-09-01"),
            app("org.example.Alpha", "Alpha", 100, "2026-09-24"),
            app("org.example.Unknown", "Unknown", null, "bad"),
            app("org.example.Zero", "Zero", 0, "2020-01-01")]
        page().catalogSortIndex = 0
        waitForPolish(page()); wait(30)
    }
    function test_orders_data() {
        return [{tag:"az", index:0, expected:"Alpha,Beta,Unknown,Zero"},
            {tag:"za", index:1, expected:"Zero,Unknown,Beta,Alpha"},
            {tag:"popular", index:2, expected:"Beta,Alpha,Zero,Unknown"},
            {tag:"least-popular", index:3, expected:"Zero,Alpha,Beta,Unknown"},
            {tag:"small", index:4, expected:"Zero,Alpha,Beta,Unknown"},
            {tag:"large", index:5, expected:"Beta,Alpha,Zero,Unknown"},
            {tag:"new", index:6, expected:"Alpha,Beta,Zero,Unknown"},
            {tag:"old", index:7, expected:"Zero,Beta,Alpha,Unknown"}]
    }
    function test_orders(data) {
        page().catalogSortIndex = data.index
        compare(names(), data.expected)
        compare(main.catalog[0].name, "Beta", "Never mutate the catalog")
        compare(preferences.homeSort, page().catalogSortKeys[data.index])
    }
    function test_popularity_note_removed() {
        page().catalogSortIndex = 2
        compare(page().sortDescription, "")
        verify(!findChild(page(), "catalogSortDescription").visible)
    }
    function test_home_only_and_offline_fallback() {
        page().catalogSortIndex = 2
        compare(stats.requests, 1)
        stats.counts = {}; stats.state = "unavailable"
        compare(names(), "Alpha,Beta,Unknown,Zero")
        verify(findChild(page(), "catalogSortDescription").text.indexOf("unavailable") >= 0)
        page().catalogSortIndex = 1
        main.selectedCategory = "Utilities"
        compare(names(), "Beta,Alpha,Unknown,Zero", "Home sorting must not change other categories")
        verify(!findChild(page(), "catalogSort").visible)
        main.selectedCategory = "All Apps"; main.searchText = "beta"
        compare(names(), "Beta")
        verify(!findChild(page(), "recommendedHeading").visible)
        main.searchText = ""; compare(names(), "Zero,Unknown,Beta,Alpha")
    }
    function test_recommendations_stable_alphabetical_and_clickable() {
        const picks = [app("org.telegram.desktop", "Telegram", 10, ""),
            app("com.discordapp.Discord", "Discord", 20, ""), app("com.valvesoftware.Steam", "Steam", 30, "")]
        const fake = app("com.google.Chrome", "Untrusted Chrome", 1, ""); fake.sourceUrl = "https://example.org/repo"
        const beta = app("com.brave.Browser", "Brave Beta", 1, ""); beta.flatpakRef = "app/com.brave.Browser/x86_64/beta"
        main.catalog = picks.concat([fake, beta])
        const expected = "Discord,Steam,Telegram"
        compare(page().recommendedApps.map(app => app.name).join(","), expected)
        for (let index = 0; index < 8; ++index) {
            page().catalogSortIndex = index
            compare(page().recommendedApps.map(app => app.name).join(","), expected)
        }
        const grid = findChild(page(), "catalogGrid")
        grid.positionViewAtBeginning(); waitForPolish(grid); wait(50)
        const card = findChild(page(), "recommended-com.discordapp.Discord")
        verify(card && card.visible)
        mouseClick(card)
        tryCompare(findChild(main, "navigationStack"), "depth", 2)
        compare(main.selectedApp.id, "com.discordapp.Discord")
        main.goBack(); tryCompare(findChild(main, "navigationStack"), "busy", false)
    }
    function test_responsive_header_data() {
        return [{tag:"narrow", width:720, height:520}, {tag:"wide", width:1400, height:1000},
            {tag:"short", width:1180, height:520}, {tag:"desktop", width:1920, height:1080}]
    }
    function test_sort_keeps_all_apps_heading_visible() {
        main.width = 720; main.height = 540
        main.catalog = page().recommendedIds.map((id, i) => app(id, "Pick " + i, i, ""))
            .concat(main.catalog)
        waitForPolish(page()); wait(50)
        page().catalogSortIndex = 1
        waitForPolish(page()); wait(50)
        const grid = findChild(page(), "catalogGrid"), sort = findChild(page(), "catalogSort")
        verify(sort.mapToItem(grid, 0, 0).y >= 0)
        verify(sort.mapToItem(grid, 0, sort.height).y < grid.height,
               "Sorting must not scroll the control out of view")
        page().catalogSortIndex = 2
        wait(50)
        stats.counts = {"org.example.Alpha":20, "org.example.Beta":10}
        waitForPolish(page()); wait(50)
        verify(sort.mapToItem(grid, 0, 0).y < 150,
               "Arriving popularity data must keep All Apps near the top")
    }
    function test_responsive_header(data) {
        main.width = data.width; main.height = data.height
        const titles = {"com.discordapp.Discord":"Discord", "com.valvesoftware.Steam":"Steam",
            "org.telegram.desktop":"Telegram", "com.spotify.Client":"Spotify", "com.google.Chrome":"Google Chrome",
            "com.brave.Browser":"Brave", "com.visualstudio.code":"Visual Studio Code",
            "org.vinegarhq.Sober":"Sober", "com.mojang.Minecraft":"Minecraft Launcher"}
        compare(page().recommendedIds.length, 9)
        main.catalog = page().recommendedIds.map(id => app(id, titles[id], 1, ""))
        waitForPolish(page()); wait(100)
        const grid = findChild(page(), "catalogGrid"), sort = findChild(page(), "catalogSort")
        grid.positionViewAtBeginning(); wait(50)
        verify(sort.width > 100)
        verify(sort.mapToItem(page(), sort.width, 0).x <= page().width - 20)
        const heading = findChild(page(), "recommendedHeading")
        verify(heading.mapToItem(grid, 0, 0).y >= -1, "Recommendations reachable at top")
        verify(heading.mapToItem(grid, 0, 0).y < sort.mapToItem(grid, 0, 0).y)
        verify(grid.headerItem.height <= grid.height - 32,
               "Home must show All Apps and the beginning of its list without scrolling")
        for (const pick of page().recommendedApps) {
            const card = findChild(page(), "recommended-" + pick.id)
            verify(card.mapToItem(grid, 0, 0).y >= 0 && card.mapToItem(grid, 0, card.height).y < grid.height)
            verify(!findChild(card, "recommendedAppName").truncated, pick.name + " should remain readable")
        }
        grid.positionViewAtEnd(); wait(30)
        findChild(page(), "catalogNaturalScroll").scrollBy(-10000, false)
        wait(30)
        verify(heading.mapToItem(grid, 0, 0).y >= -1, "Mouse wheel reaches recommendations again")
    }
}
