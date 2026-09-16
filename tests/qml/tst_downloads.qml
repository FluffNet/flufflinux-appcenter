import QtQuick
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Downloads"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    function job(name, progress, active, failed) {
        return {name: name, progress: progress, active: active, failed: failed,
                status: active ? "Installing" : failed ? "Failed" : "Complete", operations: []}
    }
    function test_queue_navigation_and_completion() {
        const queue = main.downloadQueue
        const stack = findChild(main, "navigationStack")
        const catalog = stack.currentItem
        const button = findChild(catalog, "downloadsButton")
        compare(button.visible, false)
        queue.jobs = [job("Firefox", 0, true, false), job("VLC", 0, true, false)]
        compare(queue.activeCount, 2)
        compare(button.visible, true)
        mouseClick(button)
        tryCompare(stack, "busy", false)
        compare(stack.currentItem.objectName, "downloadsPage")
        queue.jobs = [job("Firefox", 1, false, false), job("VLC", 0.6, true, false)]
        compare(queue.activeCount, 1)
        compare(queue.progress, 0.6)
        main.goBack()
        tryCompare(stack, "busy", false)
        compare(stack.currentItem, catalog)
        queue.jobs = [job("Firefox", 1, false, false), job("VLC", 1, false, false)]
        compare(queue.activeCount, 0)
        compare(queue.progress, 1)
        compare(button.visible, true)
        main.showDownloads()
        tryCompare(stack, "busy", false)
        main.goBack()
        tryCompare(stack, "busy", false)
        compare(button.visible, true)
        compare(button.unreadResult, false)
        compare(queue.jobs.length, 2)
        compare(button.text, "Downloads")
        queue.jobs = [job("VLC", 0.3, false, true)]
        compare(queue.hasError, true)
        compare(queue.activeCount, 0)
        compare(button.visible, true)
    }
}
