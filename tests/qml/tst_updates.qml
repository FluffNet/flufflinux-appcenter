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
    function page() { return stack().currentItem }
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
        backend.updates = {state:"idle", items:[]}; backend.checks = 0; backend.submitted = []; backend.busy = false
        main.width = 1180; main.height = 760; main.requestActivate()
    }
    function open() { main.showUpdates(); tryCompare(stack(), "busy", false); waitForPolish(page()); wait(30) }
    function test_manual_only_check_and_cancel() {
        mouseClick(findChild(page(), "updatesButton")); tryCompare(stack(), "busy", false)
        compare(page().objectName, "updatesPage"); compare(backend.checks, 0)
        main.goBack(); tryCompare(stack(), "busy", false); open(); compare(backend.checks, 0)
        mouseClick(findChild(page(), "checkForUpdatesButton")); compare(backend.checks, 1)
        verify(page().checking); verify(!findChild(page(), "checkForUpdatesButton").enabled)
        backend.cancelUpdateCheck(); verify(findChild(page(), "updatesEmpty").text.indexOf("cancelled") >= 0)
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
        verify(findChild(page(), "updateDates").text.indexOf("22/09/2026 11:00") >= 0)
    }
    function test_empty_error_and_busy() {
        open(); backend.updates = {state:"ready", items:[], error:"Offline source"}
        verify(findChild(page(), "updatesEmpty").text.indexOf("up to date") < 0)
        backend.updates = {state:"ready", items:[]}
        compare(findChild(page(), "updatesEmpty").text, "Everything is up to date.")
        ready(); backend.busy = true
        verify(!findChild(page(), "installUpdatesButton").enabled)
        verify(!findChild(page(), "selectAllUpdates").enabled)
    }
    function test_layout_data() { return [{tag:"small", width:720, height:520}, {tag:"normal", width:1180, height:760}, {tag:"large", width:1920, height:1080}] }
    function test_layout(data) {
        main.width = data.width; main.height = data.height; open(); ready()
        const list = findChild(page(), "updatesList")
        verify(list.width > 0 && list.height > 0)
        const button = findChild(page(), "installUpdatesButton")
        const point = button.mapToItem(page(), 0, 0)
        verify(point.x >= 0 && point.x + button.width <= page().width)
        compare(list.contentWidth, list.width)
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
