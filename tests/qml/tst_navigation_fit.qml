import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "NavigationFit"
    when: main.visible
    AppCenter.Main { id: main; minimumWidth: 1; minimumHeight: 1 }
    function test_all_destinations_fit_data() {
        return [{tag:"large", width:1920, height:1080}, {tag:"usual", width:1180, height:760},
                {tag:"720p", width:1280, height:720}, {tag:"minimum", width:720, height:520},
                {tag:"small-scaled-screen", width:640, height:360}, {tag:"very-short", width:540, height:300}]
    }
    function test_all_destinations_fit(data) {
        main.width = data.width; main.height = data.height
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const sidebar = findChild(page, "categorySidebar")
        const list = findChild(page, "categoryList")
        const installed = findChild(page, "installedButton")
        waitForPolish(main.contentItem); waitForRendering(sidebar)
        const brand = findChild(page, "brandLockup")
        compare(brand.x, 16)
        fuzzyCompare(brand.y + brand.height / 2, brand.parent.height / 2, 0.01)
        verify(brand.x + brand.width <= brand.parent.width)
        compare(list.count, 12); verify(!list.interactive)
        compare(list.contentY, 0)
        verify(list.contentHeight <= list.height + 0.5)
        verify(sidebar.navigationFontSize > 0)
        let bottom = installed.mapToItem(sidebar, 0, installed.height).y
        for (let i = 0; i < list.count; ++i) {
            tryVerify(function() { return list.itemAtIndex(i) !== null })
            const button = list.itemAtIndex(i)
            const top = button.mapToItem(sidebar, 0, 0).y
            verify(top >= bottom - 0.5, "No overlapping navigation targets")
            bottom = button.mapToItem(sidebar, 0, button.height).y
            verify(bottom <= sidebar.height - sidebar.bottomPadding + 0.5, "Every destination must fit without scrolling")
            const label = findChild(button, "categoryLabel")
            verify(!label.truncated)
            verify(label.contentWidth <= label.width + 0.5)
            verify(label.contentHeight <= button.height + 0.5)
            mouseClick(button)
            compare(main.selectedCategory, page.categories[i].name)
        }
        mouseClick(installed); compare(main.selectedCategory, "Installed")
        page.openCategory("All Apps")
    }
    function test_resize_from_tall_to_short_does_not_keep_scroll_offset() {
        main.width = 1180; main.height = 1000
        const page = findChild(main, "navigationStack").currentItem
        const list = findChild(page, "categoryList")
        waitForPolish(main.contentItem)
        list.positionViewAtIndex(11, ListView.End)
        main.height = 360; waitForPolish(main.contentItem)
        compare(list.contentY, 0)
        verify(list.contentHeight <= list.height + 0.5)
    }
}
