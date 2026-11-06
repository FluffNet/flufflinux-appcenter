// Real isolated Flatpak transactions in one uninterrupted GUI session.
import QtQuick
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    catalogPreferences: null
    catalogStats: null
    property int step: 0
    property int cycles: 0
    property var first: null
    property var second: null
    property var before: ({})
    TestCase { id: probe; when: false }
    function fail(message) {
        console.error("SIZE_LIFECYCLE_FAIL",step,message,JSON.stringify(backend.installSizes))
        Qt.exit(2)
    }
    function checkSizes(app) {
        const size=backend.installSizes[app.id]
        if (!size || size.state === "loading") return false
        if (size.state !== "ready" || !size.appSize || !size.totalSize) {
            fail("Expected complete sizes for "+app.id+": "+JSON.stringify(size)); return false
        }
        const page=probe.findChild(main,"navigationStack").currentItem
        if (probe.findChild(page,"appDownloadSize").text !== size.appSize) {
            fail("App size label did not update"); return false
        }
        if (probe.findChild(page,"totalDownloadSize").text !== size.totalSize) {
            fail("Dependency size label did not update"); return false
        }
        console.log("SIZE_LIFECYCLE_SIZE",cycles,app.id,JSON.stringify(size))
        if (cycles === 0) {
            const phase=step === 1 ? "before" : step === 4 ? "after-remove" : step === 5 ? "other-app-after-remove" : "other-app-before"
            probe.grabImage(main.contentItem).save(Qt.resolvedUrl("../../target/size-lifecycle-"
                +Qt.locale().name+"-"+phase+".png").toString().replace("file://",""))
        }
        return true
    }
    Connections {
        target: main.backend
        function onInputError(message) { main.fail(message) }
    }
    Timer {
        interval:100; running:true; repeat:true
        onTriggered: {
            const backend=main.backend
            if (backend.jobs.some(j=>j.failed)) { main.fail(JSON.stringify(backend.jobs));return }
            if (backend.review && backend.review.token) {
                if (!backend.review.removing) { main.fail("Unexpected non-removal review");return }
                backend.answerReview(backend.review.token,true)
            }
            const stack=probe.findChild(main,"navigationStack")
            if (stack.busy || backend.catalogLoading || backend.installedLoading || backend.sourcesBusy) return
            switch(main.step) {
            case 0:
                main.first=main.catalog.find(a=>a.id === "org.example.SizeCycle.App1")
                main.second=main.catalog.find(a=>a.id === "org.example.SizeCycle.App2")
                if (!main.first || !main.second) return
                main.openApp(main.first);main.step=1;break
            case 1:
                if (!main.checkSizes(main.first)) return
                main.before=backend.installSizes[main.first.id]
                if (main.cycles === 0 && main.before.totalBytes <= main.before.appBytes) {
                    main.fail("Initial estimate must include the uninstalled runtime");return
                }
                main.openApp(main.second);main.step=2;break
            case 2:
                if (!main.checkSizes(main.second)) return
                main.openApp(main.first);backend.installApp(main.first);main.step=3;break
            case 3:
                if (backend.busy || !main.findInstalled(main.first)) return
                backend.uninstallApp(main.findInstalled(main.first));main.step=4;break
            case 4:
                if (backend.busy || main.findInstalled(main.first)) return
                // Do not reopen or replace the app page before checking it.
                if (!main.checkSizes(main.first)) return
                if (backend.installSizes[main.first.id].totalBytes !== main.before.appBytes) {
                    main.fail("Reinstall estimate must exclude the runtime left installed");return
                }
                main.openApp(main.second);main.step=5;break
            case 5:
                if (!main.checkSizes(main.second)) return
                if (++main.cycles < 3) { main.openApp(main.first);main.step=1;break }
                console.log("SIZE_LIFECYCLE_PASS",main.cycles,"install/remove cycles, both app pages, one process")
                Qt.quit();break
            }
        }
    }
    Timer { interval:120000;running:true;onTriggered:main.fail("Timed out") }
}
