import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Dialog {
    id: dialog
    objectName: "appPermissionsDialog"
    property var app: ({})
    property var backend: null
    property int requestToken: 0
    readonly property var permissionData: backend && backend.appPermissions || ({})
    readonly property bool loading: permissionData.state === "loading"
    readonly property bool ready: permissionData.state === "ready"
    readonly property var groups: ready ? permissionData.groups || [] : []
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.max(0, parent.width - 64)
    height: Math.max(0, parent.height - 64)
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: window.raisedSurfaceColor; radius: window.cornerRadius; border.color: window.borderColor }
    function load() {
        if (backend && typeof backend.requestAppPermissions === "function") requestToken = backend.requestAppPermissions(app)
    }
    function cancelRead() {
        if (requestToken && backend && typeof backend.cancelAppPermissions === "function") backend.cancelAppPermissions(requestToken)
        requestToken = 0
    }
    onAboutToShow: { permissionScroll.contentY = 0; load() }
    onOpened: contentItem.forceActiveFocus(Qt.OtherFocusReason)
    onAppChanged: if (visible) close()
    onClosed: cancelRead()
    Component.onDestruction: cancelRead()
    header: ColumnLayout {
        spacing: 4
        Label {
            text: qsTr("App Permissions"); color: window.textColor; font.pixelSize: 23; font.weight: Font.DemiBold
            Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20; Layout.topMargin: 20
        }
        Label {
            objectName: "permissionsAppName"
            text: dialog.app.name || dialog.app.id || ""
            textFormat: Text.PlainText; color: window.mutedTextColor; wrapMode: Text.WrapAnywhere
            Layout.fillWidth: true; Layout.leftMargin: 20; Layout.rightMargin: 20; Layout.bottomMargin: 12
        }
    }
    contentItem: Flickable {
        id: permissionScroll
        objectName: "permissionsScroll"
        clip: true; contentWidth: width; contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: permissionScroll.contentHeight > permissionScroll.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
        NaturalWheelScroll { scrollTarget: permissionScroll }
        ColumnLayout {
            id: body
            width: Math.max(0, permissionScroll.width - 18)
            spacing: 24
            RowLayout {
                Layout.fillWidth: true
                visible: dialog.loading; spacing: 12
                LoadingSpinner { running: dialog.loading; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
                Label { text: qsTr("Loading app permissions…"); color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
            }
            Label {
                objectName: "permissionsExplanation"
                Layout.fillWidth: true; visible: dialog.ready
                text: (dialog.permissionData.installed ? qsTr("Current sandbox permissions, including Flatpak overrides.")
                    : qsTr("Sandbox permissions declared by the selected app source."))
                    + " " + qsTr("Access granted later through system dialogs is managed separately.")
                color: window.mutedTextColor; wrapMode: Text.Wrap
            }
            Label {
                objectName: "permissionsError"
                Layout.fillWidth: true; visible: !dialog.loading && !dialog.ready
                text: dialog.permissionData.message || qsTr("Permission information is unavailable.")
                textFormat: Text.PlainText; color: window.accentColor; wrapMode: Text.Wrap
            }
            FluffButton {
                objectName: "retryPermissionsButton"
                visible: !dialog.loading && !dialog.ready
                text: qsTr("Try Again"); icon.name: "view-refresh"
                onClicked: dialog.load()
            }
            Label {
                objectName: "permissionsEmpty"
                Layout.fillWidth: true; visible: dialog.ready && dialog.groups.length === 0
                text: qsTr("No additional sandbox permissions.")
                color: window.textColor; wrapMode: Text.Wrap
            }
            Repeater {
                model: dialog.groups
                delegate: RowLayout {
                    objectName: "permissionGroup"
                    required property var modelData
                    Layout.fillWidth: true; spacing: 16
                    Kirigami.Icon {
                        source: modelData.icon
                        color: window.textColor
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignTop; Layout.topMargin: 3
                        Accessible.ignored: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Label {
                            objectName: "permissionTitle"
                            text: modelData.title; textFormat: Text.PlainText
                            font.pixelSize: 18; font.weight: Font.DemiBold; color: window.textColor
                            Layout.fillWidth: true; wrapMode: Text.Wrap
                        }
                        Label {
                            text: modelData.description; textFormat: Text.PlainText
                            color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap
                        }
                        Repeater {
                            model: modelData.details
                            delegate: Label {
                                required property string modelData
                                text: "•  " + modelData; textFormat: Text.PlainText
                                color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                            }
                        }
                    }
                }
            }
        }
    }
    footer: DialogButtonBox {
        alignment: Qt.AlignHCenter
        topPadding: 8; bottomPadding: 8; leftPadding: 8; rightPadding: 8
        FluffButton {
            objectName: "closePermissionsButton"
            text: qsTr("Close"); icon.name: "window-close"
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
        onRejected: dialog.close()
    }
}
