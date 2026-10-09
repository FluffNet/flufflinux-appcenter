import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    objectName: "queueRecoveryDialog"
    property var backend: null
    readonly property var recovery: backend && backend.recovery || ({})
    readonly property var items: recovery.items || []
    property int shownNotice: 0
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(760, parent.width - 48)
    height: Math.min(560, parent.height - 48)
    closePolicy: Popup.CloseOnEscape
    padding: 20
    background: Rectangle { color: window.raisedSurfaceColor; radius: window.cornerRadius; border.color: window.borderColor }
    function showNotice() {
        if (window.visible && recovery.notice > shownNotice && (items.length || recovery.error)) {
            shownNotice = recovery.notice
            open()
        }
    }
    onRecoveryChanged: Qt.callLater(showNotice)
    Connections { target: window; function onVisibleChanged() { dialog.showNotice() } }
    header: Label {
        text: qsTr("Interrupted work")
        color: window.textColor; font.pixelSize: 24; font.bold: true
        leftPadding: 20; rightPadding: 20; topPadding: 20; bottomPadding: 12
    }
    contentItem: ColumnLayout {
        spacing: 14
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
            color: window.textColor
            text: dialog.recovery.error || qsTr("App Center stopped before this work was recorded as finished. Installed versions have been checked. Nothing will resume automatically; review unfinished work before trying again.")
        }
        Flickable {
            id: recoveryScroll
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: width; contentHeight: entries.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            PageWheelScroll { scrollTarget: recoveryScroll }
            ColumnLayout {
                id: entries
                width: recoveryScroll.width - 16; spacing: 16
                Repeater {
                    model: dialog.items
                    delegate: RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                text: (index + 1) + ". " + modelData.name
                                font.bold: true; color: window.textColor
                            }
                            Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                color: window.textColor
                                text: (modelData.action === "update" ? qsTr("Update") : modelData.action === "uninstall" ? qsTr("Remove") : qsTr("Install"))
                                    + " - " + (modelData.state === "completed" ? qsTr("Already completed")
                                    : modelData.state === "removed" ? qsTr("App removed; final data cleanup could not be verified")
                                    : modelData.state === "unknown" ? qsTr("Could not verify installed state. Check again.") : qsTr("Interrupted - review before retrying"))
                            }
                        }
                        FluffButton {
                            objectName: "reviewRecoveredJobButton"
                            text: qsTr("Review")
                            visible: modelData.state === "interrupted"
                            enabled: !!dialog.backend && !dialog.recovery.checking && !dialog.recovery.error && !dialog.backend.busy
                            onClicked: { dialog.close(); dialog.backend.reviewRecovery(index) }
                        }
                    }
                }
                PageStatusLabel { visible: !!dialog.recovery.checking; text: qsTr("Loading...") }
            }
        }
    }
    footer: RowLayout {
        spacing: 8
        FluffButton {
            objectName: "retryRecoveryIoButton"
            Layout.leftMargin: 20; Layout.bottomMargin: 16
            text: dialog.recovery.error ? qsTr("Retry") : qsTr("Check again")
            enabled: !!dialog.backend && !dialog.recovery.checking && !dialog.recovery.saving && (!!dialog.recovery.error || !dialog.backend.busy)
            onClicked: dialog.recovery.error ? dialog.backend.retryRecoveryIo() : dialog.backend.refreshRecovery()
        }
        Item { Layout.fillWidth: true }
        FluffButton {
            objectName: "dismissRecoveredJobsButton"
            Layout.bottomMargin: 16
            text: qsTr("Dismiss list")
            enabled: dialog.items.length > 0 && !dialog.recovery.checking && !dialog.recovery.saving && !dialog.recovery.error
            onClicked: { dialog.backend.dismissRecovery(); dialog.close() }
        }
        FluffButton {
            Layout.rightMargin: 20; Layout.bottomMargin: 16
            text: qsTr("Close"); onClicked: dialog.close()
        }
    }
}
