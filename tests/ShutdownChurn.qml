// Exercise teardown with queued delegates and page transitions, without installs.
import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as App

App.Main {
    id: main
    width: 1180; height: 800; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state: "online", ready: true})
    property int step: 0
    TestCase { id: probe; when: false }
    Timer {
        interval: 10; repeat: true; running: true
        onTriggered: {
            if (main.catalogLoading || main.installedLoading || !main.catalog.length) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            switch (main.step % 4) {
            case 0: main.showHome(); break
            case 1: main.openApp(main.catalog[(main.step * 17) % main.catalog.length]); break
            case 2: main.showDownloads(); break
            case 3: main.showHome(); break
            }
            if (++main.step === 80) {
                console.log("SHUTDOWN_CHURN_COMPLETE", main.step)
                stop()
                Qt.quit()
            }
        }
    }
}
