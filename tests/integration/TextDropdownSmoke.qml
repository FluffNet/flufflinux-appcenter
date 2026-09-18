import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

// Real launcher and KDE/Wayland renderer, fixture data only. The search entry
// and count deliberately show the user's exact 3297 reproducer together.
AppCenter.Main {
    id: main
    visible: true; width: 1180; height: 760
    palette.window: "#202326"; palette.windowText: "#ffffff"; palette.placeholderText: "#a5a9ad"
    property int stage: 0
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    TestCase { id: probe; when: false }
    backend: QtObject {
        property var jobs: []
        property var review: ({})
        property var installedApps: Array.from({length:7}, (_, i) => ({
            id:"org.example.Font" + i, name:"Flatpak Builder Flatpak " + i, icon:"application-x-executable",
            installedOrigin:"flathub", installation:"default", installedSize:"319.62 MiB",
            installedVersion:"v0-Flathub", screenshots:[], summary:"", description:"", category:""
        }))
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
    }
    catalog: Array.from({length:3297}, (_, i) => ({
        id:"org.example.App" + i, name:"Application " + i, summary:"Typography test 3297", category:"Utilities",
        icon:"application-x-executable", searchName:"application " + i, searchSummary:"3297", searchDescription:"",
        searchMetadata:"", searchHaystack:"application " + i + " 3297"
    }))
    function capture(name, next) {
        stage = -1
        const stack = probe.findChild(main, "navigationStack")
        if (!stack.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/text-dropdown-" + name + ".png").toString().replace("file://", ""))) { Qt.exit(1); return }
            stage = next
        })) Qt.exit(2)
    }
    Timer {
        interval: 450; repeat: true; running: true
        onTriggered: {
            const page = probe.findChild(main, "navigationStack").currentItem
            if (main.stage < 0) return
            if (main.stage === 0) {
                const stack = probe.findChild(main, "navigationStack")
                stack.background = main.snapshotBackground.createObject(stack)
                main.selectedCategory = "Installed"; main.stage = 1
            }
            else if (main.stage === 1) { main.capture("installed-az", 2) }
            else if (main.stage === 2) { page.installedSortIndex = 5; main.stage = 3 }
            else if (main.stage === 3) { main.capture("installed-size", 4) }
            else if (main.stage === 4) {
                main.selectedCategory = "All Apps"; main.searchText = "3297"
                probe.findChild(page, "searchField").text = "3297"; main.stage = 5
            } else if (main.stage === 5) { main.capture("search-all", 6) }
            else if (main.stage === 6) { main.searchCategoryFilter = "Utilities"; main.stage = 7 }
            else if (main.stage === 7) { main.capture("search-utilities", 8) }
            else if (main.stage === 8) { page.openCategory("All Apps"); main.stage = 9 }
            else if (main.stage === 9) { main.capture("all-apps", 10) }
            else if (main.stage === 10) { Qt.quit() }
        }
    }
    Timer { interval: 30000; running: true; onTriggered: Qt.exit(100 + main.stage) }
}
