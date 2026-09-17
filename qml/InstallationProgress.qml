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
    RowLayout {
        Layout.fillWidth: true
        visible: progress.planned && !progress.removing
        spacing: 12
        Label {
            id: downloadBytes
            objectName: "downloadBytesLabel"
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.alignment: Qt.AlignTop
            visible: !!progress.job && progress.job.hasDownload === true
                     && progress.job.downloadComplete !== true
            text: qsTr("%1 / %2 (%3)").arg(progress.job ? progress.job.downloadedSize || "" : "")
                                    .arg(progress.job ? progress.job.downloadTotalSize || "" : "")
                                    .arg(progress.job ? progress.job.downloadSpeed || "" : "")
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
            color: window.textColor
        }
        Item { Layout.fillWidth: true; visible: !downloadBytes.visible }
        Label {
            objectName: "overallPercentageLabel"
            Layout.alignment: Qt.AlignTop | Qt.AlignRight
            horizontalAlignment: Text.AlignRight
            text: qsTr("%1%").arg(Math.floor(Math.min(0.99, progress.job ? (progress.job.progress || 0) : 0) * 100 + 0.000001))
            color: window.textColor
        }
    }
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
}
