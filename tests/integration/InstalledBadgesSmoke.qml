// Real catalog and installed Flatpaks. No app transactions or update checks.
import QtQuick
import QtTest
import "../../qml" as App

App.Main {
    id: main
    width: 1500; height: 1000
    catalogPreferences: null
    property int stage: 0
    property int settled: 0
    TestCase { id: probe; when: false }
    function check(value, message) {
        if (!value) { console.error("BADGES_FAIL", message); Qt.exit(1); throw new Error(message) }
    }
    function theme(dark) {
        palette.window = dark ? "#202326" : "#eff0f1"
        palette.windowText = dark ? "#ffffff" : "#232629"
        palette.text = palette.windowText
        palette.buttonText = palette.windowText
        palette.base = dark ? "#202326" : "#ffffff"
        palette.button = dark ? "#292d30" : "#f8f8f8"
        palette.placeholderText = dark ? "#adb8c2" : "#667580"
        palette.highlight = dark ? "#e05562" : "#880000"
        palette.link = palette.highlight
        palette.highlightedText = "#ffffff"
    }
    function capture(name) {
        const image = probe.grabImage(main.contentItem)
        image.save(Qt.resolvedUrl("../../target/installed-badges-" + name + ".png").toString().replace("file://", ""))
        console.log("BADGES_CAPTURE", name)
    }
    function verifyCards(page, search) {
        check((main.searchText.length > 0) === search, "expected search/Home state")
        const grid = probe.findChild(page, "catalogGrid")
        let installed = 0, other = 0
        for (let i = 0; i < Math.min(grid.count, 12); ++i) {
            const card = grid.itemAtIndex(i)
            if (!card) continue
            const badge = probe.findChild(card, "installedBadge")
            check(badge.visible === !!main.findInstalled(card.app), "live installed state for " + card.app.name)
            if (card.installed) installed++; else other++
        }
        check(installed > 0, "installed card in " + (search ? "search" : "Home"))
        if (!search) {
            let commonInstalled = 0
            for (const app of page.recommendedApps) {
                const card = probe.findChild(page, "recommended-" + app.id)
                check(card.installed === !!main.findInstalled(app), "common app: " + app.name)
                if (card.installed) commonInstalled++
            }
            check(commonInstalled > 0, "installed common/favorite app")
            check(other > 0, "uninstalled cards remain unmarked")
        }
    }
    Component.onCompleted: theme(true)
    Timer {
        interval: 250; repeat: true; running: true
        onTriggered: {
            if (main.catalogLoading || main.backend.installedLoading || !main.catalog.length
                    || main.catalogStats.state === "loading") return
            if (++main.settled < 8) return
            const page = probe.findChild(main, "navigationStack").get(0)
            main.check(main.backend.jobs.length === 0 && main.backend.updates.state === "idle", "no transactions/update check")
            if (main.stage === 0) {
                main.verifyCards(page, false); main.capture("home-dark")
                probe.findChild(page, "searchField").text = "firefox"
                main.searchText = "firefox"
            } else if (main.stage === 1) {
                main.verifyCards(page, true); main.capture("search-dark")
                main.theme(false); probe.findChild(page, "searchField").clear()
                main.searchText = ""
            } else if (main.stage === 2) {
                main.verifyCards(page, false); main.capture("home-light")
                probe.findChild(page, "searchField").text = "firefox"
                main.searchText = "firefox"
            } else if (main.stage === 3) {
                main.verifyCards(page, true); main.capture("search-light")
                console.log("BADGES_PASS", main.backend.installedApps.map(app => app.name).join(", "))
                Qt.quit()
            }
            main.stage++; main.settled = 0
        }
    }
    Timer { interval: 90000; running: true; onTriggered: Qt.exit(2) }
}
