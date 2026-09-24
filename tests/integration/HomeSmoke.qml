// Read-only native check: public Flathub statistics, no update scan or installs.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1400; height: 1000; visible: true
    property int stage: 0
    TestCase { id: probe; when: false }
    property Component snapshotBackground: Rectangle { color: main.backgroundColor }
    function check(value, message) {
        if (!value) { console.error("HOME_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    function capture(item, name, next) {
        stage = -1
        item.grabToImage(function(result) {
            main.check(result.saveToFile(Qt.resolvedUrl("../../target/home-" + name + ".png").toString().replace("file://", "")), "screenshot")
            main.stage = next
        })
    }
    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (main.stage < 0 || stack.busy || main.backend.installedLoading) return
            const page = stack.currentItem, grid = probe.findChild(page, "catalogGrid")
            main.check(main.backend.updates.state === "idle", "Home must never check for updates")
            if (main.stage === 0) {
                main.check(page.catalogSortIndex === 2, "Home must default to popularity")
                main.check(page.installedSortIndex === 0, "Installed must still default to A–Z")
                stack.background = main.snapshotBackground.createObject(stack)
                main.check(page.recommendedApps.length === 9, "all nine available recommendations")
                const names = page.recommendedApps.map(app => app.name)
                main.check(names.join() === names.slice().sort((a,b) => a.localeCompare(b)).join(), "alphabetical recommendations")
                main.check(!main.catalog.some(app => /org\.(videolan\.VLC|libreoffice\.LibreOffice)(\.desktop)?$/.test(app.id)), "default exclusions on this VM")
                console.log("HOME_RECOMMENDED", names.join(", "))
                grid.positionViewAtBeginning(); main.stage = 1
            } else if (main.stage === 1) {
                if (main.catalogStats.state === "loading") return
                main.check(main.catalogStats.state === "ready", "default popularity fetch")
                main.check(probe.findChild(page, "recommendedHeading").mapToItem(grid, 0, 0).y >= 0,
                           "default sorting must not scroll past recommendations")
                main.check(!probe.findChild(page, "catalogSortDescription").visible, "no permanent popularity note")
                main.check(grid.headerItem.height < grid.height - 32, "All Apps and its list visible on wide Home")
                main.capture(stack, "wide", 2)
            }
            else if (main.stage === 2) { page.catalogSortIndex = 0; page.catalogSortIndex = 2; main.stage = 3 }
            else if (main.stage === 3) {
                if (main.catalogStats.state === "loading") return
                main.check(main.catalogStats.state === "ready", "live public popularity fetch")
                main.check(Object.keys(main.catalogStats.counts).length > 3000, "complete popularity catalog")
                const apps = page.visibleApps
                const recommended = page.recommendedApps.map(app => page.catalogId(app))
                main.check(!apps.some(app => recommended.indexOf(page.catalogId(app)) >= 0), "no duplicated recommendations in popularity")
                main.check(page.catalogSortOptions.length === 6, "Home has no size sorting")
                for (let i = 1; i < apps.length; ++i)
                    main.check(page.compareCatalog(apps[i-1], apps[i], 2, page.popularityCounts) <= 0, "descending popularity")
                console.log("HOME_POPULARITY", Object.keys(main.catalogStats.counts).length, apps.slice(0, 5).map(app => app.name).join(", "))
                const sort = probe.findChild(page, "catalogSort")
                main.check(sort.mapToItem(grid, 0, 0).y >= 0 && sort.mapToItem(grid, 0, 0).y < 150, "sort remains near the top")
                main.stage = 4
            } else if (main.stage === 4) main.capture(stack, "popular", 5)
            else if (main.stage === 5) {
                main.width = 720; main.height = 540
                main.stage = 6
            } else if (main.stage === 6) { grid.positionViewAtBeginning(); main.stage = 7 }
            else if (main.stage === 7) {
                main.check(grid.headerItem.height < grid.height - 32, "All Apps and its list visible on narrow Home")
                main.capture(stack, "narrow", 8)
            }
            else if (main.stage === 8) {
                main.width = 1180; main.height = 760
                page.openCategory("Internet"); main.stage = 9
            } else if (main.stage === 9) {
                const sort = probe.findChild(page, "catalogSort")
                main.check(sort.visible && sort.currentIndex === 0, "category defaults to A–Z")
                const count = main.catalog.filter(app => app.category === "Internet").length
                for (let order = 0; order < page.catalogSortOptions.length; ++order) {
                    page.setCatalogSort(order)
                    main.check(page.visibleApps.length === count, "categories retain recommendations in every order")
                    for (let i = 1; i < count; ++i)
                        main.check(page.compareCatalog(page.visibleApps[i-1], page.visibleApps[i], order, page.popularityCounts) <= 0, "native category order " + order)
                }
                main.check(page.catalogSortIndex === 2 && main.catalogPreferences.homeSort === "popularity-desc", "categories leave saved Home order unchanged")
                page.setCatalogSort(2); main.stage = 10
            } else if (main.stage === 10) main.capture(stack, "category", 11)
            else if (main.stage === 11) { main.width = 720; main.height = 520; main.stage = 12 }
            else if (main.stage === 12) {
                const sort = probe.findChild(page, "catalogSort")
                main.check(sort.visible && sort.mapToItem(page, sort.width, 0).x < page.width, "narrow category sort fits")
                main.check(grid.height >= 100, "narrow category keeps room for apps")
                main.capture(stack, "category-narrow", 13)
            } else if (main.stage === 13) {
                page.openCategory("Games")
                main.check(page.categorySortIndex === 0, "switching category resets temporary order")
                page.openCategory("Internet")
                main.check(page.categorySortIndex === 0, "returning category stays A–Z")
                page.openCategory("All Apps")
                main.check(page.catalogSortIndex === 2, "Home keeps its preference")
                console.log("HOME_PASS", "including category sorting"); Qt.quit()
            }
        }
    }
    Timer { interval: 180000; running: true; onTriggered: { console.error("HOME_TIMEOUT"); Qt.exit(3) } }
}
