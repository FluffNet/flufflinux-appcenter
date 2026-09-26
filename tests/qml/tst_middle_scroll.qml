import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "MiddleScroll"
    when: win.visible
    ApplicationWindow {
        id: win
        width: 600; height: 500; visible: true
        Flickable {
            id: view
            anchors.fill: parent; contentWidth: width; contentHeight: 2400; clip: true
            boundsBehavior: Flickable.StopAtBounds
            AppCenter.NaturalWheelScroll { id: wheel; scrollTarget: view; middleScrollIdleZ: -1 }
            Button { id: action; x: 20; y: 200; width: 200; height: 50; text: "Test action" }
            Flickable {
                id: strip
                x: 20; y: 350; width: 400; height: 100; contentWidth: 1600; contentHeight: height
                AppCenter.MiddleMouseScroll { id: horizontal; scrollTarget: strip; horizontal: true; vertical: false }
                Rectangle { width: 1600; height: 100; color: "gray" }
            }
        }
        Popup { id: popup; modal: true; width: 200; height: 100; anchors.centerIn: parent }
        ToolTip { id: tip; text: "Information" }
    }
    SignalSpy { id: clicked; target: action; signalName: "clicked" }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        popup.close(); tip.close(); wheel.middleMouseScroll.stop(); horizontal.stop(); wheel.stopSmoothScroll()
        view.visible = true; view.contentHeight = 2400; view.contentY = 0; strip.contentX = 0
        clicked.clear(); win.requestActivate(); tryCompare(win, "active", true)
        waitForPolish(view); wait(30)
    }
    function start(x, y) {
        mouseClick(view, x === undefined ? 300 : x, y === undefined ? 150 : y, Qt.MiddleButton)
        verify(wheel.middleMouseScroll.scrolling)
    }
    function test_latched_scroll_and_bounds() {
        const middle = wheel.middleMouseScroll
        compare(middle.parent, view); compare(middle.height, view.height)
        start(); wait(70); compare(view.contentY, 0, "Dead zone must not drift")
        mouseMove(view, 300, 250)
        tryVerify(() => view.contentY > 20)
        compare(middle.y, 0, "Anchor stays in the viewport, not moving content")
        mouseMove(view, 300, 80)
        tryCompare(view, "contentY", 0)
        view.contentY = 1899
        mouseMove(view, 300, 400)
        tryCompare(view, "contentY", 1900)
        keyClick(Qt.Key_Escape); verify(!middle.scrolling)
    }
    function test_stopping_click_never_activates_content() {
        start(100, 220)
        mouseClick(action)
        verify(!wheel.middleMouseScroll.scrolling); compare(clicked.count, 0)
        mouseClick(action); compare(clicked.count, 1)
    }
    function test_middle_toggle_and_held_scroll() {
        start(); mouseClick(view, 300, 150, Qt.MiddleButton)
        verify(!wheel.middleMouseScroll.scrolling)
        mousePress(view, 300, 150, Qt.MiddleButton)
        mouseMove(view, 300, 240)
        tryVerify(() => view.contentY > 10)
        mouseRelease(view, 300, 240, Qt.MiddleButton)
        verify(!wheel.middleMouseScroll.scrolling)
    }
    function test_wheel_and_visibility_stop() {
        start()
        mouseWheel(view, 300, 150, 0, -120)
        verify(!wheel.middleMouseScroll.scrolling); compare(view.contentY, 100)
        start(); view.visible = false
        verify(!wheel.middleMouseScroll.scrolling)
    }
    function test_popup_and_empty_content_stop() {
        start(); popup.open(); tryCompare(popup, "opened", true)
        tryCompare(wheel.middleMouseScroll, "scrolling", false)
        popup.close(); tryCompare(popup, "visible", false)
        start(); view.contentHeight = view.height
        verify(!wheel.middleMouseScroll.scrolling)
        mouseClick(view, 300, 150, Qt.MiddleButton)
        verify(!wheel.middleMouseScroll.scrolling)
    }
    function test_nested_horizontal_target() {
        mouseClick(strip, 150, 50, Qt.MiddleButton)
        verify(horizontal.scrolling); verify(!wheel.middleMouseScroll.scrolling)
        mouseMove(strip, 280, 50)
        tryVerify(() => strip.contentX > 20)
        compare(view.contentY, 0)
        keyClick(Qt.Key_Escape); verify(!horizontal.scrolling)
    }
    function test_tooltip_does_not_block_scrolling() {
        tip.open(); tryCompare(tip, "opened", true)
        start(); mouseMove(view, 300, 250)
        tryVerify(() => view.contentY > 20)
        tip.close(); keyClick(Qt.Key_Escape)
    }
    function test_page_exit_and_smooth_wheel_stop() {
        wheel.applyTouchpadDelta(250, false)
        start(); verify(!wheel.smoothScrolling)
        mouseMove(win.contentItem, 599, 499)
        // Leaving the window/view cancels the latch.
        mouseMove(win.contentItem, -5, -5)
        tryCompare(wheel.middleMouseScroll, "scrolling", false)
    }
}
