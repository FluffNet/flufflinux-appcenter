import QtQuick
import QtQuick.Templates as T

T.ProgressBar {
    id: control
    implicitWidth: 200
    implicitHeight: 8
    padding: 0
    background: Rectangle { radius: 4; color: window.borderColor }
    contentItem: Item {
        id: track
        clip: true
        Rectangle {
            id: fill
            height: parent.height
            radius: 4
            width: control.indeterminate ? parent.width * 0.3 : parent.width * control.position
            color: window.accentColor
            x: 0
            NumberAnimation on x {
                running: control.indeterminate && control.visible
                from: -fill.width; to: track.width
                duration: 1100; loops: Animation.Infinite
                onRunningChanged: if (!running) fill.x = 0
            }
        }
    }
}
