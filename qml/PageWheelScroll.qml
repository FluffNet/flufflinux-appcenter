import QtQuick
import org.kde.kirigami as Kirigami

// Kirigami owns wheel/touchpad motion. Middle-click autoscroll remains a
// separate input mode; native touch dragging is handled by the view itself.
Kirigami.WheelHandler {
    id: wheelScroll
    required property Flickable scrollTarget
    property bool enabled: true
    property real middleScrollIdleZ: 1
    signal scrollStarted()
    target: enabled ? scrollTarget : null
    blockTargetWheel: true
    scrollFlickableTarget: true
    filterMouseEvents: false
    function stopWheelAnimation() {
        // cancelFlick() does not stop Kirigami's separate wheel animation.
        // Detach during the handoff, then restore the conditional binding.
        target = null
        target = Qt.binding(function() { return wheelScroll.enabled ? wheelScroll.scrollTarget : null })
    }
    property MiddleMouseScroll middleMouseScroll: MiddleMouseScroll {
        scrollTarget: wheelScroll.scrollTarget
        enabled: wheelScroll.enabled && !!scrollTarget && scrollTarget.enabled
        idleZ: wheelScroll.middleScrollIdleZ
        onStarted: {
            wheelScroll.stopWheelAnimation()
            wheelScroll.scrollStarted()
        }
    }
    onWheel: {
        middleMouseScroll.stop()
        scrollStarted()
    }
}
