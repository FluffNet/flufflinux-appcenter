import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as App
import "../../qml/Bidi.js" as Bidi

TestCase {
    name: "RtlLayout"
    when: window.visible
    function test_values_are_isolated_without_changing_their_content() {
        compare(Bidi.format("מקור: %1\nכתובת: %2", ["App %2", "https://example.org/repo/"], true),
                "מקור: \u2068App %2\u2069\nכתובת: \u2068https://example.org/repo/\u2069")
        compare(Bidi.format("Size: %1", ["128 MiB"], false), "Size: 128 MiB")
        compare(Bidi.format("%1 / %2", ["128 MiB", "512 MiB"], true), "\u2068128 MiB\u2069 / \u2068512 MiB\u2069")
    }
    ApplicationWindow {
        id: window
        width: 800; height: 600; visible: true
        property color accentColor: "#e05562"
        property color borderColor: "#404448"
        property color textColor: "white"
        property color mutedTextColor: "#aaaaaa"
        property color surfaceColor: "#252525"
        property color hoverColor: "#333333"
        property color accentForegroundColor: "white"
        property int cornerRadius: 8
        function iconSource(name) { return "" }
        App.FluffProgressBar { id: bar; x:20; y:20; width:400; height:8; value:0.35 }
        App.AppActionButton { id: action; x:20; y:60; width:220; height:56; text:"Open" }
        App.UpdateCheckBox { id: check; x:20; y:140; width:250; text:"Select All" }
    }
    function test_open_icon_only_mirrors_in_rtl_data() {
        return [{tag:"ltr",rtl:false}, {tag:"rtl",rtl:true}]
    }
    function test_open_icon_only_mirrors_in_rtl(data) {
        action.LayoutMirroring.enabled = data.rtl
        action.LayoutMirroring.childrenInherit = true
        const icon = findChild(action, "openActionIcon")
        const otherIcon = findChild(action, "appActionIcon")
        for (const name of ["media-playback-start", "dialog-cancel", "edit-delete"]) {
            action.icon.name = name
            compare(icon.visible, name === "media-playback-start")
            compare(icon.mirror, data.rtl)
            compare(otherIcon.mirror, false)
            compare(icon.color, window.textColor)
        }
    }
    function test_checkbox_indicator_uses_leading_edge_data() {
        return [{tag:"ltr",rtl:false}, {tag:"rtl",rtl:true}]
    }
    function test_checkbox_indicator_uses_leading_edge(data) {
        check.LayoutMirroring.enabled = data.rtl
        check.LayoutMirroring.childrenInherit = true
        waitForPolish(check)
        fuzzyCompare(check.indicator.x, data.rtl
            ? check.width - check.rightPadding - check.indicator.width : check.leftPadding, 0.1)
        compare(check.contentItem.leftPadding > 0, !data.rtl)
        compare(check.contentItem.rightPadding > 0, data.rtl)
    }
    function test_progress_fill_direction_data() {
        const rows = []
        for (const rtl of [false, true]) for (const value of [0, 0.35, 1])
            rows.push({tag:(rtl ? "rtl" : "ltr") + value, rtl:rtl, value:value})
        return rows
    }
    function test_progress_fill_direction(data) {
        bar.LayoutMirroring.enabled = data.rtl
        bar.LayoutMirroring.childrenInherit = true
        bar.value = data.value; bar.indeterminate = false; bar.activeStep = false
        waitForPolish(bar)
        const fill = findChild(bar, "progressFill")
        const first = fill.mapToItem(bar, 0, 0).x
        const last = fill.mapToItem(bar, fill.width, 0).x
        fuzzyCompare(Math.abs(last - first), bar.width * data.value, 0.01)
        fuzzyCompare(Math.min(first,last), data.rtl ? bar.width * (1-data.value) : 0, 0.01)
    }
    function test_activity_direction_data() { return [{tag:"ltr",rtl:false}, {tag:"rtl",rtl:true}] }
    function test_activity_direction(data) {
        bar.LayoutMirroring.enabled = data.rtl
        bar.value = 0.35; bar.activeStep = true; bar.indeterminate = false
        waitForPolish(bar)
        const activity = findChild(bar, "progressActivity")
        const first = activity.mapToItem(bar, 0, 0).x
        const last = activity.mapToItem(bar, 1, 0).x
        verify(data.rtl ? last < first : last > first, "Activity movement mirrors with the fill")
        bar.activeStep = false; bar.indeterminate = true
        const fill = findChild(bar, "progressFill")
        const start = fill.mapToItem(bar, 0, 0).x
        const end = fill.mapToItem(bar, 1, 0).x
        verify(data.rtl ? end < start : end > start, "Indeterminate movement mirrors too")
        bar.indeterminate = false
    }
}
