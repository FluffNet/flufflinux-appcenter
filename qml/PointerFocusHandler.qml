import QtQuick

// Paired with TabFocus: pointer presses clear any previous keyboard focus,
// but keyboard activation keeps it. Observe passively so clicks and drags
// still belong to the control. Clear on press, before it can open a dialog
// whose safe default button must retain focus.
TapHandler {
    gesturePolicy: TapHandler.DragThreshold
    onPressedChanged: {
        if (pressed && parent.activeFocus)
            parent.focus = false
    }
}
