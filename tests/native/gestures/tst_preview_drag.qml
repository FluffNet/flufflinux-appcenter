import QtQuick
import QtQuick.Controls
import QtTest
import "../../../qml" as AppCenter

TestCase {
    name: "PreviewDragIsolation"
    when: main.visible
    AppCenter.Main { id: main; visible: true; width: 1180; height: 760 }
    readonly property string picture: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23820101'/%3E%3Cpath d='M0 0L640 360M0 360L640 0' stroke='white' stroke-width='12'/%3E%3C/svg%3E"
    readonly property var app: ({id:"org.example.PreviewDrag", name:"Preview drag test", summary:"Read-only fixture",
        description:"Long description to detect background scrolling. ".repeat(300), icon:"", developer:"Test fixture",
        category:"Utilities", license:"", homepage:"", screenshots:[picture,picture,picture,picture]})
    function stack() { return findChild(main, "navigationStack") }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.requestActivate()
    }
    function cleanup() {
        const page = stack().currentItem
        if (page.screenshotPreviewDialog) {
            page.screenshotPreviewDialog.close()
            tryCompare(page.screenshotPreviewDialog, "visible", false)
        }
        main.showCatalog(); tryCompare(stack(), "busy", false)
    }
    function openPage(width, height) {
        main.width = width || 1180; main.height = height || 760
        main.openApp(app); tryCompare(stack(), "busy", false)
        waitForPolish(stack().currentItem)
        const page = stack().currentItem
        const details = findChild(page, "detailsFlickable")
        // Reproduce browsing before opening a picture. Without a previous
        // timed page drag, Qt can leave the background's grab path unprimed.
        details.contentY = 400
        nativeInput.pointer(details, 0, 500, 350)
        for (let step = 1; step <= 10; ++step) {
            nativeInput.pointer(details, 1, 500, 350 - step * 12); wait(16)
        }
        nativeInput.pointer(details, 2, 500, 230)
        verify(details.contentY > 400, "Positive control: the background really scrolls")
        details.cancelFlick(); details.contentY = 400
        findChild(page, "screenshotList").contentX = 100
        return page
    }
    function openPreview(page, zoom) {
        page.openScreenshot(0)
        tryCompare(page.screenshotPreviewDialog, "opened", true)
        tryCompare(findChild(page.screenshotPreviewDialog, "previewImage"), "status", Image.Ready)
        page.setPreviewZoom(zoom || 2)
        waitForRendering(page.screenshotPreviewDialog.contentItem)
    }
    function drag(page, start, delta, touchpad, doubleClick) {
        const surface = findChild(page.screenshotPreviewDialog, "previewGestureSurface")
        const handler = findChild(page.screenshotPreviewDialog, "previewMousePan")
        const details = findChild(page, "detailsFlickable"), strip = findChild(page, "screenshotList")
        const originalY = details.contentY, originalX = strip.contentX
        const x = surface.width * start[0], y = surface.height * start[1]
        if (doubleClick) {
            nativeInput.pointer(surface, 0, x, y, touchpad)
            nativeInput.pointer(surface, 2, x, y, touchpad); wait(20)
        }
        nativeInput.pointer(surface, 0, x, y, touchpad)
        if (doubleClick) nativeInput.pointer(surface, 3, x, y, touchpad)
        try {
            for (let step = 1; step <= 10; ++step) {
                nativeInput.pointer(surface, 1, x + delta[0] * step / 10, y + delta[1] * step / 10, touchpad)
                wait(16)
                fuzzyCompare(details.contentY, originalY, 0.01, "Background page must remain stationary throughout the drag")
                fuzzyCompare(strip.contentX, originalX, 0.01, "Background screenshot strip must not steal the drag")
                if (step >= 3) verify(handler.active, "The image must retain the drag")
            }
        } finally {
            nativeInput.pointer(surface, 2, x + delta[0], y + delta[1], touchpad)
        }
        verify(!handler.active)
        if (delta[0] && page.previewPanLimitX(page.previewZoom) > 0)
            verify(page.previewPanX * Math.sign(delta[0]) > 0)
        if (delta[1] && page.previewPanLimitY(page.previewZoom) > 0)
            verify(page.previewPanY * Math.sign(delta[1]) > 0)
        wait(30)
        fuzzyCompare(details.contentY, originalY, 0.01, "Releasing the image must not flick the background")
        fuzzyCompare(strip.contentX, originalX, 0.01)
    }
    function test_drag_keeps_background_stationary_data() {
        let rows = []
        for (const size of [[1180,760],[720,560]])
            for (const zoom of [1.25,2,4])
                for (const touchpad of [false,true])
                    rows.push({tag:size[0]+"-"+zoom+"-"+(touchpad?"touchpad":"mouse"), size:size, zoom:zoom, touchpad:touchpad})
        return rows
    }
    function test_drag_keeps_background_stationary(data) {
        const page = openPage(data.size[0], data.size[1]); openPreview(page, data.zoom)
        for (const start of [[0.5,0.5],[0.15,0.15],[0.85,0.85]])
            for (const delta of [[80,80],[-80,-80],[0,90],[0,-90]]) {
                page.setPreviewPan(0,0)
                drag(page, start, delta, data.touchpad, false)
            }
    }
    function test_rapid_repeated_drag() {
        const page = openPage(); openPreview(page)
        for (let repeat = 0; repeat < 4; ++repeat) {
            page.setPreviewPan(0,0); drag(page, [0.5,0.5], [80,80], false, true)
        }
    }
    function test_open_stops_background_motion_and_close_restores_scrolling_data() {
        return ["flick", "smooth-wheel", "middle", "strip-flick", "strip-middle"].map(mode => ({tag:mode, mode:mode}))
    }
    function test_open_stops_background_motion_and_close_restores_scrolling(data) {
        const page = openPage(), details = findChild(page, "detailsFlickable"), strip = findChild(page, "screenshotList")
        const wheel = findChild(page, "detailsNaturalScroll")
        if (data.mode === "flick") { details.flick(0,-1200); wait(30); verify(details.flicking) }
        if (data.mode === "strip-flick") { strip.flick(-1200,0); wait(30); verify(strip.flicking) }
        if (data.mode === "smooth-wheel") { nativeInput.mouseWheel(details, 10, 10, 0, -120); wait(20) }
        if (data.mode === "middle" || data.mode === "strip-middle") {
            details.contentY = 0; waitForPolish(page)
            const view = data.mode === "middle" ? details : strip
            mouseClick(view, 30, 30, Qt.MiddleButton)
            verify(findChild(view, "middleMouseScroll").scrolling)
        }
        page.openScreenshot(0)
        const frozenY = details.contentY, frozenX = strip.contentX
        tryCompare(page.screenshotPreviewDialog, "opened", true)
        wait(250)
        fuzzyCompare(details.contentY, frozenY, 0.01)
        fuzzyCompare(strip.contentX, frozenX, 0.01)
        verify(!details.flicking && !strip.flicking)
        verify(!wheel.middleMouseScroll.scrolling && !findChild(strip, "middleMouseScroll").scrolling)
        page.screenshotPreviewDialog.close(); tryCompare(page.screenshotPreviewDialog, "visible", false)
        verify(details.interactive && strip.interactive && wheel.enabled)
        nativeInput.mouseWheel(details, 10, 10, 0, -120)
        tryVerify(() => details.contentY > frozenY)
    }
}
