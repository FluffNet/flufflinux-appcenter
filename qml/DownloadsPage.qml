import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    objectName: "downloadsPage"
    StackView.onActivated: window.downloadQueue.markViewed()
    Connections {
        target: window.downloadQueue
        function onActiveCountChanged() {
            if (page.StackView.status === StackView.Active) window.downloadQueue.markViewed()
        }
    }
    background: null
    header: ToolBar {
        height: 72
        background: Rectangle { color: window.surfaceColor; border.color: window.borderColor }
        RowLayout {
            anchors.fill: parent; anchors.margins: 12
            ToolButton { text: qsTr("Back"); icon.name: "go-previous"; onClicked: window.goBack() }
            Label { text: qsTr("Downloads"); color: window.textColor; font.pixelSize: 24; font.bold: true }
            Item { Layout.fillWidth: true }
        }
    }
    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}
        NaturalWheelScroll { scrollTarget: scroll }
        ColumnLayout {
            id: content
            x: 24; y: 24; width: parent.width - 48; spacing: 16
            Label {
                Layout.fillWidth: true
                text: qsTr("This session’s downloads and installations. Dependencies appear under each app.")
                wrapMode: Text.WordWrap; color: window.mutedTextColor
            }
            Repeater {
                objectName: "downloadJobs"
                model: window.downloadQueue.jobs
                delegate: Pane {
                    required property var modelData
                    Layout.fillWidth: true
                    padding: 20
                    background: Rectangle { radius: 10; color: window.surfaceColor; border.color: window.borderColor }
                    contentItem: ColumnLayout {
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.name; textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 20; font.bold: true; color: window.textColor; Layout.fillWidth: true }
                            Button {
                                visible: modelData.active
                                text: qsTr("Cancel")
                                onClicked: if (window.backend) window.backend.cancelJob(modelData.index)
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.status
                            textFormat: Text.PlainText; wrapMode: Text.Wrap
                            color: modelData.failed ? window.accentColor : window.mutedTextColor
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: modelData.active && (modelData.operations || []).length > 0
                            text: qsTr("Overall installation progress: %1%").arg(Math.round(modelData.progress * 100))
                            color: window.mutedTextColor; wrapMode: Text.Wrap
                        }
                        FluffProgressBar {
                            Layout.fillWidth: true
                            visible: modelData.active
                            value: modelData.progress
                            indeterminate: modelData.active && !(modelData.operations || []).length
                            palette.highlight: window.accentColor
                        }
                        Label {
                            Layout.fillWidth: true; visible: !!modelData.error
                            text: modelData.error || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            color: window.accentColor
                        }
                        Repeater {
                            model: modelData.operations || []
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true; spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                                        text: (modelData.dependency ? qsTr("Dependency: ") : "") + modelData.name
                                        textFormat: Text.PlainText; color: window.textColor
                                    }
                                    Label { text: modelData.downloadSize; color: window.mutedTextColor }
                                }
                                Label { Layout.fillWidth: true; text: modelData.status; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: window.mutedTextColor }
                                FluffProgressBar { Layout.fillWidth: true; visible: modelData.progress > 0 && modelData.progress < 1; value: modelData.progress }
                                Rectangle { Layout.fillWidth: true; height: 1; color: window.borderColor }
                            }
                        }
                    }
                }
            }
            Label { visible: !window.downloadQueue.jobs.length; text: qsTr("No operations yet."); color: window.textColor }
        }
    }
}
