import QtQuick

Item {
    id: spinner

    property bool running: false
    property color color: "white"

    visible: running
    width: 30
    height: 30

    Canvas {
        id: spinnerCanvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const context = getContext("2d")
            context.reset()
            context.clearRect(0, 0, width, height)
            context.beginPath()
            context.arc(width / 2, height / 2,
                        Math.max(1, Math.min(width, height) / 2 - 3),
                        0, Math.PI * 1.45)
            context.lineWidth = 3
            context.lineCap = "round"
            context.strokeStyle = spinner.color
            context.stroke()
        }

        Connections {
            target: spinner
            function onColorChanged() { spinnerCanvas.requestPaint() }
        }
    }

    RotationAnimator on rotation {
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: spinner.running
    }
}
