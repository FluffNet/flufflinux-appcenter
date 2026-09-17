import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GridLayout {
    id: details
    required property var actions
    readonly property string version: actions.installed ? actions.installed.installedVersion || ""
                                                       : actions.app && actions.app.version || ""
    readonly property bool showDependencyTotal: !actions.installed && actions.showDependencyTotal
    objectName: "installSizeDetails"
    visible: actions.visible
    columns: 2; columnSpacing: 16; rowSpacing: 8
    Label { text: qsTr("Size:"); color: window.mutedTextColor }
    Label {
        objectName: "appDownloadSize"
        text: actions.installed ? actions.installed.installedSize || qsTr("Unavailable") : actions.sizeText("appSize")
        color: window.textColor; font.bold: true
    }
    Label {
        visible: details.version.length > 0
        text: qsTr("Version:"); color: window.mutedTextColor
    }
    Label {
        objectName: "appAvailableVersion"
        visible: text.length > 0
        Layout.maximumWidth: 150
        Layout.minimumWidth: 0
        text: details.version
        textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
        color: window.textColor; font.bold: true
    }
    Label {
        objectName: "totalDownloadSizeLabel"
        visible: details.showDependencyTotal
        Layout.maximumWidth: 210
        Layout.minimumWidth: 0
        text: qsTr("Total size with dependencies:"); color: window.mutedTextColor
        wrapMode: Text.WordWrap
    }
    Label {
        objectName: "totalDownloadSize"
        visible: details.showDependencyTotal
        text: actions.sizeText("totalSize"); color: window.textColor; font.bold: true
    }
}
