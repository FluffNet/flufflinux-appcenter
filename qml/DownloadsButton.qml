import QtQuick
import QtQuick.Controls

ToolButton {
    id: control
    hoverEnabled: true
    objectName: "downloadsButton"
    focusPolicy: Qt.NoFocus
    width: Math.max(146, implicitWidth); height: 48
    text: qsTr("Queue")
    display: AbstractButton.TextBesideIcon
    spacing: 10
    leftPadding: 14; rightPadding: 14
    palette.buttonText: window.textColor
    readonly property bool unreadResult: window.downloadQueue.activeCount === 0
                                        && !window.downloadQueue.completionSeen
    visible: window.downloadQueue.buttonVisible
    contentItem: Row {
        spacing: control.spacing
        DownloadArrow {
            width: 24; height: 24
            anchors.verticalCenter: parent.verticalCenter
            color: window.textColor
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: control.text
            font: control.font
            color: window.textColor
        }
    }
    bottomPadding: 8
    Accessible.name: window.downloadQueue.activeCount === 0
        ? (window.downloadQueue.hasError ? qsTr("Queue finished with errors") : qsTr("Queue complete"))
        : qsTr("Queue: %1 active, %2% complete")
        .arg(window.downloadQueue.activeCount).arg(Math.round(window.downloadQueue.progress * 100))
    ToolTip.visible: hovered
    ToolTip.text: qsTr("Queue")
    onClicked: window.showDownloads()
    background: Rectangle {
        radius: window.cornerRadius
        border.width: control.activeFocus ? 2 : 1
        color: control.hovered ? window.hoverColor : window.raisedSurfaceColor
        border.color: control.activeFocus ? window.accentColor : window.borderColor
        Rectangle {
            visible: window.downloadQueue.activeCount > 0
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
        visible: window.downloadQueue.activeCount > 0 || control.unreadResult
        anchors.right: parent.right; anchors.rightMargin: -5
        anchors.top: parent.top; anchors.topMargin: -5
        width: Math.max(22, countLabel.implicitWidth + 10); height: 22; radius: 11
        color: control.unreadResult && !window.downloadQueue.hasError ? "#18763a" : window.accentColor
        Label {
            id: countLabel
            anchors.centerIn: parent
            text: control.unreadResult ? (window.downloadQueue.hasError ? "×" : "✓")
                                      : window.downloadQueue.activeCount
            color: "white"; font.pixelSize: 12; font.bold: true
        }
    }
}
