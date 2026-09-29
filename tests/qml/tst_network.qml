import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "NetworkStates"
    when: main.visible
    AppCenter.Main { id: main; backend: backend; networkStatus: network; catalogStats: stats }
    QtObject { id: network; property string state: "online"; property bool ready: true }
    QtObject {
        id: stats
        property var counts: ({})
        property string state: "ready"
        property int requests: 0
        function loadPopularity() { requests++ }
    }
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property bool busy: false
        property bool catalogSourcesUnavailable: false
        property bool sourcesBusy: false
        property bool catalogLoading: false
        property int catalogProgress: 0
        property int refreshes: 0
        function refreshSources(catalogs) {
            if (catalogs) refreshes++
            catalogSourcesUnavailable = false
            sourcesBusy = true
        }
        property int iconRevision: 0
        property var updates: ({state:"idle", items:[]})
        property int checks: 0
        property int installs: 0
        property int cancelled: 0
        function checkForUpdates() { checks++ }
        function installSelectedUpdates() { installs++ }
        function cancelUpdateCheck() { cancelled++; updates = {state:"cancelled", items:[]}; busy = false }
        function selectUpdate(key, selected) {
            updates = Object.assign({}, updates, {items:updates.items.map(row => Object.assign({}, row, {selected:selected}))})
        }
        function selectAllUpdates(selected) { selectUpdate("", selected) }
        function requestInstallInfo(app) {}
    }
    function root() { return findChild(main, "navigationStack").get(0) }
    function control(name) { return findChild(root(), name) }
    function app(id, name) {
        return {id:id, name:name, summary:"Network fixture", description:"Network fixture", category:"Internet",
            icon:"", developer:"Publisher", version:"1.0", screenshots:[], sources:[],
            flatpakRef:"app/" + id + "/x86_64/stable", sourceUrl:"https://dl.flathub.org/repo/",
            searchName:name.toLowerCase(), searchHaystack:name.toLowerCase(), searchSummary:"", searchDescription:"", searchMetadata:id}
    }
    function settle() { waitForPolish(root()); wait(40) }
    function test_page_status_foreground_data() {
        return [{tag:"dark", background:"#202326", foreground:"#ffffff"},
            {tag:"light", background:"#eff0f1", foreground:"#202326"}]
    }
    function test_page_status_foreground(data) {
        const background = main.palette.window, foreground = main.palette.windowText
        function status(name) {
            const label = control(name)
            verify(label.visible, name + " is visible")
            verify(label.font.bold, name + " is bold")
            compare(label.color, main.textColor, name + " follows the theme foreground")
        }
        try {
            main.palette.window = data.background; main.palette.windowText = data.foreground
            main.catalog = []; backend.catalogLoading = true; settle()
            status("catalogEmptyMessage"); compare(control("catalogEmptyMessage").text, "Loading... 0%")
            backend.catalogLoading = false; settle()
            status("catalogEmptyMessage"); compare(control("catalogEmptyMessage").text, "No results.")
            root().openCategory("Installed"); backend.installedError = "Could not read installed apps."; settle()
            status("catalogEmptyMessage")
            root().openCategory("All Apps"); backend.installedError = ""
            network.state = "offline"; settle()
            status("networkOfflineTitle"); status("networkOfflineNote")
            network.state = "limited"; backend.catalogSourcesUnavailable = true; settle()
            status("networkOfflineTitle"); status("networkOfflineNote")
            backend.catalogSourcesUnavailable = false; main.showUpdates()
            backend.updates = {state:"checking", items:[]}; settle(); status("updateCheckStatus")
            for (const updates of [{state:"ready", items:[]}, {state:"error", items:[], error:"Connection failed"},
                                   {state:"cancelled", items:[]}]) {
                backend.updates = updates; settle(); status("updatesEmpty")
            }
        } finally {
            main.palette.window = background; main.palette.windowText = foreground
            backend.catalogLoading = false; backend.installedError = ""
        }
    }
    function test_loading_local_catalog_is_not_an_empty_result() {
        main.catalog = []
        backend.catalogLoading = true
        settle()
        compare(control("catalogEmptyMessage").text, "Loading... 0%")
        verify(control("catalogEmptyMessage").visible)
        backend.catalogLoading = false
        settle()
        compare(control("catalogEmptyMessage").text, "No results.")
    }
    function test_sort_hidden_while_loading_data() {
        return test_offline_categories_data()
    }
    function test_sort_hidden_while_loading(data) {
        root().openCategory(data.category)
        root().setCatalogSort(4); settle()
        verify(control("catalogSort").visible)
        verify(control("catalogSortDescription").visible)

        main.catalog = []; backend.sourcesBusy = true; settle()
        compare(control("catalogEmptyMessage").text, "Loading... 0%")
        verify(!control("catalogSort").visible, "Hide sorting during source setup")
        verify(!control("catalogSortDescription").visible)

        backend.catalogLoading = true; backend.sourcesBusy = false
        backend.catalogProgress = 38; settle()
        compare(control("catalogEmptyMessage").text, "Loading... 38%")
        verify(!control("catalogSort").visible, "Hide sorting during catalog loading")
        verify(!control("catalogSortDescription").visible)

        main.catalog = [app("org.example.Cached", "Cached")]
        backend.catalogLoading = false; backend.catalogProgress = 100; settle()
        verify(control("catalogSort").visible)
        verify(control("catalogSortDescription").visible)
        compare(control("catalogSort").currentIndex, 4, "Preserve the selected sort order")

        backend.sourcesBusy = true; settle()
        verify(control("catalogSort").visible, "Source management must not hide sorting for a loaded list")
    }
    function test_loading_closes_sort_popup() {
        const sort = control("catalogSort")
        sort.popup.open(); tryCompare(sort.popup, "visible", true)
        backend.catalogLoading = true; settle()
        verify(!sort.visible)
        tryCompare(sort.popup, "visible", false)
        backend.catalogLoading = false; settle()
        verify(sort.visible)
        verify(!sort.popup.visible)
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        network.state = "online"; network.ready = true
        main.showCatalog(); tryCompare(findChild(main, "navigationStack"), "busy", false)
        main.width = 1180; main.height = 760
        root().openCategory("All Apps")
        main.catalog = [app("org.example.One", "One"), app("us.zoom.Zoom", "Zoom")]
        backend.updates = {state:"idle", items:[]}; backend.busy = false
        backend.jobs = []
        backend.catalogLoading = false; backend.catalogProgress = 0
        backend.catalogSourcesUnavailable = false; backend.sourcesBusy = false; backend.refreshes = 0
        backend.checks = 0; backend.installs = 0; backend.cancelled = 0
        settle(); stats.requests = 0
    }
    function test_loading_percentage_data() {
        return test_page_status_foreground_data()
    }
    function test_loading_percentage(data) {
        const background = main.palette.window, foreground = main.palette.windowText
        try {
            main.palette.window = data.background; main.palette.windowText = data.foreground
            main.catalog = []; backend.catalogLoading = true
            for (const percent of [0, 5, 10, 50, 70, 85, 95, 98, 99]) {
                backend.catalogProgress = percent; settle()
                const label = control("catalogEmptyMessage")
                verify(label.visible && label.font.bold)
                compare(label.color, main.textColor)
                compare(label.text, "Loading... " + percent + "%")
                verify(!control("catalogSort").visible)
                verify(!control("catalogSortDescription").visible)
                compare(label.horizontalAlignment, Text.AlignHCenter)
                fuzzyCompare(label.y + label.height / 2, label.parent.height / 2, 1)
            }
            // A populated warm cache must not flash the loading percentage.
            backend.catalogLoading = false; backend.catalogProgress = 100
            main.catalog = [app("org.example.Cached", "Cached")]; settle()
            verify(!control("catalogEmptyMessage").visible)
            verify(control("catalogSort").visible)
        } finally {
            main.palette.window = background; main.palette.windowText = foreground
        }
    }
    function test_offline_categories_data() {
        return ["All Apps", "Audio & Video", "Development", "Education", "Games", "Graphics", "Internet",
            "Office", "Science", "System", "Utilities", "Other"].map(name => ({tag:name, category:name}))
    }
    function test_offline_categories(data) {
        network.state = "offline"; root().openCategory(data.category); settle()
        verify(control("categorySidebar").visible)
        verify(control("catalogOfflineMessage").visible)
        compare(findChild(control("catalogOfflineMessage"), "networkOfflineTitle").text, "No Network Connection")
        const icon = findChild(control("catalogOfflineMessage"), "networkWarningIcon")
        compare(icon.icon, "dialog-warning"); compare(icon.sourceSize.width, 64)
        verify(!control("catalogGrid").visible); verify(!control("catalogEmptyMessage").visible)
        verify(!control("catalogPageScrollBar").visible)
        verify(!control("searchField").enabled)
        const updates = control("updatesButton")
        verify(!updates.enabled); verify(updates.contentItem.opacity < 0.5)
        mouseClick(updates); main.showUpdates(); root().openCategory("Updates")
        compare(main.selectedCategory, data.category)
        compare(backend.checks, 0); compare(stats.requests, 0)
        mouseClick(control("installedButton")); settle()
        compare(main.selectedCategory, "Installed"); verify(control("installedList").visible)
        verify(control("searchField").enabled); verify(!control("catalogOfflineMessage").visible)
    }
    function test_allowed_states_data() {
        return ["online", "local", "limited", "portal", "connecting", "unknown"].map(state => ({tag:state, state:state}))
    }
    function test_allowed_states(data) {
        network.state = data.state; settle()
        verify(control("catalogGrid").visible); verify(!control("catalogOfflineMessage").visible)
        verify(control("updatesButton").enabled); verify(control("searchField").enabled)
        compare(control("catalogNetworkNote"), null, "No connectivity advisories")
        root().openCategory("Internet"); settle(); verify(control("catalogGrid").visible)
        mouseClick(control("updatesButton")); settle()
        compare(main.selectedCategory, "Updates"); compare(backend.checks, 0)
        verify(control("checkForUpdatesButton").enabled)
        mouseClick(control("checkForUpdatesButton")); compare(backend.checks, 1)
        backend.updates = {state:"ready", items:[{key:"user:One", name:"One", id:"org.example.One", oldVersion:"1", newVersion:"2",
            selected:true, installation:"user", remote:"fixture", permissions:{state:"unchanged"}, plan:[]}]}
        settle(); verify(control("installUpdatesButton").enabled)
        mouseClick(control("installUpdatesButton")); compare(backend.installs, 1)
    }
    function test_drop_while_updates_open() {
        main.showUpdates(); settle()
        backend.updates = {state:"ready", items:[{key:"user:One", name:"One", id:"org.example.One", oldVersion:"1", newVersion:"2",
            selected:true, installation:"user", remote:"fixture", permissions:{state:"unchanged"}, plan:[]}]}
        network.state = "offline"; settle()
        verify(control("updatesPage").visible); verify(control("updatesOfflineNote").visible)
        verify(!control("checkForUpdatesButton").enabled); verify(!control("installUpdatesButton").enabled)
        mouseClick(control("checkForUpdatesButton")); mouseClick(control("installUpdatesButton"))
        compare(backend.checks, 0); compare(backend.installs, 0)
        mouseClick(control("selectAllUpdates")); compare(backend.updates.items[0].selected, false)
        network.state = "local"; settle()
        verify(control("checkForUpdatesButton").enabled); verify(!control("installUpdatesButton").enabled)
        compare(backend.updates.items[0].selected, false); compare(backend.checks, 0)
        backend.updates = {state:"checking", items:[]}; backend.busy = true
        network.state = "offline"; settle()
        verify(control("cancelUpdateCheckButton").enabled)
        mouseClick(control("cancelUpdateCheckButton")); compare(backend.cancelled, 1)
    }
    function test_reconnect_does_not_check_updates() {
        network.state = "offline"; settle()
        verify(control("catalogOfflineMessage").visible)
        network.state = "online"; settle()
        verify(control("catalogGrid").visible); verify(control("updatesButton").enabled)
        verify(!control("catalogOfflineMessage").visible)
        compare(backend.checks, 0)
        verify(stats.requests > 0, "Catalog popularity can load on reconnect, not updates")
    }
    function test_initial_network_status_pending() {
        network.ready = false; stats.requests = 0
        root().setCatalogSort(0); root().setCatalogSort(2); settle()
        compare(stats.requests, 0)
        network.state = "offline"; network.ready = true; settle()
        compare(stats.requests, 0); compare(backend.checks, 0)
    }
    function test_header_fit_data() {
        const rows = []
        for (const width of [720, 1180]) for (const state of ["local", "limited", "portal", "connecting"])
            for (const queue of [false, true])
                rows.push({tag:state + width + (queue ? "-queue" : ""), width:width, state:state, queue:queue})
        return rows
    }
    function test_header_fit(data) {
        main.width = data.width; main.height = 520; network.state = data.state
        if (data.queue) backend.jobs = [{id:"org.example.One", name:"One", action:"install", active:true, progress:0.5, operations:[]}]
        const titles = ["Discord", "Steam", "Telegram", "Spotify", "Google Chrome", "Brave", "Visual Studio Code", "Sober", "Minecraft Launcher", "Zoom"]
        main.catalog = root().recommendedIds.map((id, i) => app(id, titles[i]))
        settle()
        const search = control("searchField")
        const menu = control("applicationMenuButton"), queue = control("downloadsButton")
        fuzzyCompare(search.x + search.width + 10, menu.x, 0.5)
        fuzzyCompare(root().width - menu.mapToItem(root(), menu.width, 0).x, 8, 0.5)
        if (queue.visible) verify(search.x >= queue.x + queue.width + 10, "Queue and Search do not overlap")
        compare(control("catalogNetworkNote"), null)
        compare(search.anchors.verticalCenterOffset, 0)
        const grid = control("catalogGrid")
        grid.positionViewAtBeginning(); settle()
        verify(grid.headerItem.height <= grid.height - 32, "All Apps remains visible")
        network.state = "offline"; settle()
        const message = control("catalogOfflineMessage")
        verify(message.height <= root().height && message.width <= root().width)
        verify(findChild(message, "networkOfflineTitle").contentWidth <= message.width + 1)
    }
    function test_sources_failed_data() { return test_allowed_states_data() }
    function test_sources_failed(data) {
        network.state = data.state; main.catalog = []; backend.catalogSourcesUnavailable = true; settle()
        const notice = control("catalogOfflineMessage")
        verify(notice.visible)
        compare(findChild(notice, "networkOfflineTitle").text, "Cannot Connect to Sources")
        verify(!control("catalogGrid").visible); verify(!control("catalogEmptyMessage").visible)
        verify(control("updatesButton").enabled); verify(control("searchField").enabled)
        root().openCategory("Internet"); settle(); verify(notice.visible)
        mouseClick(control("installedButton")); settle(); verify(!notice.visible)
        verify(control("installedList").visible)
        main.showUpdates(); settle(); verify(control("checkForUpdatesButton").enabled)
        compare(backend.checks, 0)
        root().openCategory("All Apps"); settle()
        mouseClick(findChild(notice, "retryCatalogSourcesButton")); settle()
        compare(backend.refreshes, 1); compare(backend.checks, 0)
        verify(!notice.visible); compare(control("catalogEmptyMessage").text, "Loading... 0%")
        backend.sourcesBusy = false; main.catalog = [app("org.example.One", "One")]; settle()
        verify(control("catalogGrid").visible); verify(!notice.visible)
    }
    function test_sources_failed_offline_precedence() {
        main.width = 720; main.height = 520
        backend.catalogSourcesUnavailable = true; network.state = "offline"; settle()
        const notice = control("catalogOfflineMessage")
        compare(findChild(notice, "networkOfflineTitle").text, "No Network Connection")
        verify(!findChild(notice, "retryCatalogSourcesButton").visible)
        network.state = "limited"; settle()
        compare(findChild(notice, "networkOfflineTitle").text, "Cannot Connect to Sources")
        verify(notice.height <= root().height)
        verify(findChild(notice, "networkOfflineTitle").contentWidth <= notice.width + 1)
        verify(findChild(notice, "retryCatalogSourcesButton").visible)
    }
    function test_empty_catalog_not_connection_failure() {
        main.catalog = []; network.state = "limited"; settle()
        verify(!control("catalogOfflineMessage").visible)
        compare(control("catalogEmptyMessage").text, "No results.")
    }
}
