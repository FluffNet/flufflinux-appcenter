import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Updates"
    when: main.visible
    AppCenter.Main { id: main; backend: backend }
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property bool busy: false
        property int iconRevision: 0
        property var updates: ({state:"idle", items:[]})
        property int checks: 0
        property var submitted: []
        function checkForUpdates() { checks++; updates = {state:"checking", items:[], status:"Checking fixture…"}; busy = true }
        function cancelUpdateCheck() { busy = false; updates = {state:"cancelled", items:[]} }
        function selectUpdate(key, selected) { updates = Object.assign({}, updates, {items:updates.items.map(row => row.key === key ? Object.assign({}, row, {selected:selected}) : row)}) }
        function selectAllUpdates(selected) { updates = Object.assign({}, updates, {items:updates.items.map(row => Object.assign({}, row, {selected:selected}))}) }
        function installSelectedUpdates() { submitted = updates.items.filter(row => row.selected).map(row => row.key) }
        function requestInstallInfo(app) {}
    }
    function stack() { return findChild(main, "navigationStack") }
    function root() { return stack().get(0) }
    function page() { return findChild(root(), "updatesPage") }
    function row(name, scope) {
        return {key:scope + ":" + name, id:name, name:name, icon:"", installation:scope, remote:"fixture", runtime:false,
            oldVersion:"1.0", newVersion:"2.0", selected:true, downloadSize:"1.00 MiB", permissions:{state:"unchanged", groups:[]},
            plan:[{ref:name, commit:"a", downloadBytes:100}, {ref:"shared", commit:"b", downloadBytes:200}]}
    }
    function ready() {
        backend.busy = false
        backend.updates = {state:"ready", items:[row("Alpha", "user"), row("Beta", "user")], lastChecked:"23/09/2026 12:30", lastUpdated:"22/09/2026 11:00"}
        waitForPolish(page()); wait(50)
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.showCatalog(); tryCompare(stack(), "busy", false)
        root().openCategory("Installed")
        backend.updates = {state:"idle", items:[]}; backend.checks = 0; backend.submitted = []; backend.busy = false
        main.width = 1180; main.height = 760; main.requestActivate()
        waitForPolish(root()); wait(30)
    }
    function open() { main.showUpdates(); tryCompare(stack(), "busy", false); waitForPolish(page()); wait(30) }
    function test_clear_app_update_labels() {
        open()
        compare(findChild(root(), "updatesButton").text, "App Updates")
        compare(findChild(page(), "appUpdatesTitle").text, "App Updates")
        compare(findChild(page(), "checkForUpdatesButton").text, "Check for App Updates")
        compare(findChild(page(), "updateDates").text, "Apps were last updated: Not recorded")
        verify(!findChild(page(), "updatesEmpty").visible)
        backend.updates = {state:"idle", items:[], lastUpdated:"24/09/2026 12:39"}
        compare(findChild(page(), "updateDates").text, "Apps were last updated: 24/09/2026 12:39")
        compare(backend.checks, 0)
    }
    function test_manual_only_check_and_cancel() {
        mouseClick(findChild(root(), "updatesButton")); tryCompare(stack(), "busy", false)
        verify(page().visible); compare(stack().depth, 1); compare(backend.checks, 0)
        mouseClick(findChild(root(), "installedButton")); verify(!page().visible)
        open(); compare(backend.checks, 0)
        mouseClick(findChild(page(), "checkForUpdatesButton")); compare(backend.checks, 1)
        verify(page().checking); verify(!findChild(page(), "checkForUpdatesButton").enabled)
        waitForPolish(page()); waitForRendering(page()) // Click the rendered Cancel button, not its pre-layout position.
        mouseClick(findChild(page(), "cancelUpdateCheckButton"))
        verify(findChild(page(), "updatesEmpty").text.indexOf("cancelled") >= 0)
    }
    function test_single_checking_message_for_all_sources() {
        open()
        const label = findChild(page(), "updateCheckStatus")
        verify(!label.visible)
        mouseClick(findChild(page(), "checkForUpdatesButton"))
        for (const status of ["", "Checking user updates…", "Checking system updates…",
                "Checking extra updates…", "Checking flathub-beta system updates…",
                "Adding flathub for existing system apps… Authorization may be required."]) {
            backend.updates = {state:"checking", items:[], status:status}
            verify(label.visible)
            compare(label.text, "Checking for app updates…")
        }
        waitForPolish(page()); waitForRendering(page())
        mouseClick(findChild(page(), "cancelUpdateCheckButton"))
        verify(!label.visible)
        ready()
        verify(!label.visible)
    }
    function test_main_navigation_and_disabled_search() {
        const search = findChild(root(), "searchField")
        const sidebar = findChild(root(), "categorySidebar")
        const brand = findChild(root(), "brandLockup")
        const searchPosition = search.mapToItem(main.contentItem, 0, 0)
        const sidebarWidth = sidebar.width
        search.forceActiveFocus(); keyClick(Qt.Key_P)
        open(); wait(180)
        compare(stack().currentItem, root()); compare(stack().depth, 1)
        verify(sidebar.visible); verify(brand.visible); verify(search.visible)
        compare(findChild(root(), "updatesButton").icon.name, "system-upgrade")
        compare(findChild(page(), "installUpdatesButton").icon.name, "system-upgrade")
        compare(sidebar.width, sidebarWidth)
        compare(search.mapToItem(main.contentItem, 0, 0), searchPosition)
        verify(!search.enabled); verify(search.opacity < 0.6); verify(!search.activeFocus)
        compare(search.text, ""); compare(main.searchText, ""); compare(main.selectedCategory, "Updates")
        verify(!findChild(root(), "installedList").visible)
        verify(!findChild(root(), "catalogGrid").visible)
        verify(!findChild(root(), "catalogEmptyMessage").visible)
        verify(!findChild(root(), "installedPageScrollBar").visible)
        verify(!findChild(root(), "catalogPageScrollBar").visible)
        mouseClick(search); keyClick(Qt.Key_I)
        compare(search.text, ""); compare(main.selectedCategory, "Updates")
        mouseClick(findChild(root(), "installedButton"))
        verify(search.enabled); compare(search.opacity, 1); verify(!page().visible)
        verify(!findChild(page(), "updatesPageScrollBar").visible)
        verify(findChild(root(), "installedList").visible)
        open(); ready()
        backend.selectUpdate("user:Alpha", false)
        mouseClick(findChild(root(), "categoryButton-Internet"))
        compare(main.selectedCategory, "Internet"); verify(search.enabled); verify(!page().visible)
        open(); compare(page().selected.length, 1); compare(backend.checks, 0)
    }
    function test_check_indicator_centered_data() { return test_layout_data() }
    function test_check_indicator_centered(data) {
        main.width = data.width; main.height = data.height; open()
        mouseClick(findChild(page(), "checkForUpdatesButton"))
        waitForPolish(page()); wait(30)
        const area = findChild(page(), "updatesContentArea")
        const indicator = findChild(page(), "updateCheckIndicator")
        const spinner = findChild(page(), "updateCheckSpinner")
        const label = findChild(page(), "updateCheckStatus")
        verify(indicator.visible && spinner.running && label.visible)
        fuzzyCompare(indicator.x + indicator.width / 2, area.width / 2, 0.5)
        fuzzyCompare(indicator.y + indicator.height / 2, area.height / 2, 0.5)
        verify(indicator.x >= 0 && indicator.x + indicator.width <= area.width)
        verify(label.x >= spinner.x + spinner.width)
        verify(!label.truncated && label.contentWidth <= label.width + 1)
        verify(!findChild(page(), "updatesList").visible)
        verify(findChild(page(), "cancelUpdateCheckButton").enabled)
        root().openCategory("Installed"); verify(!spinner.running)
        open(); verify(spinner.running); compare(backend.checks, 1)
        mouseClick(findChild(page(), "cancelUpdateCheckButton"))
        verify(!indicator.visible && !spinner.running)
        ready(); verify(!indicator.visible && findChild(page(), "updatesList").visible)
    }
    function test_return_from_queue_and_settings() {
        open(); ready()
        for (const destination of ["showDownloads", "showSettings"]) {
            main[destination](); tryCompare(stack(), "busy", false)
            compare(stack().depth, 2)
            main.goBack(); tryCompare(stack(), "busy", false)
            compare(stack().depth, 1); verify(page().visible)
            compare(main.selectedCategory, "Updates")
            const search = findChild(root(), "searchField")
            verify(!search.enabled); verify(!search.activeFocus)
            compare(page().selected.length, 2); compare(backend.checks, 0)
        }
    }
    function test_defaults_selection_and_shared_downloads() {
        open(); ready()
        compare(page().selected.length, 2); compare(page().selectedBytes, 400)
        const alpha = findChild(page(), "selectUpdate-user:Alpha")
        mouseClick(alpha); compare(page().selected.length, 1); compare(page().selectedBytes, 300)
        const all = findChild(page(), "selectAllUpdates")
        verify(all.contentItem.leftPadding >= all.indicator.width + 8)
        compare(all.checkState, Qt.PartiallyChecked)
        mouseClick(all); compare(page().selected.length, 2)
        mouseClick(all); compare(page().selected.length, 0)
        verify(!findChild(page(), "installUpdatesButton").enabled)
        mouseClick(all); mouseClick(findChild(page(), "installUpdatesButton"))
        compare(backend.submitted, ["user:Alpha", "user:Beta"])
        verify(!findChild(page(), "installUpdatesButton").activeFocus)
    }
    function test_scopes_and_dates() {
        open(); ready()
        backend.updates = Object.assign({}, backend.updates, {items:[row("Alpha", "user"), row("Alpha", "system")]})
        compare(page().selectedBytes, 600)
        compare(findChild(page(), "updateDates").text,
            "Apps were last updated: 22/09/2026 11:00\nLast checked: 23/09/2026 12:30")
    }
    function test_empty_error_and_busy() {
        open(); backend.updates = {state:"ready", items:[], error:"Offline source"}
        verify(findChild(page(), "updatesEmpty").text.indexOf("up to date") < 0)
        backend.updates = {state:"ready", items:[]}
        compare(findChild(page(), "updatesEmpty").text, "Your apps are up to date.")
        ready(); backend.busy = true
        verify(!findChild(page(), "installUpdatesButton").enabled)
        verify(!findChild(page(), "selectAllUpdates").enabled)
    }
    function test_unavailable_sources_are_not_offered() {
        open()
        backend.updates = {state:"ready", items:[], skipped:["Skipped Firefox: flathub (System) is missing."]}
        verify(findChild(page(), "updatesSkipped").visible)
        verify(findChild(page(), "updatesSkipped").text.indexOf("Firefox") >= 0)
        verify(!findChild(page(), "updatesError").visible)
        verify(findChild(page(), "updatesEmpty").text.indexOf("Your apps are up to date") < 0)
        verify(!findChild(page(), "installUpdatesButton").enabled)
        backend.updates = Object.assign({}, backend.updates, {items:[row("Available app", "user")]})
        compare(page().selected.length, 1)
        verify(findChild(page(), "installUpdatesButton").enabled)
    }
    function test_layout_data() { return [{tag:"small", width:720, height:520}, {tag:"normal", width:1180, height:760}, {tag:"large", width:1920, height:1080}] }
    function test_layout(data) {
        main.width = data.width; main.height = data.height; open(); ready()
        const list = findChild(page(), "updatesList")
        verify(list.width > 0 && list.height >= 100, "Leave room for update cards")
        verify(page().width < main.width)
        const title = findChild(page(), "appUpdatesTitle"), check = findChild(page(), "checkForUpdatesButton")
        verify(title.contentWidth <= title.width + 1, "App Updates title fits")
        const titlePoint = title.mapToItem(page(), 0, 0), checkPoint = check.mapToItem(page(), 0, 0)
        verify(checkPoint.x >= titlePoint.x + title.width || checkPoint.y >= titlePoint.y + title.height,
            "Longer title and check button must not overlap")
        for (const name of ["checkForUpdatesButton", "selectAllUpdates", "installUpdatesButton"]) {
            const button = findChild(page(), name)
            const point = button.mapToItem(page(), 0, 0)
            verify(point.x >= 0 && point.x + button.width <= page().width, name + " must fit beside the sidebar")
        }
        compare(list.contentWidth, list.width)
        const bar = findChild(page(), "updatesPageScrollBar")
        compare(bar.parent, page().contentItem)
        compare(bar.height, page().height)
        compare(bar.x + bar.width, page().width)
        backend.updates = Object.assign({}, backend.updates, {error:"A repository could not be reached. Please check your connection and try again."})
        waitForPolish(page()); verify(list.height > 0)
    }
    function test_permission_changes_dialog() {
        open(); ready()
        const dialog = findChild(page(), "appPermissionsDialog")
        dialog.app = row("Alpha", "user")
        dialog.changes = {groups:[{id:"files", title:"File Access", icon:"folder", description:"", added:["Downloads — read and write"], removed:["Downloads — read only"]}]}
        dialog.open(); tryCompare(dialog, "opened", true)
        compare(findChild(dialog, "permissionsTitle").text, "Permission Changes - <b>Alpha</b>")
        compare(dialog.groups[0].details, ["Added: Downloads — read and write", "Removed: Downloads — read only"])
        mouseClick(findChild(dialog, "closePermissionsButton")); tryCompare(dialog, "visible", false)
    }
}
