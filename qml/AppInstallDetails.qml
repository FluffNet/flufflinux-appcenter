import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

GridLayout {
    required property var actions
    objectName: "installSizeDetails"
    visible: actions.visible && !actions.installed
    columns: 2; columnSpacing: 16; rowSpacing: 8
    Label { text: qsTr("Size:"); color: window.mutedTextColor }
    Label {
        objectName: "appDownloadSize"
        text: actions.sizeText("appSize"); color: window.textColor; font.bold: true
    }
    Label {
        visible: !!(actions.app && actions.app.version)
        text: qsTr("Version:"); color: window.mutedTextColor
    }
    Label {
        objectName: "appAvailableVersion"
        visible: text.length > 0
        Layout.maximumWidth: 150
        Layout.minimumWidth: 0
        text: actions.app && actions.app.version || ""
        textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere
        color: window.textColor; font.bold: true
    }
    Label {
        objectName: "totalDownloadSizeLabel"
        visible: actions.showDependencyTotal
        Layout.maximumWidth: 210
        Layout.minimumWidth: 0
        text: qsTr("Total size with dependencies:"); color: window.mutedTextColor
        wrapMode: Text.WordWrap
    }
    Label {
        objectName: "totalDownloadSize"
        visible: actions.showDependencyTotal
        text: actions.sizeText("totalSize"); color: window.textColor; font.bold: true
    }
}
