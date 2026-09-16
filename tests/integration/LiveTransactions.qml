// Destructive live-UI test launcher for the disposable VM only.
// FLUFF_APP_CENTER_QML=/absolute/path/to/this/file flufflinux-appcenter
// Refuses an already-installed Calculator. Uses real backend signals, never
// synthetic progress. Leave time at each stage for visual screenshot checks.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    property int testStage: 0
    property var testApp: null
    function fail(message) { console.error("LIVE_TEST_FAIL: " + message); testStage = -1; poll.stop() }
    Timer {
        id: poll
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (main.installedLoading || !main.backend) return
            if (main.testStage === 0) {
                main.testApp = main.catalog.find(function(app) { return app.id.replace(/\.desktop$/, "") === "org.gnome.Calculator" })
                if (!main.testApp || main.findInstalled(main.testApp)) { main.fail("Calculator missing from catalog or already installed"); return }
                main.openApp(main.testApp)
                main.installApp(main.testApp)
                main.testStage = 1
            } else if (main.testStage === 1 && main.backend.review.token) {
                console.info("LIVE_TEST_REVIEW")
                pause.action = "install"; pause.restart(); main.testStage = 2
            } else if (main.testStage === 3 && !main.backend.busy) {
                if (!main.findInstalled(main.testApp)) { main.fail("Installed metadata did not refresh"); return }
                if (main.findInstalled(main.testApp).installation !== "user") { main.fail("App was not installed for the current user"); return }
                console.info("LIVE_TEST_APP_INSTALLED")
                pause.action = "downloads"; pause.restart(); main.testStage = 4
            } else if (main.testStage === 3 && main.backend.review.token) {
                // First-run source trust and dependency review are separate.
                console.info("LIVE_TEST_REVIEW")
                pause.action = "install"; pause.restart(); main.testStage = 2
            } else if (main.testStage === 6 && main.backend.review.token) {
                console.info("LIVE_TEST_UNINSTALL_REVIEW")
                pause.action = "uninstall"; pause.restart(); main.testStage = 7
            } else if (main.testStage === 8 && !main.backend.busy) {
                if (main.findInstalled(main.testApp)) { main.fail("Uninstalled app still listed"); return }
                if (main.downloadQueue.hasError) { main.fail("The queue reports a failure"); return }
                main.showDownloads()
                console.info("LIVE_TEST_PASS: install, refreshed app actions, dependency history, installed list, uninstall and metadata refresh")
                main.testStage = 9; poll.stop()
            }
        }
    }
    Timer {
        id: pause
        interval: 30000
        property string action: ""
        onTriggered: {
            if (action === "install") {
                main.backend.answerReview(main.backend.review.token, true)
                main.testStage = 3
            } else if (action === "downloads") {
                main.showDownloads(); console.info("LIVE_TEST_DOWNLOADS")
                action = "installed"; restart()
            } else if (action === "installed") {
                main.showCatalog(); main.selectedCategory = "Installed"
                console.info("LIVE_TEST_INSTALLED_LIST")
                action = "remove"; restart()
            } else if (action === "remove") {
                const app = main.findInstalled(main.testApp)
                main.openApp(app); main.uninstallApp(app); main.testStage = 6
            } else if (action === "uninstall") {
                main.backend.answerReview(main.backend.review.token, true)
                main.testStage = 8
            }
        }
    }
}
