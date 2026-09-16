import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Transactions"
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
        property var installSizes: ({})
        property string sizeRequested: ""
        function requestInstallInfo(app) { sizeRequested = app.id }
        property string requested: ""
        property int acceptedToken: 0
        signal appOpened(var app)
        signal inputError(string message)
        function installApp(app) { requested = "install:" + app.id }
        function uninstallApp(app) { requested = "uninstall:" + app.id }
        function answerReview(token, accept) { acceptedToken = accept ? token : -token; review = ({}) }
        function cancelJob(index) { requested = "cancel:" + index }
    }
    AppCenter.Main { id: main; backend: backend; visible: true }
    function test_inline_sizes_and_website_alignment() {
        const app = {id: "org.example.Size", name: "Size test", summary: "", description: "", icon: "", screenshots: [], category: "Games", license: "MIT", homepage: "https://example.org/", developer: ""}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        compare(backend.sizeRequested, app.id)
        const page = stack.currentItem
        const appSize = findChild(page, "appDownloadSize")
        const totalSize = findChild(page, "totalDownloadSize")
        compare(appSize.text, "Unavailable")
        backend.installSizes = {"org.example.Size": {state: "ready", appSize: "2 MiB", totalSize: "3 MiB"}}
        compare(appSize.text, "2 MiB")
        compare(totalSize.text, "3 MiB")
        verify(appSize.font.bold && totalSize.font.bold)
        compare(appSize.color, main.textColor)
        const website = findChild(page, "appWebsiteLink")
        compare(website.contentItem.horizontalAlignment, Text.AlignLeft)
        compare(website.leftPadding, 0)
        compare(website.contentItem.text, app.homepage)
        backend.installSizes = {"org.example.Size": {state: "unavailable"}}
        compare(totalSize.text, "Unavailable")
        verify(findChild(page, "installAppButton").enabled)
        backend.installSizes = {"org.example.Size": {state: "partial", appSize: "2 MiB"}}
        compare(appSize.text, "2 MiB")
        compare(totalSize.text, "Unavailable")
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installSizes = ({})
    }
    function hasDownloadsText(item) {
        if (item.text === "Downloads") return true
        const children = item.children || []
        for (let i = 0; i < children.length; ++i)
            if (hasDownloadsText(children[i])) return true
        return false
    }
    function test_downloads_stays_in_catalog_not_app_view() {
        const app = {id: "org.example.Download", name: "Download test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.5,
                         status: "Downloading", operations: [{name: "org.example.Runtime", progress: 0.5}]}]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        verify(!findChild(page, "downloadsButton"))
        verify(!hasDownloadsText(page))
        verify(findChild(page, "appInstallProgress").visible)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: false, progress: 1, status: "Complete", operations: []}]
        verify(!hasDownloadsText(page))
        main.showCatalog()
        tryCompare(stack, "busy", false)
        verify(findChild(stack.currentItem, "downloadsButton").visible)
        backend.jobs = []
    }
    function test_external_flatpak_opens_app_view_without_catalog_picker() {
        const app = {id: "org.example.External", name: "External app", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.appOpened(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        compare(stack.currentItem.app.id, app.id)
        verify(findChild(stack.currentItem, "installAppButton").visible)
        compare(typeof main.openFlatpak, "undefined")
        main.showCatalog()
        tryCompare(stack, "busy", false)
    }
    function test_app_actions_review_progress_and_installed_refresh() {
        const app = {id: "org.example.Test", name: "Test", summary: "A test", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const install = findChild(page, "installAppButton")
        verify(install.visible)
        mouseClick(install)
        compare(backend.requested, "install:org.example.Test")
        verify(!findChild(main, "transactionReview").visible)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.35,
                         status: "Downloading", operations: [{name: "org.example.Runtime", progress: 0.35}]}]
        verify(findChild(page, "appInstallProgress").visible)
        compare(findChild(page, "appInstallProgress").value, 0.35)
        verify(!install.visible)
        backend.review = {token: 7, title: "Uninstall", kind: "transaction", removing: true, message: "Remove app and data",
                          operations: [], downloadSize: "10 MB"}
        const dialog = findChild(main, "transactionReview")
        tryCompare(dialog, "visible", true)
        mouseClick(dialog.standardButton(Dialog.Ok))
        compare(backend.acceptedToken, 7)
        tryCompare(dialog, "visible", false)
        wait(250) // Allow the modal dimmer's close transition to finish.
        backend.installedApps = [Object.assign({}, app, {installation: "user", installedSize: "20 MB", installedVersion: "1.2", installedBranch: "stable", installedArch: "x86_64"})]
        backend.jobs = [{id: app.id, index: 0, name: app.name, active: false, progress: 1, status: "Complete", operations: []}]
        verify(!install.visible)
        const uninstall = findChild(page, "uninstallAppButton")
        verify(uninstall.visible)
        waitForRendering(page)
        mouseClick(uninstall)
        compare(backend.requested, "uninstall:org.example.Test")
        backend.installedApps = []
        verify(install.visible)
        verify(!uninstall.visible)
        compare(main.detailsFor(app).installedSize, undefined)
    }
}
