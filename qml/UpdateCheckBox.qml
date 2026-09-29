import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    padding: 8; spacing: 10
    implicitWidth: leftPadding + rightPadding + Math.max(indicator.implicitWidth, contentItem.implicitWidth)
    implicitHeight: topPadding + bottomPadding + Math.max(indicator.implicitHeight, contentItem.implicitHeight)
    palette.windowText: window.textColor
    contentItem: Label {
        text: control.text; font: control.font; color: window.textColor
        textFormat: Text.PlainText; verticalAlignment: Text.AlignVCenter
        leftPadding: text.length ? control.indicator.width + control.spacing : 0
    }
    indicator: Rectangle {
        implicitWidth: 22; implicitHeight: 22
        x: control.leftPadding; y: (control.height - height) / 2
        radius: 5
        color: control.checked ? window.accentColor : window.surfaceColor
        border.color: control.visualFocus || control.checked ? window.accentColor : window.mutedTextColor
        border.width: control.visualFocus ? 2 : 1
        Canvas {
            id: checkCanvas
            anchors.fill: parent
            visible: control.checkState !== Qt.Unchecked
            onVisibleChanged: requestPaint()
            Connections { target: control; function onCheckStateChanged() { checkCanvas.requestPaint() } }
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = "white"; ctx.lineWidth = 2; ctx.lineCap = "round"
                ctx.beginPath()
                if (control.checkState === Qt.PartiallyChecked) { ctx.moveTo(6, 11); ctx.lineTo(16, 11) }
                else { ctx.moveTo(5, 11); ctx.lineTo(9, 15); ctx.lineTo(17, 7) }
                ctx.stroke()
            }
        }
    }
}
