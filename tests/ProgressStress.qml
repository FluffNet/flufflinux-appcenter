// Real Rust manager/Qt transport and page controls with isolated package workers.
// APPCENTER_PROFILE_PROGRESS_STRESS=1, APPCENTER_PROFILE_ITEMS=200.
import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as App

App.Main {
    id: main
    width:1180; height:800; visible:true
    catalogPreferences:null; catalogStats:null
    networkStatus:({state:"online",ready:true})
    property int phase:0
    property int ticks:0
    property int byteChecks:0
    property int deploymentChecks:0
    property int barChecks:0
    property int handoffs:0
    property int completed:0
    property real lastQueueProgress:0
    property var downloadSeen:({})
    property var installSeen:({})
    TestCase { id: probe; when:false }
    function check(value,message) {
        if (!value) { console.error("PROGRESS_STRESS_FAIL",message); Qt.exit(2); throw new Error(message) }
    }
    function validateBars(item) {
        if (!item || !item.visible) return
        if (item.objectName==="overallInstallProgress") {
            main.check(item.mirrored===main.rtl,"Page progress follows locale direction")
            main.check(probe.findChild(item,"progressActivity")===null,"No secondary animated fragment")
            const fill=probe.findChild(item,"progressFill")
            if (!item.indeterminate) {
                main.check(fill.x===0,"Determinate offset reset")
                main.check(Math.abs(fill.width-item.width*item.position)<0.01,"Fill agrees with value")
            }
            const percentage=probe.findChild(item.parent,"overallPercentageLabel")
            if (item.indeterminate && percentage) main.check(!percentage.visible,"Deployment has no invented numeric percentage")
            main.barChecks++
        }
        for (const child of item.children || []) validateBars(child)
    }
    Timer {
        interval:16; repeat:true; running:true
        onTriggered: {
            const stack=probe.findChild(main,"navigationStack")
            main.ticks++
            if (main.phase===0) {
                if (main.catalogLoading || main.installedLoading || main.backend.busy || !main.catalog.length) return
                main.showUpdates();main.backend.checkForUpdates();main.phase=1
            } else if (main.phase===1) {
                if (main.backend.updateStatus.state!=="ready" || main.backend.busy) return
                main.check(main.updateItems.length===200,"200 planned updates")
                main.backend.installSelectedUpdates();main.phase=2
            } else if (main.phase===2) {
                if (stack.depth===1) {
                    const page=probe.findChild(stack.get(0),"updatesPage")
                    for (const job of main.backendJobs) {
                        if (job.action!=="update" || !job.active || job.cancelled) continue
                        const row=main.updateItems.find(item=>item.key===job.key)
                        main.check(!!row,"Every active/queued runtime and app keeps its Updates row")
                        main.check(!!page.jobFor(row),"Updates remains attached after dependency re-resolution")
                    }
                    main.check(!probe.findChild(page,"updatesEmpty").visible || !page.updating,
                        "No up-to-date message during active updates")
                }
                for (const job of main.backendJobs) {
                    if (!job.active || job.queued || !(job.operations || []).length) continue
                    if (job.phase==="download" && job.downloadTotalBytes>0) {
                        const fraction=job.receivedBytes/job.downloadTotalBytes
                        main.check(job.progressPercent===Math.floor(fraction*100+0.000001),"Percentage matches byte counter: "+job.id)
                        main.check(Math.abs(job.progress-fraction)<1e-9,"Progress uses bytes, not Flatpak's simulated 99%")
                        main.check(!job.progressIndeterminate,"Downloads determinate")
                        main.byteChecks++;main.downloadSeen[job.id]=true
                    } else if (job.phase==="install") {
                        main.check(job.progressIndeterminate,"Deployment indeterminate")
                        main.deploymentChecks++;main.installSeen[job.id]=true
                    }
                }
                const finished=main.backendJobs.filter(job=>!job.active && !job.failed).length
                if (finished>main.completed) {main.handoffs+=finished-main.completed;main.completed=finished}
                const overall=main.downloadQueue.progress
                main.check(overall+1e-9>=main.lastQueueProgress,"Batch completion never resets the toolbar")
                main.lastQueueProgress=overall
                if (!stack.busy) {
                    main.validateBars(stack.currentItem)
                    const toolbar=probe.findChild(stack.get(0),"queueButtonProgress")
                    if (toolbar && toolbar.visible && toolbar.children.length) {
                        const fill=toolbar.children[0]
                        const start=fill.mapToItem(toolbar,0,0).x
                        main.check(Math.abs(start-(main.rtl ? toolbar.width-fill.width : 0))<0.01,"Queue toolbar fills from the leading edge")
                    }
                    // Repeated navigation and real Kirigami wheel input while
                    // progress rows are changing and items leave Updates.
                    if (main.ticks%45===0) {
                        if (stack.depth>1) main.showUpdates()
                        else main.showDownloads()
                    }
                    const view=probe.findChild(stack.currentItem,"downloadJobs") || probe.findChild(stack.currentItem,"updatesList")
                    if (view && view.visible && main.ticks%8===0)
                        probe.mouseWheel(view,view.width/2,view.height/2,0,main.ticks%160<80 ? -120 : 120,Qt.NoButton,Qt.NoModifier,0)
                }
                if (!main.backend.busy && !stack.busy) {
                    main.check(main.backendJobs.length===200 && main.backendJobs.every(job=>!job.active && !job.failed),"All 200 completed")
                    main.check(main.byteChecks>200 && main.deploymentChecks>100 && main.barChecks>100,"Both phases and rendered bars sampled")
                    main.check(main.handoffs===200 && main.downloadQueue.progress===1,"All completion handoffs accounted")
                    console.log("PROGRESS_STRESS_PASS",JSON.stringify({byteChecks:main.byteChecks,deploymentChecks:main.deploymentChecks,
                        rtl:main.rtl,renderedBarChecks:main.barChecks,handoffs:main.handoffs,downloadJobs:Object.keys(main.downloadSeen).length,
                        installationJobs:Object.keys(main.installSeen).length}))
                    main.phase=3;Qt.quit()
                }
            }
        }
    }
    Timer { interval:240000; running:true; onTriggered: {console.error("PROGRESS_STRESS_TIMEOUT",main.phase);Qt.exit(3)} }
}
