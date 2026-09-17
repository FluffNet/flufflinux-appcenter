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
    GridLayout {
        objectName: "installSizeDetails"
        Layout.fillWidth: true
        visible: !actions.installed
        columns: 2; columnSpacing: 16; rowSpacing: 4
        Label { text: qsTr("App size:"); color: window.mutedTextColor }
        Label {
            objectName: "appDownloadSize"
            Layout.fillWidth: true
            text: actions.sizeText("appSize"); color: window.textColor; font.bold: true
        }
        Label {
            objectName: "totalDownloadSizeLabel"
            visible: actions.showDependencyTotal
            text: qsTr("Total size with dependencies:"); color: window.mutedTextColor
        }
        Label {
            objectName: "totalDownloadSize"
            visible: actions.showDependencyTotal
            Layout.fillWidth: true
            text: actions.sizeText("totalSize"); color: window.textColor; font.bold: true
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: !actions.running || !actions.removing
        Button {
            objectName: "installAppButton"
            visible: !actions.installed && !actions.running
            enabled: !window.installedLoading
            text: qsTr("Install")
            icon.name: "list-add"
            onClicked: window.installApp(actions.app)
        }
        Button {
            objectName: "openAppButton"
            visible: !!actions.installed && !actions.running
            text: qsTr("Open")
            icon.name: "media-playback-start"
            onClicked: window.backend.launchApp(actions.installed)
        }
        Button {
            objectName: "uninstallAppButton"
            visible: !!actions.installed && !actions.running
            text: qsTr("Uninstall")
            onClicked: window.uninstallApp(actions.installed)
            contentItem: Row {
                spacing: 8
                Image { source: "trash-red.svg"; width: 18; height: 18; anchors.verticalCenter: parent.verticalCenter }
                Label { text: qsTr("Uninstall"); color: window.textColor; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Button {
            objectName: "cancelAppButton"
            visible: actions.running && !actions.removing
            text: qsTr("Cancel")
            onClicked: window.backend.cancelJob(actions.job.index)
        }
        Item { Layout.fillWidth: true }
    }
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
                 && (actions.removing || !installationProgress.planned || actions.job.cancelling === true
                     || (window.backend.review && window.backend.review.jobIndex === actions.job.index))))
        text: actions.awaitingRemovalConfirmation ? qsTr("Waiting for confirmation")
              : actions.job ? actions.job.status + (actions.job.error ? "\n" + actions.job.error : "") : ""
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: actions.job && actions.job.failed ? window.accentColor : window.mutedTextColor
    }
}
