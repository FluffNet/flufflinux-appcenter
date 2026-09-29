// Run the production launcher/renderer with fake data and no transactions.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    palette.window: "#202326"
    palette.windowText: "#ffffff"
    property int stage: 0
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    readonly property var fixtureApp: ({id:"org.example.Pointer", name:"Source menu test",
        summary:"Pointer and keyboard interaction check", description:"", icon:"telegram",
        developer:"", license:"", homepage:"", category:"Internet", screenshots:[],
        remote:"flathub", flatpakRef:"app/org.example.Pointer/x86_64/stable", version:"7.1.5"})
    backend: fixture
    QtObject {
        id: fixture
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        function requestInstallInfo(app) {}
    }
    TestCase { id: probe; when: false }
    function check(condition, message) {
        if (!condition) { console.error(message); Qt.exit(1); throw new Error(message) }
    }
    function capture(item, name, next) {
        stage = -1
        item.grabToImage(function(result) {
            main.check(result.saveToFile(Qt.resolvedUrl("../../target/pointer-" + name + ".png").toString().replace("file://", "")), "Capture failed")
            main.stage = next
        })
    }
    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy) return
            const button = probe.findChild(stack.currentItem, "installSourceButton")
            const menu = probe.findChild(stack.currentItem, "installSourceMenu")
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                const beta = Object.assign({}, main.fixtureApp, {remote:"flathub-beta", flatpakRef:"app/org.example.Pointer/x86_64/beta"})
                main.openApp(Object.assign({}, main.fixtureApp, {sources:[main.fixtureApp,beta]}))
                main.stage = 1
            } else if (main.stage === 1) {
                button.forceActiveFocus(Qt.TabFocusReason)
                probe.mouseClick(button); main.stage = 2
            } else if (main.stage === 2) {
                main.check(menu.opened, "Pointer did not open the source menu")
                probe.mouseClick(button); main.stage = 3
            } else if (main.stage === 3) {
                main.check(!menu.visible && !button.activeFocus && button.background.border.width === 1, "Pointer left the menu open or button focused")
                main.capture(button, "centered-arrow", 4)
            } else if (main.stage === 4) {
                main.capture(stack, "source-closed", 5)
            } else if (main.stage === 5) {
                button.forceActiveFocus(Qt.TabFocusReason)
                probe.keyClick(Qt.Key_Space); main.stage = 6
            } else if (main.stage === 6) {
                main.check(menu.opened, "Keyboard did not open the source menu")
                probe.keyClick(Qt.Key_Escape); main.stage = 7
            } else if (main.stage === 7) {
                main.check(!menu.visible && button.activeFocus && button.visualFocus, "Keyboard focus was lost")
                console.log("Pointer toggle, centered arrow and keyboard focus passed at DPR", Screen.devicePixelRatio)
                Qt.quit()
            }
        }
    }
    Timer { interval: 20000; running: true; onTriggered: Qt.exit(5) }
}
