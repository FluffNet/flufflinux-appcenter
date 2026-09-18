import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GridLayout {
    id: buttons
    objectName: "appActionButtons"
    required property var actions
    property bool stacked: true
    visible: actions.visible && (!actions.running || !actions.removing)
    columns: stacked ? 1 : 2
    columnSpacing: 12; rowSpacing: 12

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: !buttons.actions.installed && !buttons.actions.running
        AppActionButton {
            objectName: "installAppButton"
            downloadArrow: true
            visible: !buttons.actions.installed && !buttons.actions.running
            enabled: !window.installedLoading && !(window.backend && window.backend.sourcesBusy)
            text: qsTr("Install")
            icon.name: "download"
            onClicked: window.installApp(buttons.actions.app)
        }
        FluffToolButton {
            id: sourceButton
            objectName: "installSourceButton"
            readonly property var sources: buttons.actions.app && buttons.actions.app.sources || []
            visible: sources.length > 1
            enabled: !(window.backend && window.backend.sourcesBusy)
            Layout.preferredWidth: 44; Layout.preferredHeight: 56
            contentItem: Item {
                Canvas {
                    id: sourceChevron
                    objectName: "installSourceChevron"
                    anchors.centerIn: parent
                    width: 14; height: 10
                    opacity: sourceButton.enabled ? 1 : 0.45
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = window.textColor
                        ctx.lineWidth = 2; ctx.lineCap = "round"; ctx.lineJoin = "round"
                        ctx.beginPath(); ctx.moveTo(2, 2); ctx.lineTo(7, 8); ctx.lineTo(12, 2); ctx.stroke()
                    }
                    Connections { target: window; function onTextColorChanged() { sourceChevron.requestPaint() } }
                }
            }
            Accessible.name: qsTr("Choose installation source")
            background: FluffButtonBackground {}
            onClicked: {
                sourceMenu.restoreKeyboardFocus = visualFocus
                if (sourceMenu.visible) sourceMenu.close()
                else sourceMenu.open()
            }
            Menu {
                id: sourceMenu
                objectName: "installSourceMenu"
                property bool restoreKeyboardFocus: false
                // Leave the opener clickable while open. Excluding it from
                // outside-press dismissal prevents closing on press and then
                // reopening on release when the same arrow is clicked again.
                modal: false
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                Overlay.onPressed: restoreKeyboardFocus = false
                onClosed: {
                    if (!restoreKeyboardFocus) sourceButton.focus = false
                    else Qt.callLater(function() {
                        // Qt restores the opener with OtherFocusReason after
                        // closed. Restore its keyboard ring only if it still
                        // owns focus; never steal it from a newly opened popup.
                        if (!sourceMenu.visible && sourceMenu.restoreKeyboardFocus && sourceButton.activeFocus) {
                            sourceButton.focus = false
                            sourceButton.forceActiveFocus(Qt.TabFocusReason)
                        }
                    })
                }
                x: sourceButton.width - width; y: sourceButton.height + 6
                width: 300
                Instantiator {
                    model: sourceButton.sources
                    delegate: MenuItem {
                        required property var modelData
                        text: modelData.remote + " · " + String(modelData.flatpakRef || "").split('/').pop()
                        checkable: true
                        checked: modelData.remote === buttons.actions.app.remote && modelData.flatpakRef === buttons.actions.app.flatpakRef
                        TapHandler {
                            gesturePolicy: TapHandler.DragThreshold
                            onPressedChanged: if (pressed) sourceMenu.restoreKeyboardFocus = false
                        }
                        onTriggered: window.selectSource(modelData)
                    }
                    onObjectAdded: function(index, object) { sourceMenu.insertItem(index, object) }
                    onObjectRemoved: function(index, object) { sourceMenu.removeItem(object) }
                }
            }
        }
    }
    AppActionButton {
        objectName: "openAppButton"
        visible: !!buttons.actions.installed && !buttons.actions.running
        text: qsTr("Open")
        icon.name: "media-playback-start"
        onClicked: window.backend.launchApp(buttons.actions.installed)
    }
    AppActionButton {
        objectName: "uninstallAppButton"
        enabled: !(window.backend && window.backend.sourcesBusy)
        visible: !!buttons.actions.installed && !buttons.actions.running
        text: qsTr("Uninstall")
        icon.source: Qt.resolvedUrl("trash-red.svg")
        icon.color: "transparent"
        onClicked: window.uninstallApp(buttons.actions.installed)
    }
    AppActionButton {
        objectName: "cancelAppButton"
        visible: buttons.actions.running && !buttons.actions.removing
        text: qsTr("Cancel")
        icon.name: "dialog-cancel"
        onClicked: window.backend.cancelJob(buttons.actions.job.index)
    }
}
