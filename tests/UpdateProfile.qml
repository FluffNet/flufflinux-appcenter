// Real backend and Update All button; only the external package workers are fake.
import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as App
App.Main {
    id: main
    width: 1180; height: 800; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state: "online", ready: true})
    property int phase: 0
    property double phaseStart: 0
    property double lastBeat: 0
    property double worst: 0
    property int ticks: 0
    property int cycles: 1
    property int expectedJobs: 200
    property int historyMs: 30000
    property int idleMs: 30000
    property bool wheelOnly: false
    property var navigation: null
    property var scrollView: null
    property int completedCycles: 0
    property var delays: []
    property var phaseDelays: ({})
    property var cycleDelays: ({})
    property var frameDelays: ({})
    property double lastFrame: 0
    property int lastFramePhase: 0
    property string lastAction: "startup"
    onFrameSwapped: {
        const now = Date.now()
        if (lastFrame && lastFramePhase === phase && phase >= 2 && phase <= 4) {
            if (!frameDelays[phase]) frameDelays[phase] = []
            frameDelays[phase].push(now - lastFrame)
        }
        lastFrame = now
        lastFramePhase = phase
    }
    function timingSummary(values) {
        values.sort((a,b)=>a-b)
        return {worstMs:values[values.length-1], p99Ms:values[Math.floor(values.length*0.99)], samples:values.length}
    }
    TestCase { id: probe; when: false }
    Timer {
        interval: 600000; running: true
        onTriggered: { console.error("PROFILE_TIMEOUT", main.phase); Qt.exit(1) }
    }
    function stack() {
        if (!navigation) navigation = probe.findChild(main, "navigationStack")
        return navigation
    }
    Timer {
        id: heartbeat
        interval: 16; repeat: true; running: true
        onTriggered: {
            const now = Date.now()
            if (main.lastBeat && main.phase > 1) {
                const gap = now - main.lastBeat
                main.worst = Math.max(main.worst, gap)
                main.delays.push(gap)
                if (!main.phaseDelays[main.phase]) main.phaseDelays[main.phase] = []
                main.phaseDelays[main.phase].push(gap)
                if (!main.cycleDelays[main.phase]) main.cycleDelays[main.phase] = []
                main.cycleDelays[main.phase].push(gap)
                if (gap >= 50) console.log("PROFILE_GAP", main.phase, gap, main.lastAction)
            }
            main.lastBeat = now
            ++main.ticks
            if (main.ticks % 600 === 0 && main.phase === 0)
                console.log("PROFILE_STARTUP_WAIT", main.catalogLoading, main.catalog.length,
                    main.installedLoading, main.backend.busy, main.installedError)
            if (main.phase === 0 && !main.catalogLoading && !main.installedLoading && !main.backend.busy && main.catalog.length) {
                console.log("PROFILE_CHECK", main.catalog.length)
                main.showUpdates(); main.backend.checkForUpdates(); main.phase = 1
            } else if (main.phase === 1 && main.backend.updateStatus.state === "ready" && !main.backend.busy) {
                const button = probe.findChild(stack().currentItem, "installUpdatesButton")
                if (!button || !button.enabled || main.updateItems.length !== main.expectedJobs) { console.error("PROFILE_SETUP_FAILED"); Qt.exit(1); return }
                probe.waitForPolish(stack().currentItem)
                const start = Date.now()
                console.log("PROFILE_BEFORE_UPDATE_ALL")
                probe.mouseClick(button, button.width/2, button.height/2, Qt.LeftButton, Qt.NoModifier, 0)
                console.log("PROFILE_UPDATE_ALL_MS", Date.now()-start)
                if (!main.backend.busy && !main.backendJobs.length) { console.error("PROFILE_CLICK_FAILED"); Qt.exit(1); return }
                main.phase = 2; main.phaseStart = Date.now()
                main.scrollView = probe.findChild(stack().currentItem, "updatesList")
            } else if (main.phase === 2 && now - main.phaseStart > 5000) {
                main.showDownloads(); main.phase = 3
                main.scrollView = probe.findChild(stack().currentItem, "downloadJobs")
                console.log("PROFILE_QUEUE_SCROLL")
            } else if (main.phase === 3 && !main.backend.busy) {
                console.log("PROFILE_COMPLETED", main.backendJobs.length)
                if (main.backendJobs.length !== main.expectedJobs || main.backendJobs.some(j => j.active || j.failed)) { Qt.exit(1); return }
                main.phase = 4; main.phaseStart = now
            } else if (main.phase === 4 && now - main.phaseStart > main.historyMs) {
                console.log("PROFILE_IDLE_HISTORY_RETAINED")
                main.backend.clearDownloadHistory()
                main.scrollView = null
                main.showHome(); main.phase = 5; main.phaseStart = now
            } else if (main.phase === 5 && now - main.phaseStart > main.idleMs) {
                const cycle = {}
                for (const key of Object.keys(main.cycleDelays)) cycle[key] = main.timingSummary(main.cycleDelays[key])
                console.log("PROFILE_CYCLE_RESULT", main.completedCycles + 1, JSON.stringify(cycle))
                main.cycleDelays = {}
                if (++main.completedCycles < main.cycles) { main.phase = 0; return }
                const phases = {}
                for (const key of Object.keys(main.phaseDelays)) phases[key] = main.timingSummary(main.phaseDelays[key])
                console.log("PROFILE_RESULT", JSON.stringify({cycles:main.completedCycles, total:main.timingSummary(main.delays), phases:phases}))
                const frames = {}
                for (const key of Object.keys(main.frameDelays)) frames[key] = main.timingSummary(main.frameDelays[key])
                console.log("PROFILE_FRAMES", JSON.stringify(frames))
                heartbeat.stop()
                Qt.quit()
                return
            }
            const view = main.scrollView
            main.lastAction = "idle"
            if (view && view.visible && main.phase >= 2 && main.phase <= 4) {
                const started = Date.now()
                const bottom = Math.max(view.originY, view.originY + view.contentHeight-view.height)
                const y = view.contentY + (main.ticks % 120 < 60 ? 80 : -80)
                if (!main.wheelOnly) {
                    view.contentY = Math.max(view.originY, Math.min(bottom, y))
                    main.lastAction = "contentY"
                }
                if (main.wheelOnly ? main.ticks % 4 === 0 : main.ticks % 90 === 0) {
                    const delta = main.wheelOnly ? (main.ticks % 240 < 120 ? -120 : 120)
                        : (main.ticks % 180 ? 120 : -120)
                    probe.mouseWheel(view, view.width/2, view.height/2, 0, delta, Qt.NoButton, Qt.NoModifier, 0)
                    main.lastAction = "test-wheel"
                }
                if (Date.now() - started >= 15) console.log("PROFILE_SCROLL_COST", main.phase, Date.now() - started, main.lastAction)
            }
        }
    }
}
