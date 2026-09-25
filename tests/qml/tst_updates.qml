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
        backend.jobs = []; backend.review = ({})
        main.width = 1180; main.height = 760; main.requestActivate()
        waitForPolish(root()); wait(30)
    }
    function open() { main.showUpdates(); tryCompare(stack(), "busy", false); waitForPolish(page()); wait(30) }
    function test_update_icons_follow_theme_data() {
        return [{tag:"dark", background:"#202326", foreground:"#ffffff"},
            {tag:"light", background:"#eff0f1", foreground:"#202326"},
            {tag:"custom", background:"#302922", foreground:"#f2e7d9"}]
    }
    function test_update_icons_follow_theme(data) {
        const background = main.palette.window, foreground = main.palette.windowText, network = main.networkStatus
        try {
            main.palette.window = data.background; main.palette.windowText = data.foreground
            open(); ready()
            const navigation = findChild(root(), "updatesNavigationIcon")
            compare(navigation.source.toString(), "system-upgrade")
            for (const icon of [navigation,
                    findChild(findChild(page(), "checkForUpdatesButton"), "fluffButtonMonochromeIcon"),
                    findChild(findChild(page(), "installUpdatesButton"), "fluffButtonMonochromeIcon")]) {
                verify(icon.visible && icon.isMask); compare(icon.color, main.textColor)
                tryCompare(icon, "status", 1) // Kirigami.Icon.Ready; native KDE captures verify rendered colors.
            }
            backend.checkForUpdates(); waitForPolish(page())
            const cancel = findChild(findChild(page(), "cancelUpdateCheckButton"), "fluffButtonMonochromeIcon")
            verify(cancel.visible && cancel.isMask); compare(cancel.color, main.textColor)
            tryCompare(cancel, "status", 1)
            ready(); backend.busy = true
            const install = findChild(page(), "installUpdatesButton")
            verify(!install.enabled); compare(install.contentItem.opacity, 0.45)
            compare(findChild(install, "fluffButtonMonochromeIcon").color, main.textColor)
            main.networkStatus = {state:"offline", ready:true}
            verify(!findChild(root(), "updatesButton").enabled)
            compare(navigation.parent.opacity, 0.38); compare(navigation.color, main.textColor)
            main.networkStatus = network; backend.busy = false
            // Check recoloring of the existing renderer, without recreating it.
            main.palette.windowText = data.tag === "light" ? "#ffffff" : "#202326"
            compare(navigation.color, main.textColor)
        } finally {
            main.palette.window = background; main.palette.windowText = foreground; main.networkStatus = network
        }
    }
    function test_clear_app_update_labels() {
        open()
        compare(findChild(root(), "updatesButton").text, "App Updates")
        compare(findChild(page(), "appUpdatesTitle").text, "App Updates")
        compare(findChild(page(), "checkForUpdatesButton").text, "Check for App Updates")
        compare(findChild(page(), "updateDates").text, "Apps were last updated: Not recorded")
        verify(!findChild(page(), "updatesEmpty").visible)
        backend.updates = {state:"idle", items:[], lastUpdated:"24/09/2026 12:39", lastChecked:"24/09/2026 13:00"}
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
        const button = findChild(page(), "installUpdatesButton")
        compare(button.text, "Update All Apps")
        compare(page().selected.length, 2); compare(page().selectedBytes, 400)
        compare(findChild(page(), "updatesDownloadSummary").text, "2 selected — Total size: 400 B")
        const alpha = findChild(page(), "selectUpdate-user:Alpha")
        mouseClick(alpha); compare(page().selected.length, 1); compare(page().selectedBytes, 300)
        compare(button.text, "Update selected apps")
        waitForPolish(page()); waitForRendering(button)
        mouseClick(button); compare(backend.submitted, ["user:Beta"])
        const all = findChild(page(), "selectAllUpdates")
        verify(all.contentItem.leftPadding >= all.indicator.width + 8)
        compare(all.checkState, Qt.PartiallyChecked)
        mouseClick(all); compare(page().selected.length, 2)
        compare(button.text, "Update All Apps")
        mouseClick(all); compare(page().selected.length, 0)
        compare(button.text, "Update selected apps")
        verify(!findChild(page(), "installUpdatesButton").enabled)
        mouseClick(all); mouseClick(findChild(page(), "installUpdatesButton"))
        compare(backend.submitted, ["user:Alpha", "user:Beta"])
        verify(!findChild(page(), "installUpdatesButton").activeFocus)
    }
    function test_single_update_all_label() {
        open()
        backend.updates = {state:"ready", items:[row("Alpha", "user")]}
        const button = findChild(page(), "installUpdatesButton")
        compare(button.text, "Update All Apps")
        backend.selectAllUpdates(false)
        compare(button.text, "Update selected apps"); verify(!button.enabled)
        backend.selectAllUpdates(true)
        compare(button.text, "Update All Apps"); verify(button.enabled)
    }
    function test_version_labels_data() {
        return [{tag:"refresh804", oldVersion:"8.0.4", newVersion:"8.0.4", text:"8.0.4 → 8.0.4 (Refresh)"},
            {tag:"refresh171", oldVersion:"1.7.1", newVersion:"1.7.1", text:"1.7.1 → 1.7.1 (Refresh)"},
            {tag:"new", oldVersion:"1.7.1", newVersion:"1.7.2", text:"1.7.1 → 1.7.2"},
            {tag:"revisions", oldVersion:"Revision abc123", newVersion:"Revision def456", text:"Revision abc123 → Revision def456"},
            {tag:"missing", oldVersion:"", newVersion:"", text:" → "}]
    }
    function test_version_labels(data) {
        open()
        backend.updates = {state:"ready", items:[Object.assign(row("Alpha", "user"), data)]}
        const list = findChild(page(), "updatesList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        compare(findChild(list.itemAtIndex(0), "updateVersion").text, data.text)
    }
    function test_permission_status_data() {
        return [{tag:"unchanged", state:"unchanged", runtime:false, visible:false, text:""},
            {tag:"changed", state:"changed", runtime:false, visible:true, text:"Permissions changed"},
            {tag:"unavailable", state:"unavailable", runtime:false, visible:true, text:"Permission comparison unavailable"},
            {tag:"runtime", state:"unavailable", runtime:true, visible:false, text:"Permission comparison unavailable"}]
    }
    function test_permission_status(data) {
        open()
        backend.updates = {state:"ready", items:[Object.assign(row("Alpha", "user"),
            {runtime:data.runtime, permissions:{state:data.state, groups:[]}})]}
        const list = findChild(page(), "updatesList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const label = findChild(list.itemAtIndex(0), "updatePermissionsStatus")
        compare(label.visible, data.visible); compare(label.text, data.text)
        const button = findChild(list.itemAtIndex(0), "viewUpdatePermissionChanges")
        compare(button.visible, data.state === "changed")
        if (button.visible) {
            waitForPolish(page()); waitForRendering(button); mouseClick(button)
            const dialog = findChild(page(), "appPermissionsDialog")
            tryCompare(dialog, "opened", true)
            dialog.close(); tryCompare(dialog, "visible", false)
        }
    }
    function test_queued_updates_have_status_only_data() {
        const cases = []
        for (const theme of [{tag:"dark", background:"#202326", foreground:"#ffffff"},
                             {tag:"light", background:"#eff0f1", foreground:"#202326"}])
            for (const progress of [0, 0.45]) cases.push(Object.assign({}, theme, {tag:theme.tag + progress, progress:progress}))
        return cases
    }
    function test_queued_updates_have_status_only(data) {
        const originalBackground = main.palette.window, originalForeground = main.palette.windowText
        main.palette.window = data.background; main.palette.windowText = data.foreground
        open(); ready()
        const list = findChild(page(), "updatesList")
        const card = list.itemAtIndex(0), other = list.itemAtIndex(1)
        const label = findChild(card, "updateJobStatus"), progress = findChild(card, "updateJobProgress")
        const bar = findChild(progress, "overallInstallProgress")
        const queued = {key:"user:Alpha", action:"update", active:true, queued:true, progress:data.progress, status:"Queued"}
        backend.jobs = [queued]
        verify(label.visible); compare(label.text, "Queued…"); verify(!progress.visible && !bar.visible)
        verify(label.font.bold); compare(label.color, main.textColor)
        verify(!findChild(other, "updateJobStatus").visible)
        backend.jobs = [Object.assign({}, queued, {queued:false, progress:0.5, status:"Updating…"})]
        verify(progress.visible); compare(bar.value, 0.5); compare(label.text, "Updating…")
        verify(!label.font.bold); compare(label.color, main.mutedTextColor)
        backend.jobs = [queued]
        verify(!progress.visible); compare(label.text, "Queued…")
        verify(label.font.bold); compare(label.color, main.textColor)
        backend.jobs = [Object.assign({}, queued, {cancelling:true, status:"Cancelling…"})]
        compare(label.text, "Cancelling…"); verify(!progress.visible)
        verify(!label.font.bold); compare(label.color, main.mutedTextColor)
        backend.jobs = [Object.assign({}, queued, {active:false, queued:false, failed:true, status:"Failed", error:"Connection lost"})]
        verify(!progress.visible); compare(label.text, "Failed\nConnection lost")
        verify(!label.font.bold); compare(label.color, main.accentColor)
        backend.jobs = [Object.assign({}, queued, {active:false, queued:false, status:"Complete"})]
        verify(!progress.visible); compare(label.text, "Complete")
        backend.jobs = []
        verify(!label.visible && !progress.visible)
        main.palette.window = originalBackground; main.palette.windowText = originalForeground
    }
    function test_shared_live_progress_data() { return test_layout_data() }
    function test_shared_live_progress(data) {
        main.width = data.width; main.height = data.height; open(); ready()
        const card = findChild(page(), "updatesList").itemAtIndex(0)
        const progress = findChild(card, "updateJobProgress")
        const bar = findChild(progress, "overallInstallProgress")
        const bytes = findChild(progress, "downloadBytesLabel")
        const percentage = findChild(progress, "overallPercentageLabel")
        const status = findChild(card, "updateJobStatus")
        const size = findChild(card, "updateDownloadSize")
        const job = {index:0, key:"user:Alpha", action:"update", active:true, queued:false,
            progress:0.5, hasDownload:true, downloadComplete:false, phase:"download",
            downloadedSize:"128.00 MiB", downloadTotalSize:"512.00 MiB", downloadSpeed:"2.30 MiB/s",
            status:"Dependency: shared\nDownloading…", operations:[{ref:"Alpha", commit:"a", downloadBytes:100}]}
        backend.jobs = [job]; waitForPolish(page()); wait(30)
        verify(progress.visible && bar.visible && !bar.indeterminate)
        compare(bar.value, 0.5); verify(!bar.activeStep)
        compare(bytes.text, "128.00 MiB / 512.00 MiB (2.30 MiB/s)"); verify(bytes.visible)
        compare(bytes.color, main.textColor); compare(percentage.text, "50%")
        verify(!status.visible, "Shared display replaces duplicate download status")
        compare(size.text, "Size: 512.00 MiB")
        verify(bytes.x + bytes.width <= percentage.x, "Bytes and percentage must not overlap")
        verify(bytes.contentWidth <= bytes.width + 1, "Bytes wrap in narrow cards")
        verify(bar.width > 0 && bar.width <= card.width)
        backend.jobs = [Object.assign({}, job, {phase:"install", progress:0.95, downloadComplete:true,
            downloadTotalSize:"256.00 MiB"})]
        verify(!bytes.visible); verify(bar.activeStep); compare(percentage.text, "95%")
        compare(size.text, "Size: 256.00 MiB")
        backend.jobs = [Object.assign({}, job, {hasDownload:false, downloadComplete:true,
            downloadTotalSize:"0 B", phase:"install"})]
        verify(!bytes.visible && bar.visible && bar.activeStep); compare(size.text, "Size: 0 B")
        backend.jobs = [Object.assign({}, job, {operations:[], status:"Preparing…"})]
        verify(bar.indeterminate); verify(!bytes.visible && !percentage.visible)
        verify(status.visible); compare(status.text, "Preparing…")
        backend.jobs = [job]; backend.review = {jobIndex:0}
        verify(status.visible, "Review status remains visible")
        backend.review = ({})
        verify(!status.visible)
        backend.jobs = [Object.assign({}, job, {cancelling:true, status:"Cancelling…"})]
        verify(status.visible); compare(status.text, "Cancelling…")
        backend.jobs = [Object.assign({}, job, {active:false, failed:true, status:"Failed", error:"Connection lost"})]
        verify(status.visible && !progress.visible); compare(status.text, "Failed\nConnection lost")
        backend.jobs = [Object.assign({}, job, {active:false, progress:1, status:"Complete"})]
        verify(!progress.visible); compare(status.text, "Complete")
    }
    function test_resolved_download_totals() {
        open(); ready()
        const summary = findChild(page(), "updatesDownloadSummary")
        const operations = [{ref:"Alpha", commit:"a", downloadBytes:100, receivedBytes:60, downloadProgress:1},
            {ref:"shared", commit:"b", downloadBytes:200, receivedBytes:0, downloadProgress:1}]
        backend.jobs = [{key:"user:Alpha", action:"update", active:true, operations:operations}]
        compare(page().selectedBytes, 160) // 60 actual + 100 for Beta; cached shared runtime is zero.
        compare(summary.text, "2 selected — Total size: 160 B")
        backend.jobs = [{key:"user:Alpha", action:"update", active:true, queued:true, operations:operations}]
        compare(page().selectedBytes, 400, "Queued values must not replace the plan")
        backend.jobs = [{key:"user:Alpha", action:"update", active:true, operations:
            [{ref:"Alpha", commit:"a", downloadBytes:100, receivedBytes:150, downloadProgress:0.9}]}]
        compare(page().selectedBytes, 450, "Received bytes may exceed the initial estimate")
        backend.jobs = [{key:"user:Alpha", action:"update", active:false, operations:
            [{ref:"shared", commit:"b", downloadBytes:200, receivedBytes:80, downloadProgress:1}]},
            {key:"user:Beta", action:"update", active:true, operations:
            [{ref:"shared", commit:"b", downloadBytes:200, receivedBytes:0, downloadProgress:1}]}]
        compare(page().selectedBytes, 280, "A later cache hit must not erase the shared bytes already received")
        backend.selectAllUpdates(false)
        compare(summary.text, "0 selected — Total size: 0 B")
    }
    function test_download_size_labels_data() {
        return [{tag:"zero", bytes:0, text:"0 B"}, {tag:"small", bytes:1024, text:"1.00 KiB"},
            {tag:"large", bytes:1170378588, text:"1.09 GiB"}]
    }
    function test_download_size_labels(data) {
        open()
        backend.updates = {state:"ready", items:[Object.assign(row("Alpha", "user"), {downloadBytes:data.bytes})]}
        const list = findChild(page(), "updatesList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        compare(findChild(list.itemAtIndex(0), "updateDownloadSize").text, "Size: " + data.text)
    }
    function test_old_jobs_do_not_supply_new_scan_totals() {
        open()
        const candidate = Object.assign(row("Alpha", "user"), {oldCommit:"old", commit:"new", downloadBytes:300})
        backend.updates = {state:"ready", items:[candidate]}
        const list = findChild(page(), "updatesList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const card = list.itemAtIndex(0)
        const oldJob = {key:candidate.key, action:"update", active:false, status:"Complete",
            oldCommit:"older", commit:"old", downloadTotalSize:"10 B", plan:candidate.plan,
            operations:[{ref:"Alpha", commit:"a", downloadBytes:100, receivedBytes:10, downloadProgress:1}]}
        backend.jobs = [oldJob]
        compare(page().selectedBytes, 300)
        verify(!findChild(card, "updateJobStatus").visible)
        compare(findChild(card, "updateDownloadSize").text, "Size: 300 B")
        backend.jobs = [Object.assign({}, oldJob, {oldCommit:"old", commit:"new",
            plan:[{ref:"Alpha", commit:"a"}, {ref:"shared", commit:"previous-runtime"}]})]
        compare(page().selectedBytes, 300, "Old dependency refresh must not supply current transfer totals")
        verify(!findChild(card, "updateJobStatus").visible)
        backend.jobs = [Object.assign({}, oldJob, {oldCommit:"old", commit:"new"})]
        compare(page().selectedBytes, 210)
        compare(findChild(card, "updateDownloadSize").text, "Size: 10 B")
    }
    function test_scopes_and_dates() {
        open(); ready()
        backend.updates = Object.assign({}, backend.updates, {items:[row("Alpha", "user"), row("Alpha", "system")]})
        compare(page().selectedBytes, 600)
        compare(findChild(page(), "updateDates").text,
            "Apps were last updated: 22/09/2026 11:00")
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
        backend.selectUpdate("user:Alpha", false)
        waitForPolish(page())
        const selectedButton = findChild(page(), "installUpdatesButton")
        compare(selectedButton.text, "Update selected apps")
        const selectedPoint = selectedButton.mapToItem(page(), 0, 0)
        verify(selectedPoint.x >= 0 && selectedPoint.x + selectedButton.width <= page().width,
               "Partial-selection label fits beside the sidebar")
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
