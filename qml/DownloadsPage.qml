import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    focusPolicy: Qt.ClickFocus
    id: page
    objectName: "downloadsPage"
    // Keep delegates alive while the backend replaces its progress snapshots.
    // Recreating a pressed card loses its mouse grab before release/click.
    ListModel { id: jobRows }
    function syncJobRows() {
        const keys = window.downloadQueue.jobs.map(job => job.index)
        // Populate/clear in one model notification. Hundreds of individual
        // insertions/removals otherwise block navigation before the first frame.
        if (!keys.length) {
            if (jobRows.count) {
                jobRows.clear()
                scroll.forceLayout()
            }
            return
        }
        if (!jobRows.count) {
            jobRows.append(keys.map(jobIndex => ({jobIndex: jobIndex})))
            scroll.forceLayout()
            return
        }
        const present = new Set(keys)
        let changed = false
        for (let row = jobRows.count - 1; row >= 0; --row) {
            if (!present.has(jobRows.get(row).jobIndex)) {
                jobRows.remove(row)
                changed = true
            }
        }
        for (let row = 0; row < keys.length; ++row) {
            if (row < jobRows.count && jobRows.get(row).jobIndex === keys[row]) continue
            let existing = row + 1
            while (existing < jobRows.count && jobRows.get(existing).jobIndex !== keys[row]) ++existing
            if (existing < jobRows.count) jobRows.move(existing, row, 1)
            else jobRows.insert(row, {jobIndex: keys[row]})
            changed = true
        }
        if (changed) scroll.forceLayout()
    }
    Component.onCompleted: syncJobRows()
    StackView.onActivated: window.downloadQueue.markViewed()
    Connections {
        target: window.downloadQueue
        function onMembershipChanged() { page.syncJobRows() }
        function onActiveCountChanged() {
            if (page.StackView.status === StackView.Active) window.downloadQueue.markViewed()
        }
    }
    background: Control { focusPolicy: Qt.ClickFocus }
    header: ToolBar {
        focusPolicy: Qt.ClickFocus
        height: 72
        background: Rectangle {
            color: window.backgroundColor
            border.width: 0
            FluffSeparator { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom }
        }
        RowLayout {
            anchors.fill: parent; anchors.margins: 12
            Item {
                Layout.preferredWidth: Math.max(backButton.implicitWidth, clearHistory.implicitWidth)
                Layout.preferredHeight: Math.max(backButton.implicitHeight, clearHistory.implicitHeight)
                FluffToolButton {
                    id: backButton
                    objectName: "downloadsBackButton"
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Back"); icon.name: mirrored ? "go-next" : "go-previous"
                    contentItem: FluffButtonContent { monochromeIcon: true }
                    onClicked: window.goBack()
                }
            }
            Label {
                objectName: "downloadsTitle"
                Layout.fillWidth: true
                text: qsTr("Queue"); color: window.textColor
                font.pixelSize: 24; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            // Equal side columns keep the title centered on the whole page.
            Item {
                Layout.preferredWidth: Math.max(backButton.implicitWidth, clearHistory.implicitWidth)
                Layout.preferredHeight: Math.max(backButton.implicitHeight, clearHistory.implicitHeight)
                FluffToolButton {
                    id: clearHistory
                    objectName: "clearDownloadHistoryButton"
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Clear History")
                    icon.name: "edit-clear-history"
                    enabled: window.downloadQueue.jobs.some(function(job) { return !job.active })
                    onClicked: if (window.backend) window.backend.clearDownloadHistory()
                }
            }
        }
    }
    ListView {
        id: scroll
        objectName: "downloadJobs"
        EmptySpaceFocus { parent: scroll }
        anchors.fill: parent
        anchors.margins: 24
        contentWidth: width
        clip: true
        spacing: 16
        // Only visible cards and a small look-ahead are instantiated. A long
        // completed queue must not keep hundreds of controls/images alive.
        cacheBuffer: 200
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PageScrollBar {
            objectName: "downloadsPageScrollBar"
            // Keep the rail in the page gutter, outside the cards. The
            // trailing anchor mirrors to the left in RTL layouts.
            parent: page.contentItem
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            visible: page.visible && size < 1
        }
        PageWheelScroll { scrollTarget: scroll }
        model: jobRows
        delegate: Pane {
            focusPolicy: Qt.ClickFocus
            id: downloadCard
            required property int jobIndex
            readonly property var modelData: window.downloadQueue.jobsByIndex[jobIndex]
                || {id: "", name: "", active: false, operations: []}
            // Progress is not app identity. Keep catalog/publisher lookups
            // independent of a changing row's transfer/operation payload.
            readonly property string appId: modelData.id || ""
            readonly property string installation: modelData.installation || ""
            readonly property string installedBranch: modelData.installedBranch || ""
            readonly property bool addon: modelData.addon === true
            readonly property var installedApp: window.findInstalled({id: appId,
                installation: installation || undefined, installedBranch: installedBranch || undefined})
            readonly property var detailsApp: addon
                ? window.installedApps.find(item => modelData.parent
                    && item.installedRef === modelData.parent.installedRef
                    && item.installation === modelData.parent.installation) || null
                : !appId ? null : installedApp
                || window.catalogApp(appId)
                || Object.assign({summary: "", description: "", screenshots: [], developer: "", category: "", license: "", homepage: ""}, modelData)
            readonly property var appJob: window.jobForApp(installedApp)
            readonly property bool canOpen: !modelData.active && !modelData.failed
                && !modelData.cancelled && !!installedApp && (!appJob || !appJob.active)
            width: scroll.width
            padding: 20
            background: Rectangle { radius: window.cornerRadius; color: window.surfaceColor; border.color: window.borderColor }
            contentItem: ColumnLayout {
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14
                    AbstractButton {
                        focusPolicy: Qt.TabFocus
                        PointerFocusHandler {}
                        id: detailsButton
                        objectName: "downloadAppDetailsButton"
                        Layout.fillWidth: true
                        hoverEnabled: true
                        enabled: !!downloadCard.detailsApp
                        Accessible.name: (modelData.addon ? qsTr("View parent app details for %1") : qsTr("View details for %1")).arg(modelData.name)
                        onClicked: window.openApp(downloadCard.detailsApp)
                        background: FluffButtonBackground { idleColor: "transparent"; idleBorderColor: "transparent" }
                        contentItem: RowLayout {
                            spacing: 14
                            AppIcon {
                                objectName: "downloadAppIcon"
                                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                                Layout.alignment: Qt.AlignVCenter
                                sourceSize: Qt.size(64, 64)
                                Accessible.ignored: true
                                icon: modelData.icon || ""
                            }
                            ColumnLayout {
                                objectName: "downloadAppText"
                                Layout.fillWidth: true; spacing: 5
                                Label { objectName: "downloadAppName"; text: modelData.name; textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 20; font.bold: true; color: window.textColor; Layout.fillWidth: true }
                                AppPublisher { objectName: "downloadAppPublisher"; app: downloadCard.detailsApp; Layout.fillWidth: true }
                                Label {
                                    objectName: "downloadJobAction"
                                    Layout.fillWidth: true
                                    text: modelData.action === "uninstall" ? qsTr("Action: Remove")
                                        : modelData.action === "update" ? qsTr("Action: Update") : qsTr("Action: Install")
                                    color: window.textColor
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                        HoverHandler { cursorShape: detailsButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    }
                    AppActionButton {
                        objectName: "cancelDownloadButton"
                        Layout.fillWidth: false
                        visible: modelData.active
                        text: qsTr("Cancel")
                        icon.name: "dialog-cancel"
                        onClicked: if (window.backend) window.backend.cancelJob(modelData.index)
                    }
                    AppActionButton {
                        objectName: "clearFailedDownloadButton"
                        Layout.fillWidth: false
                        visible: modelData.failed === true && !modelData.active
                        text: qsTr("Clear")
                        icon.name: "edit-clear-history"
                        Accessible.name: qsTr("Clear failed operation for %1").arg(modelData.name)
                        onClicked: if (window.backend) window.backend.clearFailedJob(modelData.index)
                    }
                    AppActionButton {
                        objectName: "openDownloadButton"
                        Layout.fillWidth: false
                        visible: downloadCard.canOpen
                        text: qsTr("Open")
                        icon.name: "media-playback-start"
                        onClicked: if (window.backend && downloadCard.canOpen)
                            window.backend.launchApp(downloadCard.installedApp)
                    }
                }
                Label {
                    objectName: "downloadJobStatus"
                    Layout.fillWidth: true
                    visible: text.length > 0
                    // Successful history is represented by Open, never completion text.
                    text: modelData.failed ? qsTr("Failed")
                          : !modelData.active ? ""
                          : modelData.cancelling ? qsTr("Cancelling…")
                          : window.backend && window.backend.review && window.backend.review.jobIndex === modelData.index ? qsTr("Waiting for confirmation")
                          : modelData.queued ? qsTr("Pending…")
                          : !(modelData.operations || []).length ? qsTr("Preparing…") : ""
                    textFormat: Text.PlainText; wrapMode: Text.Wrap
                    font.bold: modelData.active && modelData.queued === true
                    color: modelData.failed ? window.accentTextColor : font.bold ? window.textColor : window.mutedTextColor
                }
                InstallationProgress {
                    objectName: "downloadJobProgress"
                    Layout.fillWidth: true
                    job: modelData
                }
                Label {
                    objectName: "downloadJobError"
                    Layout.fillWidth: true; visible: !!modelData.error
                    text: modelData.error || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: window.accentTextColor
                }
            }
        }
        PageStatusLabel { objectName: "queueEmptyMessage"; visible: !scroll.count; text: qsTr("No operations yet.") }
    }
}
