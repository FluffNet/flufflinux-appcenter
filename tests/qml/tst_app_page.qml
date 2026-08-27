import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "AppPage"
    when: window.visible

    ApplicationWindow {
        id: window
        width: 1180
        height: 760
        visible: true

        property color accentColor: "#e05562"
        property color textColor: "white"
        property color mutedTextColor: "#a0a0a0"
        property color surfaceColor: "#24282d"
        property color raisedSurfaceColor: "#30343a"
        property color borderColor: "#50545a"
        property color hoverColor: "#393d43"
        property var selectedApp: null
        property bool showCatalogCalled: false
        property var previewApp: ({
            id: "org.fluff.PreviewTest",
            name: "Preview Test",
            summary: "Screenshot preview test",
            description: "A test application",
            icon: "",
            category: "Utilities",
            developer: "FluffNet",
            license: "MIT",
            homepage: "",
            screenshots: [
                "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23820101'/%3E%3C/svg%3E",
                "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23e05562'/%3E%3C/svg%3E",
                "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%230066cc'/%3E%3C/svg%3E",
                "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23009955'/%3E%3C/svg%3E"
            ]
        })

        function showCatalog() { showCatalogCalled = true }

        AppCenter.AppPage {
            id: appPage
            anchors.fill: parent
            app: window.previewApp
        }
    }

    function init() {
        window.showCatalogCalled = false
        if (appPage.screenshotPreviewDialog.visible)
            appPage.screenshotPreviewDialog.close()
        appPage.app = window.previewApp
        window.width = 1180
        window.height = 760
    }

    function appWithScreenshots(screenshots) {
        return {
            id: window.previewApp.id,
            name: window.previewApp.name,
            summary: window.previewApp.summary,
            description: window.previewApp.description,
            icon: window.previewApp.icon,
            category: window.previewApp.category,
            developer: window.previewApp.developer,
            license: window.previewApp.license,
            homepage: window.previewApp.homepage,
            screenshots: screenshots
        }
    }

    function test_single_screenshot_is_large_and_centered() {
        appPage.app = appWithScreenshots([window.previewApp.screenshots[0]])
        const screenshotList = findChild(appPage, "screenshotList")
        verify(screenshotList !== null)
        tryCompare(screenshotList, "count", 1)
        compare(screenshotList.visible, true)
        tryCompare(screenshotList, "height", 390)

        const screenshotButton = findChild(screenshotList, "screenshotButton")
        verify(screenshotButton !== null)
        verify(screenshotButton.width >= 760)
        const position = screenshotButton.mapToItem(screenshotList, 0, 0)
        verify(Math.abs((position.x + screenshotButton.width / 2)
                        - screenshotList.width / 2) < 1)

        const loadingSpinner = findChild(screenshotButton, "screenshotLoadingSpinner")
        verify(loadingSpinner !== null)
        compare(loadingSpinner.color, window.textColor)
    }

    function test_no_screenshot_hides_the_strip_and_cannot_open_preview() {
        appPage.app = appWithScreenshots([])
        const screenshotList = findChild(appPage, "screenshotList")
        verify(screenshotList !== null)
        tryCompare(screenshotList, "count", 0)
        compare(screenshotList.visible, false)
        compare(appPage.openScreenshot(0), false)
        compare(appPage.screenshotPreviewDialog.visible, false)
    }

    function test_clicking_screenshot_opens_preview() {
        window.requestActivate()
        tryCompare(window, "active", true)

        const screenshotButton = findChild(appPage, "screenshotButton")
        verify(screenshotButton !== null)
        mouseClick(screenshotButton,
                   screenshotButton.width / 2,
                   screenshotButton.height / 2)

        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        compare(appPage.previewScreenshot, screenshotButton.modelData)
        compare(appPage.previewScreenshotIndex, 0)
        verify(preview.width <= window.width * 0.85)
        verify(preview.height <= window.height * 0.83)
        verify(preview.x >= window.width * 0.07)
        verify(preview.y >= window.height * 0.07)

        const previewImage = findChild(preview, "previewImage")
        verify(previewImage !== null)
        compare(String(previewImage.source), String(appPage.app.screenshots[0]))
        const loadingSpinner = findChild(preview, "previewLoadingSpinner")
        verify(loadingSpinner !== null)
        compare(loadingSpinner.color, window.textColor)

        const nextButton = findChild(preview, "previewNextButton")
        verify(nextButton !== null)
        verify(nextButton.visible)
        compare(nextButton.parent.objectName, "previewNextControls")
        mouseClick(nextButton, nextButton.width / 2, nextButton.height / 2)
        compare(appPage.previewScreenshotIndex, 1)
        compare(String(previewImage.source), String(appPage.app.screenshots[1]))

        const previousButton = findChild(preview, "previewPreviousButton")
        verify(previousButton !== null)
        verify(previousButton.visible)
        compare(previousButton.parent.objectName, "previewPreviousControls")
        mouseClick(previousButton, previousButton.width / 2, previousButton.height / 2)
        compare(appPage.previewScreenshotIndex, 0)
        compare(String(previewImage.source), String(appPage.app.screenshots[0]))

        const closeButton = findChild(preview, "previewCloseButton")
        verify(closeButton !== null)
        compare(closeButton.parent.objectName, "previewTopControls")
        const counter = findChild(preview, "previewCounter")
        verify(counter !== null)
        compare(counter.parent.objectName, "previewBottomControlRow")
        mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
        tryCompare(preview, "visible", false)
    }

    function test_clicking_outside_closes_preview() {
        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)

        mouseClick(window.contentItem, 2, 2)
        tryCompare(preview, "visible", false)
    }

    function test_back_control_has_text_and_icon() {
        const backButton = findChild(appPage, "backButton")
        verify(backButton !== null)
        compare(backButton.text, "←  Back")
        compare(backButton.icon.name, "")
        verify(backButton.width >= 106)
    }

    function test_page_supports_touch_and_touchpad_back_gestures() {
        const touchGesture = findChild(appPage, "pageTouchBackGesture")
        const touchpadGesture = findChild(appPage, "pageTouchpadBackGesture")
        verify(touchGesture !== null)
        verify(touchpadGesture !== null)
        verify((touchGesture.acceptedDevices & PointerDevice.TouchScreen) !== 0)
        verify((touchpadGesture.acceptedDevices & PointerDevice.TouchPad) !== 0)
        verify((touchpadGesture.acceptedDevices & PointerDevice.Mouse) !== 0)
        compare(touchpadGesture.blocking, false)

        const swipeSurface = findChild(appPage, "pageSwipeSurface")
        verify(swipeSurface !== null)
        compare(appPage.finishPageSwipe(280, 10), true)
        compare(window.showCatalogCalled, true)

        window.showCatalogCalled = false
        compare(appPage.finishPageSwipe(60, 10), false)
        compare(window.showCatalogCalled, false)

        mouseWheel(swipeSurface,
                   swipeSurface.width / 2,
                   swipeSurface.height / 2,
                   -240,
                   0,
                   Qt.NoButton)
        compare(window.showCatalogCalled, true)
    }

    function test_vertical_wheel_scrolls_without_gesture_blocking() {
        window.requestActivate()
        tryCompare(window, "active", true)

        const details = findChild(appPage, "detailsFlickable")
        verify(details !== null)
        details.contentY = 0
        mouseWheel(details,
                   details.width / 2,
                   details.height / 2,
                   0,
                   -120,
                   Qt.NoButton)
        verify(details.contentY > 0)
    }

    function test_preview_supports_touch_and_touchpad_swiping() {
        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)

        const gestureSurface = findChild(preview, "previewGestureSurface")
        const touchGesture = findChild(preview, "previewTouchSwipe")
        const touchpadGesture = findChild(preview, "previewTouchpadSwipe")
        const previewImage = findChild(preview, "previewImage")
        verify(gestureSurface !== null)
        verify(touchGesture !== null)
        verify(touchpadGesture !== null)
        verify(previewImage !== null)
        compare(touchGesture.minimumTouchPoints, 1)
        compare(touchGesture.maximumTouchPoints, 2)
        compare(touchGesture.mouseEnabled, false)
        verify((touchpadGesture.acceptedDevices & PointerDevice.TouchPad) !== 0)
        verify((touchpadGesture.acceptedDevices & PointerDevice.Mouse) !== 0)
        compare(touchpadGesture.blocking, true)

        mouseWheel(gestureSurface,
                   gestureSurface.width / 2,
                   gestureSurface.height / 2,
                   240,
                   0,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 1)
        compare(String(previewImage.source), String(appPage.app.screenshots[1]))

        touchpadGesture.gestureTriggered = true
        mouseWheel(gestureSurface,
                   gestureSurface.width / 2,
                   gestureSurface.height / 2,
                   240,
                   0,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 1)

        compare(appPage.finishPreviewSwipe(-100, 10), true)
        compare(appPage.previewScreenshotIndex, 2)
        compare(String(previewImage.source), String(appPage.app.screenshots[2]))
        compare(appPage.finishPreviewSwipe(20, 10), false)
        compare(appPage.previewScreenshotIndex, 2)
    }

    function test_preview_touchpad_swipe_previous() {
        appPage.openScreenshot(1)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)

        const gestureSurface = findChild(preview, "previewGestureSurface")
        const previewImage = findChild(preview, "previewImage")
        verify(gestureSurface !== null)
        verify(previewImage !== null)
        mouseWheel(gestureSurface,
                   gestureSurface.width / 2,
                   gestureSurface.height / 2,
                   -240,
                   0,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 0)
        compare(String(previewImage.source), String(appPage.app.screenshots[0]))
    }

    function test_preview_zoom_controls_and_cursor_centering() {
        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)

        const frame = findChild(preview, "previewImageFrame")
        const gestureSurface = findChild(preview, "previewGestureSurface")
        const previewImage = findChild(preview, "previewImage")
        const zoomInButton = findChild(preview, "previewZoomInButton")
        const zoomOutButton = findChild(preview, "previewZoomOutButton")
        const fitButton = findChild(preview, "previewFitButton")
        const zoomLabel = findChild(preview, "previewZoomLabel")
        verify(frame !== null)
        verify(gestureSurface !== null)
        verify(previewImage !== null)
        verify(zoomInButton !== null)
        verify(zoomOutButton !== null)
        verify(fitButton !== null)
        verify(zoomLabel !== null)
        tryCompare(previewImage, "status", Image.Ready)
        compare(appPage.previewZoom, 1)
        compare(zoomLabel.text, "100%")
        compare(zoomInButton.parent.objectName, "previewBottomControlRow")

        const outsideFocus = appPage.mousePreviewZoomFocus(0, 0)
        compare(outsideFocus.x, frame.width / 2)
        compare(outsideFocus.y, frame.height / 2)

        const focusX = frame.width / 2 + 50
        const focusY = frame.height / 2 + 30
        const centerX = frame.width / 2
        const centerY = frame.height / 2
        const sourceXBefore = centerX + (focusX - centerX - appPage.previewPanX)
                                           / appPage.previewZoom
        const sourceYBefore = centerY + (focusY - centerY - appPage.previewPanY)
                                           / appPage.previewZoom
        appPage.setPreviewZoom(2, focusX, focusY)
        const sourceXAfter = centerX + (focusX - centerX - appPage.previewPanX)
                                          / appPage.previewZoom
        const sourceYAfter = centerY + (focusY - centerY - appPage.previewPanY)
                                          / appPage.previewZoom
        compare(appPage.previewZoom, 2)
        compare(previewImage.scale, 2)
        verify(Math.abs(sourceXAfter - sourceXBefore) < 0.01)
        verify(Math.abs(sourceYAfter - sourceYBefore) < 0.01)
        compare(appPage.finishPreviewSwipe(-120, 5), false)

        mouseClick(fitButton, fitButton.width / 2, fitButton.height / 2)
        compare(appPage.previewZoom, 1)
        compare(appPage.previewPanX, 0)
        compare(appPage.previewPanY, 0)
        mouseWheel(gestureSurface,
                   focusX,
                   focusY,
                   0,
                   120,
                   Qt.NoButton)
        compare(appPage.previewZoom, 1.2)
        verify(appPage.previewPanX < 0)
        verify(appPage.previewPanY < 0)
        const sourceXAfterWheel = centerX
                                  + (focusX - centerX - appPage.previewPanX)
                                    / appPage.previewZoom
        const sourceYAfterWheel = centerY
                                  + (focusY - centerY - appPage.previewPanY)
                                    / appPage.previewZoom
        verify(Math.abs(sourceXAfterWheel - sourceXBefore) < 0.01)
        verify(Math.abs(sourceYAfterWheel - sourceYBefore) < 0.1)
        mouseClick(fitButton, fitButton.width / 2, fitButton.height / 2)
        mouseWheel(gestureSurface,
                   0,
                   0,
                   0,
                   120,
                   Qt.NoButton)
        compare(appPage.previewZoom, 1.2)
        compare(appPage.previewPanX, 0)
        compare(appPage.previewPanY, 0)
        mouseClick(fitButton, fitButton.width / 2, fitButton.height / 2)
        mouseClick(zoomInButton, zoomInButton.width / 2, zoomInButton.height / 2)
        compare(appPage.previewZoom, 1.25)
        mouseClick(zoomOutButton, zoomOutButton.width / 2, zoomOutButton.height / 2)
        compare(appPage.previewZoom, 1)
    }

    function test_preview_has_touch_pinch_and_pan_support() {
        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)

        const frame = findChild(preview, "previewImageFrame")
        const gestureSurface = findChild(preview, "previewGestureSurface")
        const previewImage = findChild(preview, "previewImage")
        const touchpadPinch = findChild(preview, "previewTouchpadPinch")
        const touchPan = findChild(preview, "previewTouchSwipe")
        const mousePan = findChild(preview, "previewMousePan")
        verify(frame !== null)
        verify(gestureSurface !== null)
        verify(previewImage !== null)
        verify(touchpadPinch !== null)
        verify(touchPan !== null)
        verify(mousePan !== null)
        verify((touchpadPinch.acceptedDevices & PointerDevice.TouchPad) !== 0)
        compare(touchPan.minimumTouchPoints, 1)
        compare(touchPan.maximumTouchPoints, 2)
        compare(touchPan.mouseEnabled, false)
        verify((mousePan.acceptedButtons & Qt.LeftButton) !== 0)
        tryCompare(previewImage, "status", Image.Ready)

        const centerX = gestureSurface.width / 2
        const centerY = gestureSurface.height / 2
        let pinch = touchEvent(gestureSurface)
        pinch.press(0, gestureSurface, centerX - 40, centerY).commit()
        pinch.stationary(0)
             .press(1, gestureSurface, centerX + 40, centerY).commit()
        pinch.move(0, gestureSurface, centerX - 60, centerY)
             .move(1, gestureSurface, centerX + 60, centerY)
             .commit()
        pinch.move(0, gestureSurface, centerX - 100, centerY)
             .move(1, gestureSurface, centerX + 100, centerY)
             .commit()
        tryVerify(function() { return appPage.previewZoom > 1.5 })
        pinch.release(0, gestureSurface, centerX - 100, centerY)
             .release(1, gestureSurface, centerX + 100, centerY)
             .commit()

        appPage.resetPreviewTransform()
        appPage.setPreviewZoom(2, centerX, centerY)
        const panXBeforeTouch = appPage.previewPanX
        const panYBeforeTouch = appPage.previewPanY
        let pan = touchEvent(gestureSurface)
        pan.press(0, gestureSurface, centerX, centerY).commit()
        pan.move(0, gestureSurface, centerX + 40, centerY + 24).commit()
        pan.release(0, gestureSurface, centerX + 40, centerY + 24).commit()
        verify(appPage.previewPanX > panXBeforeTouch)
        verify(appPage.previewPanY > panYBeforeTouch)

        appPage.resetPreviewTransform()
        appPage.setPreviewZoom(2, centerX, centerY)
        const panXBeforeMouse = appPage.previewPanX
        const panYBeforeMouse = appPage.previewPanY
        mousePress(gestureSurface, centerX, centerY, Qt.LeftButton)
        mouseMove(gestureSurface, centerX + 44, centerY + 28)
        mouseRelease(gestureSurface,
                     centerX + 44,
                     centerY + 28,
                     Qt.LeftButton)
        verify(appPage.previewPanX > panXBeforeMouse)
        verify(appPage.previewPanY > panYBeforeMouse)

        appPage.resetPreviewTransform()
        appPage.applyPreviewPinch(1, 0, 0,
                                  centerX + 60, centerY + 35,
                                  2, 0, 0)
        compare(appPage.previewZoom, 2)
        compare(appPage.previewPanX, -60)
        compare(appPage.previewPanY, -35)

        appPage.resetPreviewTransform()
        appPage.applyPreviewPinch(1, 0, 0,
                                  frame.width / 2, frame.height / 2,
                                  2, 24, 16)
        compare(appPage.previewZoom, 2)
        compare(appPage.previewPanX, 24)
        compare(appPage.previewPanY, 16)
        appPage.panPreviewBy(-10, -6)
        compare(appPage.previewPanX, 14)
        compare(appPage.previewPanY, 10)

        appPage.movePreview(1)
        compare(appPage.previewZoom, 1)
        compare(appPage.previewPanX, 0)
        compare(appPage.previewPanY, 0)
    }

    function test_preview_touch_swipe_changes_one_screenshot_when_fitted() {
        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        const gestureSurface = findChild(preview, "previewGestureSurface")
        verify(gestureSurface !== null)

        const y = gestureSurface.height / 2
        let swipe = touchEvent(gestureSurface)
        swipe.press(0, gestureSurface, gestureSurface.width * 0.75, y).commit()
        swipe.move(0, gestureSurface, gestureSurface.width * 0.2, y).commit()
        swipe.release(0, gestureSurface, gestureSurface.width * 0.2, y).commit()
        compare(appPage.previewScreenshotIndex, 1)
    }

    function test_preview_uses_most_of_a_large_window() {
        window.width = 1800
        window.height = 1000
        tryCompare(window, "width", 1800)
        tryCompare(window, "height", 1000)
        tryCompare(appPage, "width", 1800)
        tryCompare(appPage, "height", 1000)

        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        compare(appPage.width, window.width)
        compare(preview.desiredWidth, Math.round(window.width * 0.78))
        compare(preview.desiredHeight, Math.round(window.height * 0.78))
        compare(preview.width, Math.round(window.width * 0.78))
        compare(preview.height, Math.round(window.height * 0.78))
        verify(preview.width > 1040)
        verify(preview.height > 720)
    }
}
