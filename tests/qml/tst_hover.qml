import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

// Exercise actual pointer events and window pixels, not just color bindings.
// No real backend: hovering/touching these fixtures cannot change installations.
TestCase {
    name: "Hover"
    when: main.visible
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property var installSizes: ({})
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        signal appOpened(var app)
        signal inputError(string message)
        function answerReview(token, yes) { review = ({}) }
    }
    AppCenter.Main { id: main; backend: backend }
    Image { id: sampledImage; parent: main.contentItem; visible: false }
    Canvas { id: pixelReader; parent: main.contentItem; x: -10; width: 1; height: 1 }
    readonly property string image: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='640' height='360'%3E%3Crect width='640' height='360' fill='%23820101'/%3E%3C/svg%3E"
    readonly property var app: ({id: "org.example.Hover", name: "Hover test", summary: "", description: "", icon: image,
        developer: "", category: "Utilities", license: "", homepage: "", screenshots: [image, image, image],
        searchName: "hover test", searchSummary: "", searchDescription: "", searchMetadata: "utilities", searchHaystack: "hover test utilities",
        installation: "user", installedBranch: "stable", installedVersion: "1.0", installedSize: "12.00 MiB"})
    readonly property var job: ({id: app.id, name: app.name, index: 0, action: "install", active: true,
        progress: 0.5, operations: [{name: app.id}], icon: image})
    function stack() { return findChild(main, "navigationStack") }
    function settle() { tryCompare(stack(), "busy", false); waitForPolish(main.contentItem); wait(20) }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop)/)
        main.requestActivate()
        main.catalog = [app]
        backend.installSizes = ({[app.id]: {state: "ready", appSize: "12.00 MiB", totalSize: "12.00 MiB"}})
        settle()
    }
    function cleanup() {
        backend.review = ({})
        if (stack().currentItem.screenshotPreviewDialog) {
            stack().currentItem.screenshotPreviewDialog.close()
            tryCompare(stack().currentItem.screenshotPreviewDialog, "visible", false)
        }
        main.showCatalog(); settle()
        stack().currentItem.openCategory("All Apps")
        backend.jobs = []; backend.installedApps = []
    }
    function theme(dark) {
        main.palette.window = dark ? "#202326" : "#eff0f1"
        main.palette.windowText = dark ? "#ffffff" : "#202326"
        main.palette.placeholderText = dark ? "#a5a9ad" : "#62676b"
    }
    function neutralPoint() {
        const preview = stack().currentItem.screenshotPreviewDialog
        const review = findChild(main, "transactionReview")
        const popup = preview && preview.opened ? preview : review.opened ? review : null
        // Touch inside the popup's padding, not outside (which would dismiss
        // the screenshot dialog), and never on a real action.
        return popup ? popup.background.mapToItem(main.contentItem, popup.width / 2, 6)
                     : Qt.point(main.width / 2, 5)
    }
    function away() {
        const point = neutralPoint()
        mouseMove(main.contentItem, point.x, point.y)
    }
    function sceneRoot() {
        const preview = stack().currentItem.screenshotPreviewDialog
        const review = findChild(main, "transactionReview")
        return preview && preview.opened ? preview.contentItem : review.opened ? review.footer : stack()
    }
    function capture() {
        const root = sceneRoot()
        // Item readback honors fractional DPR. QtTest's window grab can crop
        // the offscreen software window to its unscaled size at 150%.
        let shot = null
        verify(root.grabToImage(result => shot = result))
        tryVerify(function() { return shot !== null })
        return shot
    }
    function sample(button) {
        // The right-side padding avoids text/icons. Capture the containing
        // page or popup so clipping/stale rendering cannot pass as hover.
        const root = sceneRoot()
        const point = button.mapToItem(root, button.width - 9, button.height / 2)
        const shot = capture()
        sampledImage.source = shot.url
        tryCompare(sampledImage, "status", Image.Ready)
        tryCompare(pixelReader, "available", true)
        const context = pixelReader.getContext("2d")
        context.clearRect(0, 0, 1, 1)
        context.drawImage(sampledImage, Math.floor(point.x * sampledImage.sourceSize.width / root.width),
                          Math.floor(point.y * sampledImage.sourceSize.height / root.height), 1, 1, 0, 0, 1, 1)
        const pixel = context.getImageData(0, 0, 1, 1).data
        sampledImage.source = ""
        return Qt.rgba(pixel[0] / 255, pixel[1] / 255, pixel[2] / 255, pixel[3] / 255)
    }
    function exercise(button, screenshotTag) {
        verify(button && button.visible && button.enabled)
        verify(button.hoverEnabled)
        main.contentItem.forceActiveFocus(Qt.OtherFocusReason)
        away(); tryCompare(button, "hovered", false)
        const idleBorder = button.background.border.color
        const idleWidth = button.background.border.width
        const idle = sample(button)
        for (const afterTouch of [false, true]) {
            if (afterTouch) {
                const point = neutralPoint()
                const touch = touchEvent(main.contentItem)
                touch.press(0, main.contentItem, point.x, point.y).commit()
                touch.release(0, main.contentItem, point.x, point.y).commit()
            }
            // Cover the icon/label and padding, including enter/leave/re-enter.
            for (const x of [9, button.width / 2, button.width - 9]) {
                mouseMove(button, x, button.height / 2)
                tryCompare(button, "hovered", true)
                compare(button.background.color, main.hoverColor)
                verify(!button.activeFocus, "Hover alone must not focus a control")
                compare(button.background.border.color, idleBorder, "Hover must not add a red border")
                compare(button.background.border.width, idleWidth)
            }
            const hovered = sample(button)
            if (screenshotTag && !afterTouch)
                verify(capture().saveToFile(Qt.resolvedUrl("../../target/hover-" + screenshotTag + ".png")))
            fuzzyCompare(hovered, main.hoverColor, 1 / 255, "The tint must actually render")
            verify(hovered !== idle, "Rendered hover and idle states must differ")
            away(); tryCompare(button, "hovered", false)
            fuzzyCompare(sample(button), idle, 1 / 255, "Leaving restores the original pixels")
        }
    }
    function test_all_categories_data() {
        const rows = []
        for (const dark of [true, false])
            for (const name of ["Installed"].concat(stack().get(0).categories.map(c => c.name)))
                for (const selected of [false, true])
                    rows.push({tag: (dark ? "dark-" : "light-") + name + (selected ? "-selected" : ""), dark: dark, name: name, selected: selected})
        return rows
    }
    function test_all_categories(data) {
        theme(data.dark)
        const page = stack().currentItem
        page.openCategory(data.selected ? data.name : data.name === "All Apps" ? "Games" : "All Apps")
        let button
        if (data.name === "Installed") button = findChild(page, "installedButton")
        else {
            const list = findChild(page, "categoryNaturalScroll").scrollTarget
            const index = page.categoryIndex(data.name)
            list.positionViewAtIndex(index, ListView.Center)
            tryVerify(function() { return list.itemAtIndex(index) !== null })
            button = list.itemAtIndex(index)
        }
        waitForPolish(main.contentItem); wait(20)
        exercise(button, data.dark && !data.selected && data.name === "Games" ? "category" : "")
    }
    function test_regular_buttons_data() {
        const rows = []
        for (const dark of [true, false])
            for (const control of ["backButton", "installAppButton", "openAppButton", "uninstallAppButton", "cancelAppButton",
                "downloadsButton", "downloadsBackButton", "clearDownloadHistoryButton", "downloadAppDetailsButton", "cancelDownloadButton", "openDownloadButton",
                "searchClearButton", "searchCategoryFilter", "installedSort", "uninstallButton",
                "previewCloseButton", "previewPreviousButton", "previewNextButton", "previewZoomInButton", "previewZoomOutButton",
                "confirmReviewButton", "rejectReviewButton"])
                rows.push({tag: (dark ? "dark-" : "light-") + control, dark: dark, control: control})
        return rows
    }
    function prepareControl(name) {
        let scope = stack().currentItem
        if (name === "downloadsButton") backend.jobs = [job]
        else if (["downloadsBackButton", "clearDownloadHistoryButton", "downloadAppDetailsButton", "cancelDownloadButton", "openDownloadButton"].indexOf(name) >= 0) {
            backend.installedApps = [app]
            backend.jobs = [Object.assign({}, job, {active: name !== "openDownloadButton" && name !== "clearDownloadHistoryButton"})]
            main.showDownloads(); settle(); scope = stack().currentItem
        } else if (name === "searchClearButton" || name === "searchCategoryFilter") {
            findChild(scope, "searchField").text = "Hover"
            main.searchText = "Hover"
            if (name === "searchCategoryFilter") {
                // This ComboBox has no production objectName.
                waitForPolish(main.contentItem); wait(20)
                return findFilter(scope)
            }
        } else if (name === "installedSort" || name === "uninstallButton") {
            backend.installedApps = [app]
            scope.openCategory("Installed")
        } else if (name === "confirmReviewButton" || name === "rejectReviewButton") {
            backend.review = ({token: 1, title: "Uninstall Hover test?", removing: true, message: "Test confirmation"})
            scope = findChild(main, "transactionReview")
            tryCompare(scope, "opened", true)
        } else {
            if (name === "openAppButton" || name === "uninstallAppButton") backend.installedApps = [app]
            if (name === "cancelAppButton") backend.jobs = [job]
            main.openApp(app); settle(); scope = stack().currentItem
            if (name.indexOf("preview") === 0) {
                scope.openScreenshot(1)
                scope.setPreviewZoom(2)
                scope = scope.screenshotPreviewDialog
                tryCompare(scope, "opened", true)
            }
        }
        waitForPolish(main.contentItem); wait(20)
        const control = findChild(scope, name)
        verify(control !== null, name + " must exist")
        return control
    }
    function findFilter(item) {
        if (typeof item.displayText === "string" && item.displayText.indexOf("Category:") === 0) return item
        for (const child of (item.children || [])) {
            const result = findFilter(child)
            if (result) return result
        }
        return null
    }
    function test_regular_buttons(data) {
        theme(data.dark)
        const button = prepareControl(data.control)
        exercise(button, data.dark && ["backButton", "installAppButton"].indexOf(data.control) >= 0 ? data.control : "")
    }
    function test_disabled_does_not_highlight() {
        theme(true)
        const button = prepareControl("clearDownloadHistoryButton")
        backend.jobs = [job]
        verify(!button.enabled)
        away()
        const idle = sample(button)
        mouseMove(button)
        fuzzyCompare(sample(button), idle, 1 / 255)
    }
    function test_shared_tint_is_visible_data() {
        return [{tag: "dark", dark: true}, {tag: "light", dark: false}]
    }
    function test_shared_tint_is_visible(data) {
        theme(data.dark)
        const difference = Math.max(Math.abs(main.hoverColor.r - main.surfaceColor.r),
                                    Math.abs(main.hoverColor.g - main.surfaceColor.g),
                                    Math.abs(main.hoverColor.b - main.surfaceColor.b))
        verify(difference >= 0.06, "Keep a perceptible tint on raised buttons, not only transparent navigation")
    }
    function test_keyboard_focus_outline_survives_hover() {
        theme(true)
        const button = prepareControl("backButton")
        away()
        button.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(button, "activeFocus", true)
        compare(button.background.border.color, main.accentColor)
        compare(button.background.border.width, 2)
        mouseMove(button)
        tryCompare(button, "hovered", true)
        compare(button.background.color, main.hoverColor)
        away()
        compare(button.background.border.color, main.accentColor)
        compare(button.background.border.width, 2)
    }
}
