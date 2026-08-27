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
        naturalWheel.stopSmoothScroll()
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

    function test_touchpad_uses_smaller_continuous_deltas() {
        verify((naturalWheel.acceptedDevices & PointerDevice.Mouse) !== 0)
        verify((naturalWheel.acceptedDevices & PointerDevice.TouchPad) !== 0)
        compare(naturalWheel.wheelStep, 100)
        compare(naturalWheel.touchpadStep, 42)
        compare(naturalWheel.touchpadPixelScale, 2.15)
        compare(naturalWheel.isTouchpadDevice(null, true), true)
        compare(naturalWheel.isTouchpadDevice({
                    deviceType: PointerDevice.TouchPad,
                    pointerType: PointerDevice.Finger,
                    maximumPoints: 2
                }, false), true)
        compare(naturalWheel.isTouchpadDevice({
                    deviceType: PointerDevice.Mouse,
                    pointerType: PointerDevice.Generic,
                    maximumPoints: 1
                }, false), false)
    }

    function test_touchpad_scroll_follows_a_smooth_target() {
        naturalWheel.scrollBy(215, true)
        compare(naturalWheel.smoothScrolling, true)
        compare(naturalWheel.smoothTargetY, 215)
        verify(scrollView.contentY < naturalWheel.smoothTargetY)

        tryCompare(scrollView, "contentY", 215, 1000)
        compare(naturalWheel.smoothScrolling, false)
    }
}
