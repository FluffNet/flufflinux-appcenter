import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: row
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    required property var app
    readonly property var job: typeof window.jobForApp === "function" ? window.jobForApp(app) : null
    readonly property bool removing: !!job && job.action === "uninstall" && job.active === true
    readonly property bool awaitingRemovalConfirmation: removing && job.removalConfirmed !== true
    readonly property bool removalPending: removing && job.removalConfirmed === true && job.queued === true
    readonly property bool removalFailed: !!job && job.action === "uninstall" && job.failed === true
    height: Math.max(108, contentItem.implicitHeight + topPadding + bottomPadding)
    padding: 16
    topPadding: 12
    bottomPadding: 12
    hoverEnabled: true
    // Use the same scalable glyph rendering as text inputs and other labels.
    component MetadataLabel: Label { renderType: Text.QtRendering }
    Accessible.name: app.name + ", " + app.installedSize
    background: Rectangle {
        radius: window.cornerRadius
        color: row.hovered ? window.hoverColor : window.surfaceColor
        border.color: row.visualFocus ? window.accentColor : window.borderColor
        border.width: row.visualFocus ? 2 : 1
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
            AppPublisher { objectName: "installedAppPublisher"; app: row.app; Layout.fillWidth: true }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 3
                MetadataLabel { text: qsTr("Version:"); color: window.mutedTextColor }
                MetadataLabel {
                    objectName: "installedVersionValue"
                    Layout.fillWidth: true
                    text: app.installedVersion || qsTr("Unavailable")
                    color: window.textColor
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                MetadataLabel { text: qsTr("Size:"); color: window.mutedTextColor }
                MetadataLabel {
                    Layout.fillWidth: true
                    text: app.installedSize || qsTr("Unavailable")
                    color: window.textColor
                    font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                MetadataLabel { text: qsTr("Source:"); color: window.mutedTextColor }
                MetadataLabel {
                    objectName: "installedSourceValue"
                    Layout.fillWidth: true
                    text: (app.installedOrigin || qsTr("Unavailable")) + (app.installedOrigin && app.installation !== "user"
                        ? " (" + qsTr("System") + ")" : "")
                    textFormat: Text.PlainText; color: window.textColor; font.weight: Font.Bold
                    wrapMode: Text.WrapAnywhere
                }
                MetadataLabel {
                    objectName: "installedDateCaption"
                    visible: !!app.installedDate
                    text: qsTr("Installed on:"); color: window.mutedTextColor
                }
                MetadataLabel {
                    objectName: "installedDateValue"
                    visible: !!app.installedDate
                    Layout.fillWidth: true
                    text: app.installedDate || ""
                    color: window.textColor; font.weight: Font.Bold
                    wrapMode: Text.Wrap
                }
                MetadataLabel {
                    objectName: "installedUpdatedDateCaption"
                    visible: !!app.updatedDate
                    text: qsTr("Last updated:"); color: window.mutedTextColor
                }
                MetadataLabel {
                    objectName: "installedUpdatedDateValue"
                    visible: !!app.updatedDate
                    Layout.fillWidth: true; text: app.updatedDate || ""
                    color: window.textColor; font.weight: Font.Bold; wrapMode: Text.Wrap
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
                color: row.removalFailed ? window.accentTextColor : window.mutedTextColor
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
            enabled: !!window.backend && !window.backend.sourcesBusy && !(row.job && row.job.active)
            Layout.preferredWidth: 44; Layout.preferredHeight: 44
            Accessible.name: qsTr("Uninstall %1").arg(app.name)
            onClicked: window.uninstallApp(app)
            // Explicit image keeps the trash red in both Breeze palettes.
            contentItem: Image {
                source: "trash-red.svg"
                sourceSize: Qt.size(24, 24)
                fillMode: Image.PreserveAspectFit
            }
            background: FluffButtonBackground {
                idleColor: "transparent"
                // The ordinary card border disappears against the row's
                // hover tint. Keep this nested action distinct in both themes
                // without using the red keyboard-focus outline for hover.
                idleBorderColor: Qt.tint(window.surfaceColor,
                    Qt.rgba(window.textColor.r, window.textColor.g, window.textColor.b, 0.28))
            }
        }
    }
}
