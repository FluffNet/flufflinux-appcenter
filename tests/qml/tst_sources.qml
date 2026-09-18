import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    id: tests
    name: "Sources"
    when: main.visible
    readonly property var app: ({id: "org.example.App", name: "Source Test", summary: "Choose a source", description: "Test", icon: "", developer: "", license:"", homepage:"", category: "Utilities", screenshots: [], version: "1.0", remote: "stable", sourceUrl: "https://example.org/stable", flatpakRef: "app/org.example.App/x86_64/stable"})
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        property string sourcesError: ""
        property var repositories: [
            {name: "flathub", title: "Flathub", url: "https://dl.flathub.org/repo/", scope: "user", enabled: true, verified: true},
            {name: "testing", title: "Testing", url: "https://example.org/testing", scope: "user", enabled: false, verified: true},
            {name: "flathub", title: "Flathub", url: "https://dl.flathub.org/repo/", scope: "default", enabled: true, verified: true}
        ]
        property var installSizes: ({})
        property var lastInstall: null
        property var lastEstimate: null
        property string request: ""
        function requestInstallInfo(app) { lastEstimate = app }
        function installApp(app) { lastInstall = app }
        function refreshSources(all) { request = all ? "refresh" : "list" }
        function setSourceEnabled(source, enabled) { request = "enable:" + source.name + ":" + enabled }
        function removeSource(source) { request = "remove:" + source.name }
        function openSource(source) { request = "add:" + source }
        signal appOpened(var app)
        signal inputError(string message)
    }
    AppCenter.Main { id: main; backend: backend; visible: true }
    function stack() { return findChild(main, "navigationStack") }
    function page() { return stack().currentItem }
    function init() {
        main.showCatalog(); tryCompare(stack(), "busy", false)
        main.width = 1180; main.height = 760
        backend.busy = false; backend.sourcesBusy = false; backend.installedApps = []
        backend.request = ""; backend.lastInstall = null; backend.lastEstimate = null
        main.requestActivate(); wait(50)
    }
    function test_menu_layout_data() { return [{tag:"wide", width:1180}, {tag:"narrow", width:720}] }
    function test_menu_layout(data) {
        main.width = data.width
        const button = findChild(main, "applicationMenuButton")
        const search = findChild(main, "searchField")
        waitForRendering(button)
        verify(button.x + button.width <= search.x - 9)
        verify(button.mapToItem(page(), 0, 0).x >= page().categorySidebarWidth)
        mouseClick(button)
        const menu = findChild(main, "applicationMenu")
        tryCompare(menu, "opened", true)
        compare(menu.count, 2)
        compare(menu.itemAt(0).text, "About"); verify(menu.itemAt(0).icon.name.length > 0)
        compare(menu.itemAt(1).text, "Settings"); verify(menu.itemAt(1).icon.name.length > 0)
        menu.itemAt(0).triggered(); menu.close()
        const about = findChild(main, "aboutDialog")
        tryCompare(about, "opened", true); about.close(); tryCompare(about, "visible", false)
    }
    function test_settings_controls_and_no_priority() {
        main.showSettings(); tryCompare(stack(), "busy", false)
        compare(page().objectName, "settingsPage"); compare(backend.request, "list")
        compare(page().sources.length, 3)
        compare(findChild(page(), "sourcePriorityUp"), null)
        const row = findChild(page(), "sourceRow")
        const checkbox = findChild(row, "sourceEnabled")
        verify(checkbox.checked); mouseClick(checkbox)
        compare(backend.request, "enable:flathub:false")
        mouseClick(findChild(row, "sourceDetailsButton"))
        const details = findChild(page(), "sourceDetailsDialog")
        tryCompare(details, "opened", true); details.close(); tryCompare(details, "visible", false)
        mouseClick(findChild(page(), "addSourceButton"))
        const add = findChild(page(), "addSourceDialog")
        tryCompare(add, "opened", true)
        findChild(page(), "sourceInput").text = "https://example.org/testing.flatpakrepo"
        mouseClick(findChild(page(), "confirmAddSourceButton"))
        compare(backend.request, "add:https://example.org/testing.flatpakrepo")
        tryCompare(add, "visible", false)
        mouseClick(findChild(row, "removeSourceButton"))
        const remove = findChild(page(), "removeSourceDialog")
        tryCompare(remove, "opened", true)
        verify(backend.request.indexOf("remove:") !== 0) // Showing confirmation must not remove anything.
        remove.reject(); tryCompare(remove, "visible", false)
        backend.busy = true
        verify(!findChild(page(), "addSourceButton").enabled)
        verify(!checkbox.enabled)
    }
    function test_source_selection_data() { return [{tag:"wide", width:1180}, {tag:"narrow", width:720}] }
    function test_source_selection(data) {
        main.width = data.width
        const beta = Object.assign({}, app, {remote:"beta", sourceUrl:"https://example.org/beta", flatpakRef:"app/org.example.App/x86_64/beta", version:"2.0-beta"})
        main.openApp(Object.assign({}, app, {sources:[app,beta]})); tryCompare(stack(), "busy", false)
        const choose = findChild(page(), "installSourceButton")
        const install = findChild(page(), "installAppButton")
        verify(choose.visible); verify(install.visible)
        waitForRendering(page())
        verify(choose.mapToItem(page(), choose.width, 0).x <= page().width)
        verify(install.width >= 176)
        mouseClick(choose)
        const menu = findChild(page(), "installSourceMenu")
        tryCompare(menu, "opened", true); compare(menu.count, 2)
        menu.itemAt(1).triggered(); menu.close()
        compare(main.selectedApp.remote, "beta")
        compare(main.selectedApp.version, "2.0-beta")
        compare(backend.lastEstimate.sourceUrl, beta.sourceUrl)
        compare(findChild(page(), "appSourceValue").text, "beta")
        mouseClick(install)
        compare(backend.lastInstall.flatpakRef, beta.flatpakRef)
        compare(backend.lastInstall.remote, "beta")
    }
    function test_single_source_and_installed_origin() {
        main.openApp(Object.assign({}, app, {sources:[app]})); tryCompare(stack(), "busy", false)
        verify(!findChild(page(), "installSourceButton").visible)
        backend.installedApps = [Object.assign({}, app, {installedOrigin:"installed-repo", installation:"user", installedVersion:"0.9", installedSize:"20 MiB"})]
        compare(findChild(page(), "appSourceValue").text, "installed-repo (User)")
        verify(!findChild(page(), "installSourceButton").visible)
        main.showCatalog(); tryCompare(stack(), "busy", false)
        main.selectedCategory = "Installed"
        const list = findChild(page(), "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const source = findChild(list.itemAtIndex(0), "installedSourceValue")
        compare(source.text, "installed-repo (User)")
        main.selectedCategory = "All Apps"
    }
}
