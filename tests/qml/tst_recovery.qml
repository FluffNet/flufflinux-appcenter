import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as App

TestCase {
    id: test
    name: "QueueRecovery"
    when: main.visible
    QtObject {
        id: mock
        property var jobs: []
        property var catalog: []
        property var review: ({})
        property var recovery: ({items: [], error: "", notice: 0})
        property bool busy: false
        property int reviewed: -1
        property int dismissed: 0
        property int retried: 0
        function reviewRecovery(index) { reviewed = index }
        function dismissRecovery() { dismissed++; recovery = ({items: [], error: "", notice: 0}) }
        function retryRecoveryIo() { retried++ }
        function refreshRecovery() {}
    }
    App.Main { id: main; backend: mock; visible: true }
    function dialog() { return findChild(main, "queueRecoveryDialog") }
    function init() {
        main.width = 1180; main.height = 760
        mock.reviewed = -1; mock.dismissed = 0; mock.retried = 0
    }
    function cleanup() {
        dialog().close()
        tryCompare(dialog(), "visible", false)
        mock.recovery = ({items: [], error: "", notice: 0})
        dialog().shownNotice = 0
    }
    function test_recovery_lists_completed_and_interrupted_without_replaying() {
        mock.recovery = ({notice: 1, items: [
            {name: "Completed app", action: "update", state: "completed"},
            {name: "Interrupted app", action: "install", state: "interrupted"},
            {name: "Removed app", action: "uninstall", state: "removed"}
        ], error: "", checking: false, saving: false})
        tryCompare(dialog(), "visible", true)
        compare(mock.reviewed, -1)
        compare(dialog().items.length, 3)
        mouseClick(findChild(dialog(), "dismissRecoveredJobsButton"))
        compare(mock.dismissed, 1)
        tryCompare(dialog(), "visible", false)
    }
    function test_save_failure_offers_retry_without_dismissing_records() {
        mock.recovery = ({notice: 1, items: [], error: "No space left. Queue paused.", checking: false, saving: false})
        tryCompare(dialog(), "visible", true)
        verify(!findChild(dialog(), "dismissRecoveredJobsButton").enabled)
        mouseClick(findChild(dialog(), "retryRecoveryIoButton"))
        compare(mock.retried, 1); compare(mock.reviewed, -1)
    }
    function test_notice_waits_until_window_reopened() {
        main.visible = false
        mock.recovery = ({notice: 1, items: [{name: "Example", action: "install", state: "interrupted"}], error: ""})
        verify(!dialog().visible)
        main.visible = true
        tryCompare(dialog(), "visible", true)
        dialog().close()
        tryCompare(dialog(), "visible", false)
        mock.recovery = Object.assign({}, mock.recovery, {saving: true})
        wait(30)
        verify(!dialog().visible)
    }
}
