import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    required property var app
    property string previewScreenshot: ""
    readonly property alias screenshotPreviewDialog: screenshotPreview
    background: null
    header: Control {
        height: 70; padding: 0
        background: Rectangle { color: window.surfaceColor; border.color: window.borderColor; border.width: 1 }
        contentItem: RowLayout {
            anchors.leftMargin: 14; anchors.rightMargin: 24
            ToolButton {
                objectName: "backButton"
                text: "Back"
                icon.name: "go-previous"
                icon.width: 20
                icon.height: 20
                display: AbstractButton.TextBesideIcon
                implicitWidth: 94
                leftPadding: 12
                rightPadding: 14
                spacing: 7
                font.pixelSize: 15
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
            Label { text: app ? app.name : "Application"; color: window.textColor; font.pixelSize: 20; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
        }
    }
    Flickable {
        id: detailsFlickable
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: detailsLayout.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        DirectWheelScroll { scrollTarget: detailsFlickable; stepSize: 140 }

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
                    required property string modelData
                    width: 460; height: 276
                    hoverEnabled: true
                    Accessible.name: "Preview screenshot"
                    onClicked: {
                        page.previewScreenshot = modelData
                        screenshotPreview.open()
                    }
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

    Dialog {
        id: screenshotPreview
        parent: Overlay.overlay
        modal: true
        focus: true
        width: Math.min(1180, window.width - 72)
        height: Math.min(820, window.height - 72)
        x: Math.round((window.width - width) / 2)
        y: Math.round((window.height - height) / 2)
        padding: 14
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: page.previewScreenshot = ""
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
        background: Rectangle {
            radius: 10
            color: window.surfaceColor
            border.color: window.borderColor
            border.width: 1
        }
        contentItem: Item {
            Image {
                id: previewImage
                anchors.fill: parent
                anchors.margins: 8
                source: page.previewScreenshot
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }
            BusyIndicator {
                anchors.centerIn: parent
                running: previewImage.status === Image.Loading
                visible: running
            }
            ToolButton {
                objectName: "previewCloseButton"
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 4
                text: "×"
                font.pixelSize: 26
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
    }
}
