import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: row
    required property var app
    readonly property var job: typeof window.jobForApp === "function" ? window.jobForApp(app) : null
    readonly property bool removing: !!job && job.action === "uninstall" && job.active === true
    readonly property bool awaitingRemovalConfirmation: removing && job.removalConfirmed !== true
    readonly property bool removalPending: removing && job.removalConfirmed === true && job.queued === true
    readonly property bool removalFailed: !!job && job.action === "uninstall" && job.failed === true
    height: Math.max(108, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: 16
    hoverEnabled: true
    Accessible.name: app.name + ", " + app.installedSize
    background: Rectangle {
        radius: window.cornerRadius
        color: row.hovered ? window.hoverColor : window.surfaceColor
        border.color: row.activeFocus ? window.accentColor : window.borderColor
        border.width: row.activeFocus ? 2 : 1
    }
    contentItem: RowLayout {
        spacing: 16
        AppIcon {
            Layout.preferredWidth: 56; Layout.preferredHeight: 56
            sourceSize: Qt.size(64, 64)
            icon: app.icon || ""
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            Label {
                Layout.fillWidth: true
                text: app.name; color: window.textColor
                font.pixelSize: 18; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 3
                Label { text: qsTr("Version:"); color: window.mutedTextColor }
                Label {
                    Layout.fillWidth: true
                    text: app.installedVersion || qsTr("Unavailable")
                    color: window.textColor
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                Label { text: qsTr("Size:"); color: window.mutedTextColor }
                Label {
                    Layout.fillWidth: true
                    text: app.installedSize || qsTr("Unavailable")
                    color: window.textColor
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                Label {
                    objectName: "installedDateCaption"
                    visible: !!app.installedDate
                    text: qsTr("Installed on:"); color: window.mutedTextColor
                }
                Label {
                    objectName: "installedDateValue"
                    visible: !!app.installedDate
                    Layout.fillWidth: true
                    text: app.installedDate || ""
                    color: window.textColor; font.weight: Font.Bold
                    wrapMode: Text.Wrap
                }
            }
            Label {
                objectName: "installedRemovalStatus"
                Layout.fillWidth: true
                visible: row.removing || row.removalFailed
                text: row.awaitingRemovalConfirmation ? qsTr("Waiting for confirmation")
                      : row.removalPending ? qsTr("Pending…")
                      : row.removing && !row.removalFailed ? qsTr("Uninstalling…")
                      : row.job ? row.job.status + (row.job.error ? "\n" + row.job.error : "") : ""
                textFormat: Text.PlainText; wrapMode: Text.Wrap
                color: row.removalFailed ? window.accentColor : window.mutedTextColor
            }
            FluffProgressBar {
                objectName: "installedRemovalProgress"
                Layout.fillWidth: true
                visible: row.removing && !row.awaitingRemovalConfirmation && !row.removalPending
                value: row.job ? row.job.progress : 0
                indeterminate: row.removing
                palette.highlight: window.accentColor
            }
        }
        FluffToolButton {
            objectName: "uninstallButton"
            enabled: !!window.backend && !(row.job && row.job.active)
            Layout.preferredWidth: 44; Layout.preferredHeight: 44
            Accessible.name: qsTr("Uninstall %1").arg(app.name)
            onClicked: window.uninstallApp(app)
            // Explicit image keeps the trash red in both Breeze palettes.
            contentItem: Image {
                source: "trash-red.svg"
                sourceSize: Qt.size(24, 24)
                fillMode: Image.PreserveAspectFit
            }
            background: Rectangle {
                radius: window.cornerRadius
                color: parent.hovered ? window.hoverColor : "transparent"
                border.color: parent.activeFocus ? window.accentColor : window.borderColor
                border.width: parent.activeFocus ? 2 : 1
            }
        }
    }
}
