import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "AppAddons"
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
        property var appAddons: ({})
        property var requested: null
        property var action: null
        property int token: 0
        function requestInstallInfo(app) {}
        function requestAppAddons(app) { requested = app; appAddons = {state:"loading"}; return ++token }
        function cancelAppAddons(requestToken) { if (requestToken === token) appAddons = ({}) }
        function changeAddon(reference, install) { action = {reference:reference, install:install} }
        function cancelJob(index) { action = {cancel:index} }
    }
    readonly property var addon: ({id:"org.example.App.Plugin", name:"Example Plugin", summary:"Adds a useful feature",
        flatpakRef:"runtime/org.example.App.Plugin/x86_64/stable", installation:"user", available:true, installed:false})
    readonly property var app: ({id:"org.example.App", name:"App test", description:"Test app", summary:"", category:"Utilities",
        icon:"", developer:"", homepage:"", license:"MIT", screenshots:[], addons:[addon]})
    function stack() { return findChild(main, "navigationStack") }
    function dialog() { return findChild(stack().currentItem, "appAddonsDialog") }
    function row() { return findChild(dialog(), "addonRows").itemAt(0) }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Unable to assign)/)
        if (dialog()) dialog().close()
        main.showCatalog(); tryCompare(stack(), "busy", false)
        backend.jobs = []; backend.busy = false; backend.action = null
        main.width = 1180; main.height = 760
        main.openApp(app); tryCompare(stack(), "busy", false)
    }
    function cleanup() { dialog().close(); tryCompare(dialog(), "visible", false) }
    function open() {
        const page = stack().currentItem
        const scroll = findChild(page, "detailsFlickable")
        waitForPolish(page)
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForPolish(page)
        mouseClick(findChild(page, "viewAppAddonsButton"))
        tryCompare(dialog(), "opened", true)
    }
    function test_button_only_for_apps_with_addons_and_beside_permissions() {
        const page = stack().currentItem
        const permissions = findChild(page, "viewAppPermissionsButton")
        const addons = findChild(page, "viewAppAddonsButton")
        waitForPolish(page)
        verify(addons.visible)
        compare(addons.y, permissions.y)
        verify(addons.x >= permissions.x + permissions.width + 10)
        page.app = Object.assign({}, app, {addons:[]})
        verify(!addons.visible)
    }
    function test_install_remove_cancel() {
        open(); compare(dialog().addonData.state, "loading")
        backend.appAddons = {state:"ready", items:[addon]}
        waitForPolish(dialog().contentItem)
        let button = findChild(row(), "addonActionButton")
        verify(button.downloadArrow)
        verify(findChild(button, "installDownloadArrow").visible)
        compare(button.icon.source.toString(), "")
        compare(button.text, "Install"); mouseClick(button)
        compare(backend.action.reference, addon.flatpakRef); compare(backend.action.install, true)
        backend.appAddons = {state:"ready", items:[Object.assign({}, addon, {installed:true})]}
        waitForPolish(dialog().contentItem)
        button = findChild(row(), "addonActionButton")
        verify(!button.downloadArrow)
        verify(button.icon.source.toString().endsWith("/trash-red.svg"))
        compare(button.text, "Remove"); mouseClick(button); compare(backend.action.install, false)
        backend.jobs = [Object.assign({}, addon, {index:3, active:true, addon:true, status:"Installing", progress:0.4})]
        verify(!button.downloadArrow)
        compare(button.icon.source.toString(), "")
        compare(button.icon.name, "dialog-cancel")
        compare(button.text, "Cancel"); mouseClick(button); compare(backend.action.cancel, 3)
    }
    function test_uninstalled_parent_cannot_change_addons() {
        open(); backend.appAddons = {state:"not-installed", items:[addon]}
        waitForPolish(dialog().contentItem)
        verify(!findChild(row(), "addonActionButton").visible)
    }
    function test_parent_metadata_refresh_keeps_dialog_open() {
        open(); backend.appAddons = {state:"ready", items:[addon]}
        stack().currentItem.app = Object.assign({}, app, {installed:true, installedSize:"12 MiB"})
        compare(dialog().opened, true)
        mouseClick(findChild(dialog(), "closeAddonsButton"))
        tryCompare(dialog(), "visible", false)
    }
    function test_failure_retry_and_cancel_reader() {
        open(); const first = backend.token
        backend.appAddons = {state:"error", error:"Connection failed"}
        mouseClick(findChild(dialog(), "retryAddonsButton"))
        compare(backend.token, first + 1); compare(dialog().addonData.state, "loading")
        dialog().close(); tryCompare(dialog(), "visible", false)
        compare(backend.appAddons.state, undefined)
    }
    function test_narrow_long_names_data() { return [{tag:"dark", light:false}, {tag:"light", light:true}] }
    function test_narrow_long_names(data) {
        main.palette.window = data.light ? "#eff0f1" : "#202326"
        main.palette.windowText = data.light ? "#232629" : "white"
        main.width = 720; main.height = 540
        open(); backend.appAddons = {state:"ready", items:[Object.assign({}, addon,
            {name:"A very long add-on title ".repeat(10), summary:"Details ".repeat(40)})]}
        waitForPolish(dialog().contentItem)
        verify(dialog().width <= main.width - 48)
        const button = findChild(row(), "addonActionButton")
        const position = button.mapToItem(dialog().contentItem, 0, 0)
        verify(position.x + button.width <= dialog().contentItem.width,
            "Button right " + (position.x + button.width) + " exceeds content width " + dialog().contentItem.width)
        const arrow = findChild(button, "installDownloadArrow")
        verify(arrow.visible)
        compare(arrow.color, data.light ? "#16823e" : "#65d88b")
        for (const control of [findChild(dialog(), "closeAddonsButton"), findChild(stack().currentItem, "viewAppAddonsButton")]) {
            const icon = findChild(control, "fluffButtonMonochromeIcon")
            verify(icon.visible)
            compare(icon.color, main.textColor)
        }
    }
}
