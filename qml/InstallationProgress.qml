import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: progress
    property var job: null
    readonly property bool planned: !!job && (job.operations || []).length > 0
    readonly property bool removing: !!job && job.action === "uninstall"
    visible: !!job && job.active === true && (!removing || job.removalConfirmed === true)
    spacing: 8
    FluffProgressBar {
        objectName: "overallInstallProgress"
        Layout.fillWidth: true
        value: progress.job ? (progress.job.progress || 0) : 0
        indeterminate: !progress.planned || progress.removing
        // Show activity in the unfinished section without inventing percentage
        // updates when Flatpak supplies no fine-grained deployment callbacks.
        activeStep: progress.planned && !progress.removing && progress.job.phase === "install"
        Accessible.name: qsTr("Overall installation progress")
    }
    RowLayout {
        Layout.fillWidth: true
        visible: progress.planned && !progress.removing
        spacing: 12
        Label {
            objectName: "completedOperationsLabel"
            text: qsTr("%1/%2 Complete").arg(progress.job ? (progress.job.installCompleted || 0) : 0)
                                       .arg(progress.job ? (progress.job.installTotal || 0) : 0)
            color: window.mutedTextColor
        }
        Label {
            objectName: "downloadBytesLabel"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            visible: !!progress.job && progress.job.hasDownload === true
            text: qsTr("%1/%2 Downloaded").arg(progress.job ? progress.job.downloadedSize || "" : "")
                                        .arg(progress.job ? progress.job.downloadTotalSize || "" : "")
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: window.mutedTextColor
        }
        Item { Layout.fillWidth: true; visible: !progress.job || progress.job.hasDownload !== true }
        Label {
            objectName: "overallPercentageLabel"
            text: qsTr("%1%").arg(Math.floor(Math.min(0.99, progress.job ? (progress.job.progress || 0) : 0) * 100 + 0.000001))
            color: window.mutedTextColor
        }
    }
}
