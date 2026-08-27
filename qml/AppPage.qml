import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    required property var app
    property string previewScreenshot: ""
    property int previewScreenshotIndex: -1
    property real previewZoom: 1
    property real previewPanX: 0
    property real previewPanY: 0
    property bool previewPinching: false
    readonly property real maximumPreviewZoom: 5
    readonly property alias screenshotPreviewDialog: screenshotPreview
    readonly property alias previewVerticalWheelHandler: previewVerticalWheel
    readonly property alias previewWindowWheelSurfaceItem: previewWindowWheelSurface

    function setPreviewIndex(index) {
        const screenshots = app && app.screenshots ? app.screenshots : []
        if (screenshots.length === 0)
            return
        const boundedIndex = Math.max(0, Math.min(screenshots.length - 1, index))
        resetPreviewTransform()
        previewScreenshotIndex = boundedIndex
        previewScreenshot = screenshots[boundedIndex]
    }

    function openScreenshot(index) {
        const screenshots = app && app.screenshots ? app.screenshots : []
        if (screenshots.length === 0)
            return false
        setPreviewIndex(index)
        screenshotPreview.open()
        return true
    }

    function movePreview(offset) {
        setPreviewIndex(previewScreenshotIndex + offset)
    }

    function finishPreviewSwipe(horizontalTravel, verticalTravel) {
        const shouldMove = previewZoom <= 1.001
                           && Math.abs(horizontalTravel) >= 70
                           && Math.abs(horizontalTravel) > verticalTravel * 1.5
        if (shouldMove)
            movePreview(horizontalTravel > 0 ? -1 : 1)
        return shouldMove
    }

    function previewPanLimitX(zoom) {
        if (!previewImageFrame || !previewImage)
            return 0
        return Math.max(0, previewImageFrame.width * (zoom - 1) / 2)
    }

    function previewPanLimitY(zoom) {
        if (!previewImageFrame || !previewImage)
            return 0
        return Math.max(0, previewImageFrame.height * (zoom - 1) / 2)
    }

    function setPreviewPan(x, y) {
        const limitX = previewPanLimitX(previewZoom)
        const limitY = previewPanLimitY(previewZoom)
        previewPanX = Math.max(-limitX, Math.min(limitX, x))
        previewPanY = Math.max(-limitY, Math.min(limitY, y))
    }

    function panPreviewBy(x, y) {
        setPreviewPan(previewPanX + x, previewPanY + y)
    }

    function wheelDeviceIsMouse(device) {
        return device
                && device.deviceType === PointerDevice.Mouse
                && device.pointerType !== PointerDevice.Finger
                && device.maximumPoints <= 1
    }

    function wheelEventIsMouse(device, angleX, angleY) {
        if (wheelDeviceIsMouse(device))
            return true

        // Some Wayland/X11 combinations attach incomplete pointing-device
        // metadata (and occasionally a pixel delta) to an ordinary wheel
        // event. A physical wheel still reports its standard 120-unit notch,
        // so use that as a reliable fallback instead of treating it as a
        // touchpad gesture.
        const dominantAngle = Math.abs(angleY) >= Math.abs(angleX)
                              ? Math.abs(angleY) : Math.abs(angleX)
        return dominantAngle >= 120
                && Math.abs(dominantAngle % 120) < 0.01
    }

    function wheelEventIsTouchpad(device, hasPixelDelta, angleX, angleY) {
        if (wheelEventIsMouse(device, angleX, angleY))
            return false
        return hasPixelDelta
                || (device
                    && (device.deviceType === PointerDevice.TouchPad
                        || device.pointerType === PointerDevice.Finger
                        || device.maximumPoints > 1))
    }

    function previewPointIsInsideImage(x, y) {
        if (!previewImageFrame || !previewImage
                || previewImage.status !== Image.Ready)
            return false

        const centerX = previewImageFrame.width / 2 + previewPanX
        const centerY = previewImageFrame.height / 2 + previewPanY
        const halfWidth = previewImage.paintedWidth * previewZoom / 2
        const halfHeight = previewImage.paintedHeight * previewZoom / 2
        return x >= centerX - halfWidth && x <= centerX + halfWidth
                && y >= centerY - halfHeight && y <= centerY + halfHeight
    }

    function mousePreviewZoomFocus(x, y) {
        const center = Qt.point(previewImageFrame.width / 2,
                                previewImageFrame.height / 2)
        if (!Number.isFinite(x) || !Number.isFinite(y)
                || !previewPointIsInsideImage(x, y))
            return center
        return Qt.point(x, y)
    }

    function previewImagePointAt(viewX, viewY, zoom, panX, panY) {
        const centerX = previewImageFrame.width / 2
        const centerY = previewImageFrame.height / 2
        return Qt.point(centerX + (viewX - centerX - panX) / zoom,
                        centerY + (viewY - centerY - panY) / zoom)
    }

    function previewPanForImagePoint(imagePoint, viewX, viewY, zoom) {
        const centerX = previewImageFrame.width / 2
        const centerY = previewImageFrame.height / 2
        return Qt.point(viewX - centerX
                        - zoom * (imagePoint.x - centerX),
                        viewY - centerY
                        - zoom * (imagePoint.y - centerY))
    }

    function setPreviewZoom(requestedZoom, focusX, focusY) {
        const oldZoom = previewZoom
        const newZoom = Math.max(1, Math.min(maximumPreviewZoom, requestedZoom))
        if (newZoom <= 1.001) {
            resetPreviewTransform()
            return
        }

        const centerX = previewImageFrame.width / 2
        const centerY = previewImageFrame.height / 2
        const safeFocusX = Number.isFinite(focusX) ? focusX : centerX
        const safeFocusY = Number.isFinite(focusY) ? focusY : centerY
        const imagePoint = previewImagePointAt(safeFocusX, safeFocusY,
                                               oldZoom,
                                               previewPanX, previewPanY)
        const nextPan = previewPanForImagePoint(imagePoint,
                                                safeFocusX, safeFocusY,
                                                newZoom)
        previewZoom = newZoom
        setPreviewPan(nextPan.x, nextPan.y)
    }

    function zoomPreviewBy(factor, focusX, focusY) {
        setPreviewZoom(previewZoom * factor, focusX, focusY)
    }

    function applyPreviewPinch(startZoom, startPanX, startPanY,
                               focusX, focusY, activeScale,
                               translationX, translationY) {
        const newZoom = Math.max(1,
                                 Math.min(maximumPreviewZoom,
                                          startZoom * activeScale))
        const centerX = previewImageFrame.width / 2
        const centerY = previewImageFrame.height / 2
        const ratio = newZoom / startZoom
        previewZoom = newZoom
        setPreviewPan(focusX + translationX - centerX
                      - ratio * (focusX - centerX - startPanX),
                      focusY + translationY - centerY
                      - ratio * (focusY - centerY - startPanY))
    }

    function resetPreviewTransform() {
        previewZoom = 1
        previewPanX = 0
        previewPanY = 0
        previewPinching = false
    }

    function finishPageSwipe(horizontalTravel, verticalTravel) {
        const shouldGoBack = horizontalTravel >= Math.min(180, page.width * 0.18)
                                 && horizontalTravel > verticalTravel * 1.5
        if (shouldGoBack)
            window.showCatalog()
        return shouldGoBack
    }

    function pointIsInsideScreenshotStrip(x, y) {
        if (!screenshotList || !screenshotList.visible)
            return false
        const topLeft = screenshotList.mapToItem(pageSwipeSurface, 0, 0)
        return x >= topLeft.x && x <= topLeft.x + screenshotList.width
                && y >= topLeft.y && y <= topLeft.y + screenshotList.height
    }

    function scrollScreenshotStripBy(fingerDistanceX, hasPixelDelta) {
        const minimum = screenshotList.originX
        const maximum = Math.max(minimum,
                                 minimum + screenshotList.contentWidth
                                 - screenshotList.width)
        const scale = hasPixelDelta ? 2.15 : 42
        screenshotList.contentX = Math.max(minimum,
                                           Math.min(maximum,
                                                    screenshotList.contentX
                                                    - fingerDistanceX * scale))
    }

    background: null
    header: Control {
        height: 70; padding: 0
        background: Rectangle { color: window.surfaceColor; border.color: window.borderColor; border.width: 1 }
        contentItem: RowLayout {
            anchors.leftMargin: 14; anchors.rightMargin: 24
            ToolButton {
                objectName: "backButton"
                text: "←  Back"
                implicitWidth: 106
                leftPadding: 12
                rightPadding: 14
                font.pixelSize: 16
                font.weight: Font.DemiBold
                palette.buttonText: window.textColor
                Accessible.name: "Back to app catalog"
                background: Rectangle {
                    radius: 6
                    color: parent.hovered ? window.hoverColor : "transparent"
                    border.color: parent.activeFocus ? window.accentColor : "transparent"
                }
                onClicked: window.showCatalog()
            }
            Item { Layout.fillWidth: true }
        }
    }
    Flickable {
        id: detailsFlickable
        objectName: "detailsFlickable"
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: detailsLayout.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        NaturalWheelScroll {
            objectName: "detailsNaturalScroll"
            scrollTarget: detailsFlickable
        }
        ColumnLayout {
            id: detailsLayout
            width: Math.min(1120, detailsFlickable.width - 64)
            x: Math.max(32, (detailsFlickable.width - width) / 2)
            spacing: 24

            Rectangle {
                Layout.fillWidth: true; Layout.topMargin: 32
                implicitHeight: Math.max(172, heroLayout.implicitHeight + 52)
                radius: 9; color: window.surfaceColor
                border.color: window.borderColor; border.width: 1
                RowLayout {
                    id: heroLayout
                    anchors.fill: parent; anchors.margins: 26; spacing: 24
                    Item {
                        Layout.preferredWidth: 112
                        Layout.preferredHeight: 112

                        Image {
                            id: heroIcon
                            anchors.fill: parent
                            sourceSize: Qt.size(112, 112)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            source: {
                                if (!app || !app.icon) return "image://icon/application-x-executable"
                                if (app.icon.indexOf("/") >= 0 || app.icon.indexOf("://") >= 0)
                                    return app.icon.indexOf("://") >= 0 ? app.icon : "file://" + app.icon
                                return "image://icon/" + app.icon
                            }
                        }
                        LoadingSpinner {
                            objectName: "heroIconLoadingSpinner"
                            anchors.centerIn: parent
                            running: heroIcon.status === Image.Loading
                            color: window.textColor
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 7
                        Label { Layout.fillWidth: true; text: app ? app.name : ""; color: window.textColor; font.pixelSize: 34; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
                        Label { Layout.fillWidth: true; text: app ? app.summary : ""; color: window.mutedTextColor; font.pixelSize: 17; wrapMode: Text.WordWrap }
                        Label { text: app && app.developer ? "By " + app.developer : ""; visible: text.length > 0; color: window.accentColor; font.weight: Font.DemiBold }
                    }
                }
            }
            ListView {
                id: screenshotList
                objectName: "screenshotList"
                Layout.fillWidth: true
                readonly property bool singleImage: count === 1
                readonly property real singleImageWidth: Math.min(width, 820)
                implicitHeight: count > 0 ? (singleImage ? 390 : 290) : 0
                Layout.preferredHeight: implicitHeight
                visible: count > 0
                orientation: ListView.Horizontal
                flickableDirection: Flickable.HorizontalFlick
                spacing: 16
                clip: true
                model: app ? app.screenshots : []
                WheelHandler {
                    id: screenshotTouchpadScroll
                    objectName: "screenshotTouchpadScroll"
                    target: null
                    orientation: Qt.Horizontal
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    blocking: true
                    onWheel: function(event) {
                        const hasPixelDelta = event.pixelDelta.x !== 0
                                              || event.pixelDelta.y !== 0
                        if (!page.wheelEventIsTouchpad(point.device,
                                                       hasPixelDelta,
                                                       event.angleDelta.x,
                                                       event.angleDelta.y)) {
                            event.accepted = false
                            return
                        }

                        const rawX = event.pixelDelta.x !== 0
                                     ? event.pixelDelta.x
                                     : event.angleDelta.x / 120
                        const rawY = event.pixelDelta.y !== 0
                                     ? event.pixelDelta.y
                                     : event.angleDelta.y / 120
                        if (rawX === 0 || Math.abs(rawX) <= Math.abs(rawY)) {
                            event.accepted = false
                            return
                        }

                        const fingerDistance = event.inverted ? rawX : -rawX
                        page.scrollScreenshotStripBy(fingerDistance,
                                                     hasPixelDelta)
                        event.accepted = true
                    }
                }
                header: Item {
                    width: screenshotList.singleImage
                           ? Math.max(0, (screenshotList.width
                                          - screenshotList.singleImageWidth) / 2)
                           : 0
                    height: 1
                }
                delegate: AbstractButton {
                    id: screenshotButton
                    objectName: "screenshotButton"
                    required property int index
                    required property string modelData
                    width: screenshotList.singleImage
                           ? screenshotList.singleImageWidth
                           : 460
                    height: screenshotList.singleImage
                            ? screenshotList.height
                            : 276
                    hoverEnabled: true
                    Accessible.name: "Preview screenshot"
                    onClicked: page.openScreenshot(index)
                    background: Rectangle {
                        radius: 8
                        color: window.raisedSurfaceColor
                        border.color: screenshotButton.activeFocus || screenshotButton.hovered
                                      ? window.accentColor
                                      : window.borderColor
                        border.width: screenshotButton.activeFocus ? 2 : 1
                    }
                    contentItem: Item {
                        clip: true
                        Image {
                            id: screenshotThumbnail
                            anchors.fill: parent
                            anchors.margins: 1
                            source: screenshotButton.modelData
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                        }
                        LoadingSpinner {
                            objectName: "screenshotLoadingSpinner"
                            anchors.centerIn: parent
                            running: screenshotThumbnail.status === Image.Loading
                            color: window.textColor
                        }
                        Label {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 12
                            visible: screenshotButton.hovered || screenshotButton.activeFocus
                            text: "Preview"
                            color: "white"
                            padding: 7
                            background: Rectangle {
                                radius: 5
                                color: Qt.rgba(0, 0, 0, 0.72)
                            }
                        }
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: aboutLayout.implicitHeight + 44; radius: 9
                color: window.surfaceColor; border.color: window.borderColor; border.width: 1
                ColumnLayout {
                    id: aboutLayout
                    anchors.fill: parent; anchors.margins: 22; spacing: 10
                    Label { text: "About this app"; color: window.textColor; font.pixelSize: 23; font.weight: Font.DemiBold }
                    Label {
                        Layout.fillWidth: true
                        text: app && app.description ? app.description : (app ? app.summary : "")
                        color: window.textColor; wrapMode: Text.WordWrap; font.pixelSize: 16; lineHeight: 1.25
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true; Layout.bottomMargin: 38
                columns: 2; columnSpacing: 28; rowSpacing: 10
                Label { text: "Category"; color: window.mutedTextColor }
                Label { text: app ? app.category : ""; color: window.textColor; Layout.fillWidth: true }
                Label { text: "AppStream ID"; color: window.mutedTextColor }
                Label { text: app ? app.id : ""; color: window.textColor; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: "License"; color: window.mutedTextColor; visible: app && app.license }
                Label { text: app ? app.license : ""; color: window.textColor; Layout.fillWidth: true; visible: text.length > 0 }
                Label { text: "Website"; color: window.mutedTextColor; visible: app && app.homepage }
                Button {
                    text: app ? app.homepage : ""; visible: text.length > 0; Layout.fillWidth: true
                    flat: true
                    palette.buttonText: window.accentColor
                    font.weight: Font.DemiBold
                    onClicked: Qt.openUrlExternally(text)
                }
            }
        }
    }

    Item {
        id: pageSwipeSurface
        objectName: "pageSwipeSurface"
        anchors.fill: parent
        z: 10

        PointHandler {
            id: pageTouchBackGesture
            objectName: "pageTouchBackGesture"
            target: null
            acceptedDevices: PointerDevice.TouchScreen
            acceptedButtons: Qt.NoButton
            property real travel: 0
            property real verticalTravel: 0
            property point startPosition: Qt.point(0, 0)
            property bool startedInsideScreenshotStrip: false
            onPointChanged: {
                if (active && !startedInsideScreenshotStrip) {
                    travel = Math.max(travel, point.position.x - startPosition.x)
                    verticalTravel = Math.max(verticalTravel,
                                              Math.abs(point.position.y - startPosition.y))
                }
            }
            onActiveChanged: {
                if (active) {
                    travel = 0
                    verticalTravel = 0
                    startPosition = point.position
                    startedInsideScreenshotStrip = page.pointIsInsideScreenshotStrip(
                                startPosition.x, startPosition.y)
                } else {
                    if (!startedInsideScreenshotStrip)
                        page.finishPageSwipe(travel, verticalTravel)
                    travel = 0
                    verticalTravel = 0
                    startedInsideScreenshotStrip = false
                }
            }
        }
        WheelHandler {
            id: pageTouchpadBackGesture
            objectName: "pageTouchpadBackGesture"
            target: null
            orientation: Qt.Horizontal
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: !screenshotPreview.visible
            blocking: false
            property real travel: 0
            onWheel: function(event) {
                if (page.pointIsInsideScreenshotStrip(event.x, event.y)) {
                    travel = 0
                    event.accepted = false
                    return
                }

                const rawX = event.pixelDelta.x !== 0
                             ? event.pixelDelta.x
                             : event.angleDelta.x / 2
                const rawY = event.pixelDelta.y !== 0
                             ? event.pixelDelta.y
                             : event.angleDelta.y / 2
                if (rawX === 0 || Math.abs(rawX) <= Math.abs(rawY))
                    return

                const fingerDistance = event.inverted ? rawX : -rawX
                travel += fingerDistance
                if (travel >= 80) {
                    travel = 0
                    window.showCatalog()
                }
            }
            onActiveChanged: {
                if (!active)
                    travel = 0
            }
        }
    }

    Item {
        id: previewWindowWheelSurface
        objectName: "previewWindowWheelSurface"
        parent: Overlay.overlay
        anchors.fill: parent
        visible: screenshotPreview.visible
        z: screenshotPreview.z + 1

        WheelHandler {
            id: previewVerticalWheel
            objectName: "previewVerticalWheel"
            target: null
            orientation: Qt.Vertical
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            blocking: true
            onWheel: function(event) {
                const rawX = event.pixelDelta.x !== 0
                             ? event.pixelDelta.x
                             : event.angleDelta.x
                const rawY = event.pixelDelta.y !== 0
                             ? event.pixelDelta.y
                             : event.angleDelta.y
                if (rawY === 0 || Math.abs(rawY) <= Math.abs(rawX)) {
                    event.accepted = false
                    return
                }

                const framePoint = previewImageFrame.mapFromItem(
                                     previewWindowWheelSurface,
                                     event.x, event.y)
                const overImage = page.previewPointIsInsideImage(
                                    framePoint.x, framePoint.y)
                event.accepted = true
                const hasPixelDelta = event.pixelDelta.x !== 0
                                      || event.pixelDelta.y !== 0
                const isTouchpad = page.wheelEventIsTouchpad(
                            point.device, hasPixelDelta,
                            event.angleDelta.x,
                            event.angleDelta.y)
                if (isTouchpad) {
                    if (overImage && page.previewZoom > 1.001) {
                        const fingerDistance = event.inverted ? rawY : -rawY
                        page.panPreviewBy(0, fingerDistance)
                    }
                    return
                }

                if (overImage) {
                    const steps = event.angleDelta.y / 120
                    page.zoomPreviewBy(Math.pow(1.2, steps),
                                       framePoint.x, framePoint.y)
                } else {
                    // The entire window browses photos while the modal is
                    // open; only visible photo pixels are reserved for zoom.
                    page.movePreview(event.angleDelta.y > 0 ? -1 : 1)
                }
            }
        }
    }

    Dialog {
        id: screenshotPreview
        parent: Overlay.overlay
        modal: true
        focus: true
        readonly property real desiredWidth: Math.max(360,
                                                       Math.min(window.width - 48,
                                                                Math.round(window.width * 0.78)))
        readonly property real desiredHeight: Math.max(320,
                                                        Math.min(window.height - 48,
                                                                 Math.round(window.height * 0.78)))
        width: desiredWidth
        height: desiredHeight
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)
        padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onDesiredWidthChanged: width = desiredWidth
        onDesiredHeightChanged: height = desiredHeight
        onAboutToShow: {
            width = desiredWidth
            height = desiredHeight
        }
        onOpened: {
            previewTouchpadSwipe.travel = 0
            previewTouchpadSwipe.gestureTriggered = false
            previewTouchArea.resetTouchGesture()
        }
        onClosed: {
            previewTouchpadSwipe.travel = 0
            previewTouchpadSwipe.gestureTriggered = false
            previewTouchArea.resetTouchGesture()
            page.resetPreviewTransform()
            page.previewScreenshot = ""
            page.previewScreenshotIndex = -1
        }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
        background: Rectangle {
            radius: 10
            color: window.surfaceColor
            border.color: window.borderColor
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: 8

            Item {
                objectName: "previewTopControls"
                Layout.fillWidth: true
                Layout.preferredHeight: 42

                ToolButton {
                    objectName: "previewCloseButton"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    text: "×"
                    font.pixelSize: 24
                    Accessible.name: "Close screenshot preview"
                    onClicked: screenshotPreview.close()
                    palette.buttonText: window.textColor
                    background: Rectangle {
                        radius: width / 2
                        color: parent.hovered ? window.hoverColor : window.raisedSurfaceColor
                        border.color: window.borderColor
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Item {
                    objectName: "previewPreviousControls"
                    Layout.preferredWidth: 46
                    Layout.fillHeight: true

                    ToolButton {
                        objectName: "previewPreviousButton"
                        anchors.centerIn: parent
                        width: 42
                        height: 42
                        text: "←"
                        font.pixelSize: 25
                        visible: page.previewScreenshotIndex > 0
                        Accessible.name: "Previous screenshot"
                        onClicked: page.movePreview(-1)
                        palette.buttonText: window.textColor
                        background: Rectangle {
                            radius: width / 2
                            color: parent.hovered ? window.hoverColor : window.raisedSurfaceColor
                            border.color: window.borderColor
                        }
                    }
                }

                Item {
                    id: previewImageFrame
                    objectName: "previewImageFrame"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    onWidthChanged: page.setPreviewPan(page.previewPanX, page.previewPanY)
                    onHeightChanged: page.setPreviewPan(page.previewPanX, page.previewPanY)

                    Image {
                        id: previewImage
                        objectName: "previewImage"
                        width: parent.width
                        height: parent.height
                        x: page.previewPanX
                        y: page.previewPanY
                        scale: page.previewZoom
                        transformOrigin: Item.Center
                        source: page.previewScreenshot
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        onPaintedWidthChanged: page.setPreviewPan(page.previewPanX,
                                                                 page.previewPanY)
                        onPaintedHeightChanged: page.setPreviewPan(page.previewPanX,
                                                                  page.previewPanY)
                    }
                    LoadingSpinner {
                        objectName: "previewLoadingSpinner"
                        anchors.centerIn: parent
                        running: previewImage.status === Image.Loading
                        color: window.textColor
                    }
                    Item {
                        id: previewGestureSurface
                        objectName: "previewGestureSurface"
                        anchors.fill: parent

                        MultiPointTouchArea {
                            id: previewTouchArea
                            objectName: "previewTouchSwipe"
                            anchors.fill: parent
                            minimumTouchPoints: 1
                            maximumTouchPoints: 2
                            mouseEnabled: false
                            property real horizontalTravel: 0
                            property real verticalTravel: 0
                            property point startPosition: Qt.point(0, 0)
                            property point lastPosition: Qt.point(0, 0)
                            property bool singleTouchActive: false
                            property bool pinchWasActive: false
                            property real pinchStartDistance: 1
                            property point pinchStartCenter: Qt.point(0, 0)
                            property real pinchStartZoom: 1
                            property real pinchStartPanX: 0
                            property real pinchStartPanY: 0

                            function resetTouchGesture() {
                                horizontalTravel = 0
                                verticalTravel = 0
                                singleTouchActive = false
                                pinchWasActive = false
                                page.previewPinching = false
                            }

                            function handleTouches(points) {
                                const activePoints = []
                                for (let index = 0; index < points.length; ++index) {
                                    if (points[index].pressed)
                                        activePoints.push(points[index])
                                }

                                if (activePoints.length >= 2) {
                                    const first = activePoints[0]
                                    const second = activePoints[1]
                                    const deltaX = second.x - first.x
                                    const deltaY = second.y - first.y
                                    const distance = Math.max(1,
                                                              Math.sqrt(deltaX * deltaX
                                                                        + deltaY * deltaY))
                                    const center = Qt.point((first.x + second.x) / 2,
                                                            (first.y + second.y) / 2)
                                    if (!page.previewPinching) {
                                        page.previewPinching = true
                                        pinchWasActive = true
                                        pinchStartDistance = distance
                                        pinchStartCenter = center
                                        pinchStartZoom = page.previewZoom
                                        pinchStartPanX = page.previewPanX
                                        pinchStartPanY = page.previewPanY
                                    } else {
                                        page.applyPreviewPinch(pinchStartZoom,
                                                               pinchStartPanX,
                                                               pinchStartPanY,
                                                               pinchStartCenter.x,
                                                               pinchStartCenter.y,
                                                               distance / pinchStartDistance,
                                                               center.x - pinchStartCenter.x,
                                                               center.y - pinchStartCenter.y)
                                    }
                                    lastPosition = center
                                    return
                                }

                                if (activePoints.length === 1) {
                                    const point = activePoints[0]
                                    if (page.previewPinching) {
                                        page.previewPinching = false
                                        singleTouchActive = false
                                    }
                                    if (!singleTouchActive) {
                                        singleTouchActive = true
                                        startPosition = Qt.point(point.x, point.y)
                                        lastPosition = startPosition
                                    } else if (!pinchWasActive) {
                                        if (page.previewZoom > 1.001) {
                                            page.panPreviewBy(point.x - lastPosition.x,
                                                              point.y - lastPosition.y)
                                        } else {
                                            horizontalTravel = point.x - startPosition.x
                                            verticalTravel = Math.abs(point.y - startPosition.y)
                                        }
                                        lastPosition = Qt.point(point.x, point.y)
                                    }
                                    return
                                }

                                if (singleTouchActive && !pinchWasActive)
                                    page.finishPreviewSwipe(horizontalTravel, verticalTravel)
                                resetTouchGesture()
                            }

                            onTouchUpdated: function(points) {
                                handleTouches(points)
                            }
                            onCanceled: function(points) {
                                resetTouchGesture()
                            }
                            onGestureStarted: function(gesture) {
                                gesture.grab()
                            }
                        }
                        MouseArea {
                            id: previewMousePan
                            objectName: "previewMousePan"
                            anchors.fill: parent
                            enabled: page.previewZoom > 1.001
                            acceptedButtons: Qt.LeftButton
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            property real lastX: 0
                            property real lastY: 0
                            onPressed: function(mouse) {
                                lastX = mouse.x
                                lastY = mouse.y
                            }
                            onPositionChanged: function(mouse) {
                                if (!pressed)
                                    return
                                page.panPreviewBy(mouse.x - lastX, mouse.y - lastY)
                                lastX = mouse.x
                                lastY = mouse.y
                            }
                            onWheel: function(event) {
                                event.accepted = false
                            }
                        }
                        PinchHandler {
                            id: previewTouchpadPinch
                            objectName: "previewTouchpadPinch"
                            target: null
                            acceptedDevices: PointerDevice.TouchPad
                            rotationAxis.enabled: false
                            property real startZoom: 1
                            property real startPanX: 0
                            property real startPanY: 0
                            property point startFocus: Qt.point(0, 0)

                            function applyPinch() {
                                if (!active)
                                    return
                                page.applyPreviewPinch(startZoom, startPanX, startPanY,
                                                       startFocus.x, startFocus.y,
                                                       activeScale,
                                                       activeTranslation.x,
                                                       activeTranslation.y)
                            }

                            onActiveChanged: {
                                page.previewPinching = active
                                if (active) {
                                    startZoom = page.previewZoom
                                    startPanX = page.previewPanX
                                    startPanY = page.previewPanY
                                    startFocus = centroid.position
                                } else {
                                    page.setPreviewPan(page.previewPanX, page.previewPanY)
                                }
                            }
                            onActiveScaleChanged: applyPinch()
                            onActiveTranslationChanged: applyPinch()
                        }
                        WheelHandler {
                            id: previewTouchpadSwipe
                            objectName: "previewTouchpadSwipe"
                            target: null
                            orientation: Qt.Horizontal
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            blocking: true
                            property real travel: 0
                            property bool gestureTriggered: false
                            onWheel: function(event) {
                                const rawX = event.pixelDelta.x !== 0
                                             ? event.pixelDelta.x
                                             : event.angleDelta.x / 2
                                const rawY = event.pixelDelta.y !== 0
                                             ? event.pixelDelta.y
                                             : event.angleDelta.y / 2
                                if (rawX === 0 || Math.abs(rawX) <= Math.abs(rawY)) {
                                    event.accepted = false
                                    return
                                }

                                event.accepted = true
                                const fingerDistance = event.inverted ? rawX : -rawX
                                if (page.previewZoom > 1.001) {
                                    page.panPreviewBy(fingerDistance, 0)
                                    return
                                }
                                if (gestureTriggered)
                                    return

                                travel += fingerDistance
                                if (travel >= 70) {
                                    gestureTriggered = true
                                    page.movePreview(-1)
                                } else if (travel <= -70) {
                                    gestureTriggered = true
                                    page.movePreview(1)
                                }
                            }
                            onActiveChanged: {
                                if (!active) {
                                    travel = 0
                                    gestureTriggered = false
                                }
                            }
                        }
                    }
                }

                Item {
                    objectName: "previewNextControls"
                    Layout.preferredWidth: 46
                    Layout.fillHeight: true

                    ToolButton {
                        objectName: "previewNextButton"
                        anchors.centerIn: parent
                        width: 42
                        height: 42
                        text: "→"
                        font.pixelSize: 25
                        visible: app && page.previewScreenshotIndex < app.screenshots.length - 1
                        Accessible.name: "Next screenshot"
                        onClicked: page.movePreview(1)
                        palette.buttonText: window.textColor
                        background: Rectangle {
                            radius: width / 2
                            color: parent.hovered ? window.hoverColor : window.raisedSurfaceColor
                            border.color: window.borderColor
                        }
                    }
                }
            }

            Item {
                objectName: "previewBottomControls"
                Layout.fillWidth: true
                Layout.preferredHeight: 46

                RowLayout {
                    objectName: "previewBottomControlRow"
                    anchors.centerIn: parent
                    spacing: 6

                    ToolButton {
                        objectName: "previewZoomOutButton"
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "−"
                        font.pixelSize: 24
                        enabled: page.previewZoom > 1.001
                        Accessible.name: "Zoom out"
                        onClicked: page.zoomPreviewBy(1 / 1.25,
                                                      previewImageFrame.width / 2,
                                                      previewImageFrame.height / 2)
                    }
                    Label {
                        objectName: "previewZoomLabel"
                        Layout.preferredWidth: 56
                        horizontalAlignment: Text.AlignHCenter
                        text: Math.round(page.previewZoom * 100) + "%"
                        color: window.textColor
                    }
                    ToolButton {
                        objectName: "previewZoomInButton"
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        text: "+"
                        font.pixelSize: 22
                        enabled: page.previewZoom < page.maximumPreviewZoom - 0.001
                        Accessible.name: "Zoom in"
                        onClicked: page.zoomPreviewBy(1.25,
                                                      previewImageFrame.width / 2,
                                                      previewImageFrame.height / 2)
                    }
                    ToolButton {
                        objectName: "previewFitButton"
                        Layout.preferredHeight: 44
                        text: "Fit"
                        enabled: page.previewZoom > 1.001
                        Accessible.name: "Fit screenshot to preview"
                        onClicked: page.resetPreviewTransform()
                    }
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 24
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        color: window.borderColor
                    }
                    Label {
                        objectName: "previewCounter"
                        visible: app && app.screenshots.length > 1
                        text: (page.previewScreenshotIndex + 1) + " / " + app.screenshots.length
                        color: window.textColor
                        padding: 6
                        background: Rectangle {
                            radius: 5
                            color: window.raisedSurfaceColor
                            border.color: window.borderColor
                        }
                    }
                }
            }
        }
    }
}
