import QtQuick

Item {
    Image {
        anchors.fill: parent
        source: window.darkMode ? "wallpaper-dark.svg" : "wallpaper-light.svg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }
}
