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
        id: control
        property bool downloadArrow: false
        hoverEnabled: true
        Layout.fillWidth: true
        Layout.minimumWidth: 176
        Layout.minimumHeight: 56
        leftPadding: 16; rightPadding: 16
        topPadding: 12; bottomPadding: 12
        font.pixelSize: 18
        icon.width: 24; icon.height: 24
        background: Rectangle {
            implicitWidth: 176; implicitHeight: 56
            radius: window.cornerRadius
            color: (control.hovered || control.down) && control.enabled ? window.hoverColor : window.raisedSurfaceColor
            border.width: control.activeFocus ? 2 : 1
            border.color: control.activeFocus ? window.accentColor : window.borderColor
        }
        contentItem: Item {
            implicitWidth: buttonContent.implicitWidth
            implicitHeight: buttonContent.implicitHeight
            opacity: control.enabled ? 1 : 0.45
            RowLayout {
                id: buttonContent
                anchors.centerIn: parent
                spacing: 10
                DownloadArrow {
                    objectName: "installDownloadArrow"
                    visible: control.downloadArrow
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                    color: window.darkMode ? "#65d88b" : "#16823e"
                }
                Image {
                    visible: !control.downloadArrow
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                    sourceSize: Qt.size(24, 24)
                    source: !visible ? "" : control.icon.source.toString().length > 0 ? control.icon.source : window.iconSource(control.icon.name)
                    fillMode: Image.PreserveAspectFit
                }
                Label {
                    objectName: "appActionLabel"
                    text: control.text
                    font: control.font
                    color: window.textColor
                }
            }
        }
    }
    ActionButton {
        objectName: "installAppButton"
        downloadArrow: true
        visible: !buttons.actions.installed && !buttons.actions.running
        enabled: !window.installedLoading
        text: qsTr("Install")
        icon.name: "download"
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
