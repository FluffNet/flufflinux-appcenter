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
                    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23e05562'/%3E%3C/svg%3E"
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

        const nextButton = findChild(preview, "previewNextButton")
        verify(nextButton !== null)
        verify(nextButton.visible)
        mouseClick(nextButton, nextButton.width / 2, nextButton.height / 2)
        compare(appPage.previewScreenshotIndex, 1)

        const previousButton = findChild(preview, "previewPreviousButton")
        verify(previousButton !== null)
        verify(previousButton.visible)
        mouseClick(previousButton, previousButton.width / 2, previousButton.height / 2)
        compare(appPage.previewScreenshotIndex, 0)

        const closeButton = findChild(preview, "previewCloseButton")
        verify(closeButton !== null)
        mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
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

        const swipeSurface = findChild(appPage, "pageSwipeSurface")
        verify(swipeSurface !== null)
        compare(appPage.finishPageSwipe(280, 10), true)
        compare(window.showCatalogCalled, true)

        window.showCatalogCalled = false
        compare(appPage.finishPageSwipe(60, 10), false)
        compare(window.showCatalogCalled, false)
    }

    function test_preview_supports_touch_and_touchpad_swiping() {
        appPage.openScreenshot(0)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)

        const swipeView = findChild(preview, "previewSwipe")
        const touchpadGesture = findChild(preview, "previewTouchpadSwipe")
        verify(swipeView !== null)
        verify(swipeView.interactive)
        verify(touchpadGesture !== null)
        verify((touchpadGesture.acceptedDevices & PointerDevice.TouchPad) !== 0)
    }
}
