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
    property MiddleMouseScroll middleMouseScroll: MiddleMouseScroll {
        scrollTarget: wheelScroll.scrollTarget
        enabled: wheelScroll.enabled && !!scrollTarget && scrollTarget.enabled
        idleZ: wheelScroll.middleScrollIdleZ
        onStarted: wheelScroll.scrollStarted()
    }
    onWheel: {
        middleMouseScroll.stop()
        scrollStarted()
    }
}
