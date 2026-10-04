import QtQuick
import QtQuick.Controls
import QtTest
import "../../../qml" as AppCenter

TestCase {
    name: "NativeKirigamiPages"
    when: window.visible
    ApplicationWindow {
        id: window
        visible: true
        width: 600
        height: 500
        Flickable {
            id: page
            anchors.fill: parent
            contentWidth: 1800
            contentHeight: 3000
            boundsBehavior: Flickable.StopAtBounds
            AppCenter.PageWheelScroll { id: wheel; scrollTarget: page }
            Rectangle { width: 1800; height: 3000; color: "#303030" }
            ScrollBar.vertical: ScrollBar {}
            ScrollBar.horizontal: ScrollBar {}
        }
    }
    function init() {
        window.requestActivate()
        tryCompare(window, "active", true)
        wheel.enabled = false
        page.cancelFlick()
        page.contentX = 100
        page.contentY = 100
        wheel.enabled = true
        waitForRendering(page)
    }
    function test_touchpad_pixels_keep_both_axes_and_stop_at_bounds() {
        nativeInput.scroll(page, 250, 200, -30, -45)
        tryVerify(() => page.contentX > 100 && page.contentY > 100)
        wait(300)
        verify(page.contentX < 200 && page.contentY < 250)
        nativeInput.scroll(page, 250, 200, 3000, 3000)
        tryCompare(page, "contentX", 0)
        tryCompare(page, "contentY", 0)
        nativeInput.scroll(page, 250, 200, -6000, -6000)
        tryCompare(page, "contentX", page.contentWidth - page.width)
        tryCompare(page, "contentY", page.contentHeight - page.height)
    }
    function test_touchscreen_still_drags_and_flicks() {
        const gesture = touchEvent(page)
        gesture.press(0, page, 280, 390).commit()
        for (let step = 1; step <= 8; ++step) {
            gesture.move(0, page, 280, 390 - step * 25).commit()
            wait(20)
        }
        gesture.release(0, page, 280, 190).commit()
        verify(page.contentY > 180, "Kirigami must not replace native touch dragging")
        page.cancelFlick()
        verify(page.interactive)
    }
    function test_middle_scroll_hands_back_to_touchpad() {
        mouseClick(page, 250, 200, Qt.MiddleButton)
        verify(wheel.middleMouseScroll.scrolling)
        nativeInput.scroll(page, 250, 200, 0, -45)
        tryVerify(() => !wheel.middleMouseScroll.scrolling)
        tryVerify(() => page.contentY > 100)
    }
}
