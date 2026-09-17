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
        background: Rectangle {
            color: window.backgroundColor
            border.width: 0
            FluffSeparator { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom }
        }
        RowLayout {
            anchors.fill: parent; anchors.margins: 12
            ToolButton {
                id: backButton
                objectName: "downloadsBackButton"
                text: qsTr("Back"); icon.name: "go-previous"
                onClicked: window.goBack()
            }
            Label {
                objectName: "downloadsTitle"
                Layout.fillWidth: true
                text: qsTr("Downloads"); color: window.textColor
                font.pixelSize: 24; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            // Balance Back so the title centers on the page, not the remaining space.
            Item { Layout.preferredWidth: backButton.width }
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
                    background: Rectangle { radius: window.cornerRadius; color: window.surfaceColor; border.color: window.borderColor }
                    contentItem: ColumnLayout {
                        spacing: 10
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14
                            AppIcon {
                                objectName: "downloadAppIcon"
                                Layout.preferredWidth: 56; Layout.preferredHeight: 56
                                Layout.alignment: Qt.AlignVCenter
                                sourceSize: Qt.size(64, 64)
                                Accessible.ignored: true
                                icon: modelData.icon || ""
                            }
                            Label { objectName: "downloadAppName"; text: modelData.name; textFormat: Text.PlainText; wrapMode: Text.Wrap; font.pixelSize: 20; font.bold: true; color: window.textColor; Layout.fillWidth: true }
                            Button {
                                visible: modelData.active
                                text: qsTr("Cancel")
                                onClicked: if (window.backend) window.backend.cancelJob(modelData.index)
                            }
                        }
                        Label {
                            objectName: "downloadJobStatus"
                            Layout.fillWidth: true
                            visible: !modelData.active || !(modelData.operations || []).length || modelData.cancelling === true
                                     || (window.backend.review && window.backend.review.jobIndex === modelData.index)
                            text: modelData.status
                            textFormat: Text.PlainText; wrapMode: Text.Wrap
                            color: modelData.failed ? window.accentColor : window.mutedTextColor
                        }
                        InstallationProgress {
                            objectName: "downloadJobProgress"
                            Layout.fillWidth: true
                            job: modelData
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
                                FluffSeparator { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }
            Label { visible: !window.downloadQueue.jobs.length; text: qsTr("No operations yet."); color: window.textColor }
        }
    }
}
