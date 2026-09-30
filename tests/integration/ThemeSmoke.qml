// The real UI and local catalog, with harmless simulated update/source data.
// The native driver applies KDE-generated palettes to this same open window.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter
import "../../qml/ThemeColors.js" as ThemeColors

AppCenter.Main {
    id: main
    visible: true; width: 1400; height: 1000
    backend: fixture; catalog: themeCatalog
    catalogStats: null; catalogPreferences: null; networkStatus: null
    property int caseIndex: 0
    property int stage: 0
    property bool capturing: false
    property var currentCase: ({})
    property var detailApp: null
    TestCase { id: probe; when: false }
    Rectangle { anchors.fill: parent; color: main.backgroundColor; z: -100 }
    QtObject {
        id: fixture
        property var jobs: []
        property var installedApps: []
        property var installSizes: ({})
        property var review: ({})
        property var updates: ({state:"idle", items:[]})
        property var repositories: [{name:"flathub", title:"Flathub", scope:"user", enabled:true,
            hasUser:true, verified:true, url:"https://dl.flathub.org/repo/"}]
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: jobs.some(job => job.active)
        property bool sourcesBusy: false
        property string sourcesError: ""
        function requestInstallInfo(app) {}
        function refreshSources() {}
    }
    function check(value, message) {
        if (!value) { console.error("THEME_FAIL", currentCase.name, message); Qt.exit(2); throw new Error(message) }
    }
    function capture(name, next) {
        check(themeProbe.capture(main, themeOutput + "/" + currentCase.name + "-" + name + ".png"), "save " + name)
        stage = next
    }
    function checkPublisher(label) {
        check(!!label && label.visible, "publisher visible")
        check(Qt.colorEqual(label.color, main.accentTextColor), "publisher uses readable KDE text color")
        check(ThemeColors.contrast(label.color, main.surfaceColor) >= 4.49, "publisher text contrast")
    }
    Timer {
        interval: 220; repeat: true; running: true
        onTriggered: {
            if (main.capturing) return
            const stack = probe.findChild(main, "navigationStack")
            if (stack.busy) return
            const page = stack.get(0)
            if (main.stage === 0) {
                fixture.jobs = []; fixture.updates = {state:"idle", items:[]}
                main.showHome()
                main.currentCase = themeProbe.apply(main.caseIndex)
                if (!main.currentCase.name) { console.log("THEME_PASS", main.caseIndex, "palettes"); Qt.quit(); return }
                page.catalogSortIndex = 0
                main.detailApp = Object.assign({}, main.catalog.find(app => app.id === "org.telegram.desktop"), {screenshots:[]})
                main.check(!!main.detailApp.id, "real Telegram catalog entry")
                main.stage = 1
            } else if (main.stage === 1) {
                main.check(main.darkMode === main.currentCase.name.startsWith("dark-"), "correct light/dark scheme")
                main.check(Qt.colorEqual(main.accentColor, main.currentCase.highlight), "selection follows live palette")
                main.check(Qt.colorEqual(main.accentTextColor, ThemeColors.readableText(main.currentCase.link,
                    [main.backgroundColor, main.surfaceColor], main.textColor)), "colored text follows live palette")
                main.check(Qt.colorEqual(main.accentForegroundColor, main.currentCase.highlightedText), "accent foreground")
                main.checkPublisher(probe.findChild(page, "recommendedAppPublisher"))
                const icon = probe.findChild(main, "headerAppIcon")
                main.check(icon.status === Image.Ready, "header theme icon loaded")
                main.check(icon.source.toString() === main.appIconUrl.toString(), "shared icon URL")
                const search = probe.findChild(main, "searchField")
                search.forceActiveFocus()
                main.capture("home", 2)
            } else if (main.stage === 2) {
                main.openApp(main.detailApp); main.stage = 3
            } else if (main.stage === 3) {
                main.checkPublisher(probe.findChild(stack.currentItem, "appDeveloper"))
                main.capture("details", 4)
            } else if (main.stage === 4) {
                const update = Object.assign({}, main.detailApp, {key:"preview:telegram", installation:"user",
                    oldVersion:"1.0", newVersion:"1.1", selected:true, downloadBytes:67108864,
                    permissions:{state:"unchanged"}, plan:[]})
                const other = Object.assign({}, main.catalog.find(app => app.id === "com.discordapp.Discord"),
                    {key:"preview:discord", installation:"user", oldVersion:"1.0", newVersion:"1.1",
                     selected:true, downloadBytes:10485760, permissions:{state:"unchanged"}, plan:[]})
                for (const row of [update, other]) row.plan = [{ref:row.flatpakRef,
                    commit:"theme-preview", downloadBytes:row.downloadBytes}]
                fixture.updates = {state:"ready", items:[update, other]}
                fixture.jobs = [Object.assign({}, update, {index:0, action:"update", active:true, progress:0.5,
                    queued:false, failed:false, status:"Downloading...", queuePosition:1, queueTotal:2,
                    hasDownload:true, downloadedSize:"32.00 MiB", downloadTotalSize:"64.00 MiB", downloadSpeed:"2.00 MiB/s",
                    operations:[{ref:update.flatpakRef, commit:"theme-preview", receivedBytes:33554432,
                        downloadBytes:67108864, downloadProgress:0.5}]}),
                    Object.assign({}, other, {index:1, action:"update", active:true, queued:true, failed:false, progress:0,
                    status:"Queued...", operations:[]})]
                main.showUpdates(); main.stage = 5
            } else if (main.stage === 5) {
                const mark = probe.findChild(page, "updateCheckMark")
                main.check(!!mark && Qt.colorEqual(mark.color, main.currentCase.highlightedText), "checkmark contrast")
                main.capture("updates", 6)
            } else if (main.stage === 6) {
                fixture.jobs = []
                main.showSettings(); main.stage = 7
            } else if (main.stage === 7) {
                const mark = probe.findChild(stack.currentItem, "sourceCheckMark")
                main.check(!!mark && Qt.colorEqual(mark.color, main.currentCase.highlightedText), "source checkmark contrast")
                main.capture("settings", 8)
            } else if (main.stage === 8) {
                main.showHome()
                probe.findChild(main, "aboutDialog").open(); main.stage = 9
            } else if (main.stage === 9) {
                const icon = probe.findChild(main, "aboutAppIcon")
                main.check(icon.status === Image.Ready && icon.source.toString() === main.appIconUrl.toString(), "About theme icon loaded")
                main.capture("about", 10)
            } else {
                probe.findChild(main, "aboutDialog").close()
                console.log("THEME_CASE_PASS", main.currentCase.name, "highlight", main.accentColor, "text", main.accentTextColor)
                main.caseIndex++; main.stage = 0
            }
        }
    }
}
