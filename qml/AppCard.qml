import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: card
    required property var app
    hoverEnabled: true
    implicitWidth: 250; implicitHeight: 142; padding: 18
    scale: down ? 0.985 : 1
    Behavior on scale { NumberAnimation { duration: 90 } }
    background: Rectangle {
        radius: window.cornerRadius
        color: card.down || card.hovered ? window.hoverColor : window.surfaceColor
        border.color: card.activeFocus ? window.accentColor : card.hovered ? Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, 0.55) : window.borderColor
        border.width: card.activeFocus ? 2 : 1
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    contentItem: RowLayout {
        spacing: 16
        Item {
            Layout.preferredWidth: 64; Layout.preferredHeight: 64; Layout.alignment: Qt.AlignTop

            AppIcon {
                id: appIcon
                anchors.fill: parent
                sourceSize: Qt.size(64, 64)
                icon: app.icon || ""
            }
            LoadingSpinner {
                anchors.centerIn: parent
                width: 26
                height: 26
                running: appIcon.status === Image.Loading
                color: window.textColor
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 6
            Label { Layout.fillWidth: true; text: app.name; color: window.textColor; font.pixelSize: 18; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Label {
                Layout.fillWidth: true; Layout.fillHeight: true
                text: app.summary || "Application for Fluff Linux"
                color: window.mutedTextColor; wrapMode: Text.WordWrap; maximumLineCount: 3
                elide: Text.ElideRight; verticalAlignment: Text.AlignTop
            }
            Label { text: app.category; color: window.accentColor; font.pixelSize: 12; font.weight: Font.DemiBold }
        }
    }
}
