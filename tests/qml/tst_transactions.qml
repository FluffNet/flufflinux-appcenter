import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Transactions"
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
        property string requested: ""
        property int acceptedToken: 0
        signal appOpened(var app)
        signal inputError(string message)
        function installApp(app) { requested = "install:" + app.id }
        function uninstallApp(app) { requested = "uninstall:" + app.id }
        function answerReview(token, accept) { acceptedToken = accept ? token : -token; review = ({}) }
        function cancelJob(index) { requested = "cancel:" + index }
    }
    AppCenter.Main { id: main; backend: backend; visible: true }
    function test_app_actions_review_progress_and_installed_refresh() {
        const app = {id: "org.example.Test", name: "Test", summary: "A test", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const install = findChild(page, "installAppButton")
        verify(install.visible)
        mouseClick(install)
        compare(backend.requested, "install:org.example.Test")
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.35,
                         status: "Downloading", operations: [{name: "org.example.Runtime", progress: 0.35}]}]
        verify(findChild(page, "appInstallProgress").visible)
        compare(findChild(page, "appInstallProgress").value, 0.35)
        verify(!install.visible)
        backend.review = {token: 7, title: "Review", kind: "transaction", message: "An app and a dependency",
                          operations: [], downloadSize: "10 MB"}
        const dialog = findChild(main, "transactionReview")
        tryCompare(dialog, "visible", true)
        mouseClick(dialog.standardButton(Dialog.Ok))
        compare(backend.acceptedToken, 7)
        tryCompare(dialog, "visible", false)
        wait(250) // Allow the modal dimmer's close transition to finish.
        backend.installedApps = [Object.assign({}, app, {installation: "user", installedSize: "20 MB", installedVersion: "1.2", installedBranch: "stable", installedArch: "x86_64"})]
        backend.jobs = [{id: app.id, index: 0, name: app.name, active: false, progress: 1, status: "Complete", operations: []}]
        verify(!install.visible)
        const uninstall = findChild(page, "uninstallAppButton")
        verify(uninstall.visible)
        waitForRendering(page)
        mouseClick(uninstall)
        compare(backend.requested, "uninstall:org.example.Test")
        backend.installedApps = []
        verify(install.visible)
        verify(!uninstall.visible)
        compare(main.detailsFor(app).installedSize, undefined)
    }
}
