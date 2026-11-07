import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as App

TestCase {
    name: "ProgressStress"
    when: window.visible
    ApplicationWindow {
        id: window
        width:640; height:260; visible:true
        property color accentColor:"#e05562"
        property color borderColor:"#404448"
        property color textColor:"white"
        App.FluffProgressBar { id: bar; x:20; y:20; width:300; height:8 }
        App.InstallationProgress { id: progress; x:20; y:70; width:500 }
    }
    function variants() {
        return [{tag:"dark-ltr",rtl:false,light:false},{tag:"dark-rtl",rtl:true,light:false},
                {tag:"light-ltr",rtl:false,light:true},{tag:"light-rtl",rtl:true,light:true}]
    }
    function setup(data) {
        window.borderColor=data.light ? "#d7dade" : "#404448"
        window.textColor=data.light ? "#232629" : "white"
        window.accentColor=data.light ? "#880000" : "#e05562"
        bar.LayoutMirroring.enabled=data.rtl
        progress.LayoutMirroring.enabled=data.rtl
        progress.LayoutMirroring.childrenInherit=true
        bar.visible=true; bar.indeterminate=false
    }
    function sample(value) {
        return {active:true,queued:false,action:"install",phase:"download",operations:[{}],
            progress:value,progressPercent:Math.floor(value*100+0.000001),progressIndeterminate:false,
            hasDownload:true,downloadComplete:false,downloadedSize:(200*value).toFixed(2)+" MiB",downloadTotalSize:"200 MiB",downloadSpeed:"2 MiB/s"}
    }
    function test_one_thousand_download_install_retry_transitions_data() { return variants() }
    function test_one_thousand_download_install_retry_transitions(data) {
        setup(data)
        const live=findChild(progress,"overallInstallProgress")
        const percentage=findChild(progress,"overallPercentageLabel")
        const bytes=findChild(progress,"downloadBytesLabel")
        for (let cycle=0;cycle<250;++cycle) {
            const value=(cycle%101)/100
            progress.job=sample(value)
            waitForPolish(progress)
            verify(live.visible && !live.indeterminate)
            compare(percentage.text,Math.floor(value*100+0.000001)+"%")
            compare(findChild(live,"progressFill").x,0,"Retry starts with no residual animated offset")
            fuzzyCompare(findChild(live,"progressFill").width,live.width*value,0.01)
            progress.job=Object.assign({},progress.job,{phase:"install",progressIndeterminate:true,downloadComplete:true})
            verify(live.indeterminate && !percentage.visible && !bytes.visible)
            compare(findChild(progress,"progressStageLabel").text,"Installing…")
            compare(findChild(live,"progressActivity"),null)
            if (cycle%5===0) wait(20)
            // Cache-only and local bundle deployment never invent network bytes.
            progress.job=Object.assign({},progress.job,{hasDownload:false,action:cycle%2 ? "source" : "install"})
            verify(live.indeterminate && !percentage.visible && !bytes.visible)
            progress.job=Object.assign({},progress.job,{active:false,failed:cycle%2===0})
            verify(!progress.visible)
            progress.job=Object.assign({},sample(0),{queued:true})
            verify(!progress.visible)
        }
        progress.job=null
    }
    function test_no_pixels_animate_beyond_50_95_or_99_percent_data() { return variants() }
    function test_busy_segment_travels_in_reading_direction_data() { return variants() }
    function test_busy_segment_travels_in_reading_direction(data) {
        setup(data)
        bar.indeterminate=true
        wait(60)
        const fill=findChild(bar,"progressFill")
        const before=fill.mapToItem(bar,fill.width/2,4).x
        wait(120)
        const after=fill.mapToItem(bar,fill.width/2,4).x
        verify(data.rtl ? after<before : after>before,"Busy segment travels in the locale's reading direction")
        bar.indeterminate=false
        compare(fill.x,0)
    }
    function test_no_pixels_animate_beyond_50_95_or_99_percent(data) {
        setup(data)
        progress.job=null
        for (const value of [0.5,0.95,0.99]) {
            // Actually run a busy animation, then switch back to determinate.
            bar.indeterminate=true; wait(120)
            bar.indeterminate=false; bar.value=value
            waitForRendering(bar)
            // QuickTest's software item crop is not DPR-adjusted. Use window
            // pixels at the track's physical coordinates; keep it within the
            // window crop even at fractional scaling.
            const first=grabImage(window.contentItem)
            const scale=window.screen.devicePixelRatio
            verify(scale>0)
            compare(findChild(bar,"progressFill").x,0)
            for (let frame=0;frame<25;++frame) {
                wait(50)
                const current=grabImage(window.contentItem)
                verify(current.equals(first),"Determinate bar changed during a full former animation cycle")
                compare(findChild(bar,"progressActivity"),null)
                if (value<0.99) {
                    const inset=Math.ceil(8*scale)
                    const x=Math.floor(bar.x*scale)+(data.rtl ? inset : Math.floor(bar.width*scale*value)+inset)
                    const y=Math.floor((bar.y+bar.height/2)*scale)
                    fuzzyCompare(current.pixel(x,y),window.borderColor,0.01,"No extra fragment in the unfilled track")
                }
            }
        }
    }
}
