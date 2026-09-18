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
        verify(findChild(dialog(), "permissionsExplanation").text.indexOf("overrides") >= 0)
        mouseClick(findChild(dialog(), "closePermissionsButton")); tryCompare(dialog(), "visible", false)
        verify(!button.activeFocus); compare(backend.appPermissions.state, undefined)
    }
    function test_group_layout_data() {
        return [{tag:"desktop", width:1920, height:1080}, {tag:"wide", width:1180, height:760}, {tag:"narrow", width:720, height:540}]
    }
    function test_group_layout(data) {
        main.width = data.width; main.height = data.height
        open()
        const groups = []
        for (let i = 0; i < 10; ++i) groups.push({id:"group" + i, title:"Permission " + i, icon:"folder",
            description:"A clear description of this permission.", details:["org.example." + "VeryLongServiceName".repeat(12), "Home folder — read only"]})
        backend.appPermissions = {state:"ready", groups:groups, installed:false}
        const scroll = findChild(dialog(), "permissionsScroll")
        const close = findChild(dialog(), "closePermissionsButton")
        waitForPolish(dialog().contentItem); waitForRendering(close)
        compare(dialog().width, main.width - 64)
        compare(dialog().height, main.height - 64)
        fuzzyCompare(dialog().x, 32, 1); fuzzyCompare(dialog().y, 32, 1)
        verify(scroll.contentHeight > scroll.height)
        compare(scroll.contentWidth, scroll.width)
        const center = close.mapToItem(dialog().background, close.width / 2, 0)
        fuzzyCompare(center.x, dialog().background.width / 2, 1)
        const bottom = close.mapToItem(dialog().background, 0, close.height)
        verify(dialog().background.height - bottom.y >= 8)
        verify(!close.activeFocus)
        main.width = 920; main.height = 650
        tryCompare(dialog(), "width", main.width - 64)
        tryCompare(dialog(), "height", main.height - 64)
        fuzzyCompare(dialog().x, 32, 1); fuzzyCompare(dialog().y, 32, 1)
        keyClick(Qt.Key_Tab); tryCompare(close, "activeFocus", true)
        keyClick(Qt.Key_Escape); tryCompare(dialog(), "visible", false)
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
