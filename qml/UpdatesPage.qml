import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Bidi.js" as Bidi

Page {
    id: page
    objectName: "updatesPage"
    focusPolicy: Qt.ClickFocus
    readonly property var updateData: !visible || !window.backend ? ({state: "idle"})
        : typeof window.backend.updateStatus !== "undefined" ? window.backend.updateStatus : window.backend.updates
    readonly property var rows: visible ? window.updateItems : []
    readonly property var rowsByKey: {
        const result = {}
        for (const row of rows) result["$" + row.key] = row
        return result
    }
    readonly property string membership: JSON.stringify(rows.map(row => row.key))
    ListModel { id: updateRows }
    function syncRows() {
        const keys = page.rows.map(row => row.key)
        if (!keys.length) {
            if (updateRows.count) updateRows.clear()
            return
        }
        if (!updateRows.count) {
            updateRows.append(keys.map(updateKey => ({updateKey})))
            return
        }
        const present = new Set(keys)
        for (let row = updateRows.count - 1; row >= 0; --row)
            if (!present.has(updateRows.get(row).updateKey)) updateRows.remove(row)
        for (let row = 0; row < keys.length; ++row) {
            if (row < updateRows.count && updateRows.get(row).updateKey === keys[row]) continue
            let existing = row + 1
            while (existing < updateRows.count && updateRows.get(existing).updateKey !== keys[row]) ++existing
            if (existing < updateRows.count) updateRows.move(existing, row, 1)
            else updateRows.insert(row, {updateKey: keys[row]})
        }
    }
    onMembershipChanged: syncRows()
    Component.onCompleted: syncRows()
    readonly property bool checking: updateData.state === "checking"
    readonly property var skipped: updateData.skipped || []
    readonly property bool busy: !!window.backend && window.backend.busy
    readonly property bool compact: width < 600
    property real savedScrollY: 0
    property bool restoringScroll: true
    onVisibleChanged: {
        if (!visible) { restoringScroll = true; changesDialog.close() }
        else Qt.callLater(function() {
            if (!page.visible) return
            list.forceLayout()
            list.contentY = Math.max(list.originY, Math.min(page.savedScrollY,
                list.originY + Math.max(0, list.contentHeight - list.height)))
            page.restoringScroll = false
        })
    }
    readonly property var selected: rows.filter(row => row.selected)
    readonly property bool allSelected: rows.length > 0 && selected.length === rows.length
    readonly property var plannedSizes: {
        const sizes = {}
        if (!visible) return sizes
        for (const row of selected) for (const op of row.plan || []) {
            const key = row.installation + ":" + op.ref + ":" + op.commit
            sizes[key] = Number(op.downloadBytes || 0)
        }
        return sizes
    }
    readonly property real selectedBytes: {
        if (!visible) return 0
        const sizes = Object.assign({}, plannedSizes)
        // Use resolved transfer totals once jobs start, just as the install
        // page does. Completed pulls report actual bytes, including cache hits.
        // Apply these after the plans so a queued app's shared dependency
        // cannot overwrite an already-resolved total.
        const resolved = {}
        for (const row of selected) {
            const job = jobFor(row, true)
            if (!job) continue
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
    readonly property var updateJobsByKey: {
        const grouped = {}
        if (!visible) return grouped
        for (const job of window.backendJobs) {
            if (job.action !== "update") continue
            const key = "$" + job.key
            if (!grouped[key]) grouped[key] = []
            grouped[key].push(job)
        }
        return grouped
    }
    function jobFor(row, skipQueued) {
        const jobs = updateJobsByKey["$" + row.key] || []
        for (let index = jobs.length - 1; index >= 0; --index) {
            const job = jobs[index]
            // A current queued job has no resolved bytes; do not fall back to
            // a previous completed attempt or compare all its dependency refs.
            if (skipQueued && job.queued) return null
            // Finished history must not supply sizes/status for a later scan
            // of another release (including dependency-only refreshes).
            if (row.commit && (job.commit !== row.commit || job.oldCommit !== row.oldCommit)) continue
            if (!row.plan || !job.plan || (row.plan.length === job.plan.length
                && row.plan.every(op => job.plan.some(other => op.ref === other.ref && op.commit === other.commit)))) return job
        }
        return null
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
            Layout.minimumWidth: 0
            columns: page.compact ? 1 : 2
            Label {
                objectName: "appUpdatesTitle"
                text: qsTr("App Updates"); color: window.textColor
                font.pixelSize: 32; font.weight: Font.DemiBold
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: 24
                Layout.fillWidth: true; Layout.minimumWidth: 0
                wrapMode: Text.Wrap
            }
            FluffButton {
                objectName: "checkForUpdatesButton"
                visible: !page.checking
                text: qsTr("Check for App Updates"); icon.name: "view-refresh"
                contentItem: FluffButtonContent { monochromeIcon: true }
                Layout.alignment: Qt.AlignRight
                Layout.minimumWidth: 0
                Layout.maximumWidth: page.width - 56
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
            text: Bidi.format(qsTr("Apps were last updated: %1"), [page.updateData.lastUpdated || qsTr("Not recorded")], page.mirrored)
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
            text: page.updateData.error || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; elide: Text.ElideRight; color: window.accentTextColor
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
            Layout.minimumWidth: 0
            columns: page.compact ? 1 : 3
            UpdateCheckBox {
                Layout.row: 0; Layout.column: 0
                objectName: "selectAllUpdates"
                Layout.minimumWidth: 0
                Layout.maximumWidth: page.width - 56
                text: qsTr("Select All"); enabled: !page.busy && page.updateData.state === "ready"
                checkState: page.allSelected ? Qt.Checked : page.selected.length ? Qt.PartiallyChecked : Qt.Unchecked
                nextCheckState: function() { return checkState === Qt.Checked ? Qt.Unchecked : Qt.Checked }
                onClicked: window.backend.selectAllUpdates(checkState === Qt.Checked)
            }
            Label {
                objectName: "updatesDownloadSummary"
                Layout.row: page.compact ? 1 : 0; Layout.column: page.compact ? 0 : 1
                Layout.columnSpan: 1
                Layout.minimumWidth: 0
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: window.mutedTextColor
                text: Bidi.format(qsTr("%1 selected - Total size: %2"), [page.selected.length, page.sizeText(page.selectedBytes)], page.mirrored)
                HoverHandler { id: downloadSummaryHover }
                ToolTip.visible: downloadSummaryHover.hovered
                ToolTip.text: qsTr("Required components update with selected apps. Shared components are counted once; cached data may reduce the download.")
            }
            FluffButton {
                Layout.row: page.compact ? 2 : 0; Layout.column: page.compact ? 0 : 2
                Layout.alignment: Qt.AlignRight
                Layout.minimumWidth: 0
                Layout.maximumWidth: page.width - 56
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
                clip: true; spacing: 12; contentWidth: width
                // A hidden Updates page must not rebuild native controls for
                // each completion while the user is scrolling Queue/App view.
                model: updateRows
                onContentYChanged: if (page.visible && !page.restoringScroll) page.savedScrollY = contentY
                reuseItems: true
                cacheBuffer: 200
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: PageScrollBar {
                    objectName: "updatesPageScrollBar"
                    parent: page.contentItem
                    anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                    visible: page.visible && size < 1
                }
                PageWheelScroll { scrollTarget: list }
                delegate: Rectangle {
                    id: updateRow
                    required property string updateKey
                    readonly property var modelData: page.rowsByKey["$" + updateKey]
                        || ({key: updateKey, name: "", selected: false, remote: "", permissions: {state: "unchanged"}})
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
                        AppIcon { icon: modelData.icon || ""; sourceSize: Qt.size(64, 64); Layout.preferredWidth: 56; Layout.preferredHeight: 56 }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 5
                            Label { text: modelData.name; textFormat: Text.PlainText; font.pixelSize: 18; font.weight: Font.DemiBold; color: window.textColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            AppPublisher { objectName: "updateAppPublisher"; app: modelData; Layout.fillWidth: true }
                            Label { objectName: "updateVersion"; text: page.versionLabel(modelData); textFormat: Text.PlainText; color: window.textColor; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                            Label {
                                objectName: "updateDownloadSize"
                                text: Bidi.format(qsTr("Size: %1"), [job && job.downloadTotalSize
                                    ? job.downloadTotalSize : page.sizeText(modelData.downloadBytes || 0)], page.mirrored)
                                color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap
                            }
                            Label { text: page.sourceLabel(modelData); textFormat: Text.PlainText; color: window.mutedTextColor; Layout.fillWidth: true; wrapMode: Text.Wrap }
                            Label {
                                objectName: "updatePermissionsStatus"
                                visible: !modelData.runtime && modelData.permissions.state !== "unchanged"
                                text: modelData.permissions.state === "changed" ? qsTr("Permissions changed")
                                    : modelData.permissions.state === "unchanged" ? "" : qsTr("Permission comparison unavailable")
                                color: window.accentTextColor
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
                                text: job ? (queuedStatus ? qsTr("Queued…") : qsTranslate("AppCenter", job.status || ""))
                                    + (job.error ? "\n" + job.error : "") : ""
                                textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.Wrap
                                font.bold: queuedStatus
                                color: job && job.failed ? window.accentTextColor : queuedStatus ? window.textColor : window.mutedTextColor
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
                PageStatusLabel {
                    objectName: "updateCheckStatus"
                    text: qsTr("Checking for app updates…")
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }
            PageStatusLabel {
                objectName: "updatesEmpty"
                anchors.centerIn: parent; width: parent.width; horizontalAlignment: Text.AlignHCenter
                visible: page.rows.length === 0 && !page.checking && text.length > 0
                text: window.networkOffline ? ""
                    : page.updateData.state === "ready" && !page.updateData.error
                    ? (page.skipped.length ? qsTr("No app updates available from the sources that could be checked.") : qsTr("Your apps are up to date."))
                    : page.updateData.state === "cancelled" ? qsTr("App update check cancelled.")
                    : page.updateData.error ? qsTr("Could not check all app updates. Please try again.") : ""
                wrapMode: Text.Wrap
            }
        }
    }
    AppPermissionsDialog { id: changesDialog; changesView: true; onClosed: if (page.visible) page.forceActiveFocus(Qt.OtherFocusReason) }
}
