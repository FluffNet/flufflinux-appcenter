import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "WheelScroll"
    when: window.visible

    ApplicationWindow {
        id: window
        width: 500
        height: 400
        visible: true

        Flickable {
            id: scrollView
            anchors.fill: parent
            contentWidth: width
            contentHeight: 2000
            boundsBehavior: Flickable.StopAtBounds

            AppCenter.NaturalWheelScroll {
                id: naturalWheel
                scrollTarget: scrollView
            }
        }
    }

    function init() {
        scrollView.contentY = 0
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

        compare(scrollView.contentY, 100)
    }

    function test_touchpad_is_left_to_native_flickable_scrolling() {
        compare(naturalWheel.acceptedDevices, PointerDevice.Mouse)
    }
}
