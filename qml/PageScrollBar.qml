import QtQuick
import QtQuick.Controls

ScrollBar {
    id: control
    orientation: Qt.Vertical
    policy: ScrollBar.AlwaysOn
    // Breeze otherwise disables dragging after detecting touchscreen input.
    interactive: true
    hoverEnabled: true
    width: 16
    padding: 4
    z: 2
    minimumSize: Math.min(1, 44 / Math.max(1, height - topPadding - bottomPadding))
    Accessible.name: qsTr("Scroll applications")
    contentItem: Rectangle {
        implicitWidth: 8
        implicitHeight: 44
        radius: 4
        color: control.pressed || control.hovered ? window.textColor
             : Qt.tint(window.backgroundColor, Qt.rgba(window.textColor.r, window.textColor.g, window.textColor.b, 0.55))
    }
    background: Rectangle {
        color: window.backgroundColor
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: parent.height - 8; radius: 4
            color: window.borderColor
        }
    }
}
