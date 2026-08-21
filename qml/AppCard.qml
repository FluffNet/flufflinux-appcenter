import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: card
    required property var app
    hoverEnabled: true
    implicitWidth: 250; implicitHeight: 130; padding: 18
    background: Rectangle {
        radius: 12
        color: card.down ? palette.midlight : card.hovered ? palette.alternateBase : palette.base
        border.color: card.activeFocus ? palette.highlight : palette.mid
        border.width: card.activeFocus ? 2 : 1
    }
    contentItem: RowLayout {
        spacing: 16
        Image {
            Layout.preferredWidth: 64; Layout.preferredHeight: 64; Layout.alignment: Qt.AlignTop
            sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectFit
            source: {
                if (!app.icon) return "image://icon/application-x-executable"
                if (app.icon.indexOf("/") >= 0 || app.icon.indexOf("://") >= 0)
                    return app.icon.indexOf("://") >= 0 ? app.icon : "file://" + app.icon
                return "image://icon/" + app.icon
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
            Label { Layout.fillWidth: true; text: app.name; font.pixelSize: 17; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Label {
                Layout.fillWidth: true; Layout.fillHeight: true
                text: app.summary || "Application for Fluff Linux"
                color: palette.placeholderText; wrapMode: Text.WordWrap; maximumLineCount: 3
                elide: Text.ElideRight; verticalAlignment: Text.AlignTop
            }
            Label { text: app.category; color: palette.highlight; font.pixelSize: 12 }
        }
    }
}
