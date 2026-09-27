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
        compare(page().installedSortIndex, 0, "Installed still defaults to A-Z")
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
            {tag:"new", index:4, expected:"Alpha,Beta,Zero,Unknown"},
            {tag:"old", index:5, expected:"Zero,Beta,Alpha,Unknown"}]
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
    function test_popularity_labels() {
        for (const category of ["All Apps", "Utilities"]) {
            page().openCategory(category)
            waitForPolish(page()); wait(30)
            const sort = findChild(page(), "catalogSort")
            for (const choice of [{index:2, label:"Most popular: First", key:"popularity-desc"},
                                  {index:3, label:"Least popular: First", key:"popularity-asc"}]) {
                page().setCatalogSort(choice.index)
                compare(page().catalogSortOptions[choice.index], choice.label)
                tryCompare(sort, "currentText", choice.label)
                compare(page().catalogSortKeys[choice.index], choice.key, "Saved sort keys stay compatible")
                if (category === "All Apps") compare(preferences.homeSort, choice.key)
                else compare(preferences.homeSort, "popularity-asc", "Category changes remain temporary")
            }
        }
    }
    function test_app_counts_removed_data() {
        return [{tag:"home", category:"All Apps", search:"", title:"All Apps"},
            {tag:"category", category:"Utilities", search:"", title:"Utilities"},
            {tag:"installed", category:"Installed", search:"", title:"Installed"},
            {tag:"search", category:"All Apps", search:"alpha", title:"Search results"}]
    }
    function test_app_counts_removed(data) {
        page().openCategory(data.category)
        main.searchText = data.search
        waitForPolish(page()); wait(30)
        compare(findChild(page(), "catalogTitleLabel").text, data.title)
        verify(!findChild(page(), "catalogCountLabel"), "No application count in any list heading")
    }
    function test_home_size_options_removed() {
        compare(page().catalogSortKeys.join(","), "name-asc,name-desc,popularity-desc,popularity-asc,release-desc,release-asc")
        compare(page().catalogSortOptions.length, 6)
        verify(!page().catalogSortOptions.some(option => option.indexOf("Size:") >= 0))
        compare(page().installedSortOptions.length, 6)
        verify(page().installedSortOptions[4].indexOf("Size:") === 0, "Installed keeps size sorting")
    }
    function test_popularity_omits_only_visible_recommendations_data() {
        return [{tag:"most", index:2}, {tag:"least", index:3}]
    }
    function test_popularity_omits_only_visible_recommendations(data) {
        const discord = app("com.discordapp.Discord", "Discord", 20, "2026-01-01")
        discord.id += ".desktop" // AppStream alias; identity must come from the Flatpak ref.
        const telegram = app("org.telegram.desktop", "Telegram", 10, "2026-01-01")
        telegram.sources = [Object.assign({}, telegram)]
        telegram.flatpakRef = "app/org.telegram.desktop/x86_64/beta" // Stable alternate is recommended.
        const fake = app("com.google.Chrome", "Untrusted Chrome", 1, "")
        fake.sourceUrl = "https://example.org/repo"
        const beta = app("com.brave.Browser", "Brave Beta", 1, "")
        beta.flatpakRef = "app/com.brave.Browser/x86_64/beta"
        const zoom = app("us.zoom.Zoom", "Zoom", 15, "2026-01-01")
        main.catalog = main.catalog.concat([discord, telegram, zoom, fake, beta])
        page().catalogSortIndex = data.index
        compare(page().recommendedApps.map(app => app.name).join(","), "Discord,Telegram,Zoom")
        compare(page().visibleApps.length, 6)
        verify(!page().visibleApps.some(app => ["Discord", "Telegram", "Zoom"].indexOf(app.name) >= 0))
        verify(page().visibleApps.some(app => app.name === "Untrusted Chrome"), "Unavailable recommendations must not hide an app")
        verify(page().visibleApps.some(app => app.name === "Brave Beta"))
        stats.counts = {}; stats.state = "unavailable"
        compare(page().visibleApps.length, 6, "Offline popularity fallback must also avoid duplicates")
        for (const index of [0, 1, 4, 5]) {
            page().catalogSortIndex = index
            compare(page().visibleApps.length, 9, "Name/date sorts retain all apps")
        }
        page().catalogSortIndex = data.index
        main.selectedCategory = "Utilities"
        compare(page().visibleApps.length, 9, "Categories retain recommendations")
        main.selectedCategory = "All Apps"; main.searchText = "telegram"
        compare(names(), "Telegram", "Search retains recommendations")
        main.searchText = ""
        compare(page().visibleApps.length, 6)
        main.catalog = main.catalog.map(function(app) {
            if (app.name !== "Discord") return app
            const changed = Object.assign({}, app); changed.sourceUrl = "https://example.org/repo"
            return changed
        })
        compare(page().recommendedApps.length, 2)
        compare(page().visibleApps.length, 7, "An app reappears when no longer in recommendations")
    }
    Component {
        id: cardFixture
        AppCenter.AppCard { property var window: main; width: 285; height: 142 }
    }
    function cardTexts(item) {
        let texts = typeof item.text === "string" ? [item.text] : []
        for (const child of item.children || []) texts = texts.concat(cardTexts(child))
        return texts
    }
    function test_app_cards_have_no_category_tag() {
        const card = createTemporaryObject(cardFixture, main.contentItem,
            {app: app("org.example.Alpha", "Alpha", 100, "")})
        verify(card)
        waitForPolish(card)
        const texts = cardTexts(card.contentItem)
        verify(texts.indexOf("Alpha") >= 0)
        verify(texts.indexOf("Home test") >= 0)
        verify(texts.indexOf("Utilities") < 0, "Category label must not appear on catalog cards")
    }
    function test_home_only_and_offline_fallback() {
        page().catalogSortIndex = 2
        compare(stats.requests, 1)
        stats.counts = {}; stats.state = "unavailable"
        compare(names(), "Alpha,Beta,Unknown,Zero")
        verify(findChild(page(), "catalogSortDescription").text.indexOf("unavailable") >= 0)
        page().catalogSortIndex = 1
        main.selectedCategory = "Utilities"
        compare(names(), "Alpha,Beta,Unknown,Zero", "Categories start with their own A-Z order")
        verify(findChild(page(), "catalogSort").visible)
        main.selectedCategory = "All Apps"; main.searchText = "beta"
        compare(names(), "Beta")
        verify(!findChild(page(), "recommendedHeading").visible)
        main.searchText = ""; compare(names(), "Zero,Unknown,Beta,Alpha")
    }
    function test_recommendations_stable_alphabetical_and_clickable() {
        const picks = [app("org.telegram.desktop", "Telegram", 10, ""),
            app("com.discordapp.Discord", "Discord", 20, ""), app("com.valvesoftware.Steam", "Steam", 30, ""),
            app("us.zoom.Zoom", "Zoom", 40, "")]
        const fake = app("com.google.Chrome", "Untrusted Chrome", 1, ""); fake.sourceUrl = "https://example.org/repo"
        const beta = app("com.brave.Browser", "Brave Beta", 1, ""); beta.flatpakRef = "app/com.brave.Browser/x86_64/beta"
        main.catalog = picks.concat([fake, beta])
        const expected = "Discord,Steam,Telegram,Zoom"
        compare(page().recommendedApps.map(app => app.name).join(","), expected)
        for (let index = 0; index < page().catalogSortOptions.length; ++index) {
            page().catalogSortIndex = index
            compare(page().recommendedApps.map(app => app.name).join(","), expected)
        }
        const grid = findChild(page(), "catalogGrid")
        grid.positionViewAtBeginning(); waitForPolish(grid); wait(50)
        const card = findChild(page(), "recommended-us.zoom.Zoom")
        verify(card && card.visible)
        mouseClick(card)
        tryCompare(findChild(main, "navigationStack"), "depth", 2)
        compare(main.selectedApp.id, "us.zoom.Zoom")
        main.goBack(); tryCompare(findChild(main, "navigationStack"), "busy", false)
    }
    function test_responsive_header_data() {
        return [{tag:"narrow", width:720, height:520}, {tag:"wide", width:1400, height:1000},
            {tag:"short", width:1180, height:520}, {tag:"desktop", width:1920, height:1080},
            {tag:"narrow-medium", width:720, height:640}, {tag:"narrow-tall", width:720, height:760}]
    }
    function verifyAppListSpacing(grid) {
        const title = findChild(page(), "catalogTitleLabel"), sort = findChild(page(), "catalogSort")
        const common = findChild(page(), "recommendedGrid")
        if (common.visible) {
            const headingTop = Math.min(title.mapToItem(grid, 0, 0).y, sort.mapToItem(grid, 0, 0).y)
            fuzzyCompare(headingTop - common.mapToItem(grid, 0, common.height).y,
                         (grid.height < 500 ? 4 : 8) + 8, 1)
        }
        const firstCard = grid.itemAtIndex(0)
        verify(firstCard, "First app card must remain visible")
        const headingBottom = Math.max(title.mapToItem(grid, 0, title.height).y,
                                      sort.mapToItem(grid, 0, sort.height).y)
        const gap = firstCard.mapToItem(grid, 0, 0).y - headingBottom
        const expected = grid.height < 500 ? 16 : 24
        verify(Math.abs(gap - expected) < 1, "Heading/sort-to-card gap: " + gap + " expected " + expected)
    }
    function test_spacing_without_recommendations() {
        const grid = findChild(page(), "catalogGrid")
        grid.positionViewAtBeginning(); waitForPolish(grid); wait(30)
        compare(page().recommendedApps.length, 0)
        verifyAppListSpacing(grid)
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
            "org.vinegarhq.Sober":"Sober", "com.mojang.Minecraft":"Minecraft Launcher", "us.zoom.Zoom":"Zoom"}
        compare(page().recommendedIds.length, 10)
        main.catalog = page().recommendedIds.map(id => app(id, titles[id], 1, ""))
        waitForPolish(page()); wait(100)
        const grid = findChild(page(), "catalogGrid"), sort = findChild(page(), "catalogSort")
        grid.positionViewAtBeginning(); wait(50)
        verify(sort.width > 100)
        verify(sort.mapToItem(page(), sort.width, 0).x <= page().width - 20)
        const heading = findChild(page(), "recommendedHeading")
        compare(heading.text, "Common Apps")
        compare(page().recommendedApps[9].id, "us.zoom.Zoom")
        if (data.width >= 1400) compare(findChild(page(), "recommendedGrid").columns, 5)
        verify(heading.mapToItem(grid, 0, 0).y >= -1, "Recommendations reachable at top")
        verify(heading.mapToItem(grid, 0, 0).y < sort.mapToItem(grid, 0, 0).y)
        verify(grid.headerItem.height <= grid.height - 32,
               "Home must show All Apps and the beginning of its list without scrolling")
        verifyAppListSpacing(grid)
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
