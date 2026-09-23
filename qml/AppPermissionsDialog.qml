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
    property bool changesView: false
    property var changes: ({})
    readonly property var permissionData: changesView ? ({state: "ready", groups: (changes.groups || []).map(function(group) {
        return Object.assign({}, group, {details: (group.added || []).map(value => qsTr("Added: %1").arg(value))
            .concat((group.removed || []).map(value => qsTr("Removed: %1").arg(value)))})
    })}) : backend && backend.appPermissions || ({})
    readonly property bool loading: permissionData.state === "loading"
    readonly property bool ready: permissionData.state === "ready"
    readonly property var groups: ready ? permissionData.groups || [] : []
    readonly property string appName: String(app.name || app.id || "")
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.max(0, parent.width - 64)
    height: Math.max(0, parent.height - 64)
    leftPadding: 0; rightPadding: 0; topPadding: 12; bottomPadding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: window.raisedSurfaceColor; radius: window.cornerRadius; border.color: window.borderColor }
    function load() {
        if (backend && typeof backend.requestAppPermissions === "function") requestToken = backend.requestAppPermissions(app)
    }
    function escapedName() {
        return appName.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
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
    header: Label {
        objectName: "permissionsTitle"
        text: (dialog.changesView ? qsTr("Permission Changes - %1") : qsTr("App Permissions - %1")).arg("<b>" + dialog.escapedName() + "</b>")
        textFormat: Text.StyledText; wrapMode: Text.WrapAnywhere
        Accessible.name: (dialog.changesView ? qsTr("Permission Changes - %1") : qsTr("App Permissions - %1")).arg(dialog.appName)
        color: window.textColor; font.pixelSize: 23; font.weight: Font.Normal
        leftPadding: 20; rightPadding: 20; topPadding: 20; bottomPadding: 8
    }
    contentItem: Item {
        id: viewport
        Flickable {
            id: permissionScroll
            objectName: "permissionsScroll"
            anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 28
            clip: true; contentWidth: width; contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: PageScrollBar {
                objectName: "permissionsPageScrollBar"
                parent: viewport
                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                anchors.rightMargin: 1
                visible: size < 1
                surfaceColor: window.raisedSurfaceColor
                Accessible.name: qsTr("Scroll app permissions")
            }
            NaturalWheelScroll { scrollTarget: permissionScroll }
            ColumnLayout {
                id: body
                width: permissionScroll.width
                spacing: 24
                RowLayout {
                    Layout.fillWidth: true
                    visible: dialog.loading; spacing: 12
                    LoadingSpinner { running: dialog.loading; Layout.preferredWidth: 26; Layout.preferredHeight: 26 }
                    Label { text: qsTr("Loading app permissions…"); color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
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
                RowLayout {
                    id: permissionGrid
                    objectName: "permissionGrid"
                    readonly property int columns: width >= 760 ? 2 : 1
                    readonly property int columnSpacing: 40
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    spacing: columnSpacing
                    Repeater {
                        objectName: "permissionColumns"
                        model: permissionGrid.columns
                        delegate: ColumnLayout {
                            id: permissionColumn
                            required property int index
                            property alias groupRepeater: columnGroups
                            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            spacing: 24
                            Repeater {
                                id: columnGroups
                                objectName: "permissionGroupsColumn" + permissionColumn.index
                                // Preserve group order while letting each column stack
                                // independently of longer sections in its neighbour.
                                model: dialog.groups.filter((group, index) => index % permissionGrid.columns === permissionColumn.index)
                                delegate: RowLayout {
                                    objectName: "permissionGroup"
                                    required property var modelData
                                    Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1
                                    Layout.alignment: Qt.AlignTop; spacing: 16
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
