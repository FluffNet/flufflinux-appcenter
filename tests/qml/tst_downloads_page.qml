import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    id: testCase
    name: "DownloadsPage"
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
        property var launched: null
        property int cancelledIndex: -1
        property int clearCount: 0
        signal appOpened(var app)
        signal inputError(string message)
        function launchApp(app) { launched = app }
        function cancelJob(index) { cancelledIndex = index }
        function clearDownloadHistory() { ++clearCount; jobs = jobs.filter(job => job.active) }
    }
    AppCenter.Main { id: main; backend: backend; visible: true }
    readonly property var app: { return {
        id: "org.example.App", name: "Example application", installation: "user",
        installedBranch: "stable", installedArch: "x86_64", installedVersion: "1.0", installedSize: "512.00 MiB"
    } }
    readonly property var job: { return {
        id: app.id, name: app.name, index: 3, action: "install", active: true, progress: 0.25,
        status: "Downloading dependency", hasDownload: true, downloadComplete: false,
        downloadedSize: "128.00 MiB", downloadTotalSize: "512.00 MiB", downloadSpeed: "2.30 MiB/s",
        operations: [{name: "org.example.Runtime", dependency: true, status: "Complete", downloadSize: "384.00 MiB"},
                     {name: app.id, status: "Downloading", downloadSize: "128.00 MiB"}]
    } }
    function stack() { return findChild(main, "navigationStack") }
    function card() { return findChild(stack().currentItem, "downloadJobs").itemAt(0) }
    function visibleText(item) {
        if (!item.visible) return ""
        let result = item.text || ""
        for (const child of (item.children || [])) result += "\n" + visibleText(child)
        return result
    }
    function init() {
        main.width = 1180
        backend.jobs = [Object.assign({}, job)]
        main.showDownloads()
        tryCompare(stack(), "busy", false)
        waitForRendering(stack().currentItem)
    }
    function cleanup() {
        main.showCatalog()
        tryCompare(stack(), "busy", false)
        backend.jobs = []; backend.installedApps = []; backend.review = ({})
        backend.launched = null; backend.cancelledIndex = -1
        backend.clearCount = 0; main.catalog = []
    }
    function test_open_details_from_icon_and_title_data() {
        return [{tag: "icon", object: "downloadAppIcon"}, {tag: "title", object: "downloadAppName"}]
    }
    function test_open_details_from_icon_and_title(data) {
        main.catalog = [Object.assign({}, app, {summary: "App information", description: "Description", screenshots: [], developer: "Developer", category: "Utilities", homepage: "", license: "MIT"})]
        const downloads = stack().currentItem
        mouseClick(findChild(card(), data.object))
        tryCompare(stack(), "busy", false)
        compare(stack().depth, 3)
        compare(stack().currentItem.app.id, app.id)
        compare(stack().currentItem.app.description, "Description")
        mouseClick(findChild(stack().currentItem, "backButton"))
        tryCompare(stack(), "busy", false)
        compare(stack().currentItem, downloads, "Back should return to the same Downloads page")
        compare(backend.jobs.length, 1)
    }
    function test_progress_updates_preserve_a_pressed_card_data() {
        return [{tag: "icon", object: "downloadAppIcon"}, {tag: "title", object: "downloadAppName"},
                {tag: "cancel", object: "cancelDownloadButton"}]
    }
    function test_progress_updates_preserve_a_pressed_card(data) {
        const originalCard = card()
        const button = findChild(originalCard, data.object)
        mousePress(button)
        for (let update = 1; update <= 8; ++update) {
            backend.jobs = [Object.assign({}, job, {progress: update / 10, downloadedSize: update + " MiB"})]
            compare(card(), originalCard, "Progress must update the existing card, not replace it mid-click")
        }
        mouseRelease(button)
        if (data.tag === "cancel") compare(backend.cancelledIndex, job.index)
        else {
            tryCompare(stack(), "busy", false)
            compare(stack().currentItem.app.id, app.id, "One press/release opens details despite progress updates")
        }
    }
    function test_clear_history_preserves_active_jobs() {
        const clear = findChild(stack().currentItem, "clearDownloadHistoryButton")
        verify(clear.visible && !clear.enabled)
        backend.jobs = [job, Object.assign({}, job, {id: "org.example.Done", index: 4, active: false, status: "Complete"}),
            Object.assign({}, job, {id: "org.example.Failed", index: 5, active: false, failed: true, status: "Failed"})]
        verify(clear.enabled)
        mouseClick(clear)
        compare(backend.clearCount, 1)
        compare(backend.jobs.length, 1)
        compare(backend.jobs[0].index, 3)
        verify(!clear.enabled)
        backend.jobs = [Object.assign({}, job, {active: false, status: "Complete"})]
        mouseClick(clear)
        compare(findChild(stack().currentItem, "downloadJobs").count, 0)
    }
    function test_clear_history_icon_and_header_alignment_data() {
        return [{tag: "wide", width: 1180}, {tag: "narrow", width: 720}]
    }
    function test_clear_history_icon_and_header_alignment(data) {
        main.width = data.width
        backend.jobs = [Object.assign({}, job, {active: false})]
        const page = stack().currentItem
        const clear = findChild(page, "clearDownloadHistoryButton")
        const icon = findChild(clear, "fluffButtonIcon")
        const label = findChild(clear, "fluffButtonLabel")
        const title = findChild(page, "downloadsTitle")
        waitForPolish(main.contentItem)
        compare(clear.icon.name, "edit-clear-history")
        verify(icon.visible && label.visible)
        compare(icon.source.toString(), main.iconSource("edit-clear-history"))
        compare(icon.width, 20); compare(icon.height, 20)
        verify(icon.mapToItem(clear, icon.width, 0).x < label.mapToItem(clear, 0, 0).x)
        verify(Math.abs(icon.mapToItem(clear, 0, icon.height / 2).y
                        - label.mapToItem(clear, 0, label.height / 2).y) < 1)
        verify(Math.abs(title.mapToItem(page, title.width / 2, 0).x - page.width / 2) < 1)
        verify(title.mapToItem(page, title.width, 0).x <= clear.mapToItem(page, 0, 0).x)
        verify(clear.mapToItem(page, clear.width, 0).x <= page.width - 11)
    }
    function test_history_changes_preserve_surviving_cards_and_ids() {
        const rows = findChild(stack().currentItem, "downloadJobs")
        const original = card()
        const other = Object.assign({}, job, {index: 8, id: "org.example.Other", name: "Other"})
        backend.jobs = [other, job]
        compare(rows.count, 2)
        compare(rows.itemAt(1), original)
        const otherCard = rows.itemAt(0)
        backend.jobs = [job, other]
        compare(rows.itemAt(0), original)
        compare(rows.itemAt(1), otherCard)
        backend.jobs = [other]
        compare(rows.count, 1)
        compare(rows.itemAt(0), otherCard)
        mouseClick(findChild(otherCard, "cancelDownloadButton"))
        compare(backend.cancelledIndex, 8, "Removing history must not change a surviving job's cancellation ID")
    }
    function test_simple_progress_data() {
        return [{tag: "wide", width: 1180}, {tag: "narrow", width: 720}]
    }
    function test_simple_progress(data) {
        main.width = data.width
        waitForRendering(card())
        const text = visibleText(stack().currentItem)
        verify(text.indexOf("This session") < 0)
        verify(text.indexOf("org.example.") < 0, "Neither dependency nor app operation rows should be shown")
        verify(text.indexOf("Complete") < 0)
        const progress = findChild(card(), "overallInstallProgress")
        verify(progress.visible)
        const bytes = findChild(card(), "downloadBytesLabel")
        const percentage = findChild(card(), "overallPercentageLabel")
        compare(bytes.text, "128.00 MiB / 512.00 MiB (2.30 MiB/s)")
        compare(percentage.text, "25%")
        verify(bytes.mapToItem(card(), bytes.width, 0).x <= percentage.mapToItem(card(), 0, 0).x)
        const cancel = findChild(card(), "cancelDownloadButton")
        verify(cancel.width >= 176 && cancel.height >= 56)
        verify(cancel.mapToItem(card(), cancel.width, 0).x <= card().width - 19)
        mouseClick(cancel)
        compare(backend.cancelledIndex, 3)
        verify(!findChild(card(), "openDownloadButton").visible)
    }
    function test_completed_open_uses_current_installed_record() {
        backend.jobs = [Object.assign({}, job, {active: false, progress: 1, status: "Complete"})]
        verify(!findChild(card(), "openDownloadButton").visible, "Wait for the installed-app refresh")
        backend.installedApps = [app]
        const open = findChild(card(), "openDownloadButton")
        verify(open.visible)
        verify(!findChild(card(), "downloadJobStatus").visible)
        verify(!findChild(card(), "downloadJobProgress").visible)
        verify(!findChild(card(), "cancelDownloadButton").visible)
        verify(visibleText(card()).indexOf("Complete") < 0)
        mouseClick(open)
        compare(backend.launched.id, app.id)
        compare(backend.launched.installation, "user")
        compare(backend.launched.installedBranch, "stable")
        backend.installedApps = []
        verify(!open.visible, "An app uninstalled later must not retain an Open button")
    }
    function test_removing_app_cannot_be_opened_from_history() {
        backend.installedApps = [app]
        backend.jobs = [Object.assign({}, job, {active: false, status: "Complete"}),
                        {id: app.id, index: 4, action: "uninstall", active: true}]
        verify(!findChild(card(), "openDownloadButton").visible)
        compare(findChild(stack().currentItem, "downloadJobs").count, 1)
    }
    function test_failure_keeps_error_not_open() {
        backend.installedApps = [app]
        backend.jobs = [Object.assign({}, job, {active: false, failed: true, status: "Failed", error: "Network unavailable"})]
        verify(!findChild(card(), "openDownloadButton").visible)
        verify(findChild(card(), "downloadJobError").visible)
        compare(findChild(card(), "downloadJobError").text, "Network unavailable")
        compare(findChild(card(), "downloadJobStatus").text, "Failed")
    }
    function test_repo_success_has_no_complete_or_open() {
        backend.jobs = [{index: 3, action: "source", id: "", name: "Repository", active: false, status: "Complete", operations: []}]
        verify(!findChild(card(), "openDownloadButton").visible)
        verify(!findChild(card(), "downloadJobStatus").visible)
        verify(visibleText(card()).indexOf("Complete") < 0)
    }
    function test_queued_and_cancelling_status() {
        backend.jobs = [Object.assign({}, job, {queued: true, status: "Queued"})]
        compare(findChild(card(), "downloadJobStatus").text, "Pending…")
        verify(findChild(card(), "downloadJobStatus").visible)
        verify(!findChild(card(), "downloadJobProgress").visible)
        verify(!findChild(card(), "overallInstallProgress").visible)
        backend.jobs = [Object.assign({}, job, {cancelling: true, status: "Complete"})]
        compare(findChild(card(), "downloadJobStatus").text, "Cancelling…")
        verify(visibleText(card()).indexOf("Complete") < 0)
        backend.jobs = [Object.assign({}, job, {active: false, cancelled: true})]
        compare(findChild(stack().currentItem, "downloadJobs").count, 0)
    }
}
