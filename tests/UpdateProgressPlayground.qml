// Interactive fixture: real manager/UI, disposable simulated updates.
// APPCENTER_PROFILE_INTERACTIVE=1 enables visible transfer/deployment timing.
import QtQuick
import "../qml" as App

App.Main {
    id: main
    title: "App Center - 30 update test"
    width: 1280; height: 900; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state:"online", ready:true})
    property int phase: 0
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (main.phase === 0 && !main.catalogLoading && !main.installedLoading && !main.backend.busy && main.catalog.length) {
                main.showUpdates()
                main.backend.checkForUpdates()
                main.phase = 1
            } else if (main.phase === 1 && main.backend.updateStatus.state === "ready" && !main.backend.busy) {
                if (main.updateItems.length !== 30) {
                    console.error("UPDATE_PLAYGROUND_FAILED", main.updateItems.length)
                    Qt.exit(1)
                    return
                }
                console.info("UPDATE_PLAYGROUND_READY", main.updateItems.length)
                main.requestActivate()
                main.phase = 2
                stop()
            }
        }
    }
}
