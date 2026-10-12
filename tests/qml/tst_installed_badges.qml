import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as App

TestCase {
    name: "InstalledBadges"
    when: main.visible
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property var updates: ({state: "idle", items: []})
        property var installSizes: ({})
        function requestInstallInfo(app) {}
    }
    App.Main {
        id: main
        backend: backend
        catalogStats: null
        catalogPreferences: null
        networkStatus: null
    }
    function app(id, name) {
        return {id: id, name: name, summary: "Installed badge test", developer: "Test publisher",
            icon: "", category: "Internet", description: "Test", screenshots: [], sources: [],
            homepage: "", license: "MIT", version: "1", remote: "flathub",
            sourceUrl: "https://dl.flathub.org/repo/", flatpakRef: "app/" + id + "/x86_64/stable",
            searchName: name.toLowerCase(), searchSummary: "test", searchDescription: "test",
            searchMetadata: id, searchHaystack: name.toLowerCase() + " test"}
    }
    function installed(id, name, scope) {
        return Object.assign(app(id, name), {installation:scope, installedVersion:"1", installedBranch:"stable",
            installedArch:"x86_64", installedRef:"app/" + id + "/x86_64/stable", installedOrigin:"flathub",
            installedSize:"1 MiB", installedBytes:1048576, installedDate:"", updatedDate:""})
    }
    function stack() { return findChild(main, "navigationStack") }
    function page() { return stack().get(0) }
    function grid() { return findChild(page(), "catalogGrid") }
    function card(id) {
        const index = page().visibleApps.findIndex(app => app.id === id)
        verify(index >= 0)
        grid().positionViewAtIndex(index, GridView.Contain)
        tryVerify(() => !!grid().itemAtIndex(index))
        return grid().itemAtIndex(index)
    }
    function badge(card) { return findChild(card, "installedBadge") }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.showHome(); tryCompare(stack(), "busy", false)
        main.width = 1320; main.height = 1000
        main.catalog = [app("org.mozilla.firefox.desktop", "Firefox"),
            app("com.mojang.Minecraft", "Minecraft"), app("com.spotify.Client", "Spotify")]
        backend.installedApps = [installed("org.mozilla.firefox", "Firefox", "default"),
            installed("com.spotify.Client", "Spotify", "user")]
        backend.jobs = []; backend.updates = {state:"idle", items:[]}
        page().catalogSortIndex = 0
        waitForPolish(page())
    }
    function test_home_system_user_and_uninstalled() {
        verify(badge(card("org.mozilla.firefox.desktop")).visible, "System install with AppStream alias")
        verify(badge(card("com.spotify.Client")).visible, "User installation")
        verify(!badge(card("com.mojang.Minecraft")).visible)
    }
    function test_common_favorite_cards() {
        const spotify = findChild(page(), "recommended-com.spotify.Client")
        const minecraft = findChild(page(), "recommended-com.mojang.Minecraft")
        verify(spotify && minecraft)
        verify(badge(spotify).visible); verify(!badge(minecraft).visible)
        verify(spotify.Accessible.description.startsWith("Installed\n"))
    }
    function test_search_and_category() {
        main.searchText = "firefox"
        tryCompare(grid(), "count", 1)
        verify(badge(card("org.mozilla.firefox.desktop")).visible)
        main.searchText = "minecraft"
        tryCompare(grid(), "count", 1)
        verify(!badge(card("com.mojang.Minecraft")).visible)
        main.searchText = ""; page().openCategory("Internet")
        verify(badge(card("org.mozilla.firefox.desktop")).visible)
    }
    function test_live_install_and_remove_without_catalog_reload() {
        const entry = card("com.mojang.Minecraft")
        const common = findChild(page(), "recommended-com.mojang.Minecraft")
        verify(!entry.installed)
        backend.installedApps = backend.installedApps.concat([installed("com.mojang.Minecraft", "Minecraft", "user")])
        tryCompare(entry, "installed", true); verify(common.installed)
        backend.installedApps = []
        tryCompare(entry, "installed", false); verify(!common.installed)
        compare(main.catalog.length, 3)
    }
    function test_queued_or_stale_catalog_flag_is_not_installed() {
        main.catalog = main.catalog.map(app => Object.assign({}, app, {installed:true}))
        backend.installedApps = []
        backend.jobs = [{id:"com.mojang.Minecraft", action:"install", active:true, queued:true}]
        verify(!badge(card("com.mojang.Minecraft")).visible)
        verify(!badge(findChild(page(), "recommended-com.mojang.Minecraft")).visible)
    }
    function test_updates_has_no_badges() {
        backend.updates = {state:"ready", items:[{key:"default:firefox", id:"org.mozilla.firefox",
            name:"Firefox", installation:"default", selected:true, oldVersion:"1", newVersion:"2",
            plan:[], permissions:{state:"unchanged", groups:[]}}]}
        main.showUpdates()
        const updates = findChild(page(), "updatesPage")
        tryCompare(updates, "visible", true)
        verify(!findChild(updates, "installedBadge"))
    }
    function test_badge_does_not_block_opening_app() {
        const entry = card("org.mozilla.firefox.desktop")
        const indicator = badge(entry)
        waitForRendering(entry)
        const point = indicator.mapToItem(entry, indicator.width / 2, indicator.height / 2)
        mouseClick(entry, point.x, point.y)
        tryCompare(stack(), "busy", false)
        compare(main.selectedApp.id, "org.mozilla.firefox.desktop")
        compare(stack().depth, 2)
    }
    function test_theme_data() {
        return [{tag:"light", bg:"#eff0f1", text:"#232629"}, {tag:"dark", bg:"#202326", text:"#ffffff"}]
    }
    function test_theme(data) {
        main.palette.window = data.bg; main.palette.windowText = data.text
        const indicator = badge(card("org.mozilla.firefox.desktop"))
        compare(indicator.color, "#27ae60")
        compare(indicator.border.color, main.surfaceColor)
        tryCompare(indicator.children[0], "status", Image.Ready)
        verify(indicator.children[0].source.toString().endsWith("check-white.svg"))
    }
    Component { id: compactCard; App.RecommendedAppCard { property var window: main } }
    function test_compact_badge_data() { return [{tag:"tight", width:110}, {tag:"dense", width:150}, {tag:"normal", width:220}] }
    function test_compact_badge(data) {
        const entry = createTemporaryObject(compactCard, main.contentItem,
            {app: main.catalog[2], width:data.width, height:96, installed:true})
        verify(entry)
        waitForPolish(entry)
        const indicator = badge(entry)
        verify(indicator.visible)
        const point = indicator.mapToItem(entry, 0, 0)
        verify(point.x >= 0 && point.y >= 0)
        verify(point.x + indicator.width <= entry.width && point.y + indicator.height <= entry.height)
    }
}
