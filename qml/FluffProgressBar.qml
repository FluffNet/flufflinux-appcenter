import QtQuick
import QtQuick.Templates as T

T.ProgressBar {
    id: control
    property bool activeStep: false
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
        Item {
            x: track.width * control.position
            width: track.width - x; height: track.height
            clip: true
            visible: control.activeStep && !control.indeterminate && control.position < 1
            Rectangle {
                id: activity
                width: Math.min(100, parent.width * 0.3); height: parent.height
                radius: 4; color: window.accentColor; opacity: 0.65
                NumberAnimation on x {
                    running: control.visible && activity.parent.visible
                    from: -activity.width; to: activity.parent.width
                    duration: 1100; loops: Animation.Infinite
                }
            }
        }
    }
}
