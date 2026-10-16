import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: card
    required property var app
    property bool installed: false
    readonly property bool tight: width < 128
    readonly property bool dense: width < 180 || height < 96
    implicitWidth: 190; implicitHeight: 96
    padding: dense ? 4 : 8; hoverEnabled: true
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    Accessible.name: app.name
    Accessible.description: (installed ? qsTr("Installed") + "\n" : "") + publisher.text + (app.summary ? "\n" + app.summary : "")
    ToolTip.visible: hovered
    ToolTip.delay: 700
    ToolTip.text: app.name + (installed ? "\n" + qsTr("Installed") : "") + (publisher.text ? "\n" + publisher.text : "") + (app.summary ? "\n" + app.summary : "")
    background: FluffButtonBackground { idleColor: window.surfaceColor }
    contentItem: RowLayout {
        spacing: card.tight ? 4 : card.dense ? 6 : 12
        Item {
            Layout.preferredWidth: card.tight ? 20 : card.dense ? 28 : 40
            Layout.preferredHeight: card.tight ? 20 : card.dense ? 28 : 40
            AppIcon {
                anchors.fill: parent
                sourceSize: Qt.size(64, 64)
                icon: card.app.icon || ""
            }
            InstalledBadge {
                anchors.right: parent.right; anchors.bottom: parent.bottom
                width: card.tight ? 12 : card.dense ? 16 : 20; height: width
                visible: card.installed
            }
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Label {
                objectName: "recommendedAppName"
                Layout.fillWidth: true
                text: card.app.name; textFormat: Text.PlainText; color: window.textColor
                font.pixelSize: card.tight ? 13 : card.dense ? 14 : 16; font.weight: Font.DemiBold
                fontSizeMode: Text.HorizontalFit; minimumPixelSize: card.tight ? 11 : font.pixelSize
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            AppPublisher {
                id: publisher
                objectName: "recommendedAppPublisher"
                app: card.app; Layout.fillWidth: true
                font.pixelSize: card.dense ? 11 : 12
                maximumLineCount: card.tight ? 3 : 2
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop
                showTooltip: false // The card tooltip already includes the full publisher.
            }
        }
    }
}
