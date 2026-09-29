import QtQuick

Rectangle {
    property bool vertical: false
    // Qt 6.11 exposes the window's fractional Wayland scale; Screen can still
    // report the compositor's rounded integer scale. Keep older Qt usable too.
    readonly property real pixelRatio: Window.window && typeof Window.window.devicePixelRatio === "number"
                                       ? Window.window.devicePixelRatio : Screen.devicePixelRatio
    // Match Rectangle's 1-unit pixel-aligned border at fractional scale factors.
    // Keep the edge on physical pixels instead of painting a blurry 1.5px line.
    readonly property real thickness: Math.max(1, Math.round(pixelRatio)) / pixelRatio
    implicitWidth: vertical ? thickness : 1
    implicitHeight: vertical ? 1 : thickness
    color: window.borderColor
}
