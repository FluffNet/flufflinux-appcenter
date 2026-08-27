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

        function showCatalog() { showCatalogCalled = true }

        AppCenter.AppPage {
            id: appPage
            anchors.fill: parent
            app: ({
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
        }
    }

    function init() {
        window.showCatalogCalled = false
        if (appPage.screenshotPreviewDialog.visible)
            appPage.screenshotPreviewDialog.close()
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
        compare(counter.parent.objectName, "previewBottomControls")
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
        verify((touchGesture.acceptedDevices & PointerDevice.TouchScreen) !== 0)
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
}
