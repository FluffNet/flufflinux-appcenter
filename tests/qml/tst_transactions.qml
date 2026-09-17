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
        property int sizeRequestCount: 0
        function requestInstallInfo(app) { sizeRequested = app.id; ++sizeRequestCount }
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
    function initTestCase() {
        main.requestActivate()
        waitForRendering(main.contentItem)
        wait(250) // Let startup search focus and the first layout settle.
    }
    function init() {
        main.requestActivate()
        waitForRendering(main.contentItem)
    }
    function test_simple_uninstall_confirmation_data() {
        return [{tag: "user", message: "If you proceed, Calculator and its app data will be removed."},
                {tag: "system", message: "If you proceed, Calculator will be removed for all users, and its app data for this account will be deleted."}]
    }
    function test_simple_uninstall_confirmation(data) {
        const dialog = findChild(main, "transactionReview")
        const plan = {token: 41, title: "Uninstall Calculator?", kind: "transaction", removing: true,
                      message: data.message, operations: [{name: "org.example.Test", ref: "app/org.example.Test/x86_64/stable", action: "uninstall"}]}
        backend.review = plan
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        compare(dialog.title, plan.title)
        const yes = findChild(dialog.footer, "confirmReviewButton")
        const no = findChild(dialog.footer, "rejectReviewButton")
        compare(yes.text, "Yes")
        verify(yes.icon.source.toString().endsWith("trash-red.svg"))
        compare(yes.icon.color, Qt.rgba(0, 0, 0, 0))
        compare(no.text, "No")
        compare(no.icon.name, "dialog-cancel")
        verify(no.activeFocus)
        verify(dialog.contentItem.visible)
        const message = findChild(dialog.contentItem, "reviewMessage")
        compare(message.text, data.message)
        compare(message.textFormat, Text.PlainText)
        verify(message.visible && message.height >= message.implicitHeight)
        verify(!message.text.includes("your"))
        compare(findChild(dialog.contentItem, "reviewOperations").count, 0)
        verify(dialog.width <= 480 && dialog.height < 260, "Removal prompt must stay compact")
        const messagePosition = message.mapToItem(dialog.contentItem, 0, 0)
        verify(messagePosition.y + message.height <= dialog.contentItem.height, "Paragraph must fit above the buttons")
        const point = no.mapToItem(dialog.footer, 0, 0)
        verify(point.x >= 0 && point.x + no.width <= dialog.footer.width)
        verify(point.y >= 0 && point.y + no.height <= dialog.footer.height)
        mousePress(no)
        verify(no.down, "No button must receive pointer input")
        mouseRelease(no)
        compare(backend.acceptedToken, -41)
        tryCompare(dialog, "visible", false)
        backend.review = Object.assign({}, plan, {token: 42})
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        keyClick(Qt.Key_Escape)
        compare(backend.acceptedToken, -42)
        tryCompare(dialog, "visible", false)
        backend.review = Object.assign({}, plan, {token: 43})
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        mouseClick(yes)
        compare(backend.acceptedToken, 43)
        tryCompare(dialog, "visible", false)
        // Source trust is a different confirmation: keep its information.
        backend.review = {token: 44, title: "Add source?", kind: "remote", message: "Source URL and trust details"}
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        verify(dialog.contentItem.visible)
        compare(yes.text, "Trust and add source")
        compare(no.text, "Cancel")
        mouseClick(no)
        compare(backend.acceptedToken, -44)
        tryCompare(dialog, "visible", false)
    }
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
        const totalCaption = findChild(page, "totalDownloadSizeLabel")
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 2097152, totalBytes: 2097152, appSize: "2 MiB", totalSize: "2 MiB"}}
        verify(appSize.visible)
        verify(!totalSize.visible && !totalCaption.visible)
        // Compare the displayed text, not byte-level differences hidden by rounding.
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 2097152, totalBytes: 2097153, appSize: "2 MiB", totalSize: "2 MiB"}}
        verify(!totalSize.visible && !totalCaption.visible)
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 1900000000, totalBytes: 1900010000, appSize: "1.77 GiB", totalSize: "1.77 GiB"}}
        verify(!totalSize.visible && !totalCaption.visible)
        backend.installSizes = {"org.example.Size": {state: "ready", appSize: "1.77 GiB", totalSize: "1.78 GiB"}}
        verify(totalSize.visible && totalCaption.visible)
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 0, totalBytes: 0, appSize: "0 bytes", totalSize: "0 bytes"}}
        verify(!totalSize.visible && !totalCaption.visible)
        verify(appSize.font.bold && totalSize.font.bold)
        compare(appSize.color, main.textColor)
        const website = findChild(page, "appWebsiteLink")
        compare(website.contentItem.horizontalAlignment, Text.AlignLeft)
        compare(website.leftPadding, 4)
        compare(website.rightPadding, 4)
        compare(website.topPadding, 4)
        compare(website.bottomPadding, 4)
        compare(website.contentItem.text, app.homepage)
        verify(Math.abs(website.width - website.contentItem.implicitWidth - 8) < 1,
               "Website focus/click target must fit the URL plus 4px on each side")
        verify(website.width < website.parent.width / 2)
        backend.installSizes = {"org.example.Size": {state: "unavailable"}}
        verify(totalSize.visible && totalCaption.visible)
        compare(totalSize.text, "Unavailable")
        verify(findChild(page, "installAppButton").enabled)
        backend.installSizes = {"org.example.Size": {state: "partial", appSize: "2 MiB"}}
        compare(appSize.text, "2 MiB")
        compare(totalSize.text, "Unavailable")
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installSizes = ({})
    }
    function test_long_website_fits_narrow_window() {
        const previousWidth = main.width
        main.width = 720
        const app = {id: "org.example.Website", name: "Website test", summary: "", description: "", category: "", license: "", developer: "", icon: "", screenshots: [],
                     homepage: "https://example.org/" + "long-path/".repeat(40)}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const website = findChild(stack.currentItem, "appWebsiteLink")
        verify(website.width > 0 && website.width <= website.parent.width)
        verify(website.width < website.contentItem.implicitWidth)
        const point = website.mapToItem(stack.currentItem, 0, 0)
        verify(point.x + website.width <= stack.currentItem.width)
        website.forceActiveFocus()
        verify(website.activeFocus)
        main.showCatalog(); tryCompare(stack, "busy", false)
        main.width = previousWidth
    }
    function test_installed_app_tracks_size_target_data() {
        return [{tag: "fresh-session", priorApp: false}, {tag: "different-app-viewed-first", priorApp: true}]
    }
    function test_installed_app_tracks_size_target(data) {
        const app = {id: "org.example.Installed", name: "Installed test", summary: "", description: "", icon: "", screenshots: [], category: "Games", license: "", homepage: "", developer: "",
                     installation: "user", installedBranch: "stable", installedArch: "x86_64", installedSize: "10 MB", installedVersion: "1.0"}
        const stack = findChild(main, "navigationStack")
        backend.installSizes = ({})
        backend.sizeRequested = ""
        backend.installedApps = [app]
        if (data.priorApp) {
            main.openApp(Object.assign({}, app, {id: "org.example.Prior"}))
            tryCompare(stack, "busy", false)
            compare(backend.sizeRequested, "org.example.Prior")
        }
        const before = backend.sizeRequestCount
        main.openApp(app)
        tryCompare(stack, "busy", false)
        compare(backend.sizeRequested, app.id)
        compare(backend.sizeRequestCount, before + 1)
        const page = stack.currentItem
        verify(!findChild(page, "installSizeDetails").visible)
        // The manager refreshes the tracked app's sizes before it publishes
        // the new installed list. The same page must reveal those fresh values.
        backend.installSizes = {"org.example.Installed": {state: "ready", appSize: "2 MiB", totalSize: "2 MiB"}}
        backend.installedApps = []
        compare(stack.currentItem, page)
        verify(findChild(page, "appDownloadSize").visible)
        compare(findChild(page, "appDownloadSize").text, "2 MiB")
        verify(!findChild(page, "totalDownloadSize").visible)
        verify(findChild(page, "installAppButton").visible)
        // Icon/list notifications must not introduce additional size reads.
        ++backend.iconRevision
        backend.installedApps = []
        compare(backend.sizeRequestCount, before + 1)
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
        verify(!findChild(page, "appJobStatus").visible)
        main.showCatalog()
        tryCompare(stack, "busy", false)
        verify(findChild(stack.currentItem, "downloadsButton").visible)
        backend.jobs = []
    }
    function test_cancelled_job_removed_from_app_and_downloads() {
        const app = {id: "org.example.Cancel", name: "Cancel test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.jobs = [{id: app.id, index: 5, name: app.name, active: true, progress: 0.4, status: "Downloading", operations: []}]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        mouseClick(findChild(page, "cancelAppButton"))
        compare(backend.requested, "cancel:5")
        // The backend removes a completed cancellation from its public list.
        backend.jobs = []
        verify(findChild(page, "installAppButton").visible)
        verify(!findChild(page, "appJobStatus").visible)
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!main.downloadQueue.buttonVisible)
        main.showDownloads(); tryCompare(stack, "busy", false)
        compare(findChild(stack.currentItem, "downloadJobs").count, 0)
        // Other completed/failed operations still remain in session history.
        backend.jobs = [{id: "org.example.Keep", index: 8, name: "Keep", active: false, failed: false, progress: 1, status: "Complete", operations: []}]
        compare(findChild(stack.currentItem, "downloadJobs").count, 1)
        verify(main.downloadQueue.buttonVisible)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
    }
    function test_separate_download_and_install_progress() {
        const app = {id: "org.example.Stages", name: "Stages", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        const job = {id: app.id, name: app.name, index: 0, active: true, action: "install", progress: 0.5,
            hasDownload: true, downloadProgress: 0.5, installProgress: 0, installCompleted: 0, installTotal: 2,
            phase: "download", status: "Downloading…", operations: [{name: "Runtime", phase: "download", progress: 0.5, status: "Downloading…", downloadSize: "2 MiB"}]}
        backend.jobs = [job]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const download = findChild(page, "downloadPhaseProgress")
        const install = findChild(page, "installPhaseProgress")
        verify(download.visible && install.visible)
        compare(download.value, 0.5); compare(install.value, 0)
        verify(!install.activeStep)
        compare(findChild(page, "downloadPhaseLabel").text, "Download: 50%")
        compare(findChild(page, "installPhaseLabel").text, "Installation: 0 of 2 completed")
        backend.jobs = [Object.assign({}, job, {downloadProgress: 1, phase: "install", installCompleted: 1, installProgress: 0.5})]
        compare(download.value, 1); compare(install.value, 0.5)
        verify(install.activeStep && !install.indeterminate)
        compare(findChild(page, "installPhaseLabel").text, "Installation: 1 of 2 completed")
        main.showDownloads(); tryCompare(stack, "busy", false)
        let card = findChild(stack.currentItem, "downloadJobProgress")
        verify(card.visible)
        compare(findChild(card, "downloadPhaseProgress").value, 1)
        compare(findChild(card, "installPhaseProgress").value, 0.5)
        backend.jobs = [Object.assign({}, job, {downloadEstimating: true})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(findChild(card, "downloadPhaseProgress").indeterminate)
        compare(findChild(card, "downloadPhaseLabel").text, "Downloading…")
        backend.jobs = [Object.assign({}, job, {hasDownload: false, phase: "install"})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(!findChild(card, "downloadPhaseProgress").visible)
        backend.jobs = [Object.assign({}, job, {active: false, progress: 1, status: "Complete"})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(!card.visible)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
    }
    function test_removals_only_show_in_installed_and_app_view() {
        const app = {id: "org.example.Remove", name: "Remove test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "",
                     installedSize: "10 MB", installedVersion: "1.0", installation: "user", installedBranch: "stable", installedArch: "x86_64"}
        const removal = {id: app.id, index: 4, action: "uninstall", name: app.name, active: true, removalConfirmed: true, progress: 0.3, status: "Removing…", operations: [{name: app.id, progress: 0.3}]}
        const download = {id: "org.example.Download", index: 7, action: "install", name: "Download", active: true, progress: 0.5, status: "Downloading", operations: []}
        backend.installedApps = [app]
        backend.jobs = [removal]
        main.showCatalog()
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        main.selectedCategory = "Installed"
        const list = findChild(stack.currentItem, "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const row = list.itemAtIndex(0)
        verify(findChild(row, "installedRemovalProgress").visible)
        compare(findChild(row, "installedRemovalProgress").value, 0.3)
        compare(findChild(row, "installedRemovalStatus").text, "Removing…")
        verify(!findChild(row, "uninstallButton").enabled)
        verify(!main.downloadQueue.buttonVisible)
        compare(main.downloadQueue.activeCount, 0)
        backend.jobs = [removal, download]
        compare(main.downloadQueue.jobs.length, 1)
        compare(main.downloadQueue.activeCount, 1)
        compare(main.downloadQueue.progress, 0.5)
        main.openApp(app); tryCompare(stack, "busy", false)
        verify(findChild(stack.currentItem, "appInstallProgress").visible)
        compare(findChild(stack.currentItem, "appJobStatus").text, "Removing…")
        backend.jobs = [Object.assign({}, removal, {active: false, failed: true, status: "Failed", error: "Removal failed"}), download]
        verify(findChild(stack.currentItem, "appJobStatus").visible)
        verify(!main.downloadQueue.hasError) // Removal errors stay with the app.
        backend.jobs = [Object.assign({}, removal, {active: false, failed: false, status: "Complete"}), download]
        verify(!findChild(stack.currentItem, "appJobStatus").visible)
        main.showDownloads(); tryCompare(stack, "busy", false)
        compare(findChild(stack.currentItem, "downloadJobs").count, 1)
        // A cancelled download must not create a badge alongside a removal.
        backend.jobs = [removal, Object.assign({}, download, {active: false, cancelled: true, status: "Cancelled"})]
        compare(findChild(stack.currentItem, "downloadJobs").count, 0)
        verify(!main.downloadQueue.buttonVisible)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
        backend.installedApps = []
        main.selectedCategory = "All Apps"
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
    function test_removal_progress_waits_for_yes_data() {
        return [{tag: "queued", status: "Queued", operations: []},
                {tag: "preparing", status: "Preparing…", operations: []},
                {tag: "review", status: "Waiting for confirmation", operations: [{name: "App", progress: 0}]}]
    }
    function test_removal_progress_waits_for_yes(data) {
        const app = {id: "org.example.Confirmation", name: "Confirmation", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "",
            installedSize: "10 MB", installedVersion: "1.0", installation: "user", installedBranch: "stable", installedArch: "x86_64"}
        const removal = {id: app.id, index: 0, action: "uninstall", name: app.name, active: true,
            removalConfirmed: false, progress: 0, status: data.status, operations: data.operations}
        backend.installedApps = [app]
        backend.jobs = [removal]
        main.showCatalog()
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        main.selectedCategory = "Installed"
        const list = findChild(stack.currentItem, "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const row = list.itemAtIndex(0)
        verify(!findChild(row, "installedRemovalProgress").visible)
        compare(findChild(row, "installedRemovalStatus").text, "Waiting for confirmation")
        main.openApp(app); tryCompare(stack, "busy", false)
        const page = stack.currentItem
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!findChild(page, "cancelAppButton").visible)
        compare(findChild(page, "appJobStatus").text, "Waiting for confirmation")
        // No must not briefly display the bar while its worker exits.
        backend.jobs = [Object.assign({}, removal, {status: "Cancelling…"})]
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!findChild(page, "cancelAppButton").visible)
        backend.jobs = []
        verify(findChild(page, "uninstallAppButton").visible)
        verify(!findChild(page, "appJobStatus").visible)
        // A later Yes explicitly starts progress, never a Cancel action.
        backend.jobs = [Object.assign({}, removal, {removalConfirmed: true, status: "Uninstalling…"})]
        verify(findChild(page, "appInstallProgress").visible)
        verify(!findChild(page, "cancelAppButton").visible)
        compare(findChild(page, "appJobStatus").text, "Uninstalling…")
        main.showCatalog(); tryCompare(stack, "busy", false)
        verify(findChild(row, "installedRemovalProgress").visible)
        verify(findChild(row, "installedRemovalProgress").indeterminate)
        compare(findChild(row, "installedRemovalStatus").text, "Uninstalling…")
        backend.jobs = []
        backend.installedApps = []
        main.selectedCategory = "All Apps"
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
                         downloadProgress: 0.35, installProgress: 0, installTotal: 1, installCompleted: 0,
                         status: "Downloading", operations: [{name: "org.example.Runtime", progress: 0.35}]}]
        verify(findChild(page, "appInstallProgress").visible)
        compare(findChild(page, "downloadPhaseProgress").value, 0.35)
        verify(findChild(page, "downloadPhaseLabel").visible)
        compare(findChild(page, "downloadPhaseLabel").text, "Download: 35%")
        verify(findChild(page, "appJobStatus").visible)
        verify(!install.visible)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.99,
                         downloadProgress: 1, installProgress: 0, phase: "install", installTotal: 1, installCompleted: 0,
                         status: "Installing…", operations: [{name: app.id, progress: 1}]}]
        compare(findChild(page, "appJobStatus").text, "Installing…")
        compare(findChild(page, "downloadPhaseProgress").value, 1)
        compare(findChild(page, "installPhaseProgress").value, 0)
        verify(findChild(page, "installPhaseProgress").activeStep)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.4,
                         status: "Downloading… 1.50 MiB received", operations: [{name: app.id, progress: 0.4}]}]
        compare(findChild(page, "appJobStatus").text, "Downloading… 1.50 MiB received")
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: false, failed: true,
                         progress: 0.35, status: "Failed", error: "Connection lost", operations: []}]
        verify(findChild(page, "appJobStatus").visible)
        verify(findChild(page, "appJobStatus").text.indexOf("Connection lost") !== -1)
        backend.review = {token: 7, title: "Uninstall", kind: "transaction", removing: true, message: "Remove app and data",
                          operations: [], downloadSize: "10 MB"}
        const dialog = findChild(main, "transactionReview")
        tryCompare(dialog, "visible", true)
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        mouseClick(findChild(dialog.footer, "confirmReviewButton"))
        compare(backend.acceptedToken, 7)
        tryCompare(dialog, "visible", false)
        wait(250) // Allow the modal dimmer's close transition to finish.
        backend.installedApps = [Object.assign({}, app, {installation: "user", installedSize: "20 MB", installedVersion: "1.2", installedBranch: "stable", installedArch: "x86_64"})]
        backend.jobs = [{id: app.id, index: 0, name: app.name, active: false, progress: 1, status: "Complete", operations: []}]
        verify(!install.visible)
        verify(!findChild(page, "appJobStatus").visible)
        verify(!findChild(page, "appInstallProgress").visible)
        compare(main.downloadQueue.jobs.length, 1)
        verify(!findChild(page, "downloadPhaseLabel").visible)
        compare(main.downloadQueue.jobs[0].status, "Complete")
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
