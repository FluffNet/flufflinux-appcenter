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
        for (let row = jobRows.count - 1; row >= 0; --row)
            if (keys.indexOf(jobRows.get(row).jobIndex) < 0) jobRows.remove(row)
        for (let row = 0; row < keys.length; ++row) {
            if (row < jobRows.count && jobRows.get(row).jobIndex === keys[row]) continue
            let existing = row + 1
            while (existing < jobRows.count && jobRows.get(existing).jobIndex !== keys[row]) ++existing
            if (existing < jobRows.count) jobRows.move(existing, row, 1)
            else jobRows.insert(row, {jobIndex: keys[row]})
        }
    }
    Component.onCompleted: syncJobRows()
    StackView.onActivated: window.downloadQueue.markViewed()
    Connections {
        target: window.downloadQueue
        function onJobsChanged() { page.syncJobRows() }
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
                    text: qsTr("Back"); icon.name: "go-previous"
                    onClicked: window.goBack()
                }
            }
            Label {
                objectName: "downloadsTitle"
                Layout.fillWidth: true
                text: qsTr("Downloads"); color: window.textColor
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
    Flickable {
        id: scroll
        EmptySpaceFocus { parent: scroll }
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        NaturalWheelScroll { scrollTarget: scroll }
        ColumnLayout {
            id: content
            x: 24; y: 24; width: parent.width - 48; spacing: 16
            Repeater {
                objectName: "downloadJobs"
                model: jobRows
                delegate: Pane {
                    focusPolicy: Qt.ClickFocus
                    id: downloadCard
                    required property int jobIndex
                    readonly property var modelData: window.downloadQueue.jobs.find(job => job.index === jobIndex)
                        || {id: "", name: "", active: false, operations: []}
                    readonly property var installedApp: window.findInstalled(modelData)
                    readonly property var detailsApp: !modelData.id ? null : installedApp
                        || window.catalog.find(function(app) {
                            return app.id.replace(/\.desktop$/, "") === modelData.id.replace(/\.desktop$/, "")
                        }) || Object.assign({summary: "", description: "", screenshots: [], developer: "", category: "", license: "", homepage: ""}, modelData)
                    readonly property var appJob: window.jobForApp(installedApp)
                    readonly property bool canOpen: !modelData.active && !modelData.failed
                        && !modelData.cancelled && !!installedApp && (!appJob || !appJob.active)
                    Layout.fillWidth: true
                    padding: 20
                    background: Rectangle { radius: window.cornerRadius; color: window.surfaceColor; border.color: window.borderColor }
                    contentItem: ColumnLayout {
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            AbstractButton {
                                id: detailsButton
                                objectName: "downloadAppDetailsButton"
                                Layout.fillWidth: true
                                hoverEnabled: true
                                enabled: !!downloadCard.detailsApp
                                Accessible.name: qsTr("View details for %1").arg(modelData.name)
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
                                    Label { objectName: "downloadAppName"; text: modelData.name; textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 20; font.bold: true; color: window.textColor; Layout.fillWidth: true }
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
                            color: modelData.failed ? window.accentColor : window.mutedTextColor
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
                            color: window.accentColor
                        }
                    }
                }
            }
            Label { visible: !window.downloadQueue.jobs.length; text: qsTr("No operations yet."); color: window.textColor }
        }
    }
}
