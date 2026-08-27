import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    required property var app
    property string previewScreenshot: ""
    property int previewScreenshotIndex: -1
    readonly property alias screenshotPreviewDialog: screenshotPreview

    function setPreviewIndex(index) {
        const screenshots = app && app.screenshots ? app.screenshots : []
        if (screenshots.length === 0)
            return
        const boundedIndex = Math.max(0, Math.min(screenshots.length - 1, index))
        previewScreenshotIndex = boundedIndex
        previewScreenshot = screenshots[boundedIndex]
    }

    function openScreenshot(index) {
        setPreviewIndex(index)
        screenshotPreview.open()
    }

    function movePreview(offset) {
        setPreviewIndex(previewScreenshotIndex + offset)
    }

    function finishPreviewSwipe(horizontalTravel, verticalTravel) {
        const shouldMove = Math.abs(horizontalTravel) >= 70
                           && Math.abs(horizontalTravel) > verticalTravel * 1.5
        if (shouldMove)
            movePreview(horizontalTravel > 0 ? -1 : 1)
        return shouldMove
    }

    function finishPageSwipe(horizontalTravel, verticalTravel) {
        const shouldGoBack = horizontalTravel >= Math.min(180, page.width * 0.18)
                                 && horizontalTravel > verticalTravel * 1.5
        if (shouldGoBack)
            window.showCatalog()
        return shouldGoBack
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
                    Image {
                        Layout.preferredWidth: 112; Layout.preferredHeight: 112
                        sourceSize: Qt.size(112, 112); fillMode: Image.PreserveAspectFit
                        source: {
                            if (!app || !app.icon) return "image://icon/application-x-executable"
                            if (app.icon.indexOf("/") >= 0 || app.icon.indexOf("://") >= 0)
                                return app.icon.indexOf("://") >= 0 ? app.icon : "file://" + app.icon
                            return "image://icon/" + app.icon
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
                Layout.fillWidth: true
                Layout.preferredHeight: count > 0 ? 290 : 0; visible: count > 0
                orientation: ListView.Horizontal; spacing: 16; clip: true
                model: app ? app.screenshots : []
                delegate: AbstractButton {
                    id: screenshotButton
                    objectName: "screenshotButton"
                    required property int index
                    required property string modelData
                    width: 460; height: 276
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
                            anchors.fill: parent
                            anchors.margins: 1
                            source: screenshotButton.modelData
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
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
            onPointChanged: {
                if (active) {
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
                } else {
                    page.finishPageSwipe(travel, verticalTravel)
                    travel = 0
                    verticalTravel = 0
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

    Dialog {
        id: screenshotPreview
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.max(360, Math.min(1040, Math.round(window.width * 0.84)))
        height: Math.max(320, Math.min(720, Math.round(window.height * 0.82)))
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)
        padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            previewTouchpadSwipe.travel = 0
            previewTouchpadSwipe.gestureTriggered = false
        }
        onClosed: {
            previewTouchpadSwipe.travel = 0
            previewTouchpadSwipe.gestureTriggered = false
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

                    Image {
                        id: previewImage
                        objectName: "previewImage"
                        anchors.fill: parent
                        source: page.previewScreenshot
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                    BusyIndicator {
                        anchors.centerIn: parent
                        running: previewImage.status === Image.Loading
                        visible: running
                    }
                    Item {
                        id: previewGestureSurface
                        objectName: "previewGestureSurface"
                        anchors.fill: parent

                        PointHandler {
                            id: previewTouchSwipe
                            objectName: "previewTouchSwipe"
                            target: null
                            acceptedDevices: PointerDevice.TouchScreen
                            acceptedButtons: Qt.NoButton
                            property real horizontalTravel: 0
                            property real verticalTravel: 0
                            property point startPosition: Qt.point(0, 0)
                            onPointChanged: {
                                if (active) {
                                    horizontalTravel = point.position.x - startPosition.x
                                    verticalTravel = Math.abs(point.position.y - startPosition.y)
                                }
                            }
                            onActiveChanged: {
                                if (active) {
                                    horizontalTravel = 0
                                    verticalTravel = 0
                                    startPosition = point.position
                                } else {
                                    page.finishPreviewSwipe(horizontalTravel, verticalTravel)
                                    horizontalTravel = 0
                                    verticalTravel = 0
                                }
                            }
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
                                if (gestureTriggered)
                                    return

                                const fingerDistance = event.inverted ? rawX : -rawX
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
                Layout.preferredHeight: 34

                Label {
                    objectName: "previewCounter"
                    anchors.centerIn: parent
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
