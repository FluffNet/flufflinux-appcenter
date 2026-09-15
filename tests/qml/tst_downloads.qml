import QtQuick
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Downloads"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    function test_queue_navigation_and_completion() {
        const queue = main.downloadQueue
        const stack = findChild(main, "navigationStack")
        const catalog = stack.currentItem
        const button = findChild(catalog, "downloadsButton")
        compare(button.visible, false)
        queue.startDemo()
        queue.ticker.stop()
        compare(queue.activeCount, 3)
        compare(button.visible, true)
        mouseClick(button)
        tryCompare(stack, "busy", false)
        compare(stack.currentItem.objectName, "downloadsPage")
        queue.updateDemo(70)
        compare(queue.activeCount, 2)
        verify(queue.progress > 0.5 && queue.progress < 1)
        main.goBack()
        tryCompare(stack, "busy", false)
        compare(stack.currentItem, catalog)
        queue.updateDemo(120)
        compare(queue.activeCount, 0)
        compare(queue.progress, 1)
        compare(button.visible, false)
    }
}
