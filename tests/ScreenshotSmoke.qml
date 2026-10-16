// Production Rust download/cache plus real QML preview. No app transactions.
import QtQuick
import QtTest
import "../qml" as App
App.Main {
    id: main
    width: 1180; height: 800; visible: true
    catalogPreferences: null
    catalogStats: null
    networkStatus: ({state: "online", ready: true})
    property int phase: 0
    property int ticks: 0
    TestCase { id: probe; when: false }
    function check(ok, message) {
        if (!ok) { console.error("SCREENSHOT_FAIL", message); Qt.exit(1); throw new Error(message) }
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            main.check(++main.ticks < 1800, "screenshot load timeout")
            const stack = probe.findChild(main, "navigationStack")
            if (main.ticks % 100 === 0) console.log("SCREENSHOT_WAIT", main.phase, main.catalog.length, main.catalogLoading, main.installedLoading, stack.busy, JSON.stringify(main.backend.screenshotFiles))
            if (main.phase === 0) {
                if (main.catalogLoading || main.installedLoading || !main.catalog.length) return
                const app = main.catalogApp("org.mozilla.firefox")
                main.check(app && app.screenshots.length > 1, "Firefox fixture has real screenshots")
                main.openApp(app); main.phase = 1
                return
            }
            if (stack.busy) return
            const page = stack.currentItem
            if (main.phase === 1 || main.phase === 4) {
                const files = Object.values(main.backend.screenshotFiles)
                if (!files.length || files.some(file => file.state === "loading")) return
                main.check(files.every(file => file.state === "ready" && String(file.source).startsWith("file:///")), "every screenshot fetched to a complete local cache file")
                page.openScreenshot(0)
                main.phase = main.phase === 1 ? 2 : 5
            } else if (main.phase === 2 || main.phase === 5) {
                const image = probe.findChild(page, "previewImage")
                if (!image || image.status !== Image.Ready) return
                main.check(image.sourceSize.width > 0 && image.paintedWidth > 0, "preview retains full decoded image")
                page.setPreviewZoom(2); main.check(page.previewZoom === 2, "zoom")
                page.panPreviewBy(20, 20)
                page.resetPreviewTransform()
                if (main.phase === 5) {
                    console.log("SCREENSHOT_SMOKE_COMPLETE", JSON.stringify({files:Object.keys(main.backend.screenshotFiles).length, width:image.sourceSize.width, height:image.sourceSize.height, rtl:main.rtl}))
                    Qt.quit(); stop(); return
                }
                page.movePreview(1); main.phase = 3
            } else if (main.phase === 3) {
                const image = probe.findChild(page, "previewImage")
                if (image.status !== Image.Ready) return
                main.check(page.previewScreenshotIndex === 1, "LTR image order")
                page.screenshotPreviewDialog.close()
                const app = page.app
                main.showHome(); main.openApp(app)
                main.phase = 4
            }
        }
    }
}
