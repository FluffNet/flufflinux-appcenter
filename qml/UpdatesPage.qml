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
    readonly property var skipped: updateData.skipped || []
    readonly property bool busy: !!window.backend && window.backend.busy
    readonly property bool compact: width < 600
    onVisibleChanged: if (!visible) changesDialog.close()
    readonly property var selected: rows.filter(row => row.selected)
    readonly property bool allSelected: rows.length > 0 && selected.length === rows.length
    readonly property real selectedBytes: {
        const sizes = {}
        for (const row of selected) for (const op of row.plan || []) {
            const key = row.installation + ":" + op.ref + ":" + op.commit
            sizes[key] = Number(op.downloadBytes || 0)
        }
        // Use resolved transfer totals once jobs start, just as the install
        // page does. Completed pulls report actual bytes, including cache hits.
        // Apply these after the plans so a queued app's shared dependency
        // cannot overwrite an already-resolved total.
        const resolved = {}
        for (const row of selected) {
            const job = jobFor(row)
            if (!job || job.queued) continue
            for (const op of job.operations || []) {
                const key = row.installation + ":" + op.ref + ":" + op.commit
                if (sizes[key] === undefined) continue
                const received = Number(op.receivedBytes || 0)
                const bytes = op.downloadProgress >= 1 ? received
                    : Math.max(received, Number(op.downloadBytes || 0))
                resolved[key] = Math.max(resolved[key] || 0, bytes)
            }
        }
        Object.assign(sizes, resolved)
        return Object.values(sizes).reduce((total, bytes) => total + bytes, 0)
    }
    function sizeText(bytes) {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"]
        let i = 0; while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++ }
        return bytes.toLocaleString(Qt.locale(), 'f', i ? 2 : 0) + " " + units[i]
    }
    function jobFor(row) {
        const jobs = (window.backend && window.backend.jobs || []).filter(job => {
            if (job.action !== "update" || job.key !== row.key) return false
            // Finished history must not supply sizes/status for a later scan
            // of another release (including dependency-only refreshes).
            if (row.commit && (job.commit !== row.commit || job.oldCommit !== row.oldCommit)) return false
            return !row.plan || !job.plan || (row.plan.length === job.plan.length
                && row.plan.every(op => job.plan.some(other => op.ref === other.ref && op.commit === other.commit)))
        })
        return jobs.length ? jobs[jobs.length - 1] : null
    }
    function versionLabel(row) {
        const oldVersion = String(row.oldVersion || "").trim()
        const newVersion = String(row.newVersion || "").trim()
        return oldVersion && oldVersion === newVersion
            ? qsTr("%1 → %2 (Refresh)").arg(oldVersion).arg(newVersion)
            : qsTr("%1 → %2").arg(oldVersion).arg(newVersion)
    }
    function sourceLabel(row) {
        const parts = String(row.flatpakRef || "").split("/")
        return row.remote + (row.installation !== "user" ? " (" + qsTr("System") + ")" : "")
            + (parts.length === 4 ? " - " + parts[3] + (row.runtime ? " / " + parts[2] : "") : "")
            + (row.runtime ? " - " + qsTr("Runtime") : "")
    }
    background: Control { focusPolicy: Qt.ClickFocus }
    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 28; anchors.rightMargin: 28
        anchors.topMargin: 26; anchors.bottomMargin: 20
        spacing: 14
        GridLayout {
            Layout.fillWidth: true
            columns: page.compact ? 1 : 2
            Label { objectName: "appUpdatesTitle"; text: qsTr("App Updates"); color: window.textColor; font.pixelSize: 32; font.weight: Font.DemiBold; Layout.fillWidth: true }
            FluffButton {
                objectName: "checkForUpdatesButton"
                visible: !page.checking
                text: qsTr("Check for App Updates"); icon.name: "view-refresh"
                contentItem: FluffButtonContent { monochromeIcon: true }
                Layout.alignment: Qt.AlignRight
                enabled: !window.networkOffline && !page.busy && !page.checking
                onClicked: if (!window.networkOffline) window.backend.checkForUpdates()
            }
            FluffButton {
                objectName: "cancelUpdateCheckButton"
                visible: page.checking; text: qsTr("Cancel"); icon.name: "dialog-cancel"
                contentItem: FluffButtonContent { monochromeIcon: true }
                Layout.alignment: Qt.AlignRight
                onClicked: window.backend.cancelUpdateCheck()
            }
        }
        Label {
            objectName: "updateDates"
            Layout.fillWidth: true; wrapMode: Text.Wrap; color: window.mutedTextColor
            text: qsTr("Apps were last updated: %1").arg(page.updateData.lastUpdated || qsTr("Not recorded"))
        }
        NetworkNotice {
            objectName: "updatesOfflineNote"
            networkState: "offline"; compact: true
            visible: window.networkOffline
            Layout.fillWidth: true
        }
        Label {
            objectName: "updatesError"; visible: !!page.updateData.error
            Layout.fillWidth: true; maximumLineCount: 3
            text: page.updateData.error || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; elide: Text.ElideRight; color: window.accentColor
        }
        Label {
            objectName: "updatesSkipped"
            visible: page.skipped.length > 0
            Layout.fillWidth: true; maximumLineCount: 3
            text: page.skipped.join("\n"); textFormat: Text.PlainText
            wrapMode: Text.Wrap; elide: Text.ElideRight; color: window.mutedTextColor
            HoverHandler { id: skippedHover }
            ToolTip.visible: skippedHover.hovered
            ToolTip.text: text
        }
        GridLayout {
            visible: page.rows.length > 0; Layout.fillWidth: true
            columns: page.compact ? 2 : 3
            UpdateCheckBox {
                Layout.row: 0; Layout.column: 0
                objectName: "selectAllUpdates"
                text: qsTr("Select All"); enabled: !page.busy && page.updateData.state === "ready"
                checkState: page.allSelected ? Qt.Checked : page.selected.length ? Qt.PartiallyChecked : Qt.Unchecked
                nextCheckState: function() { return checkState === Qt.Checked ? Qt.Unchecked : Qt.Checked }
                onClicked: window.backend.selectAllUpdates(checkState === Qt.Checked)
            }
            Label {
                objectName: "updatesDownloadSummary"
                Layout.row: page.compact ? 1 : 0; Layout.column: page.compact ? 0 : 1
                Layout.columnSpan: page.compact ? 2 : 1
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: window.mutedTextColor
                text: qsTr("%1 selected — Total size: %2").arg(page.selected.length).arg(page.sizeText(page.selectedBytes))
                HoverHandler { id: downloadSummaryHover }
                ToolTip.visible: downloadSummaryHover.hovered
                ToolTip.text: qsTr("Required components update with selected apps. Shared components are counted once; cached data may reduce the download.")
            }
            FluffButton {
                Layout.row: 0; Layout.column: page.compact ? 1 : 2
                Layout.alignment: Qt.AlignRight
                objectName: "installUpdatesButton"
                text: page.allSelected ? qsTr("Update All Apps") : qsTr("Update selected apps")
                icon.name: "system-upgrade"
                contentItem: FluffButtonContent { monochromeIcon: true }
                enabled: !window.networkOffline && page.selected.length > 0 && !page.busy && page.updateData.state === "ready"
                onClicked: if (!window.networkOffline) window.backend.installSelectedUpdates()
            }
        }
        Item {
            objectName: "updatesContentArea"
            Layout.fillWidth: true; Layout.fillHeight: true
            ListView {
                id: list
                objectName: "updatesList"
                visible: !page.checking
                anchors.fill: parent
                clip: true; spacing: 12; model: page.rows; contentWidth: width
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: PageScrollBar {
                    objectName: "updatesPageScrollBar"
                    parent: page.contentItem
                    anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                    visible: page.visible && size < 1
                }
                NaturalWheelScroll { scrollTarget: list }
                delegate: Rectangle {
                    id: updateRow
                    required property var modelData
                    objectName: "updateRow-" + modelData.key
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
                            AppPublisher { objectName: "updateAppPublisher"; app: modelData; Layout.fillWidth: true }
                            Label { objectName: "updateVersion"; text: page.versionLabel(modelData); textFormat: Text.PlainText; color: window.textColor; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                            Label {
                                objectName: "updateDownloadSize"
                                text: qsTr("Size: %1").arg(job && job.downloadTotalSize
                                    ? job.downloadTotalSize : page.sizeText(modelData.downloadBytes || 0))
                                color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap
                            }
                            Label { text: page.sourceLabel(modelData); textFormat: Text.PlainText; color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Label {
                                objectName: "updatePermissionsStatus"
                                visible: !modelData.runtime && modelData.permissions.state !== "unchanged"
                                text: modelData.permissions.state === "changed" ? qsTr("Permissions changed")
                                    : modelData.permissions.state === "unchanged" ? "" : qsTr("Permission comparison unavailable")
                                color: window.accentColor
                                Layout.fillWidth: true; wrapMode: Text.Wrap
                            }
                            FluffButton {
                                objectName: "viewUpdatePermissionChanges"
                                visible: modelData.permissions.state === "changed"
                                text: qsTr("View Permission Changes"); icon.name: "object-locked"
                                contentItem: FluffButtonContent { monochromeIcon: true }
                                onClicked: { changesDialog.app = modelData; changesDialog.changes = modelData.permissions; changesDialog.open() }
                            }
                            Label {
                                objectName: "updateJobStatus"
                                readonly property bool queuedStatus: !!job && job.active && job.queued && !job.failed && !job.cancelling
                                // The shared installation display supplies normal
                                // transfer/deployment details. Keep actionable states.
                                visible: !!job && (queuedStatus || !job.active || job.failed || job.error || job.cancelling
                                    || !updateProgress.planned || (job.index !== undefined && window.backend.review && window.backend.review.jobIndex === job.index))
                                text: job ? (queuedStatus ? qsTr("Queued…") : job.status)
                                    + (job.error ? "\n" + job.error : "") : ""
                                textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.Wrap
                                font.bold: queuedStatus
                                color: job && job.failed ? window.accentColor : queuedStatus ? window.textColor : window.mutedTextColor
                            }
                            InstallationProgress {
                                id: updateProgress
                                objectName: "updateJobProgress"
                                Layout.fillWidth: true
                                job: updateRow.job
                            }
                        }
                    }
                }
            }
            RowLayout {
                objectName: "updateCheckIndicator"
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                spacing: 10
                visible: page.checking
                LoadingSpinner {
                    objectName: "updateCheckSpinner"
                    running: page.checking && page.visible
                    color: window.textColor
                    Layout.preferredWidth: 24; Layout.preferredHeight: 24
                }
                Label {
                    objectName: "updateCheckStatus"
                    text: qsTr("Checking for app updates…")
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: window.mutedTextColor; Layout.fillWidth: true
                }
            }
            Label {
                objectName: "updatesEmpty"
                anchors.centerIn: parent; width: parent.width; horizontalAlignment: Text.AlignHCenter
                visible: page.rows.length === 0 && !page.checking && text.length > 0
                text: window.networkOffline ? ""
                    : page.updateData.state === "ready" && !page.updateData.error
                    ? (page.skipped.length ? qsTr("No app updates available from the sources that could be checked.") : qsTr("Your apps are up to date."))
                    : page.updateData.state === "cancelled" ? qsTr("App update check cancelled.")
                    : page.updateData.error ? qsTr("Could not check all app updates. Please try again.") : ""
                color: window.mutedTextColor; wrapMode: Text.Wrap
            }
        }
    }
    AppPermissionsDialog { id: changesDialog; changesView: true; onClosed: if (page.visible) page.forceActiveFocus(Qt.OtherFocusReason) }
}
