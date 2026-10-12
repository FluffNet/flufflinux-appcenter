import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Keep popup colors and wrapped titles consistent with the containing window.
Dialog {
    id: dialog
    palette.window: window.raisedSurfaceColor
    palette.windowText: window.textColor
    palette.text: window.textColor
    palette.base: window.backgroundColor
    palette.button: window.raisedSurfaceColor
    palette.buttonText: window.textColor
    background: Rectangle {
        color: window.raisedSurfaceColor
        border.color: window.borderColor
        radius: window.cornerRadius
    }
    header: Control {
        leftPadding: 16; rightPadding: 8; topPadding: 8; bottomPadding: 8
        contentItem: RowLayout {
            Label {
                objectName: "fluffDialogTitle"
                text: dialog.title; textFormat: Text.PlainText
                font.pixelSize: 20; color: window.textColor
                Layout.fillWidth: true; Layout.minimumWidth: 0
                wrapMode: Text.Wrap
            }
            FluffToolButton {
                Layout.preferredWidth: 44; Layout.preferredHeight: 44
                icon.name: "window-close"
                Accessible.name: qsTr("Close")
                onClicked: dialog.reject()
            }
        }
    }
}
