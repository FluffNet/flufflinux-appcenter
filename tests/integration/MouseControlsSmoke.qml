// Native KDE input simulation. All catalogue/source data is fake; no transactions.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    backend: fixture; catalogStats: null; catalogPreferences: null
    property int stage: 0
    property real savedY: 0
    property bool capturing: false
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    catalog: Array.from({length:80}, (_, i) => ({id:"org.example.Mouse" + i, name:"Mouse test " + i,
        description:"A read-only mouse input fixture. ".repeat(100), summary:"Mouse controls test", icon:"application-x-executable",
        category:"Utilities", developer:"Test fixture", screenshots:[], homepage:"", license:"MIT",
        searchName:"mouse test " + i, searchHaystack:"mouse test utilities", searchSummary:"", searchDescription:"", searchMetadata:""}))
    QtObject {
        id: fixture
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property var updates: ({state:"idle", items:[]})
        property var repositories: Array.from({length:25}, (_, i) => ({name:"fixture" + i, title:"Source fixture " + i,
            url:"https://example.invalid/", scope:"user", enabled:true}))
        property bool busy: false
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        function requestInstallInfo(app) {}
        function refreshSources() {}
    }
    function check(ok, text) {
        if (!ok) { console.error("MOUSE_CONTROLS_FAIL", "stage", stage, text); Qt.exit(2); throw new Error(text) }
    }
    function middle(view) {
        probe.mouseClick(view, view.width / 2, view.height / 2, Qt.MiddleButton)
        main.check(probe.findChild(view, "middleMouseScroll").scrolling, "Middle click starts autoscroll")
        probe.mouseMove(view, view.width / 2, view.height / 2 + 70)
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            if (main.capturing) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            main.check(fluffBackend.updates.state === "idle" && !fluffBackend.busy, "Real backend remains idle")
            const grid = probe.findChild(stack.get(0), "catalogGrid")
            if (main.stage === 0) {
                main.requestActivate(); stack.background = main.snapshotBackground.createObject(stack)
                main.middle(grid); main.stage = 1
            } else if (main.stage === 1) {
                main.check(grid.contentY > 0 && stack.depth === 1, "Catalogue scrolls without opening a card")
                main.capturing = true
                main.check(stack.grabToImage(result => {
                    main.check(result.saveToFile(Qt.resolvedUrl("../../target/mouse-autoscroll.png").toString().replace("file://", "")), "Save screenshot")
                    probe.keyClick(Qt.Key_Escape)
                    main.savedY = grid.contentY; main.stage = 2; main.capturing = false
                }), "Capture")
            } else if (main.stage === 2) {
                main.check(!probe.findChild(grid, "middleMouseScroll").scrolling, "Escape stops autoscroll")
                main.openApp(main.catalog[0]); main.stage = 3
            } else if (main.stage === 3) {
                main.middle(probe.findChild(stack.currentItem, "detailsFlickable")); main.stage = 4
            } else if (main.stage === 4) {
                main.check(probe.findChild(stack.currentItem, "detailsFlickable").contentY > 0, "Details scroll")
                probe.mouseClick(stack, 500, 200, Qt.BackButton); main.stage = 5
            } else if (main.stage === 5) {
                main.check(stack.depth === 1, "Back returns to catalogue (depth " + stack.depth + ")")
                main.check(Math.abs(grid.contentY - main.savedY) < 1, "Back preserves catalogue position (" + main.savedY + " -> " + grid.contentY + ")")
                main.showSettings(); main.stage = 6
            } else if (main.stage === 6) {
                main.middle(probe.findChild(stack.currentItem, "middleMouseScroll").scrollTarget); main.stage = 7
            } else if (main.stage === 7) {
                main.check(probe.findChild(stack.currentItem, "middleMouseScroll").scrollTarget.contentY > 0, "Settings scroll")
                probe.mouseClick(stack, 500, 200, Qt.BackButton); main.stage = 8
            } else if (main.stage === 8) {
                main.check(stack.depth === 1, "Back from Settings")
                main.openApp(main.catalog[0]); main.stage = 9
            } else if (main.stage === 9) {
                const dialog = probe.findChild(stack.currentItem, "appPermissionsDialog")
                dialog.changesView = true
                dialog.changes = {groups:Array.from({length:24}, (_, i) => ({id:"group" + i, title:"Permission fixture " + i,
                    icon:"object-locked", description:"Read-only test", added:["Test access"], removed:[]}))}
                dialog.open(); main.stage = 10
            } else if (main.stage === 10) {
                main.middle(probe.findChild(stack.currentItem, "permissionsScroll")); main.stage = 11
            } else if (main.stage === 11) {
                const dialog = probe.findChild(stack.currentItem, "appPermissionsDialog")
                main.check(probe.findChild(dialog, "permissionsScroll").contentY > 0, "Dialog scrolls independently")
                probe.keyClick(Qt.Key_Escape)
                main.check(dialog.visible && !probe.findChild(dialog, "middleMouseScroll").scrolling, "Escape stops without dismissing dialog")
                probe.mouseClick(dialog.contentItem, 20, 20, Qt.BackButton)
                main.check(stack.depth === 2 && dialog.visible, "Back never navigates behind modal dialog")
                dialog.close(); main.stage = 12
            } else if (main.stage === 12) {
                main.showCatalog()
                fixture.jobs = main.catalog.slice(0, 25).map((app, i) => Object.assign({}, app, {
                    index:i, action:"install", active:false, progress:1, status:"Complete", operations:[]}))
                main.showDownloads(); main.stage = 13
            } else if (main.stage === 13) {
                main.middle(probe.findChild(stack.currentItem, "middleMouseScroll").scrollTarget); main.stage = 14
            } else if (main.stage === 14) {
                main.check(probe.findChild(stack.currentItem, "middleMouseScroll").scrollTarget.contentY > 0, "Queue scrolls over its cards")
                probe.mouseClick(stack, 500, 200, Qt.BackButton); main.stage = 15
            } else if (main.stage === 15) {
                main.check(stack.depth === 1, "Back from queue")
                fixture.installedApps = main.catalog.slice(0, 25).map(app => Object.assign({}, app, {
                    installation:"user", installedBranch:"stable", installedArch:"x86_64", installedVersion:"1.0", installedSize:"1 MiB"}))
                stack.get(0).openCategory("Installed"); main.stage = 16
            } else if (main.stage === 16) {
                main.middle(probe.findChild(stack.get(0), "installedList")); main.stage = 17
            } else if (main.stage === 17) {
                main.check(probe.findChild(stack.get(0), "installedList").contentY > 0, "Installed scrolls")
                fixture.updates = {state:"ready", items:main.catalog.slice(0, 25).map(app => Object.assign({}, app, {
                    key:app.id, installation:"user", remote:"fixture", oldVersion:"1", newVersion:"2", selected:true,
                    downloadSize:"1 MiB", permissions:{state:"unchanged", groups:[]}, plan:[]}))}
                main.showUpdates(); main.stage = 18
            } else if (main.stage === 18) {
                main.middle(probe.findChild(stack.get(0), "updatesList")); main.stage = 19
            } else if (main.stage === 19) {
                main.check(probe.findChild(stack.get(0), "updatesList").contentY > 0, "App Updates scrolls")
                console.log("MOUSE_CONTROLS_PASS"); Qt.quit()
            }
        }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.exit(3) }
}
