import QtQuick

Image {
    property string icon: ""
    readonly property url requestedSource: resolveIcon(icon)
    property bool loadFailed: false
    function resolveIcon(value) {
        if (typeof window.iconSource === "function") return window.iconSource(value)
        if (!value) return "image://icon/application-x-executable"
        if (value.indexOf(":") >= 0) return value
        return value.indexOf("/") >= 0 ? "file://" + value : "image://icon/" + value
    }
    asynchronous: true
    fillMode: Image.PreserveAspectFit
    onRequestedSourceChanged: loadFailed = false
    source: loadFailed ? resolveIcon("application-x-executable") : requestedSource
    onStatusChanged: if (status === Image.Error && !loadFailed) loadFailed = true
}
