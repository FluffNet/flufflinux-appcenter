import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    objectName: "transactionReview"
    property var backend: null
    property var plan: ({})
    anchors.centerIn: parent
    width: Math.min(window.width - 48, plan.removing ? 480 : 740)
    height: Math.min(window.height - 64, (plan.removing ? 12 : body.implicitHeight + 48) + header.implicitHeight + footer.implicitHeight)
    modal: true
    padding: 20
    background: Rectangle {
        radius: 10
        // Keep transaction/trust details readable over bright screenshots.
        color: Qt.rgba(window.raisedSurfaceColor.r, window.raisedSurfaceColor.g, window.raisedSurfaceColor.b, 1)
        border.color: window.borderColor
    }
    title: plan.title || qsTr("Confirm action")
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape
    onAccepted: if (backend) backend.answerReview(plan.token, true)
    onRejected: if (backend) backend.answerReview(plan.token, false)
    onOpened: rejectButton.forceActiveFocus()
    header: Label {
        text: dialog.title; textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.pixelSize: 22; color: window.textColor
        leftPadding: 20; rightPadding: 20; topPadding: 20; bottomPadding: 12
    }
    footer: Item {
        implicitHeight: reviewButtons.implicitHeight + 24
        RowLayout {
            id: reviewButtons
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.top: parent.top; anchors.topMargin: 8
            spacing: 8
            Button {
                objectName: "confirmReviewButton"
                Layout.minimumHeight: 40
                text: dialog.plan.removing ? qsTr("Yes") : dialog.plan.kind === "remote" ? qsTr("Trust and add source") : qsTr("Continue")
                icon.name: dialog.plan.removing ? "" : "dialog-ok-apply"
                icon.source: dialog.plan.removing ? Qt.resolvedUrl("trash-red.svg") : ""
                icon.color: dialog.plan.removing ? "transparent" : palette.buttonText
                onClicked: dialog.accept()
            }
            Button {
                id: rejectButton
                objectName: "rejectReviewButton"
                Layout.minimumHeight: 40
                text: dialog.plan.removing ? qsTr("No") : qsTr("Cancel")
                icon.name: "dialog-cancel"
                onClicked: dialog.reject()
            }
        }
    }
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
        visible: !dialog.plan.removing
        contentWidth: availableWidth
        clip: true
        ColumnLayout {
            id: body
            width: parent.width
            spacing: 14
            Label { Layout.fillWidth: true; text: dialog.plan.message || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap }
            Repeater {
                objectName: "reviewOperations"
                model: dialog.plan.removing ? [] : dialog.plan.operations || []
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
