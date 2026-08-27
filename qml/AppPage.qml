import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    required property var app
    background: null
    header: Control {
        height: 70; padding: 0
        background: Rectangle { color: window.surfaceColor; border.color: window.borderColor; border.width: 1 }
        contentItem: RowLayout {
            anchors.leftMargin: 14; anchors.rightMargin: 24
            ToolButton {
                text: "‹"; font.pixelSize: 30; palette.buttonText: window.textColor
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
    ScrollView {
        anchors.fill: parent; clip: true
        ColumnLayout {
            width: Math.min(parent.width, 980); anchors.horizontalCenter: parent.horizontalCenter; spacing: 24
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32; Layout.topMargin: 32
                implicitHeight: 172; radius: 9; color: window.surfaceColor
                border.color: window.borderColor; border.width: 1
                RowLayout {
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
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32
                Layout.preferredHeight: count > 0 ? 290 : 0; visible: count > 0
                orientation: ListView.Horizontal; spacing: 16; clip: true
                model: app ? app.screenshots : []
                delegate: Rectangle {
                    required property string modelData
                    width: 460; height: 276; radius: 8; color: window.raisedSurfaceColor; clip: true
                    border.color: window.borderColor; border.width: 1
                    Image { anchors.fill: parent; source: modelData; asynchronous: true; fillMode: Image.PreserveAspectFit }
                }
            }
            Rectangle {
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32
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
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32; Layout.bottomMargin: 38
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
}
