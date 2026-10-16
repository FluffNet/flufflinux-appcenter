// Real catalog, read-only installed state, simulated operation/error states.
// Never starts a transaction, edits a source, or changes desktop preferences.
import QtQuick
import QtQuick.Controls
import QtTest
import "../qml" as App

App.Main {
    id: main
    width: 1500; height: 1000
    visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state: "online", ready: true})
    backend: mock
    property string outputDirectory: "../output/i18n-2026-10-12/"
    property string language: rtl ? "he" : "de"
    property string expectedSettings: rtl ? "הגדרות" : "Einstellungen"
    property var scenes: []
    property int sceneIndex: -1
    property bool capturing: false
    property bool afterApplied: false
    property int elapsedTicks: 0
    property var realInstalled: []
    property var sampleApp: null
    property var groups: [
        {title:"Network Access", description:"Internet and local network connections.", icon:"network-wireless", details:["Network connections"]},
        {title:"Sound System Access", description:"Audio playback and recording through the sound server.", icon:"audio-card", details:["Play and record audio"]},
        {title:"Device Access", description:"Access to hardware devices outside the sandbox.", icon:"computer", details:["Graphics acceleration", "USB devices"]},
        {title:"File Access", description:"Locations available outside the app's private storage. Denied entries are exceptions to broader access.", icon:"folder", details:["Downloads - read and write", "Pictures - read only", "/run/media/mai/Backup - read only"]},
        {title:"Session Bus Access", description:"Communication with applications and services in your desktop session.", icon:"network-connect", details:["org.freedesktop.Notifications - communicate", "org.kde.StatusNotifierWatcher - communicate"]},
        {title:"Additional Capabilities", description:"Extra capabilities enabled or denied by the sandbox configuration.", icon:"preferences-system", details:["Bluetooth sockets", "Development and debugging system calls"]}
    ]
    QtObject {
        id: mock
        property var catalog: fluffBackend.catalog
        property bool catalogLoading: fluffBackend.catalogLoading
        property int catalogProgress: 50
        property bool catalogSourcesUnavailable: false
        property var jobs: []
        property var review: ({})
        property var installedApps: fluffBackend.installedApps
        property bool installedLoading: fluffBackend.installedLoading
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property bool sourcesBusy: false
        property string sourceInputStatus: ""
        property string sourcesError: ""
        property var repositories: [{name:"flathub", title:"Flathub", url:"https://dl.flathub.org/repo/", scope:"merged", hasUser:true, hasSystem:true, enabled:true, verified:true}]
        property var installSizes: ({})
        property var appPermissions: ({state:"ready", groups:main.groups})
        property var appAddons: ({state:"ready", items:[]})
        property var updates: ({state:"idle", items:[]})
        property var recovery: ({items:[], error:"", notice:0})
        signal appOpened(var app)
        signal inputError(string message)
        function requestInstallInfo(app) {}
        function requestAppPermissions(app) { return 1 }
        function cancelAppPermissions(token) {}
        function requestAppAddons(app) { return 1 }
        function cancelAppAddons(token) {}
        function refreshSources(all) {}
        function refreshRecovery() {}
        function answerReview(token, accepted) { review = ({}) }
    }
    TestCase { id: probe; objectName: "captureProbe"; when: false }
    function find(name) { return probe.findChild(main, name) }
    function findPage(name) { return probe.findChild(page(), name) }
    function stack() { return find("navigationStack") }
    function root() { return stack().get(0) }
    function page() { return stack().currentItem }
    function check(value, message) {
        if (!value) { console.error("I18N_FAIL", message); Qt.exit(1); throw new Error(message) }
    }
    function theme(dark) {
        palette.window = dark ? "#202326" : "#eff0f1"
        palette.windowText = dark ? "#ffffff" : "#232629"
        palette.text = palette.windowText; palette.buttonText = palette.windowText
        palette.base = dark ? "#202326" : "#ffffff"
        palette.button = dark ? "#292d30" : "#f8f8f8"
        palette.placeholderText = dark ? "#adb8c2" : "#667580"
        palette.highlight = dark ? "#e05562" : "#880000"
        palette.link = palette.highlight; palette.highlightedText = "#ffffff"
    }
    function closeDialogs() {
        for (const name of ["applicationMenu", "aboutDialog", "flatpakErrorDialog", "queueRecoveryDialog", "transactionReview", "appPermissionsDialog", "appAddonsDialog", "addSourceDialog", "removeSourceDialog", "sourceDetailsDialog"]) {
            const popup = find(name); if (popup) popup.close()
        }
        for (const name of ["catalogSort", "installedSort", "searchCategoryFilter"]) {
            const combo = find(name); if (combo && combo.popup) combo.popup.close()
        }
    }
    function reset() {
        closeDialogs(); main.showHome()
        mock.catalogLoading = false; mock.catalogSourcesUnavailable = false
        main.networkStatus = {state:"online", ready:true}
        mock.jobs = []; mock.review = ({}); mock.busy = false
        mock.installedApps = main.realInstalled; mock.installedError = ""
        mock.installedLoading = false
        mock.updates = {state:"idle", items:[]}
        mock.recovery = {items:[], error:"", notice:0}
        mock.sourcesBusy = false; mock.sourcesError = ""
        mock.appPermissions = {state:"ready", groups:main.groups}
        mock.appAddons = {state:"ready", items:[]}
    }
    function openSample() { main.openApp(main.sampleApp) }
    function bottom() {
        const scroll = find("detailsFlickable")
        if (scroll) scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
    }
    function job(index, action, active, failed, queued) {
        const name = ["Firefox", "Telegram", "Discord", "PrusaSlicer"][index]
        const app = catalog.find(entry => entry.name === name) || {id:"org.example." + name, name:name}
        return Object.assign({}, app, {index:index,
            action:action, active:active, failed:failed, queued:queued, queuePosition:2, queueTotal:4,
            status:failed ? "Failed" : "Installing…", error:failed ? qsTr("Connection failed") : "",
            progress:0.35, hasDownload:true, downloadComplete:false, phase:"download",
            downloadedSize:"128.00 MiB", downloadTotalSize:"512.00 MiB", downloadSpeed:"2.30 MiB/s",
            operations:[{ref:"app/org.mozilla.firefox/x86_64/stable", name:"Firefox", dependency:false, downloadSize:"512.00 MiB"}]})
    }
    function updateRow(name, version, permissions) {
        const app = catalog.find(entry => entry.name === name) || sampleApp
        return {key:name, id:app.id, name:name, installation:"system", remote:"flathub", icon:app.icon,
            flatpakRef:"app/" + name + "/x86_64/stable", oldVersion:"1.0", newVersion:version, selected:true,
            downloadSize:"128.00 MiB", downloadBytes:134217728, permissions:permissions, plan:[{ref:name, commit:"test", downloadBytes:134217728}]}
    }
    function buildScenes() { return baseScenes() }
    function baseScenes() {
        let result = [
            {name:"home", run:function() {}},
            {name:"menu", run:function() { find("applicationMenu").open() }},
            {name:"search", run:function() { find("searchField").text = "firefox"; main.searchText = "firefox" }},
            {name:"no-results", run:function() { find("searchField").text = "no-such-application"; main.searchText = "no-such-application" }},
            {name:"loading", run:function() { mock.catalogLoading = true }},
            {name:"offline", run:function() { main.networkStatus = {state:"offline",ready:true} }},
            {name:"source-error", run:function() { mock.catalogSourcesUnavailable = true }},
            {name:"installed", run:function() { root().openCategory("Installed") }},
            {name:"installed-empty", run:function() { mock.installedApps = []; root().openCategory("Installed") }},
            {name:"updates", run:function() { main.showUpdates(); mock.updates = {state:"ready",lastUpdated:"12/10/2026 10:30",items:[updateRow("Firefox","2.0",{state:"unchanged"}),updateRow("Discord","1.0",{state:"changed",groups:main.groups.map(g=>Object.assign({},g,{added:g.details,removed:[]}))})]} }},
            {name:"updates-checking", run:function() { main.showUpdates(); mock.updates = {state:"checking",items:[]} }},
            {name:"updates-empty", run:function() { main.showUpdates(); mock.updates = {state:"ready",items:[]} }},
            {name:"queue", run:function() {
                mock.jobs = [job(0,"install",true,false,false),job(1,"update",true,false,true),job(2,"install",false,true,false),job(3,"install",false,false,false)]
                mock.installedApps = main.realInstalled.concat([Object.assign({}, mock.jobs[3], {installed:true})])
                main.showDownloads()
            }},
            {name:"queue-empty", run:function() { main.showDownloads() }},
            {name:"app", run:openSample},
            {name:"app-details", run:openSample, after:bottom},
            {name:"local-source", run:function() { main.openApp(Object.assign({},sampleApp,{id:"org.example.Local",name:"Local Flatpak Preview",localSource:"/home/mai/Downloads/app.flatpakref",sourceUrl:"https://example.org/repo/",sourceWillBeAdded:true})) }},
            {name:"permissions", run:function() { openSample(); findPage("appPermissionsDialog").open() }},
            {name:"permissions-loading", run:function() { openSample(); mock.appPermissions = {state:"loading"}; findPage("appPermissionsDialog").open() }},
            {name:"permissions-error", run:function() { openSample(); mock.appPermissions = {state:"error",message:qsTr("Permission information is unavailable.")}; findPage("appPermissionsDialog").open() }},
            {name:"addons", run:function() { openSample(); mock.appAddons = {state:"ready",items:[{id:"org.example.Plugin",name:"Example add-on with a deliberately long unchanged application name",summary:"Layout fixture - no changes are made to installed add-ons.",flatpakRef:"runtime/org.example.Plugin/x86_64/stable",available:true,installed:false},{id:"org.example.Plugin2",name:"Installed add-on",flatpakRef:"runtime/org.example.Plugin2/x86_64/stable",available:true,installed:true}]}; findPage("appAddonsDialog").open() }},
            {name:"addons-install-first", run:function() { openSample(); mock.appAddons = {state:"not-installed",items:[]}; findPage("appAddonsDialog").open() }},
            {name:"settings", run:function() { main.showSettings() }},
            {name:"source-add", run:function() { main.showSettings(); findPage("addSourceDialog").open() }, popup:"addSourceDialog"},
            {name:"source-details", run:function() { main.showSettings(); page().selectedSource = mock.repositories[0]; findPage("sourceDetailsDialog").open() }, popup:"sourceDetailsDialog"},
            {name:"source-remove", run:function() { main.showSettings(); page().selectedSource = mock.repositories[0]; findPage("removeSourceDialog").open() }, popup:"removeSourceDialog"},
            {name:"uninstall", run:function() { openSample(); mock.review = {token:1,removing:true,titleKey:"Uninstall %1?",messageKey:"If you proceed, %1 will be removed for all users, and its app data for this account will be deleted.",textArguments:["Firefox"],operations:[]} }},
            {name:"recovery", run:function() { mock.recovery = {notice:1,items:[{name:"Firefox",action:"update",state:"completed"},{name:"Telegram",action:"install",state:"interrupted"}],error:"",checking:false,saving:false}; main.showRecovery() }},
            {name:"about", run:function() { main.showAbout() }},
            {name:"file-error", run:function() { mock.inputError(qsTr("Connection failed")) }}
        ]
        for (const category of ["Multimedia","Development","Education","Games","Graphics","Internet","Office","Science","System","Utilities","Other"])
            result.push({name:"category-" + category.toLowerCase(),run:function() { root().openCategory(category) }})
        return result
    }
    function capture(scene, mode) {
        const filename = language + "-" + mode + "-" + scene.name + ".png"
        probe.grabImage(main.contentItem).save(Qt.resolvedUrl(outputDirectory + filename).toString().replace("file://", ""))
        console.log("I18N_CAPTURE", filename)
    }
    Timer {
        interval: 450; repeat: true; running: true
        onTriggered: {
            if (++main.elapsedTicks > 600) { console.error("I18N_FAIL timeout"); Qt.exit(2); return }
            if (main.sceneIndex < 0) {
                if (fluffBackend.catalogLoading || fluffBackend.installedLoading || !fluffBackend.catalog.length) return
                main.check(qsTr("Settings") === main.expectedSettings, "translation loaded: " + qsTr("Settings"))
                main.realInstalled = fluffBackend.installedApps
                for (const transition of ["pushEnter","pushExit","popEnter","popExit","replaceEnter","replaceExit"]) stack()[transition] = null
                main.sampleApp = fluffBackend.catalog.find(app => app.id === "org.mozilla.firefox")
                main.check(main.sampleApp && main.sampleApp.name === "Firefox", "catalog name remains unchanged")
                main.scenes = main.buildScenes(); main.sceneIndex = 0
            }
            const count = main.scenes.length
            if (main.sceneIndex >= count * 2) { console.log("I18N_PASS", main.language, count * 2, "screens"); Qt.quit(); return }
            const scene = main.scenes[main.sceneIndex % count]
            const mode = main.sceneIndex < count ? "dark" : "light"
            if (!main.capturing) {
                main.theme(mode === "dark"); main.reset(); scene.run()
                main.capturing = true; main.afterApplied = false
            } else {
                if (scene.after && !main.afterApplied) { scene.after(); main.afterApplied = true; return }
                if (scene.popup) main.check(findPage(scene.popup).visible, "dialog is visible: " + scene.popup)
                main.capture(scene, mode); main.sceneIndex++; main.capturing = false
            }
        }
    }
}
