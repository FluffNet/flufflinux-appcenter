// Exercise the production UI through the real executable and IPC socket.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visible: true
    backend: null // This fixture never starts Flatpak transactions or source operations.
    catalogStats: null
    catalogPreferences: null
    networkStatus: null
    TestCase { id: probe; when: false }
    property string previousState: ""
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (!stack || stack.busy) return
            const page = stack.get(0)
            const state = JSON.stringify({category:main.selectedCategory, search:main.searchText,
                mime:page.cliMimeType, rawCategory:page.cliCategory,
                settings:stack.currentItem.objectName === "settingsPage",
                about:probe.findChild(main, "aboutDialog").visible,
                updates:fluffBackend.updates.state})
            if (state !== main.previousState) { console.log("CLI_STATE " + state); main.previousState = state }
        }
    }
    Connections {
        target: fluffBackend
        function onInputError(message) { console.log("CLI_ERROR " + message) }
        function onAppOpened(app) { console.log("CLI_APP " + app.id) }
    }
}
