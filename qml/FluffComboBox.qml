import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

// KDE paints non-editable combo labels/arrows in its background. Replacing
// just that background erases both. Own all three pieces and retain the
// standard ComboBox keyboard, popup, selection and accessibility behavior.
Basic.ComboBox {
    id: control
    // ComboBox routes popup arrow/Enter keys through the control, including
    // after opening with the mouse. Keep that temporary focus until it closes.
    Connections {
        target: control.popup
        function onClosed() {
            if (!control.visualFocus) control.focus = false
        }
    }
    hoverEnabled: true
    leftPadding: 12; rightPadding: 36
    topPadding: 8; bottomPadding: 8
    palette.button: window.raisedSurfaceColor
    palette.buttonText: window.textColor
    palette.window: window.raisedSurfaceColor
    palette.text: window.textColor
    palette.highlight: window.accentColor
    // Basic's popup highlight is a light/neutral surface, not the accent.
    // Keep its text and surface paired in both KDE color schemes.
    palette.highlightedText: window.textColor
    palette.light: window.hoverColor
    palette.midlight: window.hoverColor
    contentItem: Label {
        objectName: "comboDisplayLabel"
        text: control.displayText
        font: control.font
        color: window.textColor
        opacity: control.enabled ? 1 : 0.45
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Canvas {
        objectName: "comboArrow"
        x: control.width - width - 13; y: (control.height - height) / 2
        width: 12; height: 8
        opacity: control.enabled ? 1 : 0.45
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = window.textColor
            ctx.lineWidth = 1.5; ctx.lineCap = "round"; ctx.lineJoin = "round"
            ctx.beginPath(); ctx.moveTo(1, 1); ctx.lineTo(6, 6); ctx.lineTo(11, 1); ctx.stroke()
        }
        Connections { target: window; function onTextColorChanged() { control.indicator.requestPaint() } }
    }
    background: Rectangle {
        implicitWidth: 210; implicitHeight: 42
        radius: window.cornerRadius
        color: control.hovered || control.down ? window.hoverColor : window.raisedSurfaceColor
        border.color: control.visualFocus ? window.accentColor : window.borderColor
        border.width: control.visualFocus ? 2 : 1
    }
}
