import QtQuick

Canvas {
    id: mark
    property color color: window.accentForegroundColor
    property bool partial: false
    onColorChanged: requestPaint()
    onPartialChanged: requestPaint()
    onVisibleChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = color
        ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round"
        ctx.beginPath()
        if (partial) { ctx.moveTo(width * 0.25, height * 0.5); ctx.lineTo(width * 0.75, height * 0.5) }
        else {
            ctx.moveTo(width * 0.22, height * 0.5)
            ctx.lineTo(width * 0.41, height * 0.69)
            ctx.lineTo(width * 0.78, height * 0.31)
        }
        ctx.stroke()
    }
}
