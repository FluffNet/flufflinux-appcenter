import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    objectName: "transactionReview"
    property var backend: null
    property var plan: ({})
    anchors.centerIn: parent
    width: Math.min(window.width - 48, 740)
    height: Math.min(window.height - 64, body.implicitHeight + header.height + footer.height + 48)
    modal: true
    padding: 20
    background: Rectangle {
        radius: 10
        // Keep transaction/trust details readable over bright screenshots.
        color: Qt.rgba(window.raisedSurfaceColor.r, window.raisedSurfaceColor.g, window.raisedSurfaceColor.b, 1)
        border.color: window.borderColor
    }
    title: plan.title || qsTr("Review installation")
    standardButtons: Dialog.Cancel | Dialog.Ok
    closePolicy: Popup.CloseOnEscape
    onAccepted: if (backend) backend.answerReview(plan.token, true)
    onRejected: if (backend) backend.answerReview(plan.token, false)
    onOpened: standardButton(Dialog.Ok).text = plan.removing ? qsTr("Uninstall and delete data")
                : plan.kind === "remote" ? qsTr("Trust and add source")
                : plan.kind === "bundle" ? qsTr("Continue") : qsTr("Install")
    Connections {
        target: dialog.backend
        function onReviewChanged() {
            if (dialog.backend.review && dialog.backend.review.token) {
                dialog.plan = dialog.backend.review
                dialog.open()
            } else dialog.close()
        }
    }
    contentItem: ScrollView {
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 14
            Label { Layout.fillWidth: true; text: dialog.plan.message || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap }
            Label {
                Layout.fillWidth: true
                visible: dialog.plan.kind === "transaction" && !dialog.plan.removing
                text: qsTr("Estimated download: %1").arg(dialog.plan.downloadSize || "")
                font.bold: true
            }
            Repeater {
                model: dialog.plan.operations || []
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 3
                    Label { Layout.fillWidth: true; text: (modelData.dependency ? qsTr("Dependency: ") : qsTr("App: ")) + modelData.name; textFormat: Text.PlainText; font.bold: true; wrapMode: Text.WrapAnywhere }
                    Label { Layout.fillWidth: true; text: modelData.action + " · " + (modelData.remote || qsTr("Local bundle")) + " · " + modelData.downloadSize; textFormat: Text.PlainText; color: window.mutedTextColor; wrapMode: Text.Wrap }
                    Label { Layout.fillWidth: true; text: modelData.ref; textFormat: Text.PlainText; color: window.mutedTextColor; font.pixelSize: 12; wrapMode: Text.WrapAnywhere }
                    Rectangle { Layout.fillWidth: true; height: 1; color: window.borderColor }
                }
            }
        }
    }
}
