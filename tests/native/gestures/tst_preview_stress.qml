import QtQuick
import QtQuick.Controls
import QtTest
import "../../../qml" as AppCenter

TestCase {
    name: "PreviewStress"
    when: main.visible
    AppCenter.Main { id: main; visible: true; width: 1180; height: 760 }

    function picture(width, height, color) {
        return "data:image/svg+xml," + encodeURIComponent(
            "<svg xmlns='http://www.w3.org/2000/svg' width='" + width
            + "' height='" + height + "'><rect width='100%' height='100%' fill='"
            + color + "'/><path d='M0 0L" + width + " " + height
            + "M0 " + height + "L" + width + " 0' stroke='white' stroke-width='12'/></svg>")
    }
    readonly property var app: ({
        id: "org.example.PreviewStress", name: "Preview stress test", summary: "Read-only fixture",
        description: "Long description to detect background movement. ".repeat(300),
        icon: "", developer: "Test fixture", category: "Utilities", license: "", homepage: "",
        screenshots: [picture(640, 360, "#820101"), picture(360, 640, "#0066cc"), picture(500, 500, "#009955")]
    })
    function stack() { return findChild(main, "navigationStack") }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.requestActivate()
        tryCompare(main, "active", true)
    }
    function cleanup() {
        const page = stack().currentItem
        if (page.screenshotPreviewDialog) {
            page.screenshotPreviewDialog.close()
            tryCompare(page.screenshotPreviewDialog, "visible", false)
        }
        main.showCatalog()
        tryCompare(stack(), "busy", false)
    }
    function click(control) { mouseClick(control, control.width / 2, control.height / 2) }
    function ready(page) {
        tryCompare(page.screenshotPreviewDialog, "opened", true)
        tryCompare(findChild(page.screenshotPreviewDialog, "previewImage"), "status", Image.Ready)
        waitForRendering(page.screenshotPreviewDialog.contentItem)
    }
    function stationary(page, expectedY, expectedX) {
        fuzzyCompare(findChild(page, "detailsFlickable").contentY, expectedY, 0.01,
                     "Preview input must not scroll the page")
        fuzzyCompare(findChild(page, "screenshotList").contentX, expectedX, 0.01,
                     "Preview input must not scroll the screenshot strip")
        verify(stack().currentItem === page, "Preview gestures must not navigate back")
    }
    function test_resize_rapid_reopen_and_drag_outside() {
        main.openApp(app)
        tryCompare(stack(), "busy", false)
        const page = stack().currentItem
        for (let cycle = 0; cycle < 24; ++cycle) {
            page.openScreenshot(cycle % 3)
            ready(page)
            page.setPreviewZoom(4)
            main.width = cycle % 2 ? 720 : 1180
            main.height = cycle % 2 ? 560 : 760
            waitForRendering(page.screenshotPreviewDialog.contentItem)
            const frame = findChild(page.screenshotPreviewDialog, "previewGestureSurface")
            const details = findChild(page, "detailsFlickable")
            const strip = findChild(page, "screenshotList")
            const originalY = details.contentY, originalX = strip.contentX
            nativeInput.pointer(frame, 0, frame.width / 2, frame.height / 2)
            for (let step = 1; step <= 8; ++step) {
                nativeInput.pointer(frame, 1, frame.width / 2 - step * frame.width / 8,
                                    frame.height / 2)
                wait(16)
            }
            nativeInput.pointer(frame, 2, -frame.width / 2, frame.height / 2)
            verify(page.screenshotPreviewDialog.visible, "Dragging beyond the image is not an outside press")
            verify(Math.abs(page.previewPanX) <= page.previewPanLimitX(page.previewZoom) + 0.01)
            stationary(page, originalY, originalX)

            // Reopen immediately, including while an exit transition could run.
            page.screenshotPreviewDialog.close()
            page.openScreenshot((cycle + 1) % 3)
            ready(page)
            compare(page.previewScreenshotIndex, (cycle + 1) % 3)
            compare(page.previewZoom, 1)
            mouseClick(page.previewWindowWheelSurfaceItem, 2, 2,
                       cycle % 2 ? Qt.RightButton : Qt.MiddleButton)
            tryCompare(page.screenshotPreviewDialog, "visible", false)
            verify(!findChild(details, "middleMouseScroll").scrolling)
        }

        // An unavailable picture must not trap the modal or block closing.
        page.app = Object.assign({}, app, {screenshots: ["file:///missing-preview-stress-image.png"]})
        page.openScreenshot(0)
        tryCompare(page.screenshotPreviewDialog, "opened", true)
        tryCompare(findChild(page.screenshotPreviewDialog, "previewImage"), "status", Image.Error)
        nativeInput.mouseWheel(page.previewWindowWheelSurfaceItem, 2, 2, 0, -120)
        compare(page.previewScreenshotIndex, 0)
        click(findChild(page.screenshotPreviewDialog, "previewCloseButton"))
        tryCompare(page.screenshotPreviewDialog, "visible", false)
    }

    function test_repeated_interactions_data() {
        let rows = []
        for (const width of [720, 1180])
            for (const dark of [false, true])
                for (const rtl of [false, true])
                    rows.push({tag: width + "-" + (dark ? "dark" : "light") + "-" + (rtl ? "rtl" : "ltr"),
                               width: width, dark: dark, rtl: rtl})
        return rows
    }
    function test_repeated_interactions(data) {
        main.width = data.width
        main.height = data.width === 720 ? 560 : 760
        main.palette.window = data.dark ? "#202326" : "#eeeeee"
        main.palette.windowText = data.dark ? "white" : "black"
        main.contentItem.LayoutMirroring.enabled = data.rtl
        main.Overlay.overlay.LayoutMirroring.enabled = data.rtl
        main.openApp(app)
        tryCompare(stack(), "busy", false)
        const page = stack().currentItem
        const details = findChild(page, "detailsFlickable")
        const strip = findChild(page, "screenshotList")
        details.contentY = 240
        strip.contentX = 80
        waitForRendering(page)

        for (let cycle = 0; cycle < 12; ++cycle) {
            page.openScreenshot(cycle % 3)
            ready(page)
            const dialog = page.screenshotPreviewDialog
            const frame = findChild(dialog, "previewGestureSurface")
            const wheelSurface = page.previewWindowWheelSurfaceItem
            const originalY = details.contentY, originalX = strip.contentX
            const plus = findChild(dialog, "previewZoomInButton")
            const minus = findChild(dialog, "previewZoomOutButton")

            // Repeated button clicks clamp at both zoom limits, without drift.
            for (let i = 0; i < 10; ++i) click(plus)
            compare(page.previewZoom, page.maximumPreviewZoom)
            verify(!plus.enabled)
            for (let i = 0; i < 10; ++i) click(minus)
            compare(page.previewZoom, 1)
            verify(!minus.enabled)

            for (let i = 0; i < 8; ++i) {
                nativeInput.mouseWheel(frame, frame.width / 2, frame.height / 2, 0, 120)
                fuzzyCompare(page.previewZoom, 1.25, 0.0001)
                nativeInput.mouseWheel(frame, frame.width / 2, frame.height / 2, 0, -120)
                fuzzyCompare(page.previewZoom, 1, 0.0001)
            }
            // Native two-finger scroll zooms on the image, with paired deltas.
            nativeInput.scroll(frame, frame.width / 2, frame.height / 2, 0, 20)
            verify(page.previewZoom > 1)
            nativeInput.scroll(frame, frame.width / 2, frame.height / 2, 0, -20)
            fuzzyCompare(page.previewZoom, 1, 0.0001)

            for (let i = 0; i < 3; ++i) {
                nativeInput.gesture(frame, Qt.BeginNativeGesture, frame.width / 2, frame.height / 2)
                nativeInput.gesture(frame, Qt.ZoomNativeGesture, frame.width / 2, frame.height / 2, 0.5)
                nativeInput.gesture(frame, Qt.EndNativeGesture, frame.width / 2, frame.height / 2)
            }
            fuzzyCompare(page.previewZoom, 3.375, 0.0001)
            verify(!page.previewPinching)

            // Alternate mouse and touchpad held-click drags, in both axes.
            const x = frame.width / 2, y = frame.height / 2
            nativeInput.pointer(frame, 0, x, y, cycle % 2 === 1)
            for (let step = 1; step <= 5; ++step) {
                nativeInput.pointer(frame, 1, x + step * 12, y + step * 10, cycle % 2 === 1)
                wait(16)
                stationary(page, originalY, originalX)
            }
            nativeInput.pointer(frame, 2, x + 60, y + 50, cycle % 2 === 1)
            if (page.previewPanLimitX(page.previewZoom) > 0) verify(page.previewPanX > 0)
            if (page.previewPanLimitY(page.previewZoom) > 0) verify(page.previewPanY > 0)
            const panX = page.previewPanX, panY = page.previewPanY
            nativeInput.scroll(frame, x, y, 120, 0)
            compare(page.previewPanX, panX)
            compare(page.previewPanY, panY)
            compare(page.previewScreenshotIndex, cycle % 3)

            // Browse outside the image; changing pictures must reset zoom/pan.
            nativeInput.mouseWheel(wheelSurface, 2, 2, 0, -120)
            compare(page.previewScreenshotIndex, Math.min(2, cycle % 3 + 1))
            compare(page.previewZoom, 1)
            compare(page.previewPanX, 0)
            compare(page.previewPanY, 0)
            ready(page)
            dialog.contentItem.forceActiveFocus()
            for (let i = 0; i < 4; ++i) keyClick(Qt.Key_Left)
            compare(page.previewScreenshotIndex, 0)
            for (let i = 0; i < 4; ++i) keyClick(Qt.Key_Right)
            compare(page.previewScreenshotIndex, 2)
            click(findChild(dialog, "previewPreviousButton"))
            compare(page.previewScreenshotIndex, 1)
            click(findChild(dialog, "previewNextButton"))
            compare(page.previewScreenshotIndex, 2)
            stationary(page, originalY, originalX)

            // Close through every outside margin, Escape and the close button.
            const positions = [[2, 2], [main.width - 2, main.height - 2],
                               [2, main.height / 2], [main.width - 2, main.height / 2]]
            if (cycle % 6 < 4) {
                const point = positions[cycle % 6]
                if (cycle >= 6) {
                    const touch = touchEvent(wheelSurface)
                    touch.press(0, wheelSurface, point[0], point[1]).commit()
                    touch.release(0, wheelSurface, point[0], point[1]).commit()
                } else {
                    mouseClick(wheelSurface, point[0], point[1])
                }
            } else if (cycle % 6 === 4) {
                keyClick(Qt.Key_Escape)
            } else {
                click(findChild(dialog, "previewCloseButton"))
            }
            tryCompare(dialog, "visible", false)
            compare(page.previewScreenshotIndex, -1)
            compare(page.previewScreenshot, "")
            compare(page.previewZoom, 1)
            stationary(page, originalY, originalX)
            verify(details.interactive && strip.interactive)
        }
        nativeInput.mouseWheel(details, 10, 10, 0, -120)
        tryVerify(() => details.contentY > 240, 5000, "Page scrolling must recover after the last close")
    }
}
