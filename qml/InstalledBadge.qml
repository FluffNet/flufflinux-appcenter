import QtQuick

Rectangle {
    objectName: "installedBadge"
    implicitWidth: 22; implicitHeight: 22
    radius: width / 2
    color: "#27ae60" // Match FLU's green success circle, independent of accent color.
    border.color: window.surfaceColor
    border.width: 2
    antialiasing: true
    Accessible.ignored: true // The enclosing app card announces Installed.
    Image {
        anchors.centerIn: parent
        width: parent.width * 0.7; height: width
        source: "check-white.svg"
        sourceSize: Qt.size(width, height)
    }
}
