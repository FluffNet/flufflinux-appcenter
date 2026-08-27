import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "AppPage"
    when: window.visible

    ApplicationWindow {
        id: window
        width: 1180
        height: 760
        visible: true

        property color accentColor: "#e05562"
        property color textColor: "white"
        property color mutedTextColor: "#a0a0a0"
        property color surfaceColor: "#24282d"
        property color raisedSurfaceColor: "#30343a"
        property color borderColor: "#50545a"
        property color hoverColor: "#393d43"
        property var selectedApp: null

        function showCatalog() {}

        AppCenter.AppPage {
            id: appPage
            anchors.fill: parent
            app: ({
                id: "org.fluff.PreviewTest",
                name: "Preview Test",
                summary: "Screenshot preview test",
                description: "A test application",
                icon: "",
                category: "Utilities",
                developer: "FluffNet",
                license: "MIT",
                homepage: "",
                screenshots: [
                    "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23820101'/%3E%3C/svg%3E"
                ]
            })
        }
    }

    function test_clicking_screenshot_opens_preview() {
        window.requestActivate()
        tryCompare(window, "active", true)

        const screenshotButton = findChild(appPage, "screenshotButton")
        verify(screenshotButton !== null)
        mouseClick(screenshotButton,
                   screenshotButton.width / 2,
                   screenshotButton.height / 2)

        const preview = appPage.screenshotPreviewDialog
        tryCompare(preview, "visible", true)
        compare(appPage.previewScreenshot, screenshotButton.modelData)

        const closeButton = findChild(preview, "previewCloseButton")
        verify(closeButton !== null)
        mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
        tryCompare(preview, "visible", false)
    }
}
