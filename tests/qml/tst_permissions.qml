import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "AppPermissions"
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
        property var appPermissions: ({})
        property var requested: null
        property int token: 0
        function requestInstallInfo(app) {}
        function requestAppPermissions(app) { requested = app; appPermissions = {state:"loading"}; return ++token }
        function cancelAppPermissions(requestToken) { if (requestToken === token) appPermissions = ({}) }
    }
    readonly property var app: ({id:"org.example.Permissions", name:"Permission test", description:"Test app",
        summary:"", category:"Utilities", icon:"", developer:"", homepage:"https://example.org", license:"MIT",
        remote:"selected-source", flatpakRef:"app/org.example.Permissions/x86_64/beta", screenshots:[]})
    function stack() { return findChild(main, "navigationStack") }
    function page() { return stack().currentItem }
    function dialog() { return findChild(page(), "appPermissionsDialog") }
    function columnGroups(index) {
        return findChild(dialog(), "permissionColumns").itemAt(index).groupRepeater
    }
    function groupItem(index) {
        const columns = findChild(dialog(), "permissionGrid").columns
        return columnGroups(index % columns).itemAt(Math.floor(index / columns))
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop)/)
        main.showCatalog(); tryCompare(stack(), "busy", false)
        main.width = 1180; main.height = 760
        main.requestActivate(); main.openApp(app); tryCompare(stack(), "busy", false)
        backend.appPermissions = ({}); backend.requested = null
    }
    function cleanup() { if (dialog()) { dialog().close(); tryCompare(dialog(), "visible", false) } }
    function open() {
        waitForPolish(page()); wait(30)
        const button = findChild(page(), "viewAppPermissionsButton")
        compare(button.icon.name, "object-locked")
        const flick = findChild(page(), "detailsFlickable")
        flick.contentY = Math.max(0, flick.contentHeight - flick.height)
        waitForPolish(page()); waitForRendering(button)
        mouseClick(button); tryCompare(dialog(), "opened", true)
        compare(backend.requested.flatpakRef, app.flatpakRef)
        compare(backend.requested.remote, app.remote)
        return button
    }
    function test_loading_error_retry_and_empty() {
        const button = open()
        verify(dialog().loading)
        verify(!findChild(dialog(), "permissionsEmpty").visible)
        backend.appPermissions = {state:"error", message:"Cannot read this source"}
        compare(findChild(dialog(), "permissionsError").text, "Cannot read this source")
        waitForPolish(dialog().contentItem); waitForRendering(dialog().contentItem)
        mouseClick(findChild(dialog(), "retryPermissionsButton")); verify(dialog().loading)
        backend.appPermissions = {state:"ready", groups:[], installed:true}
        verify(findChild(dialog(), "permissionsEmpty").visible)
        compare(findChild(dialog(), "permissionsExplanation"), null)
        compare(findChild(dialog(), "permissionsAppName"), null)
        compare(findChild(dialog(), "permissionsTitle").text, "App Permissions - <b>Permission test</b>")
        mouseClick(findChild(dialog(), "closePermissionsButton")); tryCompare(dialog(), "visible", false)
        verify(!button.activeFocus); compare(backend.appPermissions.state, undefined)
    }
    function test_local_file_details_warning_does_not_hide_permissions() {
        const warning = "Could not load app details from this source."
        main.openApp(Object.assign({}, app, {detailsWarning:warning}))
        tryCompare(stack(), "busy", false)
        const label = findChild(page(), "appDetailsWarning")
        compare(label.text, warning); verify(label.visible && label.font.bold)
        compare(label.color, main.textColor)
        open()
        backend.appPermissions = {state:"ready", groups:[], installed:false}
        verify(dialog().ready)
    }
    function test_unrelated_installed_refresh_keeps_permissions_open() {
        open()
        backend.appPermissions = {state:"ready", groups:[], installed:false}
        try {
            backend.installedApps = [{id:"org.example.Unrelated", name:"Unrelated app"}]
            wait(50)
            verify(dialog().opened, "An unrelated installed-list refresh must not close this app's permissions")
            verify(dialog().ready)
        } finally {
            backend.installedApps = []
        }
    }
    function test_same_app_republished_keeps_permissions_but_source_change_closes() {
        open()
        backend.appPermissions = {state:"ready", groups:[], installed:false}
        main.selectedApp = Object.assign({}, app)
        wait(50)
        verify(dialog().opened)
        verify(dialog().ready)
        main.selectedApp = Object.assign({}, app, {sourceUrl:"https://different.example/repo/"})
        tryCompare(dialog(), "visible", false)
    }
    function test_group_layout_data() {
        return [{tag:"desktop", width:1920, height:1080}, {tag:"wide", width:1180, height:760}, {tag:"narrow", width:720, height:540}]
    }
    function test_group_layout(data) {
        main.width = data.width; main.height = data.height
        open()
        const groups = []
        for (let i = 0; i < 20; ++i) groups.push({id:"group" + i, title:"Permission " + i, icon:"folder",
            description:"A clear description of this permission.", details:["org.example." + "VeryLongServiceName".repeat(12), "Home folder - read only"]})
        backend.appPermissions = {state:"ready", groups:groups, installed:false}
        const scroll = findChild(dialog(), "permissionsScroll")
        const bar = findChild(dialog(), "permissionsPageScrollBar")
        const grid = findChild(dialog(), "permissionGrid")
        const close = findChild(dialog(), "closePermissionsButton")
        waitForPolish(dialog().contentItem); waitForRendering(close)
        compare(dialog().width, main.width - 64)
        compare(dialog().height, main.height - 64)
        fuzzyCompare(dialog().x, 32, 1); fuzzyCompare(dialog().y, 32, 1)
        tryVerify(() => scroll.contentHeight > scroll.height)
        compare(scroll.contentWidth, scroll.width)
        compare(grid.columns, data.width >= 900 ? 2 : 1)
        let count = 0
        for (let column = 0; column < grid.columns; ++column)
            count += columnGroups(column).count
        compare(count, groups.length)
        for (let i = 0; i < groups.length; ++i) {
            const item = groupItem(i)
            const position = item.mapToItem(grid, 0, 0)
            compare(item.modelData.id, groups[i].id)
            verify(position.x >= 0 && position.x + item.width <= grid.width + 1)
            fuzzyCompare(item.width, (grid.width - (grid.columns - 1) * grid.columnSpacing) / grid.columns, 1)
            if (i >= grid.columns) {
                const previous = groupItem(i - grid.columns)
                fuzzyCompare(item.y - previous.y - previous.height, 24, 1)
            }
        }
        if (grid.columns === 2) {
            fuzzyCompare(groupItem(0).y, groupItem(1).y, 1)
            verify(groupItem(1).mapToItem(grid, 0, 0).x > grid.width / 2)
        }
        tryVerify(() => bar.visible && bar.interactive)
        compare(bar.width, 16); compare(bar.padding, 4)
        compare(bar.contentItem.width, 8)
        compare(bar.background.color, main.raisedSurfaceColor)
        const edge = bar.mapToItem(dialog().background, bar.width, 0)
        fuzzyCompare(dialog().background.width - edge.x, 1, 1)
        mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -120, Qt.NoButton)
        tryVerify(() => scroll.contentY > 0)
        scroll.contentY = 0
        mousePress(bar, bar.width / 2, bar.contentItem.y + bar.contentItem.height / 2)
        mouseMove(bar, bar.width / 2, bar.height * 0.65, 50)
        mouseRelease(bar, bar.width / 2, bar.height * 0.65)
        tryVerify(() => scroll.contentY > 0)
        scroll.contentY = scroll.contentHeight - scroll.height
        tryVerify(() => bar.position > 0)
        const center = close.mapToItem(dialog().background, close.width / 2, 0)
        fuzzyCompare(center.x, dialog().background.width / 2, 1)
        const bottom = close.mapToItem(dialog().background, 0, close.height)
        verify(dialog().background.height - bottom.y >= 8)
        verify(!close.activeFocus)
        main.width = 920; main.height = 650
        tryCompare(dialog(), "width", main.width - 64)
        tryCompare(dialog(), "height", main.height - 64)
        tryCompare(grid, "columns", 2)
        fuzzyCompare(dialog().x, 32, 1); fuzzyCompare(dialog().y, 32, 1)
        keyClick(Qt.Key_Tab); tryCompare(close, "activeFocus", true)
        keyClick(Qt.Key_Escape); tryCompare(dialog(), "visible", false)
    }
    function test_columns_stack_independently() {
        open()
        const services = []
        for (let i = 0; i < 20; ++i) services.push("org.example.Service" + i)
        backend.appPermissions = {state:"ready", groups:[
            {id:"ipc", title:"Shared Memory Access", icon:"computer", description:"Shared memory", details:["Host IPC"]},
            {id:"session", title:"Session Bus Access", icon:"network-connect", description:"Session services", details:services},
            {id:"system", title:"System Bus Access", icon:"network-connect", description:"System services", details:["org.bluez"]}
        ]}
        waitForPolish(dialog().contentItem); waitForRendering(dialog().contentItem)
        fuzzyCompare(groupItem(2).y - groupItem(0).height, 24, 1)
        verify(groupItem(2).y < groupItem(1).height, "The long adjacent bus section must not create a gap")
        main.width = 720
        tryCompare(findChild(dialog(), "permissionGrid"), "columns", 1)
        waitForPolish(dialog().contentItem)
        for (let i = 0; i < 3; ++i) compare(groupItem(i).modelData.id, backend.appPermissions.groups[i].id)
        verify(groupItem(2).y > groupItem(1).y + groupItem(1).height)
    }
    function test_short_content_hides_scrollbar() {
        open()
        backend.appPermissions = {state:"ready", groups:[
            {id:"network", title:"Network Access", icon:"network-wireless", description:"Internet access", details:[]},
            {id:"audio", title:"Sound System Access", icon:"audio-volume-high", description:"Play audio", details:[]}
        ]}
        const bar = findChild(dialog(), "permissionsPageScrollBar")
        tryCompare(bar, "visible", false)
        compare(findChild(dialog(), "permissionGrid").columns, 2)
    }
    function test_title_escapes_app_name_and_wraps() {
        const name = '<img src="bad"> & ' + "Long application name ".repeat(15)
        dialog().app = Object.assign({}, app, {name:name})
        open()
        const title = findChild(dialog(), "permissionsTitle")
        verify(title.text.indexOf('<img') < 0)
        verify(title.text.indexOf('&lt;img') >= 0 && title.text.indexOf('&amp;') >= 0)
        compare(title.Accessible.name, "App Permissions - " + name)
        waitForPolish(dialog().contentItem)
        verify(title.height > title.font.pixelSize * 2)
        verify(dialog().contentItem.height > 0)
    }
    function test_close_while_loading_and_reopen() {
        const button = open()
        keyClick(Qt.Key_Escape); tryCompare(dialog(), "visible", false)
        verify(!button.activeFocus)
        compare(backend.appPermissions.state, undefined)
        open(); verify(dialog().loading)
        main.selectedApp = Object.assign({}, app, {remote:"different-source"})
        tryCompare(dialog(), "visible", false)
    }
    function test_old_page_cannot_cancel_new_dialog() {
        open(); dialog().close()
        main.openApp(Object.assign({}, app, {id:"org.example.Other", name:"Other app"}))
        tryCompare(stack(), "busy", false)
        dialog().open(); tryCompare(dialog(), "opened", true)
        wait(350) // Let the old page and its closing dialog finish destruction.
        compare(backend.requested.id, "org.example.Other")
        compare(backend.appPermissions.state, "loading")
        backend.appPermissions = {state:"ready", groups:[]}
        verify(dialog().ready)
    }
}
