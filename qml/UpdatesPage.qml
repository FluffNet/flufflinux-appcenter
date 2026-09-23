import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    objectName: "updatesPage"
    focusPolicy: Qt.ClickFocus
    readonly property var updateData: window.backend && window.backend.updates || ({state: "idle", items: []})
    readonly property var rows: updateData.items || []
    readonly property bool checking: updateData.state === "checking"
    readonly property bool busy: !!window.backend && window.backend.busy
    readonly property var selected: rows.filter(row => row.selected)
    readonly property real selectedBytes: {
        const seen = {}; let total = 0
        for (const row of selected) for (const op of row.plan || []) {
            const key = row.installation + ":" + op.ref + ":" + op.commit
            if (!seen[key]) { seen[key] = true; total += Number(op.downloadBytes || 0) }
        }
        return total
    }
    function sizeText(bytes) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"]
        let i = 0; while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++ }
        return bytes.toLocaleString(Qt.locale(), 'f', i ? 2 : 0) + " " + units[i]
    }
    function jobFor(row) {
        const jobs = (window.backend && window.backend.jobs || []).filter(job => job.action === "update" && job.key === row.key)
        return jobs.length ? jobs[jobs.length - 1] : null
    }
    function sourceLabel(row) {
        const parts = String(row.flatpakRef || "").split("/")
        return row.remote + (row.installation !== "user" ? " (" + qsTr("System") + ")" : "")
            + (parts.length === 4 ? " - " + parts[3] + (row.runtime ? " / " + parts[2] : "") : "")
            + (row.runtime ? " - " + qsTr("Runtime") : "")
    }
    background: Control { focusPolicy: Qt.ClickFocus }
    header: ToolBar {
        height: 72
        background: Rectangle {
            color: window.backgroundColor
            FluffSeparator { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom }
        }
        RowLayout {
            anchors.fill: parent; anchors.margins: 12
            FluffToolButton { text: qsTr("Back"); icon.name: "go-previous"; onClicked: window.goBack() }
            Item { Layout.fillWidth: true }
            FluffToolButton { text: qsTr("Queue"); icon.name: "view-list-details"; onClicked: window.showDownloads() }
        }
    }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 24
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Updates"); color: window.textColor; font.pixelSize: 32; font.weight: Font.DemiBold; Layout.fillWidth: true }
            FluffButton {
                objectName: "checkForUpdatesButton"
                text: qsTr("Check for Updates"); icon.name: "view-refresh"
                enabled: !page.busy && !page.checking
                onClicked: window.backend.checkForUpdates()
            }
            FluffButton {
                visible: page.checking; text: qsTr("Cancel"); icon.name: "dialog-cancel"
                onClicked: window.backend.cancelUpdateCheck()
            }
        }
        Label {
            objectName: "updateDates"
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: window.mutedTextColor
            text: (page.updateData.lastChecked ? qsTr("Last checked: %1").arg(page.updateData.lastChecked) : qsTr("Updates are checked only when you press Check for Updates."))
                + (page.updateData.lastUpdated ? "\n" + qsTr("Last app update: %1").arg(page.updateData.lastUpdated) : "")
        }
        RowLayout {
            visible: page.checking; Layout.fillWidth: true
            LoadingSpinner { running: page.checking; Layout.preferredWidth: 24; Layout.preferredHeight: 24 }
            Label { text: page.updateData.status || qsTr("Checking for updates…"); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: window.mutedTextColor; Layout.fillWidth: true }
        }
        Label {
            objectName: "updatesError"; visible: !!page.updateData.error
            Layout.fillWidth: true; Layout.maximumHeight: 100
            text: page.updateData.error || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; elide: Text.ElideRight; color: window.accentColor
        }
        RowLayout {
            visible: page.rows.length > 0; Layout.fillWidth: true
            UpdateCheckBox {
                objectName: "selectAllUpdates"
                text: qsTr("Select All"); enabled: !page.busy && page.updateData.state === "ready"
                checkState: page.selected.length === page.rows.length ? Qt.Checked : page.selected.length ? Qt.PartiallyChecked : Qt.Unchecked
                nextCheckState: function() { return checkState === Qt.Checked ? Qt.Unchecked : Qt.Checked }
                onClicked: window.backend.selectAllUpdates(checkState === Qt.Checked)
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: window.mutedTextColor
                text: qsTr("%1 selected - up to %2 download").arg(page.selected.length).arg(page.sizeText(page.selectedBytes))
            }
            FluffButton {
                objectName: "installUpdatesButton"
                text: qsTr("Update Selected"); icon.name: "system-software-update"
                enabled: page.selected.length > 0 && !page.busy && page.updateData.state === "ready"
                onClicked: window.backend.installSelectedUpdates()
            }
        }
        Label {
            visible: page.rows.length > 0; Layout.fillWidth: true; wrapMode: Text.Wrap; color: window.mutedTextColor
            text: qsTr("Required components update with selected apps. Shared components are counted once in the download estimate; cached data may reduce it.")
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true
            ListView {
                id: list
                objectName: "updatesList"
                anchors.fill: parent; anchors.rightMargin: 16
                clip: true; spacing: 12; model: page.rows; contentWidth: width
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: PageScrollBar {
                    parent: list.parent; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                    visible: size < 1
                }
                NaturalWheelScroll { scrollTarget: list }
                delegate: Rectangle {
                    required property var modelData
                    readonly property var job: page.jobFor(modelData)
                    width: list.width; implicitHeight: contents.implicitHeight + 32
                    color: window.surfaceColor; radius: window.cornerRadius; border.color: window.borderColor
                    RowLayout {
                        id: contents
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
                        spacing: 16
                        UpdateCheckBox {
                            objectName: "selectUpdate-" + modelData.key
                            checked: modelData.selected; enabled: !page.busy && page.updateData.state === "ready"
                            Accessible.name: qsTr("Update %1").arg(modelData.name)
                            onClicked: window.backend.selectUpdate(modelData.key, checked)
                        }
                        AppIcon { icon: modelData.icon || ""; Layout.preferredWidth: 56; Layout.preferredHeight: 56 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 5
                            Label { text: modelData.name; textFormat: Text.PlainText; font.pixelSize: 18; font.weight: Font.DemiBold; color: window.textColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Label { text: modelData.oldVersion + " → " + modelData.newVersion; textFormat: Text.PlainText; color: window.textColor; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                            Label { text: qsTr("Download: up to %1").arg(page.sizeText(modelData.downloadBytes || 0)); color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Label { text: page.sourceLabel(modelData); textFormat: Text.PlainText; color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Label {
                                visible: !modelData.runtime
                                text: modelData.permissions.state === "changed" ? qsTr("Permissions changed")
                                    : modelData.permissions.state === "unchanged" ? qsTr("No permission changes") : qsTr("Permission comparison unavailable")
                                color: modelData.permissions.state === "unchanged" ? window.mutedTextColor : window.accentColor
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                            }
                            FluffButton {
                                visible: modelData.permissions.state === "changed"
                                text: qsTr("View Permission Changes"); icon.name: "object-locked"
                                onClicked: { changesDialog.app = modelData; changesDialog.changes = modelData.permissions; changesDialog.open() }
                            }
                            Label { visible: !!job; text: job ? job.status + (job.error ? "\n" + job.error : "") : ""; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.Wrap; color: job && job.failed ? window.accentColor : window.mutedTextColor }
                            FluffProgressBar { visible: !!job && job.active; Layout.fillWidth: true; value: job ? job.progress : 0; indeterminate: !!job && job.queued }
                        }
                    }
                }
            }
            Label {
                objectName: "updatesEmpty"
                anchors.centerIn: parent; width: parent.width; horizontalAlignment: Text.AlignHCenter
                visible: page.rows.length === 0 && !page.checking
                text: page.updateData.state === "ready" && !page.updateData.error ? qsTr("Everything is up to date.")
                    : page.updateData.state === "cancelled" ? qsTr("Update check cancelled.")
                    : page.updateData.error ? qsTr("Could not check all updates. Please try again.") : qsTr("Press Check for Updates to see available updates.")
                color: window.mutedTextColor; wrapMode: Text.Wrap
            }
        }
    }
    AppPermissionsDialog { id: changesDialog; changesView: true; onClosed: page.forceActiveFocus(Qt.OtherFocusReason) }
}
