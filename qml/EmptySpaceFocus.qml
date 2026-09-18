import QtQuick

TapHandler {
    // Attach directly to a scroll view. Interactive children handle their own
    // clicks; an unclaimed tap clears the old focus without taking a drag grab.
    gesturePolicy: TapHandler.DragThreshold
    onTapped: {
        const focused = parent.Window.window.activeFocusItem
        if (focused) focused.focus = false
        parent.forceActiveFocus(Qt.MouseFocusReason)
    }
}
