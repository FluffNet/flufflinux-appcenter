import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs as FileDialogs
import org.kde.kirigami as Kirigami

Page {
    id: page
    objectName: "settingsPage"
    focusPolicy: Qt.ClickFocus
    background: Control { focusPolicy: Qt.ClickFocus }
    readonly property var sources: window.backend && window.backend.repositories || []
    readonly property bool busy: !!window.backend && !!window.backend.busy
    property var selectedSource: null
    property Item detailsOpener: null
    readonly property string inputStatus: window.backend && window.backend.sourceInputStatus || ""
    readonly property bool sourceWorkPending: !!inputStatus || !!(window.backend && window.backend.sourcesBusy)
    header: Control {
        focusPolicy: Qt.ClickFocus
        height: 70; leftPadding: 24; rightPadding: 24
        background: Rectangle {
            color: window.backgroundColor
            FluffSeparator { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom }
        }
        contentItem: Item {
            FluffToolButton {
                objectName: "settingsBackButton"
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 106; implicitHeight: 44; font.pixelSize: 16; font.weight: Font.DemiBold
                text: qsTr("←  Back"); onClicked: window.goBack()
            }
            Label { anchors.centerIn: parent; text: qsTr("Settings"); font.pixelSize: 26; font.bold: true; color: window.textColor }
        }
    }
    ScrollView {
        id: scroll
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        property MiddleMouseScroll middleScroll: MiddleMouseScroll { scrollTarget: scroll.contentItem; idleZ: 1 }
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 16
            RowLayout {
                Layout.fillWidth: true; Layout.margins: 24; Layout.bottomMargin: 4
                Label { text: qsTr("Flatpak Sources"); font.pixelSize: 25; font.bold: true; color: window.textColor; Layout.fillWidth: true }
                FluffToolButton {
                    objectName: "refreshSourcesButton"
                    text: qsTr("Refresh"); icon.name: "view-refresh"
                    enabled: !page.busy
                    onClicked: window.backend.refreshSources(true)
                }
                FluffButton {
                    objectName: "addSourceButton"
                    text: qsTr("Add Source…"); icon.name: "list-add"
                    enabled: !page.busy
                    onClicked: { sourceInput.text = ""; addDialog.open() }
                }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
                spacing: 10
                visible: !!sourceStatusLabel.text
                LoadingSpinner {
                    objectName: "sourceWorkSpinner"
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                    running: page.sourceWorkPending
                    color: window.textColor
                }
                Label {
                    id: sourceStatusLabel
                    objectName: "sourcesStatus"
                    Layout.fillWidth: true
                    text: page.inputStatus || (window.backend && window.backend.sourcesBusy ? qsTr("Updating software sources…")
                          : window.backend && window.backend.sourcesError || "")
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: page.sourceWorkPending ? window.mutedTextColor : window.accentTextColor
                    Accessible.role: Accessible.StaticText
                }
            }
            Repeater {
                model: page.sources
                delegate: Pane {
                    id: sourceRow
                    required property var modelData
                    objectName: "sourceRow"
                    Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
                    padding: 16; focusPolicy: Qt.ClickFocus
                    background: Rectangle { color: window.surfaceColor; radius: window.cornerRadius; border.color: window.borderColor }
                    contentItem: RowLayout {
                        spacing: 14
                        CheckBox {
                            id: sourceEnabled
                            focusPolicy: Qt.TabFocus
                            PointerFocusHandler {}
                            objectName: "sourceEnabled"
                            implicitWidth: 44; implicitHeight: 44
                            Layout.alignment: Qt.AlignVCenter
                            padding: 0; spacing: 0; hoverEnabled: true
                            contentItem: Item {}
                            background: Rectangle {
                                radius: window.cornerRadius
                                color: sourceEnabled.enabled && (sourceEnabled.hovered || sourceEnabled.down)
                                    ? window.hoverColor : "transparent"
                                border.width: sourceEnabled.visualFocus ? 2 : 0
                                border.color: window.accentColor
                            }
                            indicator: Rectangle {
                                objectName: "sourceCheckIndicator"
                                x: (sourceEnabled.width - width) / 2
                                y: (sourceEnabled.height - height) / 2
                                width: 24; height: 24; radius: 5
                                opacity: sourceEnabled.enabled ? 1 : 0.45
                                color: sourceEnabled.checked ? window.accentColor : "transparent"
                                border.width: 2
                                border.color: sourceEnabled.checked ? window.accentColor
                                    : Qt.tint(window.surfaceColor, Qt.rgba(window.textColor.r, window.textColor.g, window.textColor.b, 0.4))
                                ThemeCheckMark {
                                    objectName: "sourceCheckMark"
                                    anchors.fill: parent
                                    visible: sourceEnabled.checked
                                }
                            }
                            checked: sourceRow.modelData.enabled
                            enabled: !page.busy && (sourceRow.modelData.hasUser || sourceRow.modelData.scope === "user")
                            Accessible.name: qsTr("Enable %1").arg(sourceRow.modelData.name)
                            onClicked: {
                                window.backend.setSourceEnabled(sourceRow.modelData, checked)
                                checked = Qt.binding(function() { return sourceRow.modelData.enabled })
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Label {
                                Layout.fillWidth: true; color: window.textColor
                                objectName: "sourceTitle"
                                text: (sourceRow.modelData.title || sourceRow.modelData.name)
                                      + (sourceRow.modelData.scope === "merged" || sourceRow.modelData.scope === "user" ? "" : " (" + qsTr("System") + ")")
                                textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 18; font.bold: true
                            }
                            Label { Layout.fillWidth: true; text: sourceRow.modelData.url; textFormat: Text.PlainText; color: window.mutedTextColor; wrapMode: Text.WrapAnywhere }
                        }
                        FluffToolButton {
                            objectName: "removeSourceButton"
                            width: 44; height: 44
                            enabled: !page.busy
                            icon.source: Qt.resolvedUrl("trash-red.svg"); icon.color: "transparent"
                            Accessible.name: qsTr("Remove %1").arg(sourceRow.modelData.name)
                            onClicked: { page.selectedSource = sourceRow.modelData; removeDialog.open() }
                        }
                        FluffToolButton {
                            id: sourceDetailsButton
                            objectName: "sourceDetailsButton"
                            width: 44; height: 44
                            icon.name: "dialog-information"
                            // Use the menu's Kirigami icon renderer and logical
                            // size. A QIcon pixmap request at fractional DPR can
                            // choose the unrelated large blue information asset.
                            contentItem: Item {
                                Kirigami.Icon {
                                    objectName: "sourceInformationIcon"
                                    anchors.centerIn: parent
                                    source: sourceDetailsButton.icon.name
                                    width: Kirigami.Settings.hasTransientTouchInput ? Kirigami.Units.iconSizes.smallMedium : Kirigami.Units.iconSizes.small
                                    height: width
                                    color: sourceDetailsButton.icon.color
                                    selected: sourceDetailsButton.pressed
                                }
                            }
                            Accessible.name: qsTr("Details for %1").arg(sourceRow.modelData.name)
                            onClicked: { page.detailsOpener = sourceDetailsButton; page.selectedSource = sourceRow.modelData; detailsDialog.open() }
                        }
                    }
                }
            }
            PageStatusLabel { objectName: "sourcesEmptyMessage"; Layout.margins: 24; visible: page.sources.length === 0 && !page.busy; text: qsTr("No sources configured.") }
            Item { Layout.preferredHeight: 24 }
        }
    }
    Dialog {
        id: addDialog
        objectName: "addSourceDialog"
        anchors.centerIn: parent; width: Math.min(page.width - 48, 600)
        title: qsTr("Add Flatpak Source"); modal: true
        contentItem: ColumnLayout {
            spacing: 14
            Label { Layout.fillWidth: true; text: qsTr("Enter an HTTPS .flatpakrepo address or choose a repository file."); wrapMode: Text.Wrap }
            TextField { id: sourceInput; objectName: "sourceInput"; Layout.fillWidth: true; placeholderText: "https://example.org/source.flatpakrepo"; selectByMouse: true }
            FluffButton { objectName: "chooseSourceFileButton"; text: qsTr("Choose File…"); icon.name: "document-open"; onClicked: sourceFile.open() }
            RowLayout {
                Layout.fillWidth: true
                FluffButton {
                    objectName: "addDefaultSourcesButton"
                    text: qsTr("Add Default Sources"); icon.name: "list-add"
                    visible: page.sources.length === 0
                    enabled: !page.busy
                    onClicked: { window.backend.addDefaultSources(); addDialog.close() }
                }
                Item { Layout.fillWidth: true }
                FluffButton { objectName: "cancelAddSourceButton"; text: qsTr("Cancel"); icon.name: "dialog-cancel"; onClicked: addDialog.close() }
                FluffButton {
                    objectName: "confirmAddSourceButton"
                    text: qsTr("Add Source"); icon.name: "list-add"
                    enabled: !!sourceInput.text.trim() && !page.busy
                    onClicked: { window.backend.openSource(sourceInput.text.trim()); addDialog.close() }
                }
            }
        }
    }
    FileDialogs.FileDialog {
        id: sourceFile
        objectName: "sourceFileDialog"
        title: qsTr("Choose a Flatpak repository")
        nameFilters: [qsTr("Flatpak repositories (*.flatpakrepo)")]
        onAccepted: sourceInput.text = selectedFile.toString()
    }
    Dialog {
        id: removeDialog
        objectName: "removeSourceDialog"
        anchors.centerIn: parent; width: Math.min(page.width - 48, 520)
        title: qsTr("Remove source?"); modal: true
        onOpened: cancelRemoveSourceButton.forceActiveFocus(Qt.TabFocusReason)
        contentItem: Label {
            text: (page.selectedSource && page.selectedSource.hasSystem
                ? qsTr("Remove %1 for all users?\n\nAdministrator authentication is required. Installed apps won’t be removed.")
                : qsTr("Remove %1?\n\nInstalled apps won’t be removed."))
                .arg(page.selectedSource ? page.selectedSource.title || page.selectedSource.name : "")
            textFormat: Text.PlainText; wrapMode: Text.Wrap
        }
        footer: DialogButtonBox {
            FluffButton {
                id: cancelRemoveSourceButton
                objectName: "cancelRemoveSourceButton"
                text: qsTr("Cancel"); icon.name: "dialog-cancel"
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
            FluffButton { objectName: "confirmRemoveSourceButton"; text: qsTr("Remove"); icon.source: Qt.resolvedUrl("trash-red.svg"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole }
            onAccepted: { window.backend.removeSource(page.selectedSource); removeDialog.close() }
            onRejected: removeDialog.close()
        }
    }
    Dialog {
        id: detailsDialog
        objectName: "sourceDetailsDialog"
        anchors.centerIn: parent; width: Math.min(page.width - 48, 560)
        title: qsTr("Source details"); modal: true
        // Opening information is not an action on Close. Start at the text;
        // Tab can still reach Close and Escape still dismisses the dialog.
        onOpened: contentItem.forceActiveFocus(Qt.OtherFocusReason)
        onClosed: {
            const opener = page.detailsOpener
            page.detailsOpener = null
            if (!opener) return
            const wasActive = opener.activeFocus
            opener.focus = false
            if (wasActive && page.StackView.status === StackView.Active)
                page.forceActiveFocus(Qt.OtherFocusReason)
        }
        header: Control {
            leftPadding: 18; rightPadding: 8; topPadding: 8; bottomPadding: 8
            contentItem: RowLayout {
                Label { text: detailsDialog.title; font.pixelSize: 20; Layout.fillWidth: true }
                FluffToolButton {
                    objectName: "closeSourceDetailsButton"
                    Layout.preferredWidth: 44; Layout.preferredHeight: 44
                    icon.name: "window-close"
                    Accessible.name: qsTr("Close")
                    onClicked: detailsDialog.close()
                }
            }
        }
        contentItem: Label {
            text: page.selectedSource ? qsTr("Name: %1\nAddress: %2\nInstallation: %3\nSignature verification: %4")
                .arg(page.selectedSource.name).arg(page.selectedSource.url)
                .arg(page.selectedSource.scope === "merged" ? qsTr("User and System") : page.selectedSource.scope)
                .arg(page.selectedSource.verified ? qsTr("Enabled") : qsTr("Disabled by source configuration")) : ""
            textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
        }
    }
}
