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
        property color accentTextColor: "#e05562"
        property color accentForegroundColor: "white"
        property color backgroundColor: "#202326"
        property int cornerRadius: 8
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
        tryCompare(appPage.screenshotPreviewDialog, "visible", false)
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
        compare(screenshotList.flickableDirection, Flickable.HorizontalFlick)
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

    function test_hero_artwork_and_developer_label() {
        const artwork = Qt.resolvedUrl("../../assets/flufflinux-appcenter.svg").toString()
        appPage.app = Object.assign({}, window.previewApp, {icon: artwork})
        const logo = findChild(appPage, "appHeroIcon")
        tryCompare(logo, "status", Image.Ready)
        verify(logo.paintedWidth > 0 && logo.paintedHeight > 0)
        compare(findChild(appPage, "appDeveloper").text, "FluffNet")
        appPage.app = Object.assign({}, window.previewApp, {icon: "file:///missing-appcenter-logo.png", developer: ""})
        tryCompare(logo, "loadFailed", true)
        compare(logo.source.toString(), "image://icon/application-x-executable")
        verify(!findChild(appPage, "appDeveloper").visible)
        appPage.app = Object.assign({}, window.previewApp, {icon: artwork})
        tryCompare(logo, "status", Image.Ready)
        compare(logo.loadFailed, false)
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

    function test_preview_keyboard_arrows_move_one_screenshot() {
        appPage.openScreenshot(1)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        preview.contentItem.forceActiveFocus()
        tryCompare(preview.contentItem, "activeFocus", true)

        keyClick(Qt.Key_Right)
        compare(appPage.previewScreenshotIndex, 2)
        compare(appPage.previewScreenshot, appPage.app.screenshots[2])
        keyClick(Qt.Key_Left)
        compare(appPage.previewScreenshotIndex, 1)
        compare(appPage.previewScreenshot, appPage.app.screenshots[1])
    }

    function test_back_control_has_text_and_icon() {
        const backButton = findChild(appPage, "backButton")
        verify(backButton !== null)
        compare(backButton.text, "←  Back")
        compare(backButton.icon.name, "")
        verify(backButton.width >= 106)
    }

    function test_back_hover_background_is_inset_data() {
        return [{tag: "narrow", width: 720}, {tag: "wide", width: 1180}]
    }

    function test_back_hover_background_is_inset(data) {
        window.width = data.width
        window.requestActivate()
        const back = findChild(appPage, "backButton")
        waitForPolish(appPage)
        compare(back.mapToItem(appPage.header, 0, 0).x, 14)
        const position = back.background.mapToItem(appPage.header, 0, 0)
        verify(position.x >= 14, "Inset the whole hover background, not just the label")
        verify(position.y > 0)
        verify(position.y + back.background.height < appPage.header.height)
        verify(back.width >= 106 && back.height >= 40)
        mouseMove(back, back.width / 2, back.height / 2)
        tryCompare(back, "hovered", true)
        compare(back.background.color, window.hoverColor)
        // The inset is not part of the Back button's hit target.
        mouseClick(appPage.header, 7, appPage.header.height / 2)
        verify(!window.showCatalogCalled)
        mouseClick(back)
        verify(window.showCatalogCalled)
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
        const screenshotList = findChild(appPage, "screenshotList")
        verify(swipeSurface !== null)
        verify(screenshotList !== null)
        const stripCenter = screenshotList.mapToItem(
                    swipeSurface,
                    screenshotList.width / 2,
                    screenshotList.height / 2)
        compare(appPage.pointIsInsideScreenshotStrip(stripCenter.x,
                                                      stripCenter.y), true)
        compare(appPage.finishPageSwipe(280, 10), true)
        compare(window.showCatalogCalled, true)

        window.showCatalogCalled = false
        compare(appPage.finishPageSwipe(60, 10), false)
        compare(window.showCatalogCalled, false)

        mouseWheel(swipeSurface,
                   stripCenter.x,
                   stripCenter.y,
                   -240,
                   0,
                   Qt.NoButton)
        compare(window.showCatalogCalled, false)

        mouseWheel(swipeSurface,
                   swipeSurface.width / 2,
                   5,
                   -240,
                   0,
                   Qt.NoButton)
        compare(window.showCatalogCalled, true)
    }

    function test_screenshot_strip_owns_touch_swipes_and_uses_natural_direction() {
        const screenshotList = findChild(appPage, "screenshotList")
        verify(screenshotList !== null)
        tryCompare(screenshotList, "count", 4)

        screenshotList.contentX = 0
        appPage.scrollScreenshotStripBy(-10, true)
        compare(screenshotList.contentX, 50)

        screenshotList.contentX = 0
        appPage.scrollScreenshotStripBy(-10, false)
        compare(screenshotList.contentX, 30)

        const touchpadScroll = findChild(screenshotList,
                                         "screenshotTouchpadScroll")
        verify(touchpadScroll !== null)
        compare(touchpadScroll.acceptedDevices, PointerDevice.TouchPad)

        screenshotList.contentX = 300
        window.showCatalogCalled = false
        const y = screenshotList.height / 2
        let swipe = touchEvent(screenshotList)
        swipe.press(0, screenshotList, screenshotList.width * 0.3, y).commit()
        swipe.move(0, screenshotList, screenshotList.width * 0.65, y).commit()
        swipe.release(0, screenshotList, screenshotList.width * 0.65, y).commit()
        compare(window.showCatalogCalled, false)
        // Qt Quick Test does not run ListView's platform touch-flick
        // recognizer, so the helper above covers direction while this real
        // touch sequence covers ownership (it must never trigger page-back).
    }

    function test_vertical_wheel_scrolls_without_gesture_blocking() {
        window.requestActivate()
        tryCompare(window, "active", true)

        const details = findChild(appPage, "detailsFlickable")
        const naturalScroll = findChild(appPage, "detailsNaturalScroll")
        verify(details !== null)
        verify(naturalScroll !== null)
        details.contentY = 0
        mouseWheel(details,
                   details.width / 2,
                   details.height / 2,
                   0,
                   -120,
                   Qt.NoButton)
        tryVerify(() => details.contentY > 0)
        wait(500)
        compare(naturalScroll.target, details)
        compare(naturalScroll.blockTargetWheel, true)
        compare(naturalScroll.scrollFlickableTarget, true)
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
        const wheelSurface = appPage.previewWindowWheelSurfaceItem
        const mouseWheelHandler = appPage.previewVerticalWheelHandler
        const previewImage = findChild(preview, "previewImage")
        const zoomInButton = findChild(preview, "previewZoomInButton")
        const zoomOutButton = findChild(preview, "previewZoomOutButton")
        const zoomLabel = findChild(preview, "previewZoomLabel")
        verify(frame !== null)
        verify(gestureSurface !== null)
        verify(wheelSurface !== null)
        verify(mouseWheelHandler !== null)
        verify((mouseWheelHandler.acceptedDevices & PointerDevice.Mouse) !== 0)
        verify((mouseWheelHandler.acceptedDevices & PointerDevice.TouchPad) !== 0)
        compare(findChild(appPage, "previewTouchpadVerticalPan"), null)
        verify(previewImage !== null)
        verify(zoomInButton !== null)
        verify(zoomOutButton !== null)
        compare(findChild(preview, "previewFitButton"), null)
        verify(zoomLabel !== null)
        tryCompare(previewImage, "status", Image.Ready)
        compare(appPage.previewZoom, 1)
        compare(zoomLabel.text, "100%")
        compare(zoomInButton.parent.objectName, "previewBottomControlRow")
        compare(appPage.wheelEventIsTouchpad({
                    deviceType: PointerDevice.Mouse,
                    pointerType: PointerDevice.Generic,
                    maximumPoints: 16
                }, true, 0, 120), false)
        compare(appPage.wheelEventIsTouchpad({
                    deviceType: PointerDevice.TouchPad,
                    pointerType: PointerDevice.Finger,
                    maximumPoints: 2,
                    buttonCount: 1
                }, true, 0, 120), true)
        compare(appPage.wheelEventIsTouchpad({
                    deviceType: PointerDevice.Mouse,
                    pointerType: PointerDevice.Generic,
                    maximumPoints: 1,
                    buttonCount: 5
                }, true, 0, 8), false)
        compare(appPage.wheelEventIsTouchpad({
                    deviceType: PointerDevice.Unknown,
                    pointerType: PointerDevice.Generic,
                    maximumPoints: 1,
                    buttonCount: 3
                }, true, 0, 8), false)
        compare(appPage.wheelEventIsMouse({
                    deviceType: PointerDevice.Unknown,
                    pointerType: PointerDevice.Unknown,
                    maximumPoints: 0
                }, 0, 120), true)
        compare(appPage.wheelEventIsTouchpad({
                    deviceType: PointerDevice.Unknown,
                    pointerType: PointerDevice.Unknown,
                    maximumPoints: 0
                }, true, 0, 120), false)

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

        appPage.resetPreviewTransform()
        compare(appPage.previewZoom, 1)
        compare(appPage.previewPanX, 0)
        compare(appPage.previewPanY, 0)
        const wheelFocus = gestureSurface.mapToItem(wheelSurface,
                                                     focusX, focusY)
        mouseWheel(wheelSurface,
                   wheelFocus.x,
                   wheelFocus.y,
                   0,
                   120,
                   Qt.NoButton)
        fuzzyCompare(appPage.previewZoom, 1.25, 0.0001)
        verify(appPage.previewPanX < 0)
        verify(appPage.previewPanY < 0)
        const sourceXAfterWheel = centerX
                                  + (focusX - centerX - appPage.previewPanX)
                                    / appPage.previewZoom
        verify(Math.abs(sourceXAfterWheel - sourceXBefore) < 0.01)
        verify(Math.abs(appPage.previewPanY)
               <= appPage.previewPanLimitY(appPage.previewZoom) + 0.01)

        const imagePointBeforeSecondWheel = appPage.previewImagePointAt(
                    focusX, focusY,
                    appPage.previewZoom,
                    appPage.previewPanX,
                    appPage.previewPanY)
        mouseWheel(wheelSurface,
                   wheelFocus.x,
                   wheelFocus.y,
                   0,
                   120,
                   Qt.NoButton)
        fuzzyCompare(appPage.previewZoom, 1.5625, 0.0001)
        const imagePointAfterSecondWheel = appPage.previewImagePointAt(
                    focusX, focusY,
                    appPage.previewZoom,
                    appPage.previewPanX,
                    appPage.previewPanY)
        verify(Math.abs(imagePointAfterSecondWheel.x
                        - imagePointBeforeSecondWheel.x) < 0.01)
        verify(Math.abs(appPage.previewPanY)
               <= appPage.previewPanLimitY(appPage.previewZoom) + 0.01)
        mouseWheel(wheelSurface,
                   wheelFocus.x,
                   wheelFocus.y,
                   0,
                   -120,
                   Qt.NoButton)
        fuzzyCompare(appPage.previewZoom, 1.25, 0.0001)
        appPage.resetPreviewTransform()
        const centeredFocus = appPage.mousePreviewZoomFocus(0, 0)
        appPage.zoomPreviewBy(1.2, centeredFocus.x, centeredFocus.y)
        compare(appPage.previewZoom, 1.2)
        compare(appPage.previewPanX, 0)
        compare(appPage.previewPanY, 0)
        appPage.resetPreviewTransform()
        mouseClick(zoomInButton, zoomInButton.width / 2, zoomInButton.height / 2)
        compare(appPage.previewZoom, 1.25)
        mouseClick(zoomOutButton, zoomOutButton.width / 2, zoomOutButton.height / 2)
        compare(appPage.previewZoom, 1)
    }

    function test_mouse_wheel_outside_photo_browses_one_screenshot_per_notch() {
        appPage.openScreenshot(1)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        const gestureSurface = findChild(preview, "previewGestureSurface")
        const verticalWheel = appPage.previewVerticalWheelHandler
        const wheelSurface = appPage.previewWindowWheelSurfaceItem
        const closeButton = findChild(preview, "previewCloseButton")
        verify(gestureSurface !== null)
        verify(verticalWheel !== null)
        verify(wheelSurface !== null)
        verify(closeButton !== null)

        const frameCorner = gestureSurface.mapToItem(wheelSurface, 0, 0)
        mouseWheel(wheelSurface,
                   frameCorner.x,
                   frameCorner.y,
                   0,
                   120,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 0)
        compare(appPage.previewZoom, 1)

        mouseWheel(wheelSurface,
                   frameCorner.x,
                   frameCorner.y,
                   0,
                   -120,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 1)
        compare(appPage.previewZoom, 1)

        const closePoint = closeButton.mapToItem(wheelSurface,
                                                  closeButton.width / 2,
                                                  closeButton.height / 2)
        mouseWheel(wheelSurface,
                   closePoint.x,
                   closePoint.y,
                   0,
                   120,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 0)
        compare(preview.visible, true)

        mouseWheel(wheelSurface,
                   2,
                   2,
                   0,
                   -120,
                   Qt.NoButton)
        compare(appPage.previewScreenshotIndex, 1)
        compare(preview.visible, true)
    }

    function test_thumbnail_highlight_without_preview_badge() {
        window.requestActivate()
        const list = findChild(appPage, "screenshotList")
        const thumbnail = list.itemAtIndex(0)
        verify(thumbnail !== null)
        mouseMove(thumbnail, thumbnail.width / 2, thumbnail.height / 2)
        tryCompare(thumbnail, "hovered", true)
        compare(thumbnail.background.border.color, window.accentColor)
        function hasBadge(item) {
            if (item.text === "Preview") return true
            return (item.children || []).some(child => hasBadge(child))
        }
        verify(!hasBadge(thumbnail))
    }
    function test_preview_controls_hover() {
        window.requestActivate()
        appPage.openScreenshot(1)
        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        appPage.setPreviewZoom(2)
        for (const name of ["previewCloseButton", "previewPreviousButton", "previewNextButton", "previewZoomInButton", "previewZoomOutButton"]) {
            const button = findChild(preview, name)
            verify(button.hoverEnabled)
            mouseMove(button, button.width / 2, button.height / 2)
            tryCompare(button, "hovered", true)
            compare(button.background.color, window.hoverColor)
        }
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
        compare(mousePan.acceptedDevices, PointerDevice.Mouse | PointerDevice.TouchPad)
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
        wait(20)

        compare(touchPan.touchPinching, false)
        compare(touchPan.pinchWasActive, false)
        compare(touchPan.pinchLastDistance, 1)
        const firstPinchZoom = appPage.previewZoom
        appPage.applyPreviewPinchStep(100, 150,
                                      centerX, centerY,
                                      0, 0)
        verify(appPage.previewZoom > firstPinchZoom)

        const secondPinchZoom = appPage.previewZoom
        appPage.applyPreviewPinchStep(160, 80,
                                      centerX, centerY,
                                      0, 0)
        verify(appPage.previewZoom < secondPinchZoom)

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
        mousePan.lastActiveTranslation = Qt.point(0, 0)
        mousePan.applyMouseTranslation(Qt.point(44, 28))
        verify(appPage.previewPanX > panXBeforeMouse)
        verify(appPage.previewPanY > panYBeforeMouse)

        appPage.resetPreviewTransform()
        appPage.applyPreviewPinchStep(1, 2,
                                      centerX + 60, centerY + 35,
                                      0, 0)
        compare(appPage.previewZoom, 2)
        compare(appPage.previewPanX, -60)
        compare(appPage.previewPanY, -35)

        appPage.resetPreviewTransform()
        appPage.applyPreviewPinchStep(1, 2,
                                      frame.width / 2, frame.height / 2,
                                      24, 16)
        compare(appPage.previewZoom, 2)
        compare(appPage.previewPanX, 24)
        compare(appPage.previewPanY, 16)
        appPage.panPreviewBy(-10, -6)
        compare(appPage.previewPanX, 14)
        compare(appPage.previewPanY, 10)

        appPage.resetPreviewTransform()
        const firstFocus = Qt.point(centerX + 45, centerY + 30)
        const firstTranslation = Qt.point(28, 18)
        const firstImagePoint = appPage.previewImagePointAt(
                    firstFocus.x, firstFocus.y,
                    appPage.previewZoom,
                    appPage.previewPanX,
                    appPage.previewPanY)
        appPage.applyPreviewPinchStep(1, 1.6,
                                      firstFocus.x, firstFocus.y,
                                      firstTranslation.x,
                                      firstTranslation.y)
        const firstPointAfter = appPage.previewImagePointAt(
                    firstFocus.x + firstTranslation.x,
                    firstFocus.y + firstTranslation.y,
                    appPage.previewZoom,
                    appPage.previewPanX,
                    appPage.previewPanY)
        verify(Math.abs(firstPointAfter.x - firstImagePoint.x) < 0.01)
        verify(Math.abs(firstPointAfter.y - firstImagePoint.y) < 0.01)

        const secondFocus = Qt.point(centerX - 35, centerY + 20)
        const secondTranslation = Qt.point(-22, 14)
        const secondImagePoint = appPage.previewImagePointAt(
                    secondFocus.x, secondFocus.y,
                    appPage.previewZoom,
                    appPage.previewPanX,
                    appPage.previewPanY)
        appPage.applyPreviewPinchStep(1, 1.35,
                                      secondFocus.x, secondFocus.y,
                                      secondTranslation.x,
                                      secondTranslation.y)
        const secondPointAfter = appPage.previewImagePointAt(
                    secondFocus.x + secondTranslation.x,
                    secondFocus.y + secondTranslation.y,
                    appPage.previewZoom,
                    appPage.previewPanX,
                    appPage.previewPanY)
        verify(Math.abs(secondPointAfter.x - secondImagePoint.x) < 0.01)
        verify(Math.abs(secondPointAfter.y - secondImagePoint.y) < 0.01)

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
