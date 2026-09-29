import QtQuick
import QtQuick.Controls

ToolButton {
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    hoverEnabled: true
    palette.buttonText: window.textColor
    leftPadding: 10; rightPadding: 10
    topPadding: 6; bottomPadding: 6
    contentItem: FluffButtonContent {}
    background: FluffButtonBackground {
        implicitWidth: 40; implicitHeight: 40
        idleColor: "transparent"
        idleBorderColor: "transparent"
    }
}
