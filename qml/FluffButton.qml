import QtQuick
import QtQuick.Controls

Button {
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    hoverEnabled: true
    palette.buttonText: window.textColor
    leftPadding: 12; rightPadding: 12
    topPadding: 8; bottomPadding: 8
    contentItem: FluffButtonContent {}
    background: FluffButtonBackground {
        implicitWidth: 100
        implicitHeight: 40
    }
}
