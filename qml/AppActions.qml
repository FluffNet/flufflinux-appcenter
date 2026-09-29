import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: actions
    required property var app
    readonly property var installed: typeof window.findInstalled === "function" ? window.findInstalled(app) : null
    readonly property var job: typeof window.jobForApp === "function" ? window.jobForApp(app) : null
    readonly property bool running: !!job && job.active === true
    readonly property bool removing: !!job && job.action === "uninstall"
    readonly property bool awaitingRemovalConfirmation: running && removing && job.removalConfirmed !== true
    readonly property bool pending: running && job.queued === true
    readonly property var sizeInfo: running && !removing && job.sizeInfo && job.sizeInfo.state === "ready"
                                   ? job.sizeInfo : window.backend && window.backend.installSizes
                                   ? window.backend.installSizes[String(app.id).replace(/\.desktop$/, "")] || ({}) : ({})
    // Hide redundant displayed sizes, including differences lost to rounding.
    // Missing estimates are not equal sizes: keep their unavailable row.
    readonly property bool showDependencyTotal: !(sizeInfo.appSize && sizeInfo.totalSize
                                                  && sizeInfo.appSize === sizeInfo.totalSize)
    function sizeText(field) {
        return sizeInfo[field] || qsTr("Unavailable")
    }
    visible: typeof window.backend !== "undefined" && !!window.backend
    Layout.fillWidth: true
    spacing: 8
    InstallationProgress {
        id: installationProgress
        objectName: "appInstallProgress"
        Layout.fillWidth: true
        job: actions.job
    }
    Label {
        objectName: "appJobStatus"
        Layout.fillWidth: true
        // The unified bar already gives all normal install/download details.
        // Keep errors, cancellation, source trust and removal messages visible.
        visible: !!actions.job && (actions.job.failed === true || (actions.running
                 && (actions.pending || actions.removing || !installationProgress.planned || actions.job.cancelling === true
                     || (window.backend.review && window.backend.review.jobIndex === actions.job.index))))
        text: actions.awaitingRemovalConfirmation ? qsTr("Waiting for confirmation")
              : actions.pending ? qsTr("Pending…")
              : actions.running && actions.removing && !actions.job.failed ? qsTr("Uninstalling…")
              : actions.job ? actions.job.status + (actions.job.error ? "\n" + actions.job.error : "") : ""
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: actions.job && actions.job.failed ? window.accentColor : window.mutedTextColor
    }
}
