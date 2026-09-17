import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    objectName: "downloadsPage"
    StackView.onActivated: window.downloadQueue.markViewed()
    Connections {
        target: window.downloadQueue
        function onActiveCountChanged() {
            if (page.StackView.status === StackView.Active) window.downloadQueue.markViewed()
        }
    }
    background: null
    header: ToolBar {
        height: 72
        background: Rectangle {
            color: window.backgroundColor
            border.width: 0
            FluffSeparator { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom }
        }
        RowLayout {
            anchors.fill: parent; anchors.margins: 12
            ToolButton {
                id: backButton
                objectName: "downloadsBackButton"
                text: qsTr("Back"); icon.name: "go-previous"
                onClicked: window.goBack()
            }
            Label {
                objectName: "downloadsTitle"
                Layout.fillWidth: true
                text: qsTr("Downloads"); color: window.textColor
                font.pixelSize: 24; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            // Balance Back so the title centers on the page, not the remaining space.
            Item { Layout.preferredWidth: backButton.width }
        }
    }
    Flickable {
        id: scroll
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
                model: window.downloadQueue.jobs
                delegate: Pane {
                    id: downloadCard
                    required property var modelData
                    readonly property var installedApp: window.findInstalled(modelData)
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
                            AppIcon {
                                objectName: "downloadAppIcon"
                                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                                Layout.alignment: Qt.AlignVCenter
                                sourceSize: Qt.size(64, 64)
                                Accessible.ignored: true
                                icon: modelData.icon || ""
                            }
                            Label { objectName: "downloadAppName"; text: modelData.name; textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 20; font.bold: true; color: window.textColor; Layout.fillWidth: true }
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
