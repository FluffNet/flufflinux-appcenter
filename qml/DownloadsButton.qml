import QtQuick
import QtQuick.Controls

ToolButton {
    id: control
    objectName: "downloadsButton"
    width: 52; height: 48
    visible: window.downloadQueue.activeCount > 0
    icon.name: "download"
    icon.width: 24; icon.height: 24
    icon.color: window.textColor
    bottomPadding: 8
    Accessible.name: qsTr("Downloads: %1 active, %2% complete")
        .arg(window.downloadQueue.activeCount).arg(Math.round(window.downloadQueue.progress * 100))
    ToolTip.visible: hovered
    ToolTip.text: qsTr("Downloads")
    onClicked: window.showDownloads()
    background: Rectangle {
        radius: 8
        color: control.hovered ? window.hoverColor : window.raisedSurfaceColor
        border.color: control.activeFocus ? window.accentColor : window.borderColor
        Rectangle {
            x: 6; y: parent.height - 7
            width: parent.width - 12; height: 3; radius: 1.5
            color: window.borderColor
            Rectangle {
                width: parent.width * window.downloadQueue.progress
                height: parent.height; radius: 1.5
                color: window.accentColor
            }
        }
    }
    Rectangle {
        anchors.right: parent.right; anchors.rightMargin: -5
        anchors.top: parent.top; anchors.topMargin: -5
        width: Math.max(22, countLabel.implicitWidth + 10); height: 22; radius: 11
        color: window.accentColor
        Label {
            id: countLabel
            anchors.centerIn: parent
            text: window.downloadQueue.activeCount
            color: "white"; font.pixelSize: 12; font.bold: true
        }
    }
}
