import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: actions
    required property var app
    readonly property var installed: typeof window.findInstalled === "function" ? window.findInstalled(app) : null
    readonly property var job: typeof window.jobForApp === "function" ? window.jobForApp(app) : null
    readonly property bool running: !!job && job.active === true
    readonly property var sizeInfo: window.backend && window.backend.installSizes
                                   ? window.backend.installSizes[String(app.id).replace(/\.desktop$/, "")] || ({}) : ({})
    readonly property bool showDependencyTotal: !(typeof sizeInfo.appBytes === "number"
                                                  && typeof sizeInfo.totalBytes === "number"
                                                  && sizeInfo.appBytes === sizeInfo.totalBytes)
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
        Button {
            objectName: "installAppButton"
            visible: !actions.installed && !actions.running
            enabled: !window.installedLoading
            text: qsTr("Install")
            icon.name: "list-add"
            onClicked: window.installApp(actions.app)
        }
        Button {
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
            visible: actions.running
            text: qsTr("Cancel")
            onClicked: window.backend.cancelJob(actions.job.index)
        }
        Item { Layout.fillWidth: true }
    }
    FluffProgressBar {
        objectName: "appInstallProgress"
        Layout.fillWidth: true
        visible: actions.running
        value: actions.job ? actions.job.progress : 0
        indeterminate: actions.running && !(actions.job.operations || []).length
        palette.highlight: window.accentColor
    }
    Label {
        objectName: "appJobStatus"
        Layout.fillWidth: true
        visible: !!actions.job
        text: actions.job ? actions.job.status + (actions.job.error ? "\n" + actions.job.error : "") : ""
        textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: actions.job && actions.job.failed ? window.accentColor : window.mutedTextColor
    }
}
