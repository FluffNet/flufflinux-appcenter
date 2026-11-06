// Native Rust/Qt launcher with presentation-only jobs. Never updates real apps.
// Run with the isolated update-profile example, LANGUAGE=en/he/de.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    backend: fixture
    catalogPreferences: null
    property int step: 0
    property bool pending: false
    readonly property var scenarios: [
        {page:"updates", bytes:2}, {page:"updates", bytes:54},
        {page:"updates", bytes:190}, {page:"updates", bytes:54, installing:true},
        {page:"queue", bytes:54}, {page:"queue", bytes:54, installing:true},
        {page:"app", bytes:54}, {page:"app", bytes:54, installing:true}]
    property var app: ({id:"org.example.Progress", key:"user:org.example.Progress",
        name:"Progress example", developer:"UI test fixture", icon:"application-x-executable",
        description:"Presentation fixture. No real app is updated.", summary:"Progress presentation test",
        screenshots:[], category:"Utilities", homepage:"https://example.org", license:"MIT",
        installation:"user", remote:"fixture", installedOrigin:"fixture", installedVersion:"1.0",
        oldVersion:"1.0", newVersion:"1.1", selected:true, downloadBytes:209715200,
        permissions:{state:"unchanged",groups:[]}, plan:[{ref:"org.example.Progress", downloadBytes:209715200}]})
    TestCase { id: probe; when: false }
    QtObject {
        id: fixture
        property var jobs: []
        property var review: ({})
        property var installedApps: [main.app]
        property var installSizes: ({})
        property bool installedLoading: false
        property bool catalogLoading: false
        property string installedError: ""
        property bool busy: true
        property int iconRevision: 0
        property var updates: ({state:"ready", items:[main.app]})
        function requestInstallInfo(app) {}
    }
    function check(value, message) {
        if (!value) { console.error("PROGRESS_PRESENTATION_FAIL", message); Qt.exit(2); throw new Error(message) }
    }
    function prepare() {
        const dark = step < scenarios.length
        palette.window = dark ? "#202326" : "#eff0f1"
        palette.windowText = dark ? "#ffffff" : "#232629"
        palette.text = palette.windowText; palette.buttonText = palette.windowText
        palette.base = dark ? "#202326" : "#ffffff"
        palette.button = dark ? "#292d30" : "#f8f8f8"
        palette.placeholderText = dark ? "#adb8c2" : "#667580"
        palette.highlight = dark ? "#e05562" : "#880000"
        palette.highlightedText = "#ffffff"; palette.link = palette.highlight
        const state = scenarios[step % scenarios.length]
        fixture.jobs = [Object.assign({}, app, {index:0, action:"update", active:true, queued:false,
            queueBatch:1, progress:state.bytes / 200, progressPercent:Math.floor(state.bytes / 2),
            phase:state.installing ? "install" : "download", progressIndeterminate:!!state.installing,
            status:state.installing ? "Installing…" : "Downloading…",
            hasDownload:true, downloadComplete:!!state.installing,
            downloadedSize:state.bytes + ".00 MiB", downloadTotalSize:"200.00 MiB", downloadSpeed:"2.30 MiB/s",
            operations:[{ref:app.id, downloadBytes:209715200}]})]
        main.showCatalog()
        if (state.page === "updates") main.showUpdates()
        else if (state.page === "queue") main.showDownloads()
        else main.openApp(app)
        pending = true
    }
    Timer {
        interval: 650; repeat: true; running: true
        onTriggered: {
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            if (!main.pending) { main.prepare(); return }
            const state = main.scenarios[main.step % main.scenarios.length]
            const root = state.page === "updates" ? probe.findChild(stack.get(0), "updatesPage") : stack.currentItem
            const bar = probe.findChild(root, "overallInstallProgress")
            const percentage = probe.findChild(root, "overallPercentageLabel")
            main.check(bar && bar.visible, "Shared bar visible on " + state.page)
            main.check(bar.indeterminate === !!state.installing, "Correct progress mode")
            main.check(bar.mirrored === main.rtl, "Bar follows layout direction")
            main.check(percentage.visible === !state.installing, "Only downloads show a numeric percentage")
            if (!state.installing) {
                main.check(percentage.text === qsTr("%1%").arg(Math.floor(state.bytes / 2)), "Percentage matches bytes")
                main.check(Math.abs(probe.findChild(bar, "progressFill").width / bar.width - state.bytes / 200) < 0.001, "Fill matches bytes")
            } else {
                const label = probe.findChild(root, "progressStageLabel")
                main.check(label.visible && label.text === qsTranslate("AppCenter", "Installing…"), "Translated installation status")
                main.check(label.implicitWidth <= label.width, "Installation text fits")
            }
            main.check(probe.findChild(bar, "progressActivity") === null, "One fill only")
            const language = Qt.locale().name
            const name = "progress-202611-" + language + "-" + (main.darkMode ? "dark-" : "light-")
                + state.page + "-" + (state.installing ? "installing" : Math.floor(state.bytes / 2)) + ".png"
            // QuickTest's image save method returns void; inspect the output
            // files after the run rather than treating that return as failure.
            probe.grabImage(main.contentItem).save(Qt.resolvedUrl("../../target/" + name).toString().replace("file://", ""))
            main.step++; main.pending = false
            if (main.step === main.scenarios.length * 2) { console.log("PROGRESS_PRESENTATION_PASS", language, main.rtl); Qt.quit() }
        }
    }
    Timer { interval:60000; running:true; onTriggered:Qt.exit(3) }
}
