import QtQuick

WheelHandler {
    required property Flickable scrollTarget
    property real stepSize: 140

    target: null
    acceptedDevices: PointerDevice.Mouse

    onWheel: function(event) {
        const angleDistance = event.angleDelta.y !== 0
                              ? event.angleDelta.y / 120 * stepSize
                              : event.pixelDelta.y
        if (angleDistance === 0)
            return

        scrollTarget.cancelFlick()
        const minimum = scrollTarget.originY
        const maximum = Math.max(minimum,
                                 minimum + scrollTarget.contentHeight - scrollTarget.height)
        scrollTarget.contentY = Math.max(minimum,
                                         Math.min(maximum,
                                                  scrollTarget.contentY - angleDistance))
        event.accepted = true
    }
}
