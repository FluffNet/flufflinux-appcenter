import QtQuick
import QtQuick.Controls

Label {
    id: label
    property var app: null
    property bool showTooltip: true
    text: typeof window.publisherFor === "function" ? window.publisherFor(app)
        : String(app && app.developer || "").trim()
    visible: text.length > 0
    textFormat: Text.PlainText
    color: window.accentTextColor
    font.weight: Font.DemiBold
    font.pixelSize: 14
    fontSizeMode: Text.HorizontalFit
    minimumPixelSize: Math.max(10, font.pixelSize - 2)
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    ToolTip.visible: showTooltip && truncated && pointer.hovered
    ToolTip.delay: 700
    ToolTip.text: text
    HoverHandler { id: pointer }
}
