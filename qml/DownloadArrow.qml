import QtQuick

Canvas {
    property color color: "white"
    implicitWidth: 24; implicitHeight: 24
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.scale(width / 24, height / 24)
        ctx.strokeStyle = color
        ctx.lineWidth = 1.8
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(12, 4)
        ctx.lineTo(12, 20)
        ctx.moveTo(6, 14)
        ctx.lineTo(12, 20)
        ctx.lineTo(18, 14)
        ctx.stroke()
        ctx.restore()
    }
}
