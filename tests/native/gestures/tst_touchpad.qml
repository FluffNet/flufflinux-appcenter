import QtQuick
import QtQuick.Controls
import QtTest
import "../../../qml" as AppCenter

TestCase {
    name: "NativeTouchpad"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    readonly property var app: ({id: "org.example.Preview", name: "Preview", summary: "", description: "", icon: "", developer: "", category: "", license: "", homepage: "", screenshots: [
        "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23820101'/%3E%3C/svg%3E"]})
    function test_repeated_native_gestures_keep_focus_data() {
        return [{tag: "same-focus", moveFocus: false}, {tag: "new-focus-each-gesture", moveFocus: true}]
    }
    function test_repeated_native_gestures_keep_focus(data) {
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        page.openScreenshot(0)
        const dialog = page.screenshotPreviewDialog
        tryCompare(dialog, "visible", true)
        const frame = findChild(dialog, "previewImageFrame")
        const image = findChild(dialog, "previewImage")
        const handler = findChild(dialog, "previewTouchpadPinch")
        tryCompare(image, "status", Image.Ready)
        waitForRendering(frame)
        // A release must never alter the picture, nor may the next Begin
        // replay the previous gesture's accumulated scale or reset deltas.
        const factors = [1.6, 1.25, 0.8, 1.2, 0.75]
        for (let i = 0; i < factors.length; ++i) {
            const factor = factors[i]
            const focus = Qt.point(frame.width * (data.moveFocus && i % 2 ? 0.45 : 0.62), frame.height * 0.5)
            const imagePoint = page.previewImagePointAt(focus.x, focus.y, page.previewZoom, page.previewPanX, page.previewPanY)
            const oldZoom = page.previewZoom
            const oldPanX = page.previewPanX, oldPanY = page.previewPanY
            nativeInput.gesture(frame, Qt.BeginNativeGesture, focus.x, focus.y)
            verify(handler.active)
            fuzzyCompare(page.previewZoom, oldZoom, 0.0001, "Beginning another gesture must not change zoom")
            fuzzyCompare(page.previewPanX, oldPanX, 0.001, "Beginning another gesture must not jump the focus")
            fuzzyCompare(page.previewPanY, oldPanY, 0.001)
            // Multiple incremental updates, as emitted by a real touchpad.
            for (let step = 0; step < 4; ++step)
                nativeInput.gesture(frame, Qt.ZoomNativeGesture, focus.x, focus.y, Math.pow(factor, 0.25) - 1)
            fuzzyCompare(page.previewZoom, oldZoom * factor, 0.0001)
            const after = page.previewImagePointAt(focus.x, focus.y, page.previewZoom, page.previewPanX, page.previewPanY)
            fuzzyCompare(after.x, imagePoint.x, 0.001, "Image point under the pinch focus must stay fixed")
            fuzzyCompare(after.y, imagePoint.y, 0.001)
            const zoom = page.previewZoom, panX = page.previewPanX, panY = page.previewPanY
            nativeInput.gesture(frame, Qt.EndNativeGesture, focus.x, focus.y)
            verify(!handler.active)
            fuzzyCompare(page.previewZoom, zoom, 0.0001, "Release must not rescale")
            fuzzyCompare(page.previewPanX, panX, 0.001, "Release must not move the image")
            fuzzyCompare(page.previewPanY, panY, 0.001)
        }
        dialog.close()
        main.showCatalog()
        tryCompare(stack, "busy", false)
    }
}
