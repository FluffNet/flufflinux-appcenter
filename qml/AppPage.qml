import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    required property var app
    header: ToolBar {
        height: 64
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 22
            ToolButton {
                text: "‹"; font.pixelSize: 30; Accessible.name: "Back to app catalog"
                onClicked: window.showCatalog()
            }
            Label { text: app ? app.name : "Application"; font.pixelSize: 20; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
        }
    }
    ScrollView {
        anchors.fill: parent; clip: true
        ColumnLayout {
            width: Math.min(parent.width, 980); anchors.horizontalCenter: parent.horizontalCenter; spacing: 24
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32; Layout.topMargin: 36; spacing: 24
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
                    Label { Layout.fillWidth: true; text: app ? app.name : ""; font.pixelSize: 34; font.weight: Font.Bold; wrapMode: Text.WordWrap }
                    Label { Layout.fillWidth: true; text: app ? app.summary : ""; color: palette.placeholderText; font.pixelSize: 17; wrapMode: Text.WordWrap }
                    Label { text: app && app.developer ? "By " + app.developer : ""; visible: text.length > 0; color: palette.highlight }
                }
            }
            ListView {
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32
                Layout.preferredHeight: count > 0 ? 290 : 0; visible: count > 0
                orientation: ListView.Horizontal; spacing: 16; clip: true
                model: app ? app.screenshots : []
                delegate: Rectangle {
                    required property string modelData
                    width: 460; height: 276; radius: 10; color: palette.alternateBase; clip: true
                    Image { anchors.fill: parent; source: modelData; asynchronous: true; fillMode: Image.PreserveAspectFit }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32; spacing: 10
                Label { text: "About this app"; font.pixelSize: 23; font.weight: Font.Bold }
                Label {
                    Layout.fillWidth: true
                    text: app && app.description ? app.description : (app ? app.summary : "")
                    wrapMode: Text.WordWrap; font.pixelSize: 16; lineHeight: 1.25
                }
            }
            GridLayout {
                Layout.fillWidth: true; Layout.leftMargin: 32; Layout.rightMargin: 32; Layout.bottomMargin: 38
                columns: 2; columnSpacing: 28; rowSpacing: 10
                Label { text: "Category"; color: palette.placeholderText }
                Label { text: app ? app.category : ""; Layout.fillWidth: true }
                Label { text: "AppStream ID"; color: palette.placeholderText }
                Label { text: app ? app.id : ""; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: "License"; color: palette.placeholderText; visible: app && app.license }
                Label { text: app ? app.license : ""; Layout.fillWidth: true; visible: text.length > 0 }
                Label { text: "Website"; color: palette.placeholderText; visible: app && app.homepage }
                LinkButton {
                    text: app ? app.homepage : ""; visible: text.length > 0; Layout.fillWidth: true
                    onClicked: Qt.openUrlExternally(text)
                }
            }
        }
    }
}
