import QtQuick

Rectangle {
    property var control: parent
    property color idleColor: window.raisedSurfaceColor
    property color idleBorderColor: window.borderColor
    radius: window.cornerRadius
    color: control.enabled && (control.hovered || control.down) ? window.hoverColor : idleColor
    border.color: control.visualFocus ? window.accentColor : idleBorderColor
    border.width: control.visualFocus ? 2 : 1
}
