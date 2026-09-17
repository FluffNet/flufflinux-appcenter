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

    component ActionButton: Button {
        Layout.fillWidth: true
        Layout.minimumWidth: 176
        Layout.minimumHeight: 56
        font.pixelSize: 18
        icon.width: 24; icon.height: 24
    }
    ActionButton {
        objectName: "installAppButton"
        visible: !buttons.actions.installed && !buttons.actions.running
        enabled: !window.installedLoading
        text: qsTr("Install")
        icon.name: "list-add"
        onClicked: window.installApp(buttons.actions.app)
    }
    ActionButton {
        objectName: "openAppButton"
        visible: !!buttons.actions.installed && !buttons.actions.running
        text: qsTr("Open")
        icon.name: "media-playback-start"
        onClicked: window.backend.launchApp(buttons.actions.installed)
    }
    ActionButton {
        objectName: "uninstallAppButton"
        visible: !!buttons.actions.installed && !buttons.actions.running
        text: qsTr("Uninstall")
        icon.source: Qt.resolvedUrl("trash-red.svg")
        icon.color: "transparent"
        onClicked: window.uninstallApp(buttons.actions.installed)
    }
    ActionButton {
        objectName: "cancelAppButton"
        visible: buttons.actions.running && !buttons.actions.removing
        text: qsTr("Cancel")
        icon.name: "dialog-cancel"
        onClicked: window.backend.cancelJob(buttons.actions.job.index)
    }
}
