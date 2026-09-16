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
    function test_app_icons_in_downloads_data() {
        return [{tag: "downloading", active: true, failed: false},
                {tag: "completed", active: false, failed: false},
                {tag: "failed", active: false, failed: true}]
    }
    function test_app_icons_in_downloads(data) {
        const queue = main.downloadQueue
        const stack = findChild(main, "navigationStack")
        const artwork = Qt.resolvedUrl("../../assets/flufflinux-appcenter.svg").toString()
        queue.jobs = [Object.assign(job("Test App", 0.5, data.active, data.failed), {icon: artwork})]
        main.showDownloads()
        tryCompare(stack, "busy", false)
        const row = findChild(stack.currentItem, "downloadJobs").itemAt(0)
        const icon = findChild(row, "downloadAppIcon")
        const title = findChild(row, "downloadAppName")
        tryCompare(icon, "status", Image.Ready)
        compare(icon.source.toString(), main.iconSource(artwork))
        compare(icon.width, 56)
        compare(icon.height, 56)
        compare(icon.fillMode, Image.PreserveAspectFit)
        const iconPosition = icon.mapToItem(row, 0, 0)
        const titlePosition = title.mapToItem(row, 0, 0)
        verify(iconPosition.x + icon.width < titlePosition.x, "Icon must sit beside, not over, the title")
        verify(Math.abs(iconPosition.y + icon.height / 2 - titlePosition.y - title.height / 2) < 1)
        // Invalid local artwork gets a themed fallback, then a new source
        // recovers automatically rather than keeping the previous error.
        queue.jobs = [Object.assign(job("Missing", 0, data.active, data.failed), {icon: "file:///nonexistent/appcenter-test-icon.png"})]
        const missing = findChild(findChild(stack.currentItem, "downloadJobs").itemAt(0), "downloadAppIcon")
        tryCompare(missing, "loadFailed", true)
        compare(missing.source.toString(), main.iconSource("application-x-executable"))
        queue.jobs = [Object.assign(job("Recovered", 1, false, false), {icon: artwork})]
        tryCompare(findChild(findChild(stack.currentItem, "downloadJobs").itemAt(0), "downloadAppIcon"), "status", Image.Ready)
        main.goBack(); tryCompare(stack, "busy", false)
        queue.jobs = []
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
