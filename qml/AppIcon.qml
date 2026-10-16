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
    // Theme pixmaps use KDE's shared icon/font state, like the window icon and
    // native controls. Keep those requests on the GUI thread; app image files
    // still decode asynchronously.
    asynchronous: !String(source).startsWith("image://icon/")
    fillMode: Image.PreserveAspectFit
    onRequestedSourceChanged: loadFailed = false
    // Hidden pages must not decode/reload icons when an install changes the
    // desktop icon cache. Resolve the latest revision when shown again.
    source: !visible ? "" : loadFailed ? resolveIcon("application-x-executable") : requestedSource
    function useFallback() { if (status === Image.Error && !loadFailed) loadFailed = true }
    // A synchronous theme miss can emit Error while source is still being
    // evaluated. Defer the fallback so it cannot change that binding in flight.
    onStatusChanged: if (status === Image.Error && !loadFailed) Qt.callLater(useFallback)
}
