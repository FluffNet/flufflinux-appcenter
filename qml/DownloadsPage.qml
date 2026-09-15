import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    objectName: "downloadsPage"
    background: null
    header: ToolBar {
        height: 72
        background: Rectangle { color: window.surfaceColor; border.color: window.borderColor }
        RowLayout {
            anchors.fill: parent; anchors.margins: 12
            ToolButton {
                text: qsTr("Back"); icon.name: "go-previous"
                onClicked: window.goBack()
            }
            Label { text: qsTr("Downloads"); color: window.textColor; font.pixelSize: 24; font.bold: true }
            Item { Layout.fillWidth: true }
        }
    }
    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: 16
            Label {
                Layout.fillWidth: true; Layout.margins: 24
                text: qsTr("Simulation — no apps are downloaded or installed.")
                wrapMode: Text.WordWrap; color: window.mutedTextColor
                visible: window.downloadQueue.simulated
            }
            Repeater {
                model: window.downloadQueue.jobs
                delegate: Pane {
                    required property var modelData
                    Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
                    padding: 20
                    background: Rectangle { radius: 10; color: window.surfaceColor; border.color: window.borderColor }
                    ColumnLayout {
                        anchors.fill: parent
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; font.pixelSize: 20; color: window.textColor; Layout.fillWidth: true }
                            Label { text: modelData.status; color: window.mutedTextColor }
                        }
                        ProgressBar { Layout.fillWidth: true; value: modelData.progress; palette.highlight: window.accentColor }
                        Label { text: Math.round(modelData.progress * 100) + "%"; color: window.mutedTextColor }
                    }
                }
            }
            Button {
                Layout.leftMargin: 24
                visible: window.downloadQueue.simulated
                text: qsTr("Restart simulation")
                onClicked: window.downloadQueue.startDemo()
            }
        }
    }
}
