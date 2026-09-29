// Native KDE rendering of simulated states; never checks or updates real apps.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 900; visible: true
    backend: fixture
    property int stage: 0
    property bool capturing: false
    property string capturePrefix: "update-presentation-"
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function sample(id, name, version, next, date) {
        return {id:id, key:"user:" + id, name:name, developer:"UI test fixture", icon:"application-x-executable",
            summary:"Simulated app used for layout testing.", description:"No real app is updated by this preview.",
            category:"Utilities", license:"MIT", homepage:"https://example.org", screenshots:[],
            installation:"user", remote:"fixture", installedOrigin:"fixture", installedSize:"10 MiB",
            installedVersion:version, installedRef:"app/" + id + "/x86_64/stable", updatedDate:date,
            flatpakRef:"app/" + id + "/x86_64/stable", oldVersion:version, newVersion:next, selected:true,
            downloadBytes:1048576, permissions:{state:"unchanged", groups:[]},
            plan:[{ref:id, commit:"fixture", downloadBytes:1048576}]}
    }
    QtObject {
        id: fixture
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property bool busy: false
        property int iconRevision: 0
        property var updates: ({state:"idle", items:[]})
        function requestInstallInfo(app) {}
        function selectUpdate(key, selected) {
            updates = Object.assign({}, updates, {items:updates.items.map(row => Object.assign({}, row,
                {selected:row.key === key ? selected : row.selected}))})
        }
    }
    function check(value, message) {
        if (!value) { console.error("UPDATE_PRESENTATION_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    function capture(item, name, next) {
        main.capturing = true
        main.check(item.grabToImage(function(result) {
            main.check(result.saveToFile(Qt.resolvedUrl("../../target/" + main.capturePrefix + name + ".png").toString().replace("file://", "")), "Save screenshot")
            console.log("UPDATE_PRESENTATION_CAPTURE", name)
            main.stage = next; main.capturing = false
        }), "Capture accepted")
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (main.capturing) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            main.check(fluffBackend.updates.state === "idle", "Real update backend stays idle")
            const updatesPage = probe.findChild(stack.get(0), "updatesPage")
            const button = probe.findChild(updatesPage, "installUpdatesButton")
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                const refresh = main.sample("org.example.Refresh", "Refresh example", "1.7.1", "1.7.1", "")
                const release = main.sample("org.example.Release", "New release example", "1.0", "1.1", "24/09/2026 12:39")
                release.permissions = {state:"changed", groups:[{id:"network", title:"Network Access", icon:"network-wireless",
                    description:"Internet connections", added:["Network connections"], removed:[]}]}
                fixture.installedApps = [refresh, release]
                fixture.updates = {state:"ready", items:[refresh, release], lastUpdated:"24/09/2026 12:39"}
                main.showUpdates(); main.stage = 1
            } else if (main.stage === 1) {
                main.check(button.text === "Update All Apps", "All-selection label")
                for (const icon of [probe.findChild(stack.get(0), "updatesNavigationIcon"),
                        probe.findChild(button, "fluffButtonMonochromeIcon"),
                        probe.findChild(probe.findChild(updatesPage, "checkForUpdatesButton"), "fluffButtonMonochromeIcon")])
                    main.check(icon.visible && icon.isMask && icon.color === main.textColor, "Theme-aware update icons")
                const row = probe.findChild(updatesPage, "updateRow-user:org.example.Refresh")
                main.check(probe.findChild(row, "updateVersion").text === "1.7.1 → 1.7.1 (Refresh)", "Refresh suffix")
                main.check(!probe.findChild(row, "updatePermissionsStatus").visible, "Unchanged permissions hidden")
                main.capture(stack, "all", 2)
            } else if (main.stage === 2) {
                fixture.selectUpdate("user:org.example.Release", false); main.stage = 3
            } else if (main.stage === 3) {
                main.check(button.text === "Update selected apps", "Partial-selection label")
                main.capture(stack, "selected", 4)
            } else if (main.stage === 4) {
                fixture.busy = true
                fixture.jobs = [{key:"user:org.example.Refresh", id:"org.example.Refresh", action:"update",
                    name:"Refresh example", active:true, queued:true, status:"Queued", progress:0.4}]
                main.stage = 5
            } else if (main.stage === 5) {
                const row = probe.findChild(updatesPage, "updateRow-user:org.example.Refresh")
                main.check(probe.findChild(row, "updateJobStatus").text === "Queued…", "Queued status")
                main.check(probe.findChild(row, "updateJobStatus").font.bold
                    && probe.findChild(row, "updateJobStatus").color === main.textColor, "Bold theme-aware queued text")
                main.check(!probe.findChild(row, "updateJobProgress").visible, "No queued bar")
                main.check(!probe.findChild(stack.get(0), "queueButtonProgress").visible, "No queued-only toolbar bar")
                main.capture(stack, "queued", 6)
            } else if (main.stage === 6) {
                fixture.jobs = []; fixture.busy = false
                stack.get(0).openCategory("Installed"); main.stage = 7
            } else if (main.stage === 7) {
                const list = probe.findChild(stack.get(0), "installedList")
                let recorded = 0, missing = 0
                for (let i = 0; i < list.count; ++i) {
                    const row = list.itemAtIndex(i)
                    const date = probe.findChild(row, "installedUpdatedDateValue")
                    main.check(date.visible === !!row.app.updatedDate, "Installed dates only when recorded")
                    if (date.visible) recorded++; else missing++
                }
                main.check(recorded === 1 && missing === 1, "Both Installed history states")
                main.capture(stack, "installed", 8)
            } else if (main.stage === 8) {
                main.openApp(fixture.installedApps[1]); main.stage = 9
            } else if (main.stage === 9 || main.stage === 12) {
                const flick = probe.findChild(stack.currentItem, "detailsFlickable")
                flick.contentY = Math.max(0, flick.contentHeight - flick.height)
                main.stage++
            } else if (main.stage === 10 || main.stage === 13) {
                const detail = stack.currentItem
                const date = probe.findChild(detail, "appUpdatedDateValue")
                main.check(date.visible === (main.stage === 10), "Detail dates only when recorded")
                if (date.visible) {
                    const website = probe.findChild(detail, "appWebsiteLink")
                    main.check(date.mapToItem(detail, 0, 0).y >= website.mapToItem(detail, 0, website.height).y, "Date below Website")
                }
                main.capture(stack, main.stage === 10 ? "details-recorded" : "details-missing", main.stage + 1)
            } else if (main.stage === 11) {
                main.openApp(fixture.installedApps[0]); main.stage = 12
            } else if (main.stage === 14) {
                main.showCatalog(); main.showUpdates(); main.width = 720; main.height = 520; main.stage = 15
            } else if (main.stage === 15) {
                const point = button.mapToItem(updatesPage, 0, 0)
                main.check(point.x >= 0 && point.x + button.width <= updatesPage.width, "Small-window selection button fits")
                main.capture(stack, "compact", 16)
            } else if (main.stage === 16) {
                main.width = 1180; main.height = 900; fixture.busy = true
                const rows = fixture.updates.items.map((row, index) => Object.assign({}, row, {
                    selected:true, downloadBytes:(index ? 10 : 512) * 1048576,
                    permissions:{state:"unchanged", groups:[]},
                    plan:[{ref:row.id, commit:"fixture", downloadBytes:(index ? 10 : 512) * 1048576}]}))
                fixture.updates = Object.assign({}, fixture.updates, {items:rows})
                fixture.jobs = [{index:0, key:rows[0].key, id:rows[0].id, action:"update", name:rows[0].name,
                    active:true, queued:false, status:"Downloading…", phase:"download", progress:0.225,
                    hasDownload:true, downloadComplete:false, receivedBytes:134217728, downloadTotalBytes:536870912,
                    downloadedSize:"128.00 MiB", downloadTotalSize:"512.00 MiB", downloadSpeed:"2.30 MiB/s",
                    operations:[{ref:rows[0].id, commit:"fixture", downloadBytes:536870912,
                        receivedBytes:134217728, downloadProgress:0.25}]},
                    {index:1, key:rows[1].key, id:rows[1].id, action:"update", name:rows[1].name,
                        active:true, queued:true, status:"Queued", progress:0, operations:[]}]
                main.stage = 17
            } else if (main.stage === 17 || main.stage === 21) {
                const row = probe.findChild(updatesPage, "updateRow-user:org.example.Refresh")
                const progress = probe.findChild(row, "updateJobProgress")
                main.check(progress.visible, "Shared progress visible")
                main.check(probe.findChild(progress, "downloadBytesLabel").text === "128.00 MiB / 512.00 MiB (2.30 MiB/s)", "Live transfer metrics")
                main.check(probe.findChild(progress, "overallPercentageLabel").text === "22%", "Live percentage")
                main.check(!probe.findChild(row, "updateJobStatus").visible, "No redundant transfer status")
                main.check(probe.findChild(row, "updateDownloadSize").text === "Size: 512.00 MiB", "Resolved row size")
                main.check(probe.findChild(updatesPage, "updatesDownloadSummary").text === "2 selected - Total size: 522.00 MiB", "Resolved selection size")
                main.capture(stack, main.stage === 17 ? "downloading" : "downloading-compact", main.stage + 1)
            } else if (main.stage === 18) {
                fixture.jobs = [Object.assign({}, fixture.jobs[0], {phase:"install", progress:0.9, downloadComplete:true}), fixture.jobs[1]]
                main.stage = 19
            } else if (main.stage === 19) {
                const row = probe.findChild(updatesPage, "updateRow-user:org.example.Refresh")
                main.check(!probe.findChild(row, "downloadBytesLabel").visible, "Finished download metrics hidden")
                main.check(probe.findChild(row, "overallInstallProgress").activeStep, "Deployment activity shown")
                main.capture(stack, "installing", 20)
            } else if (main.stage === 20) {
                fixture.jobs = [Object.assign({}, fixture.jobs[0], {phase:"download", progress:0.225, downloadComplete:false}), fixture.jobs[1]]
                main.width = 720; main.height = 520; main.stage = 21
            } else if (main.stage === 22) { console.log("UPDATE_PRESENTATION_PASS"); Qt.quit() }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(3) }
}
