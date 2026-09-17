// Read-only visual checks in KDE. Installed metadata is real; download jobs
// are fixtures. No apps are installed, removed, cancelled, or launched.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    visibility: Window.Maximized
    property int stage: 0
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    property QtObject fixtureBackend: QtObject {
        property var jobs: []
        property var review: ({})
        property var installedApps: fluffBackend.installedApps
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property var installSizes: ({})
        signal appOpened(var app)
        signal inputError(string message)
        function launchApp(app) {}
        function cancelJob(index) {}
    }
    function find(item, name) {
        if (item.objectName === name) return item
        for (const child of (item.children || [])) {
            const found = find(child, name)
            if (found) return found
        }
        return null
    }
    function capture(name, next) {
        const stack = find(contentItem, "navigationStack")
        stage = -1
        stack.grabToImage(function(result) {
            if (!result.saveToFile(Qt.resolvedUrl("../../target/downloads-sort-" + name + ".png").toString().replace("file://", ""))) {
                console.error("DOWNLOADS_SORT_FAIL: capture " + name); Qt.exit(1); return
            }
            stage = next
        })
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            const stack = main.find(main.contentItem, "navigationStack")
            if (main.installedLoading || stack.busy || main.stage < 0) return
            if (main.stage === 0) {
                stack.background = main.snapshotBackground.createObject(stack)
                main.selectedCategory = "Installed"
                stack.currentItem.installedSortIndex = 4
                main.stage = 1
            } else if (main.stage === 1) {
                const sorted = stack.currentItem.installedMatches
                for (let index = 0; index < sorted.length; ++index) {
                    if (typeof sorted[index].installedBytes !== "number"
                            || (index > 0 && sorted[index].installedBytes > sorted[index - 1].installedBytes)) {
                        console.error("DOWNLOADS_SORT_FAIL: native installed byte sorting"); Qt.exit(1); return
                    }
                }
                main.capture("installed", 2)
            } else if (main.stage === 2) {
                main.find(stack.currentItem, "installedSort").popup.open()
                main.stage = 3
            } else if (main.stage === 3) {
                main.capture("sort-menu", 4)
            } else if (main.stage === 4) {
                main.find(stack.currentItem, "installedSort").popup.close()
                const app = main.catalog.find(item => item.id === "com.play0ad.zeroad")
                const installed = main.installedApps.find(item => item.id === "com.valvesoftware.Steam")
                if (!app || !installed) {
                    console.error("DOWNLOADS_SORT_FAIL: expected catalog/installed fixtures unavailable"); Qt.exit(1); return
                }
                main.fixtureBackend.jobs = [
                    {id: app.id, name: app.name, icon: app.icon, index: 0, action: "install", active: true,
                     status: "Downloading", progress: 0.25, hasDownload: true, downloadComplete: false,
                     downloadedSize: "448.00 MiB", downloadTotalSize: "1.77 GiB", downloadSpeed: "2.30 MiB/s",
                     operations: [{name: "Hidden dependency", dependency: true}, {name: app.id}]},
                    {id: installed.id, name: installed.name, icon: installed.icon, index: 1, action: "install", active: false,
                     status: "Complete", progress: 1, operations: [{name: installed.id, status: "Complete"}]}
                ]
                main.backend = main.fixtureBackend
                main.showDownloads()
                main.stage = 5
            } else if (main.stage === 5) {
                main.capture("downloads", 6)
            } else if (main.stage === 6) {
                main.visibility = Window.Windowed
                main.stage = 7
            } else if (main.stage === 7) {
                // Wait for Wayland's restored-size configure before resizing.
                main.width = 720; main.height = 760
                main.stage = 8
            } else if (main.stage === 8) {
                if (main.width !== 720) {
                    console.error("DOWNLOADS_SORT_FAIL: narrow window was not resized"); Qt.exit(1); return
                }
                main.capture("downloads-narrow", 9)
            } else if (main.stage === 9) {
                main.showCatalog()
                main.selectedCategory = "All Apps"
                main.searchText = "no-such-application-visual-test"
                main.stage = 10
            } else if (main.stage === 10) {
                main.capture("empty", 11)
            } else if (main.stage === 11) {
                console.info("DOWNLOADS_SORT_PASS")
                Qt.quit()
            }
        }
    }
}
