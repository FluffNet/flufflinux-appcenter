// Native KDE rendering of simulated scan states. No transactions or source changes.
import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1180; height: 760; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state:"online",ready:true})
    backend: mock
    QtObject {
        id: mock
        property var catalog: []
        property bool catalogLoading: false
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property var jobs: []
        property var review: ({})
        property bool busy: true
        property var updates: ({state:"checking",items:[],progress:25,phase:"source",target:"flathub"})
        function cancelUpdateCheck() {}
    }
    TestCase { id: probe; when: false }
    property int scene: 0
    property bool prepared: false
    property Component backdrop: Rectangle { color: main.backgroundColor }
    readonly property var scenes: [
        {name:"source",width:1180,progress:25,phase:"metadata",target:"flathub"},
        {name:"plans",width:1180,progress:73,phase:"plan",target:"Blender"},
        {name:"narrow",width:720,progress:45,phase:"source",target:"flathub-community-source-with-a-very-long-name-for-wrapping-checks"}
    ]
    function check(value,message) {
        if (!value) { console.error("SCAN_CAPTURE_FAIL",message);Qt.exit(2);throw new Error(message) }
    }
    function setTheme(dark) {
        palette.window=dark ? "#202326" : "#eff0f1"
        palette.windowText=dark ? "#ffffff" : "#232629"
        palette.text=palette.windowText;palette.buttonText=palette.windowText
        palette.base=dark ? "#202326" : "#ffffff"
        palette.button=dark ? "#292d30" : "#f8f8f8"
        palette.placeholderText=dark ? "#adb8c2" : "#667580"
        palette.highlight=dark ? "#e05562" : "#880000"
        palette.link=palette.highlight;palette.highlightedText="#ffffff"
    }
    Timer {
        interval:400;repeat:true;running:true
        onTriggered: {
            const stack=probe.findChild(main,"navigationStack")
            if (stack.busy) return
            if (main.scene>=main.scenes.length*2) { console.log("SCAN_CAPTURE_PASS",Qt.locale().name,main.rtl);Qt.quit();return }
            const state=main.scenes[main.scene%main.scenes.length]
            const dark=main.scene<main.scenes.length
            if (!main.prepared) {
                if (!stack.background) stack.background=main.backdrop.createObject(stack)
                main.setTheme(dark);main.width=state.width
                mock.updates={state:"checking",items:[],progress:state.progress,phase:state.phase,target:state.target}
                main.showUpdates();main.prepared=true;return
            }
            const page=probe.findChild(stack.get(0),"updatesPage")
            const bar=probe.findChild(page,"updateCheckProgress")
            const fill=probe.findChild(bar,"progressFill")
            main.check(bar.visible && bar.value===state.progress,"Displayed scan progress")
            main.check(!bar.indeterminate,"No invented network progress")
            const first=fill.mapToItem(bar,0,0).x
            const last=fill.mapToItem(bar,fill.width,0).x
            main.check(Math.abs(Math.min(first,last)-(main.rtl ? bar.width*(1-state.progress/100) : 0))<0.2,"Fill follows RTL")
            const caption=probe.findChild(page,"updateCheckStatus")
            main.check(caption.text===qsTr("Checking for app updates…"),"Localized caption")
            const indicator=probe.findChild(page,"updateCheckIndicator")
            const point=indicator.mapToItem(page,0,0)
            main.check(point.x>=0 && point.x+indicator.width<=page.width,"Narrow/long labels fit")
            const path=Qt.resolvedUrl("../../target/scan-check-"+Qt.locale().name+"-"+(dark?"dark":"light")+"-"+state.name+".png").toString().replace("file://","")
            probe.grabImage(main.contentItem).save(path)
            console.log("SCAN_CAPTURE",path)
            ++main.scene;main.prepared=false
        }
    }
    Timer {interval:30000;running:true;onTriggered:main.check(false,"Timed out")}
}
