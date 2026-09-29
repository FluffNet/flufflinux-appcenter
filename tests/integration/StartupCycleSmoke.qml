// Installed UI/backend with a private socket. Only automates close/reopen.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visible: false
    property bool awaitingFrame: true
    property bool frameReported: false
    Component.onCompleted: showMaximized()
    onVisibleChanged: {
        if (visible) { awaitingFrame = true; frameReported = false }
        else console.log("CYCLE_CLOSED")
    }
    onFrameSwapped: {
        if (!visible) return
        if (!frameReported) {
            frameReported = true
            console.log("CYCLE_FRAME", "apps", catalog.length, "loading", catalogLoading)
        }
        if (awaitingFrame && !catalogLoading && catalog.length > 0) {
            awaitingFrame = false
            console.log("CYCLE_READY", "apps", catalog.length)
            closeWindow.start()
        }
    }
    Timer { id: closeWindow; interval: 400; onTriggered: main.close() }
}
