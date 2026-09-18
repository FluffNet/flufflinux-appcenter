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
        readonly property var initialRepositories: [
            {name: "flathub", title: "Flathub", url: "https://dl.flathub.org/repo/", scope: "merged", hasUser: true, hasSystem: true, enabled: true, verified: true},
            {name: "testing", title: "Testing", url: "https://example.org/testing", scope: "user", enabled: false, verified: true},
            {name: "flathub", title: "Flathub", url: "https://dl.flathub.org/repo/", scope: "default", enabled: true, verified: true}
        ]
        property var repositories: initialRepositories
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
        function addDefaultSources() { request = "defaults" }
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
        backend.repositories = backend.initialRepositories
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
        compare(menu.itemAt(0).text, "Settings"); verify(menu.itemAt(0).icon.name.length > 0)
        compare(menu.itemAt(1).text, "About"); verify(menu.itemAt(1).icon.name.length > 0)
        menu.itemAt(1).triggered(); menu.close()
        const about = findChild(main, "aboutDialog")
        tryCompare(about, "opened", true)
        compare(findChild(about, "aboutVersion").text, "Version 2026.09 (Beta)")
        const copyright = findChild(about, "aboutCopyright")
        compare(copyright.text, "Copyright © 2026 FluffNet LLC - MIT License")
        compare(copyright.lineCount, 1)
        const close = findChild(about, "aboutCloseButton")
        waitForRendering(close)
        const center = close.mapToItem(about.background, close.width / 2, 0)
        fuzzyCompare(center.x, about.background.width / 2, 1)
        const bottom = close.mapToItem(about.background, 0, close.height)
        verify(about.background.height - bottom.y >= 8)
        mouseClick(close); tryCompare(about, "visible", false)
    }
    function test_settings_controls_and_no_priority() {
        main.showSettings(); tryCompare(stack(), "busy", false)
        compare(page().objectName, "settingsPage"); compare(backend.request, "list")
        compare(page().sources.length, 3)
        compare(findChild(page(), "sourcePriorityUp"), null)
        const row = findChild(page(), "sourceRow")
        compare(findChild(row, "sourceTitle").text, "Flathub")
        const checkbox = findChild(row, "sourceEnabled")
        verify(checkbox.checked); mouseClick(checkbox)
        compare(backend.request, "enable:flathub:false")
        mouseClick(findChild(row, "sourceDetailsButton"))
        const details = findChild(page(), "sourceDetailsDialog")
        tryCompare(details, "opened", true)
        const close = findChild(details, "closeSourceDetailsButton")
        verify(close.visible); compare(close.icon.name, "window-close")
        const topRight = close.mapToItem(details.background, close.width, 0)
        verify(details.background.width - topRight.x >= 8)
        verify(topRight.y >= 8)
        mouseClick(close); tryCompare(details, "visible", false)
        mouseClick(findChild(page(), "addSourceButton"))
        const add = findChild(page(), "addSourceDialog")
        tryCompare(add, "opened", true)
        verify(!findChild(page(), "addDefaultSourcesButton").visible)
        findChild(page(), "sourceInput").text = "https://example.org/testing.flatpakrepo"
        mouseClick(findChild(page(), "confirmAddSourceButton"))
        compare(backend.request, "add:https://example.org/testing.flatpakrepo")
        tryCompare(add, "visible", false)
        mouseClick(findChild(row, "removeSourceButton"))
        const remove = findChild(page(), "removeSourceDialog")
        tryCompare(remove, "opened", true)
        compare(remove.contentItem.text, "Remove Flathub for all users?\n\nAdministrator authentication is required. Installed apps won’t be removed.")
        verify(backend.request.indexOf("remove:") !== 0) // Showing confirmation must not remove anything.
        remove.reject(); tryCompare(remove, "visible", false)
        backend.busy = true
        verify(!findChild(page(), "addSourceButton").enabled)
        verify(!checkbox.enabled)
    }
    function test_checkbox_geometry_and_states_data() {
        return [{tag:"dark-checked", dark:true, checked:true}, {tag:"dark-unchecked", dark:true, checked:false},
                {tag:"light-checked", dark:false, checked:true}, {tag:"light-unchecked", dark:false, checked:false}]
    }
    function test_checkbox_geometry_and_states(data) {
        const oldWindow = main.palette.window, oldText = main.palette.windowText
        main.palette.window = data.dark ? "#202326" : "#eff0f1"
        main.palette.windowText = data.dark ? "white" : "#202326"
        backend.repositories = [{name:"testing", title:"Testing", url:"https://example.org/testing",
            scope:"user", enabled:data.checked, verified:true}]
        main.showSettings(); tryCompare(stack(), "busy", false)
        const row = findChild(page(), "sourceRow")
        const control = findChild(row, "sourceEnabled")
        const indicator = findChild(control, "sourceCheckIndicator")
        waitForRendering(control)
        compare(findChild(row, "sourceTitle").text, "Testing")
        verify(control.width >= 44 && control.height >= 44)
        fuzzyCompare(indicator.x + indicator.width / 2, control.width / 2, 0.01)
        fuzzyCompare(indicator.y + indicator.height / 2, control.height / 2, 0.01)
        fuzzyCompare(control.mapToItem(row, 0, control.height / 2).y, row.height / 2, 0.5)
        verify(indicator.border.width >= 2)
        verify(indicator.border.color.toString() !== main.surfaceColor.toString())
        mouseMove(control, 3, 3); tryCompare(control, "hovered", true)
        compare(control.background.color, main.hoverColor)
        compare(control.background.border.width, 0)
        control.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(control, "visualFocus", true)
        compare(control.background.border.width, 2)
        mouseClick(control, 3, 3) // Entire target, not just the indicator, is clickable.
        compare(backend.request, "enable:testing:" + !data.checked)
        backend.busy = true; verify(!control.enabled)
        verify(indicator.opacity < 1)
        main.palette.window = oldWindow; main.palette.windowText = oldText
    }
    function test_add_source_cancel_icon() {
        main.showSettings(); tryCompare(stack(), "busy", false)
        mouseClick(findChild(page(), "addSourceButton"))
        const add = findChild(page(), "addSourceDialog")
        tryCompare(add, "opened", true)
        const cancel = findChild(add, "cancelAddSourceButton")
        compare(cancel.icon.name, "dialog-cancel")
        mouseClick(cancel); tryCompare(add, "visible", false)
        compare(backend.request, "list")
    }
    function test_remove_source_message_data() {
        return [{tag:"merged", scope:"merged", hasSystem:true},
                {tag:"system", scope:"default", hasSystem:true},
                {tag:"user", scope:"user", hasSystem:false}]
    }
    function test_remove_source_message(data) {
        backend.repositories = [{name:"flathub", title:"Flathub", url:"https://dl.flathub.org/repo/",
                                 scope:data.scope, hasSystem:data.hasSystem, enabled:true}]
        main.showSettings(); tryCompare(stack(), "busy", false)
        mouseClick(findChild(page(), "removeSourceButton"))
        const dialog = findChild(page(), "removeSourceDialog")
        tryCompare(dialog, "opened", true)
        compare(dialog.contentItem.text, data.hasSystem
            ? "Remove Flathub for all users?\n\nAdministrator authentication is required. Installed apps won’t be removed."
            : "Remove Flathub from your account?\n\nInstalled apps won’t be removed.")
        mouseClick(findChild(dialog, "cancelRemoveSourceButton"))
        tryCompare(dialog, "visible", false)
        verify(backend.request.indexOf("remove:") !== 0)
    }
    function test_remove_source_defaults_to_cancel_data() {
        return [{tag:"return", key:Qt.Key_Return}, {tag:"enter", key:Qt.Key_Enter},
                {tag:"space", key:Qt.Key_Space}, {tag:"escape", key:Qt.Key_Escape}]
    }
    function test_remove_source_defaults_to_cancel(data) {
        main.showSettings(); tryCompare(stack(), "busy", false)
        const trigger = findChild(page(), "removeSourceButton")
        const dialog = findChild(page(), "removeSourceDialog")
        const cancel = findChild(dialog, "cancelRemoveSourceButton")
        const confirm = findChild(dialog, "confirmRemoveSourceButton")
        mouseClick(trigger); tryCompare(dialog, "opened", true)
        tryCompare(cancel, "activeFocus", true)
        compare(cancel.icon.name, "dialog-cancel")
        verify(cancel.visualFocus); verify(!confirm.activeFocus)
        keyClick(data.key); tryCompare(dialog, "visible", false)
        verify(backend.request.indexOf("remove:") !== 0)
        // A previous focus on Remove must not survive reopening the dialog.
        mouseClick(trigger); tryCompare(dialog, "opened", true)
        confirm.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Escape); tryCompare(dialog, "visible", false)
        mouseClick(trigger); tryCompare(dialog, "opened", true)
        tryCompare(cancel, "activeFocus", true)
        mouseClick(cancel); tryCompare(dialog, "visible", false)
        verify(backend.request.indexOf("remove:") !== 0)
    }
    function test_empty_sources_default_button_data() { return [{tag:"wide", width:1180}, {tag:"narrow", width:720}] }
    function test_empty_sources_default_button(data) {
        main.width = data.width; backend.repositories = []
        main.showSettings(); tryCompare(stack(), "busy", false)
        mouseClick(findChild(page(), "addSourceButton"))
        const add = findChild(page(), "addSourceDialog")
        tryCompare(add, "opened", true)
        const defaults = findChild(page(), "addDefaultSourcesButton")
        const custom = findChild(page(), "confirmAddSourceButton")
        verify(defaults.visible && defaults.enabled)
        verify(defaults.mapToItem(add.contentItem, 0, 0).x < custom.mapToItem(add.contentItem, 0, 0).x)
        verify(defaults.mapToItem(add.contentItem, 0, 0).y === custom.mapToItem(add.contentItem, 0, 0).y)
        mouseClick(defaults); compare(backend.request, "defaults")
        tryCompare(add, "visible", false)
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
        compare(findChild(page(), "appSourceValue").text, "installed-repo")
        verify(!findChild(page(), "installSourceButton").visible)
        main.showCatalog(); tryCompare(stack(), "busy", false)
        main.selectedCategory = "Installed"
        const list = findChild(page(), "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const source = findChild(list.itemAtIndex(0), "installedSourceValue")
        compare(source.text, "installed-repo")
        compare(source.renderType, Text.NativeRendering)
        backend.installedApps = [Object.assign({}, backend.installedApps[0], {installation:"default"})]
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        compare(findChild(list.itemAtIndex(0), "installedSourceValue").text, "installed-repo (System)")
        main.selectedCategory = "All Apps"
    }
}
