import QtQuick

WheelHandler {
    required property Flickable scrollTarget
    property real wheelStep: 100

    target: null
    orientation: Qt.Vertical
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    onWheel: function(event) {
        const rawX = event.pixelDelta.x !== 0
                     ? event.pixelDelta.x
                     : event.angleDelta.x / 120 * wheelStep
        const rawY = event.pixelDelta.y !== 0
                     ? event.pixelDelta.y
                     : event.angleDelta.y / 120 * wheelStep
        if (rawY === 0 || Math.abs(rawY) <= Math.abs(rawX)) {
            event.accepted = false
            return
        }

        const minimum = scrollTarget.originY
        const maximum = Math.max(minimum,
                                 minimum + scrollTarget.contentHeight - scrollTarget.height)
        scrollTarget.contentY = Math.max(minimum,
                                         Math.min(maximum,
                                                  scrollTarget.contentY - rawY))
        event.accepted = true
    }
}
