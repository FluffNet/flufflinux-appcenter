import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

AbstractButton {
    id: card
    required property var app
    readonly property bool dense: width < 180 || height < 64
    implicitWidth: 190; implicitHeight: 72
    padding: dense ? 6 : 10; hoverEnabled: true
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    Accessible.name: app.name
    Accessible.description: app.summary || ""
    ToolTip.visible: hovered
    ToolTip.delay: 700
    ToolTip.text: app.name + (app.summary ? "\n" + app.summary : "")
    background: FluffButtonBackground { idleColor: window.surfaceColor }
    contentItem: RowLayout {
        spacing: card.dense ? 6 : 12
        AppIcon {
            Layout.preferredWidth: card.dense ? 28 : 40
            Layout.preferredHeight: card.dense ? 28 : 40
            sourceSize: Qt.size(64, 64)
            icon: card.app.icon || ""
        }
        Label {
            objectName: "recommendedAppName"
            Layout.fillWidth: true
            text: card.app.name; color: window.textColor
            font.pixelSize: card.dense ? 14 : 16; font.weight: Font.DemiBold
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
        }
    }
}
