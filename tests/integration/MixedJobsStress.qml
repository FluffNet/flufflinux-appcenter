// Real updates/removals, scoped by the Python runner to temporary installations.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 900; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state:"online",ready:true})
    property int phase: 0
    property int reviewed: 0
    property int priorToken: 0
    property int overlapSamples: 0
    property int activeSamples: 0
    property int navigationCycles: 0
    property int ticks: 0
    property double lastBeat: 0
    property double longestPause: 0
    property var sizeTarget: null
    property int sizeSamplesDuringUpdates: 0
    TestCase { id: probe; when: false }
    function check(value,message) {
        if (!value) { console.error("MIXED_JOBS_FAIL",phase,message,JSON.stringify(backendJobs));Qt.exit(2);throw new Error(message) }
    }
    Connections {
        target: main.backend
        function onInputError(message) { main.check(false,message) }
    }
    Timer {
        interval:16;repeat:true;running:true
        onTriggered: {
            const now=Date.now()
            if (main.lastBeat) main.longestPause=Math.max(main.longestPause,now-main.lastBeat)
            main.lastBeat=now
            ++main.ticks
            const backend=main.backend
            const stack=probe.findChild(main,"navigationStack")
            if (main.phase===0) {
                if (main.catalogLoading || main.installedLoading || backend.busy) return
                main.check(main.installedApps.length===24,"24 isolated apps installed")
                main.showUpdates();backend.checkForUpdates();main.phase=1
            } else if (main.phase===1) {
                if (backend.updateStatus.state!=="ready" || backend.busy) return
                main.check(main.updateItems.length===13,"12 app updates plus one shared runtime")
                const sizeApp=main.findInstalled({id:"org.example.MixedRemove01"})
                main.sizeTarget={id:sizeApp.id,remote:sizeApp.installedOrigin,flatpakRef:sizeApp.installedRef}
                backend.requestInstallInfo(main.sizeTarget)
                backend.installSelectedUpdates()
                const cancelled=backend.jobs.find(j=>j.id==="org.example.MixedUpdate02")
                main.check(!!cancelled && cancelled.queued,"Cancellation target is still queued")
                backend.cancelJob(cancelled.index)
                const first=main.findInstalled({id:"org.example.MixedUpdate00"})
                backend.uninstallApp(first)
                main.check(!backend.jobs.some(j=>j.action==="uninstall" && j.id===first.id),
                    "Same app cannot update and uninstall concurrently")
                for (const app of main.installedApps.filter(a=>a.id.startsWith("org.example.MixedRemove")))
                    backend.uninstallApp(app)
                main.phase=2
            } else if (main.phase===2) {
                main.check(!backend.jobs.some(j=>j.failed),"No unexpected worker failures")
                const review=backend.review
                if (review && review.token) {
                    main.check(review.removing && review.appId.startsWith("org.example.MixedRemove"),"Only intended removal prompts")
                    if (main.priorToken) {
                        backend.answerReview(main.priorToken,true)
                        main.check(backend.review.token===review.token,"Stale approval cannot approve another app")
                    }
                    main.priorToken=review.token
                    const number=Number(review.appId.slice(-2))
                    backend.answerReview(review.token,number%4!==0)
                    ++main.reviewed
                }
                const updates=backend.jobs.filter(j=>j.action==="update" && j.active)
                const removals=backend.jobs.filter(j=>j.action==="uninstall" && j.active && !j.queued)
                if (updates.length && removals.length) ++main.overlapSamples
                if (updates.length) ++main.activeSamples
                if (!main.findInstalled(main.sizeTarget)) {
                    const size=backend.installSizes[main.sizeTarget.id]
                    main.check(!!size && (size.state==="loading" || size.state==="ready"),
                        "Concurrent removals never expose a false unavailable estimate")
                    if (updates.length && size.state==="ready") ++main.sizeSamplesDuringUpdates
                }
                if (!stack.busy && stack.depth===1) {
                    const page=probe.findChild(stack.get(0),"updatesPage")
                    for (const job of updates) {
                        const row=main.updateItems.find(r=>r.key===job.key)
                        main.check(!!row && !!page.jobFor(row),"Every live update stays on Updates during removals")
                    }
                    main.check(!probe.findChild(page,"updatesEmpty").visible || !page.updating,"No premature up-to-date label")
                }
                if (!stack.busy && main.ticks%15===0) {
                    if (stack.depth>1) main.showUpdates()
                    else main.showDownloads()
                    ++main.navigationCycles
                }
                if (!backend.busy && !main.installedLoading && !main.catalogLoading) {
                    main.check(main.reviewed===12,"Every removal received its own confirmation")
                    main.check(main.overlapSamples>0,"Update and removal lanes overlapped")
                    main.check(main.sizeSamplesDuringUpdates>0,"Reinstall sizes resolved while updates were active")
                    main.check(main.longestPause<1000,"No one-second GUI event-loop stall")
                    main.showUpdates();main.phase=3
                }
            } else if (main.phase===3 && !stack.busy) {
                // Only the explicitly cancelled app should still need an update.
                backend.checkForUpdates();main.phase=4
            } else if (main.phase===4) {
                if (backend.updateStatus.state!=="ready" || backend.busy) return
                main.check(main.updateItems.length===1 && main.updateItems[0].id==="org.example.MixedUpdate02",
                    "Only the cancelled update remains")
                console.log("MIXED_JOBS_PASS",JSON.stringify({locale:Qt.locale().name,rtl:main.rtl,
                    reviews:main.reviewed,overlapSamples:main.overlapSamples,updateSamples:main.activeSamples,
                    navigationCycles:main.navigationCycles,longestPauseMs:main.longestPause,
                    sizeSamplesDuringUpdates:main.sizeSamplesDuringUpdates}))
                Qt.quit()
            }
        }
    }
    Timer { interval:180000;running:true;onTriggered:main.check(false,"Mixed jobs timed out") }
}
