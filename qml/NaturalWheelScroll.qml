import QtQuick

WheelHandler {
    id: wheelScroll

    required property Flickable scrollTarget
    property real wheelStep: 100
    property real touchpadStep: 42
    property real touchpadPixelScale: 2.15
    property real smoothTargetY: 0
    property bool smoothScrolling: false

    target: null
    orientation: Qt.Vertical
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    function isTouchpadDevice(device, hasPixelDelta) {
        return hasPixelDelta
               || (device
                   && (device.deviceType === PointerDevice.TouchPad
                       || device.pointerType === PointerDevice.Finger
                       || device.maximumPoints > 1))
    }

    function minimumContentY() {
        return scrollTarget.originY
    }

    function maximumContentY() {
        const minimum = minimumContentY()
        return Math.max(minimum,
                        minimum + scrollTarget.contentHeight - scrollTarget.height)
    }

    function boundedContentY(value) {
        return Math.max(minimumContentY(), Math.min(maximumContentY(), value))
    }

    function stopSmoothScroll() {
        smoothTimer.stop()
        smoothScrolling = false
        smoothTargetY = boundedContentY(scrollTarget.contentY)
    }

    function scrollBy(delta, smoothly) {
        if (!smoothly) {
            stopSmoothScroll()
            scrollTarget.contentY = boundedContentY(scrollTarget.contentY + delta)
            smoothTargetY = scrollTarget.contentY
            return
        }

        if (!smoothScrolling)
            smoothTargetY = boundedContentY(scrollTarget.contentY)
        smoothTargetY = boundedContentY(smoothTargetY + delta)
        smoothScrolling = true
        smoothTimer.start()
    }

    function applyTouchpadDelta(rawDelta, hasPixelDelta) {
        const scale = hasPixelDelta ? touchpadPixelScale : 1
        // Pixel deltas already arrive as a continuous stream, including the
        // compositor's momentum phase. Apply them immediately so the content
        // stays under the user's fingers. Only legacy angle-only touchpads
        // need interpolation between coarse ticks.
        scrollBy(rawDelta * scale, !hasPixelDelta)
    }

    property Timer smoothTimer: Timer {
        interval: 8
        repeat: true
        onTriggered: {
            const difference = wheelScroll.smoothTargetY
                               - wheelScroll.scrollTarget.contentY
            if (Math.abs(difference) < 0.35) {
                wheelScroll.scrollTarget.contentY = wheelScroll.smoothTargetY
                wheelScroll.smoothScrolling = false
                stop()
                return
            }

            wheelScroll.scrollTarget.contentY = wheelScroll.boundedContentY(
                        wheelScroll.scrollTarget.contentY + difference * 0.38)
        }
    }

    onWheel: function(event) {
        const hasPixelDelta = event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0
        const isTouchpad = isTouchpadDevice(point.device, hasPixelDelta)

        const rawX = event.pixelDelta.x !== 0
                     ? event.pixelDelta.x
                     : event.angleDelta.x / 120
                       * (isTouchpad ? touchpadStep : wheelStep)
        const rawY = event.pixelDelta.y !== 0
                     ? event.pixelDelta.y
                     : event.angleDelta.y / 120
                       * (isTouchpad ? touchpadStep : wheelStep)
        if (rawY === 0 || Math.abs(rawY) <= Math.abs(rawX)) {
            event.accepted = false
            return
        }

        if (isTouchpad)
            applyTouchpadDelta(-rawY, hasPixelDelta)
        else
            scrollBy(-rawY, false)
        event.accepted = true
    }
}
