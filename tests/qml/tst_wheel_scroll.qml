import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "KirigamiPageScroll"
    when: window.visible

    ApplicationWindow {
        id: window
        width: 500
        height: 400
        visible: true

        Flickable {
            id: scrollView
            anchors.fill: parent
            contentWidth: 2000
            contentHeight: 2000
            boundsBehavior: Flickable.StopAtBounds

            AppCenter.PageWheelScroll {
                id: naturalWheel
                scrollTarget: scrollView
            }
        }
    }

    function init() {
        naturalWheel.enabled = false
        scrollView.cancelFlick()
        scrollView.contentX = 0
        scrollView.contentY = 0
        naturalWheel.enabled = true
    }

    function test_mouse_wheel_uses_a_normal_step() {
        window.requestActivate()
        tryCompare(window, "active", true)

        mouseWheel(scrollView,
                   scrollView.width / 2,
                   scrollView.height / 2,
                   0,
                   -120,
                   Qt.NoButton)

        tryVerify(() => scrollView.contentY > 0)
        wait(500)
        verify(scrollView.contentY < scrollView.height)
    }

    function test_kirigami_is_the_page_wheel_owner() {
        compare(naturalWheel.target, scrollView)
        compare(naturalWheel.blockTargetWheel, true)
        compare(naturalWheel.scrollFlickableTarget, true)
        compare(naturalWheel.filterMouseEvents, false)
        compare(scrollView.interactive, true)
        compare(naturalWheel.keyNavigationEnabled, false)
    }

    function test_both_axes_and_bounds() {
        naturalWheel.scrollDown(215)
        tryCompare(scrollView, "contentY", 215)
        naturalWheel.scrollRight(80)
        tryCompare(scrollView, "contentX", 80)
        naturalWheel.scrollDown(10000); naturalWheel.scrollRight(10000)
        tryCompare(scrollView, "contentY", scrollView.contentHeight - scrollView.height)
        tryCompare(scrollView, "contentX", scrollView.contentWidth - scrollView.width)
        naturalWheel.scrollUp(10000); naturalWheel.scrollLeft(10000)
        tryCompare(scrollView, "contentY", 0); tryCompare(scrollView, "contentX", 0)
    }

    function test_handler_detaches_for_modal_image_preview() {
        naturalWheel.enabled = false; compare(naturalWheel.target, null)
        naturalWheel.enabled = true; compare(naturalWheel.target, scrollView)
        mouseWheel(scrollView, 250, 200, 0, -120)
        tryVerify(() => scrollView.contentY > 0)
        wait(500)
    }
}
