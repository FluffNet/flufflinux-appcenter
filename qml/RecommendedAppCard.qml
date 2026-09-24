import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: card
    required property var app
    readonly property bool dense: width < 180 || height < 96
    implicitWidth: 190; implicitHeight: 96
    padding: dense ? 4 : 8; hoverEnabled: true
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    Accessible.name: app.name
    Accessible.description: publisher.text + (app.summary ? "\n" + app.summary : "")
    ToolTip.visible: hovered
    ToolTip.delay: 700
    ToolTip.text: app.name + (publisher.text ? "\n" + publisher.text : "") + (app.summary ? "\n" + app.summary : "")
    background: FluffButtonBackground { idleColor: window.surfaceColor }
    contentItem: RowLayout {
        spacing: card.dense ? 6 : 12
        AppIcon {
            Layout.preferredWidth: card.dense ? 28 : 40
            Layout.preferredHeight: card.dense ? 28 : 40
            sourceSize: Qt.size(64, 64)
            icon: card.app.icon || ""
        }
        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Label {
                objectName: "recommendedAppName"
                Layout.fillWidth: true
                text: card.app.name; textFormat: Text.PlainText; color: window.textColor
                font.pixelSize: card.dense ? 14 : 16; font.weight: Font.DemiBold
                wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            }
            AppPublisher {
                id: publisher
                objectName: "recommendedAppPublisher"
                app: card.app; Layout.fillWidth: true
                font.pixelSize: card.dense ? 11 : 12
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignTop
                showTooltip: false // The card tooltip already includes the full publisher.
            }
        }
    }
}
