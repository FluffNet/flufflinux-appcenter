// Production UI and real metadata. Desktop clients use the fixture's isolated
// socket. Local bundles are always declined; no app installation is approved.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760
    catalogStats: null
    catalogPreferences: null
    networkStatus: null
    property string previousState: ""
    property string captureName: ""
    property int captureDelay: 0
    property int homeCount: 0
    property bool capturing: false
    property bool snapshotReady: false
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    Connections {
        target: main.backend
        function onHomeRequested() {
            main.captureName = "home-fallback-" + (++main.homeCount)
            main.captureDelay = 4
            console.log("DESKTOP_HOME " + main.homeCount)
        }
        function onAppOpened(app) {
            main.captureName = "app-" + app.id
            main.captureDelay = 4
            console.log("DESKTOP_APP " + app.id)
        }
        function onInputError(message) { console.error("DESKTOP_ERROR " + message) }
        function onReviewChanged() {
            if (!main.backend.review.token) return
            console.log("DESKTOP_REVIEW " + JSON.stringify(main.backend.review))
            main.captureName = "local-bundle-confirmation"
            main.captureDelay = 4
        }
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (!stack || stack.busy || main.backend.installedLoading) return
            if (!main.snapshotReady) {
                stack.background = main.snapshotBackground.createObject(stack)
                main.snapshotReady = true
            }
            const install = probe.findChild(stack.currentItem, "installAppButton")
            const uninstall = probe.findChild(stack.currentItem, "uninstallAppButton")
            const state = JSON.stringify({depth:stack.depth, category:main.selectedCategory,
                search:main.searchText, app:main.selectedApp ? main.selectedApp.id : "",
                install:!!(install && install.visible), uninstall:!!(uninstall && uninstall.visible),
                busy:main.backend.busy, review:main.backend.review.kind || "",
                jobs:main.backend.jobs.map(job => ({active:job.active, failed:job.failed, id:job.id}))})
            if (state !== main.previousState) { main.previousState = state; console.log("DESKTOP_STATE " + state) }
            if (!main.captureName || main.capturing) return
            if (main.captureName.startsWith("app-") && main.backend.busy) return
            if (main.captureDelay-- > 0) return
            main.capturing = true
            const name = main.captureName
            main.captureName = ""
            const review = probe.findChild(main, "transactionReview")
            const item = main.backend.review.token ? review.contentItem.parent : stack
            if (!item.grabToImage(function(result) {
                const target = Qt.resolvedUrl("../../target/desktop-verification/" + name + ".png").toString().replace("file://", "")
                if (!result.saveToFile(target)) { console.error("DESKTOP_CAPTURE_FAILED " + target); Qt.exit(2); return }
                console.log("DESKTOP_CAPTURE " + name)
                main.capturing = false
                if (main.backend.review.token) main.backend.answerReview(main.backend.review.token, false)
            })) { console.error("DESKTOP_CAPTURE_FAILED " + name); Qt.exit(2) }
        }
    }
    Timer { interval: 240000; running: true; onTriggered: Qt.exit(3) }
}
