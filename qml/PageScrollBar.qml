import QtQuick
import QtQuick.Templates as T

// This is fully painted here; using the template prevents KDE's internal
// groove padding and delayed visibility bindings from overriding our geometry.
T.ScrollBar {
    id: control
    property color surfaceColor: window.backgroundColor
    orientation: Qt.Vertical
    policy: T.ScrollBar.AlwaysOn
    stepSize: 0.02
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
             : Qt.tint(control.surfaceColor, Qt.rgba(window.textColor.r, window.textColor.g, window.textColor.b, 0.55))
    }
    background: Rectangle {
        color: control.surfaceColor
        Rectangle {
            anchors.centerIn: parent
            width: 8; height: parent.height - 8; radius: 4
            color: window.borderColor
        }
    }
}
