// Real Flatpak install in the isolated installation prepared by the live test.
// No synthetic progress and no approval of unexpected trust/permission prompts.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760
    catalogStats: null
    property int stage: 0
    property bool fullscreenTest: false
    property bool batchTest: false
    property bool secondTransferLogged: false
    property var testApp: ({id: "org.flufflinux.BackgroundTest", name: "App Center Test App", remote: "background-test",
                            developer: "FluffNet LLC", summary: "Isolated background installation test"})
    Connections {
        target: main.backend
        function onInputError(message) { console.error("BACKGROUND_FAIL: " + message); Qt.exit(5) }
        function onJobsChanged() {
            // QML animation timers pause when every window is hidden. The
            // native manager signal still arrives, just like the tray tracker.
            if (main.stage !== 2) return
            const jobs = main.backend.jobs.filter(job => job.id.startsWith("org.flufflinux.BackgroundTest"))
            const failed = jobs.find(job => job.failed)
            if (failed) { console.error("BACKGROUND_FAIL: " + failed.error); Qt.exit(4); return }
            const second = jobs.find(job => job.active && job.receivedBytes > 0 && job.queuePosition === 2 && job.queueTotal === 5)
            if (second && !main.secondTransferLogged) {
                main.secondTransferLogged = true
                console.info("BACKGROUND_TRANSFER_2_OF_5: " + JSON.stringify(second))
            }
            if (!jobs.length || jobs.some(job => job.active)) return
            console.info("BACKGROUND_COMPLETE: " + JSON.stringify(jobs)); main.stage = 3
        }
    }
    Window {
        transientParent: null
        visible: main.fullscreenTest && main.stage >= 2
        visibility: main.fullscreenTest && main.stage >= 2 ? Window.FullScreen : Window.Hidden
        title: "App Center fullscreen suppression test"
        color: "#17191c"
        Text {
            anchors.centerIn: parent; color: "white"; font.pixelSize: 32
            horizontalAlignment: Text.AlignHCenter
            text: "Fullscreen test\n\nApp Center is closed.\nThe installation continues without a popup."
        }
    }
    Timer {
        interval: 200; repeat: true; running: true
        onTriggered: {
            if (main.backend.installedLoading) return
            if (main.stage === 0) {
                main.testApp = main.catalog.find(app => app.id.replace(/\.desktop$/, "") === "org.flufflinux.BackgroundTest") || main.testApp
                if (main.backend.installedApps.some(app => app.id === main.testApp.id)) {
                    console.error("BACKGROUND_FAIL: fixture already installed"); Qt.exit(2); return
                }
                const apps = main.batchTest ? main.catalog.filter(app => app.id.startsWith("org.flufflinux.BackgroundTest.Item"))
                    .sort((a, b) => a.id.localeCompare(b.id)) : [main.testApp]
                if (main.batchTest && apps.length !== 5) { console.error("BACKGROUND_FAIL: expected five apps"); Qt.exit(6); return }
                main.testApp = apps[0]
                apps.forEach(app => main.backend.installApp(app))
                main.showDownloads(); main.stage = 1
            }
            if (main.backend.review.token) {
                console.error("BACKGROUND_FAIL: unexpected confirmation"); Qt.exit(3); return
            }
            const job = main.backend.jobs.find(job => job.id === main.testApp.id)
            if (!job) return
            if (main.stage === 1 && job.receivedBytes > 0) {
                console.info("BACKGROUND_TRANSFER: " + JSON.stringify(job))
                main.close(); main.stage = 2
            }
        }
    }
}
