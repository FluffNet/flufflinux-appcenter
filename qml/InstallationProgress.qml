import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: stages
    property var job: null
    readonly property bool planned: !!job && (job.operations || []).length > 0
    readonly property bool removing: !!job && job.action === "uninstall"
    readonly property bool downloadVisible: planned && !removing && job.hasDownload !== false
    readonly property real downloadValue: job ? (job.downloadProgress || 0) : 0
    readonly property int installedCount: job ? (job.installCompleted || 0) : 0
    readonly property int installCount: job ? (job.installTotal || 0) : 0
    visible: !!job && job.active === true && (!removing || job.removalConfirmed === true)
    spacing: 8
    Label {
        objectName: "downloadPhaseLabel"
        Layout.fillWidth: true
        visible: stages.downloadVisible
        text: stages.job && stages.job.downloadEstimating ? qsTr("Downloading…")
              : qsTr("Download: %1%").arg(Math.floor(stages.downloadValue * 100))
        color: window.mutedTextColor; wrapMode: Text.Wrap
    }
    FluffProgressBar {
        objectName: "downloadPhaseProgress"
        Layout.fillWidth: true
        visible: stages.downloadVisible
        value: stages.downloadValue
        indeterminate: !!stages.job && stages.job.downloadEstimating === true
    }
    Label {
        objectName: "installPhaseLabel"
        Layout.fillWidth: true
        visible: stages.planned && !stages.removing
        text: qsTr("Installation: %1 of %2 completed").arg(stages.installedCount).arg(stages.installCount)
        color: window.mutedTextColor; wrapMode: Text.Wrap
    }
    FluffProgressBar {
        objectName: "installPhaseProgress"
        Layout.fillWidth: true
        value: stages.job ? (stages.job.installProgress || 0) : 0
        // Deployment has no percentage callback. Preserve completed steps,
        // animating only the unfinished portion while Flatpak is installing.
        activeStep: !!stages.job && stages.job.phase === "install"
        indeterminate: !stages.planned || stages.removing
    }
}
