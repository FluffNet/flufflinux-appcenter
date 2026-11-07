import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: progress
    property var job: null
    readonly property bool planned: !!job && (job.operations || []).length > 0
    readonly property bool removing: !!job && job.action === "uninstall"
    readonly property bool indeterminate: !planned || removing || (!!job && job.progressIndeterminate === true)
    // A queued operation has not started: only its Pending status is shown.
    visible: !!job && job.active === true && job.queued !== true
             && (!removing || job.removalConfirmed === true)
    spacing: 8
    Label {
        objectName: "queuePositionLabel"
        Layout.fillWidth: true
        visible: !!progress.job && progress.job.queueTotal > 1
        text: visible ? qsTr("App %1/%2").arg(progress.job.queuePosition).arg(progress.job.queueTotal) : ""
        font.bold: true
        color: window.textColor
    }
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
            visible: !progress.indeterminate
            text: qsTr("%1%").arg(progress.job && progress.job.progressPercent !== undefined
                ? progress.job.progressPercent : Math.floor(Math.min(1, progress.job ? (progress.job.progress || 0) : 0) * 100 + 0.000001))
            color: window.textColor
        }
    }
    Label {
        objectName: "progressStageLabel"
        Layout.fillWidth: true
        visible: progress.planned && !progress.removing && progress.indeterminate
        text: qsTranslate("AppCenter", progress.job && progress.job.phase === "install" ? "Installing…" : "Preparing…")
        color: window.textColor
        wrapMode: Text.Wrap
    }
    FluffProgressBar {
        objectName: "overallInstallProgress"
        Layout.fillWidth: true
        value: progress.job ? (progress.job.progress || 0) : 0
        indeterminate: progress.indeterminate
        Accessible.name: qsTr("Overall installation progress")
    }
}
