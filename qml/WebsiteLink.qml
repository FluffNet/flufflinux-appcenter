import QtQuick
import QtQuick.Controls

AbstractButton {
    id: link
    property color linkColor: palette.link
    signal activated(string url)
    implicitWidth: contentItem.implicitWidth
    implicitHeight: contentItem.implicitHeight
    padding: 0
    background: null
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    PointerFocusHandler {}
    font.underline: hovered || visualFocus
    Accessible.role: Accessible.Link
    Accessible.name: text
    Accessible.onPressAction: clicked()
    contentItem: Label {
        text: link.text
        textFormat: Text.PlainText
        color: link.linkColor
        font: link.font
        horizontalAlignment: Text.AlignLeft
        elide: Text.ElideRight
    }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
    onClicked: activated(text)
}
