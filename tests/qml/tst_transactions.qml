import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Transactions"
    when: main.visible
    QtObject {
        id: backend
        property var jobs: []
        property var review: ({})
        property var installedApps: []
        property bool installedLoading: false
        property string installedError: ""
        property int iconRevision: 0
        property bool busy: false
        property var installSizes: ({})
        property string sizeRequested: ""
        property int sizeRequestCount: 0
        function requestInstallInfo(app) { sizeRequested = app.id; ++sizeRequestCount }
        property string requested: ""
        property int acceptedToken: 0
        signal appOpened(var app)
        signal inputError(string message)
        function installApp(app) { requested = "install:" + app.id }
        function uninstallApp(app) { requested = "uninstall:" + app.id }
        function launchApp(app) { requested = "open:" + app.id }
        function answerReview(token, accept) { acceptedToken = accept ? token : -token; review = ({}) }
        function cancelJob(index) { requested = "cancel:" + index }
    }
    AppCenter.Main { id: main; backend: backend; visible: true }
    function initTestCase() {
        main.requestActivate()
        waitForRendering(main.contentItem)
        wait(250) // Let startup search focus and the first layout settle.
    }
    function init() {
        main.requestActivate()
        waitForRendering(main.contentItem)
    }
    function captureTouchLayout(page, name) {
        let captured = false
        page.grabToImage(function(result) {
            captured = result.saveToFile(Qt.resolvedUrl("../../target/touch-" + name + ".png").toString().replace("file://", ""))
        })
        tryVerify(function() { return captured })
    }
    function verifyMirroredHeroInsets(page) {
        const card = findChild(page, "appHeroCard")
        const icon = findChild(page, "appHeroIcon")
        const buttons = findChild(page, "appActionButtons")
        const leftInset = icon.mapToItem(card, 0, 0).x
        const rightInset = card.width - buttons.mapToItem(card, buttons.width, 0).x
        compare(leftInset, 26)
        verify(Math.abs(leftInset - rightInset) < 1,
               "The action stack's right inset must mirror the icon's left inset")
    }
    function test_simple_uninstall_confirmation_data() {
        return [{tag: "user", message: "If you proceed, Calculator and its app data will be removed."},
                {tag: "system", message: "If you proceed, Calculator will be removed for all users, and its app data for this account will be deleted."}]
    }
    function test_local_source_note_data() {
        return [{tag: "dark", background: "#202326", foreground: "white", width: 1180},
                {tag: "light-narrow", background: "#eff0f1", foreground: "#202326", width: 720}]
    }
    function test_local_source_note(data) {
        const previousWindow = main.palette.window
        const previousText = main.palette.windowText
        main.palette.window = data.background; main.palette.windowText = data.foreground
        main.width = data.width
        const app = {id: "org.example.Local", name: "Local file", summary: "Preview", description: "About the app",
            icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "",
            localSource: "file:///tmp/example.flatpakref", sourceUrl: "https://storage.googleapis.com/pieces-flatpak-repo"}
        try {
            main.openApp(app)
            const stack = findChild(main, "navigationStack")
            tryCompare(stack, "busy", false)
            const page = stack.currentItem
            waitForPolish(page)
            const note = findChild(page, "localSourceNote")
            const label = findChild(page, "localSourceNoteText")
            const hero = findChild(page, "appHeroCard")
            const about = findChild(page, "appAboutCard")
            verify(note.visible)
            verify(label.text.includes(app.sourceUrl) && label.text.includes("receive updates"))
            compare(label.textFormat, Text.PlainText)
            compare(label.color, main.textColor)
            verify(note.y >= hero.y + hero.height, "The note belongs below the main app section")
            verify(about.y >= note.y + note.height, "The note belongs above About this app")
            verify(label.height >= label.implicitHeight, "The source note must wrap without clipping")
            main.openApp(Object.assign({}, app, {localSource: ""}))
            tryCompare(stack, "busy", false)
            verify(!findChild(stack.currentItem, "localSourceNote").visible, "Regular catalog apps need no file-source note")
        } finally {
            main.showCatalog(); tryCompare(findChild(main, "navigationStack"), "busy", false)
            main.width = 1180
            main.palette.window = previousWindow; main.palette.windowText = previousText
        }
    }
    function test_version_stack_data() {
        return [{tag: "with-version", version: "0.28.0", total: "1.77 GiB", width: 1180},
                {tag: "dependencies", version: "1.0", total: "2.35 GiB", width: 1180},
                {tag: "compact-wide", version: "1.0", total: "2.35 GiB", width: 980},
                {tag: "narrow", version: "2026.09.17", total: "2.35 GiB", width: 720},
                {tag: "unknown", version: "", total: "1.77 GiB", width: 1180}]
    }
    function test_version_stack(data) {
        main.width = data.width
        const app = {id: "org.example.Version", name: "Version test", version: data.version, summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "Developer"}
        backend.installSizes = {[app.id]: {state: "ready", appSize: "1.77 GiB", totalSize: data.total}}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const size = findChild(page, "appDownloadSize")
        const version = findChild(page, "appAvailableVersion")
        compare(size.text, "1.77 GiB")
        compare(version.text, data.version)
        compare(version.visible, data.version.length > 0)
        waitForRendering(page)
        if (version.visible) {
            const position = version.mapToItem(page, version.width, 0)
            verify(position.x <= page.width - 24, "Version must fit the page")
            verify(version.mapToItem(page, 0, 0).y > size.mapToItem(page, 0, 0).y)
        }
        const info = findChild(page, "appHeroText")
        const details = findChild(page, "installSizeDetails")
        const buttons = findChild(page, "appActionButtons")
        verify(details.mapToItem(page, 0, 0).y >= info.mapToItem(page, 0, info.height).y,
               "Size and version belong beneath the developer")
        compare(details.mapToItem(page, 0, 0).x, info.mapToItem(page, 0, 0).x)
        if (data.width >= 980) {
            verify(buttons.mapToItem(page, 0, 0).x >= info.mapToItem(page, info.width, 0).x,
                   "Actions belong to the right of the information")
            verifyMirroredHeroInsets(page)
        } else
            verify(buttons.mapToItem(page, 0, 0).y >= details.mapToItem(page, 0, details.height).y,
                   "Narrow windows put actions below the information")
        const install = findChild(page, "installAppButton")
        verify(install.width >= 176 && install.height >= 56, "Install must be touch-friendly")
        verify(install.width <= 200, "Actions must not stretch across the entire empty column")
        backend.jobs = [{id: app.id, index: 0, active: true, progress: 0.25, status: "Downloading", operations: [{name: app.id}]}]
        waitForRendering(page)
        const bar = findChild(page, "overallInstallProgress")
        verify(bar.visible)
        verify(bar.mapToItem(page, bar.width, 0).x >= buttons.mapToItem(page, buttons.width, 0).x - 1,
               "Progress must extend beneath the right-side buttons too")
        verify(bar.mapToItem(page, 0, 0).y >= buttons.mapToItem(page, 0, buttons.height).y)
        if (data.width >= 980) {
            verifyMirroredHeroInsets(page)
            verify(Math.abs(bar.mapToItem(page, bar.width, 0).x - buttons.mapToItem(page, buttons.width, 0).x) < 1,
                   "Actions and progress should share the same right edge")
        }
        const cancel = findChild(page, "cancelAppButton")
        verify(cancel.width >= 176 && cancel.height >= 56, "Cancel must be touch-friendly")
        if (data.width === 720) captureTouchLayout(page, "narrow-progress")
        mouseClick(cancel)
        compare(backend.requested, "cancel:0")
        backend.jobs = []
        main.showCatalog(); tryCompare(stack, "busy", false)
        main.width = 1180
        backend.installSizes = ({})
    }
    function test_installed_touch_actions_data() {
        return [{tag: "wide", width: 1180}, {tag: "compact-wide", width: 980}, {tag: "narrow", width: 720}]
    }
    function test_installed_touch_actions(data) {
        main.width = data.width
        const app = {id: "org.example.Touch", name: "Touch test", summary: "An installed app", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "Developer", installation: "user", version: "2.0", installedVersion: "1.0", installedSize: "12.34 MiB"}
        backend.installedApps = [app]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        waitForRendering(page)
        const open = findChild(page, "openAppButton")
        const uninstall = findChild(page, "uninstallAppButton")
        verify(uninstall.icon.source.toString().endsWith("/qml/trash-red.svg"))
        const info = findChild(page, "appHeroText")
        verify(findChild(page, "installSizeDetails").visible)
        compare(findChild(page, "appDownloadSize").text, "12.34 MiB")
        compare(findChild(page, "appAvailableVersion").text, "1.0")
        verify(findChild(page, "appAvailableVersion").visible)
        verify(!findChild(page, "totalDownloadSize").visible)
        for (const button of [open, uninstall]) {
            verify(button.visible && button.width >= 176 && button.height >= 56)
            const point = button.mapToItem(page, 0, 0)
            verify(point.x >= 0 && point.x + button.width <= page.width - 24, "Buttons must fit the window")
        }
        if (data.width >= 980) {
            verifyMirroredHeroInsets(page)
            verify(open.mapToItem(page, 0, 0).x >= info.mapToItem(page, info.width, 0).x)
            verify(uninstall.mapToItem(page, 0, 0).y >= open.mapToItem(page, 0, open.height).y + 12)
        } else {
            verify(open.mapToItem(page, 0, 0).y >= info.mapToItem(page, 0, info.height).y)
            verify(uninstall.mapToItem(page, 0, 0).x >= open.mapToItem(page, open.width, 0).x + 12)
        }
        if (data.width === 720) captureTouchLayout(page, "narrow-installed")
        mouseClick(open)
        compare(backend.requested, "open:" + app.id)
        mouseClick(uninstall)
        compare(backend.requested, "uninstall:" + app.id)
        backend.installedApps = [Object.assign({}, app, {installedVersion: "", installedSize: ""})]
        verify(findChild(page, "installSizeDetails").visible)
        verify(!findChild(page, "appAvailableVersion").visible,
               "Unknown installed versions must not fall back to the newer catalog release")
        compare(findChild(page, "appDownloadSize").text, "Unavailable")
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installedApps = []
        main.width = 1180
    }
    function test_catalog_page_uses_current_installed_version() {
        const catalogApp = {id: "org.example.InstalledVersion", name: "Installed version test",
            version: "2.0", summary: "", description: "", icon: "", screenshots: [],
            category: "", license: "", homepage: "", developer: ""}
        const installedApp = Object.assign({}, catalogApp,
            {installation: "user", installedVersion: "1.0", installedSize: "10 MiB"})
        backend.installedApps = [installedApp]
        main.openApp(catalogApp)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const version = findChild(page, "appAvailableVersion")
        compare(version.text, "1.0", "Opening from the catalog must show the installed version")
        backend.installedApps = [Object.assign({}, installedApp, {version: "3.0"})]
        compare(version.text, "1.0", "A newer catalog release must not replace the installed version")
        backend.installedApps = [Object.assign({}, installedApp, {installedVersion: "1.1"})]
        compare(stack.currentItem, page)
        compare(version.text, "1.1", "Refreshing installed metadata must update the same page")
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installedApps = []
    }
    function contrastRatio(first, second) {
        function luminance(color) {
            function linear(channel) { return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
        }
        const a = luminance(first), b = luminance(second)
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
    }
    function test_action_style_data() {
        return [{tag: "dark", background: "#202326", foreground: "#ffffff"},
                {tag: "light", background: "#eff0f1", foreground: "#202326"},
                {tag: "custom", background: "#302922", foreground: "#f2e7d9"}]
    }
    function test_action_style(data) {
        const previousBackground = main.palette.window, previousForeground = main.palette.windowText
        main.palette.window = data.background
        main.palette.windowText = data.foreground
        const app = {id: "org.example.Contrast", name: "Contrast test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const install = findChild(page, "installAppButton")
        waitForRendering(page)
        mouseMove(page, 3, 3)
        compare(install.background.color, main.raisedSurfaceColor)
        compare(install.background.radius, main.cornerRadius)
        const label = findChild(install, "appActionLabel")
        compare(label.color, main.textColor)
        verify(contrastRatio(install.background.color, label.color) >= 4.5, "Action text must be readable")
        const arrow = findChild(install, "installDownloadArrow")
        verify(arrow.visible && arrow.width === 24 && arrow.height === 24)
        verify(arrow.color.g > arrow.color.r && arrow.color.g > arrow.color.b, "Install arrow must be green")
        verify(contrastRatio(install.background.color, arrow.color) >= 3, "Green arrow must contrast with the button")
        install.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(install, "activeFocus", true)
        compare(install.background.border.width, 2)
        mousePress(install)
        verify(install.down)
        compare(install.background.color, main.hoverColor)
        verify(contrastRatio(install.background.color, label.color) >= 4.5)
        mouseRelease(install)
        compare(backend.requested, "install:" + app.id)
        verify(contrastRatio(install.background.color, label.color) >= 4.5, "Hover text must remain readable")
        backend.installedLoading = true
        verify(!install.enabled)
        compare(install.contentItem.opacity, 0.45)
        backend.installedLoading = false
        backend.installedApps = [Object.assign({}, app, {installation: "user"})]
        const open = findChild(page, "openAppButton"), uninstall = findChild(page, "uninstallAppButton")
        mouseMove(page, 3, 3)
        compare(findChild(uninstall, "appActionLabel").color, main.textColor)
        compare(open.background.color, main.raisedSurfaceColor)
        compare(uninstall.background.color, main.raisedSurfaceColor)
        compare(uninstall.background.border.color, main.borderColor)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installedApps = []
        main.palette.window = previousBackground
        main.palette.windowText = previousForeground
    }
    function test_simple_uninstall_confirmation(data) {
        const dialog = findChild(main, "transactionReview")
        const plan = {token: 41, title: "Uninstall Calculator?", kind: "transaction", removing: true,
                      message: data.message, operations: [{name: "org.example.Test", ref: "app/org.example.Test/x86_64/stable", action: "uninstall"}]}
        backend.review = plan
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        compare(dialog.title, plan.title)
        const yes = findChild(dialog.footer, "confirmReviewButton")
        const no = findChild(dialog.footer, "rejectReviewButton")
        compare(yes.text, "Yes")
        verify(yes.icon.source.toString().endsWith("trash-red.svg"))
        compare(yes.icon.color, Qt.rgba(0, 0, 0, 0))
        compare(no.text, "No")
        compare(no.icon.name, "dialog-cancel")
        verify(no.activeFocus)
        verify(no.visualFocus)
        verify(dialog.contentItem.visible)
        const message = findChild(dialog.contentItem, "reviewMessage")
        compare(message.text, data.message)
        compare(message.textFormat, Text.PlainText)
        verify(message.visible && message.height >= message.implicitHeight)
        verify(!message.text.includes("your"))
        compare(findChild(dialog.contentItem, "reviewOperations").count, 0)
        verify(dialog.width <= 480 && dialog.height < 260, "Removal prompt must stay compact")
        const messagePosition = message.mapToItem(dialog.contentItem, 0, 0)
        verify(messagePosition.y + message.height <= dialog.contentItem.height, "Paragraph must fit above the buttons")
        const point = no.mapToItem(dialog.footer, 0, 0)
        verify(point.x >= 0 && point.x + no.width <= dialog.footer.width)
        verify(point.y >= 0 && point.y + no.height <= dialog.footer.height)
        mousePress(no)
        verify(no.down, "No button must receive pointer input")
        mouseRelease(no)
        compare(backend.acceptedToken, -41)
        tryCompare(dialog, "visible", false)
        backend.review = Object.assign({}, plan, {token: 42})
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        keyClick(Qt.Key_Escape)
        compare(backend.acceptedToken, -42)
        tryCompare(dialog, "visible", false)
        backend.review = Object.assign({}, plan, {token: 43})
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        mouseClick(yes)
        compare(backend.acceptedToken, 43)
        tryCompare(dialog, "visible", false)
        // Source trust is a different confirmation: keep its information.
        backend.review = {token: 44, title: "Add source?", kind: "remote", message: "Source URL and trust details"}
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        verify(dialog.contentItem.visible)
        compare(yes.text, "Trust and add source")
        compare(no.text, "Cancel")
        mouseClick(no)
        compare(backend.acceptedToken, -44)
        tryCompare(dialog, "visible", false)
    }
    function test_inline_sizes_and_website_alignment() {
        const app = {id: "org.example.Size", name: "Size test", summary: "", description: "", icon: "", screenshots: [], category: "Games", license: "MIT", homepage: "https://example.org/", developer: ""}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        compare(backend.sizeRequested, app.id)
        const page = stack.currentItem
        const appSize = findChild(page, "appDownloadSize")
        const totalSize = findChild(page, "totalDownloadSize")
        compare(appSize.text, "Unavailable")
        backend.installSizes = {"org.example.Size": {state: "ready", appSize: "2 MiB", totalSize: "3 MiB"}}
        compare(appSize.text, "2 MiB")
        compare(totalSize.text, "3 MiB")
        const totalCaption = findChild(page, "totalDownloadSizeLabel")
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 2097152, totalBytes: 2097152, appSize: "2 MiB", totalSize: "2 MiB"}}
        verify(appSize.visible)
        verify(!totalSize.visible && !totalCaption.visible)
        // Compare the displayed text, not byte-level differences hidden by rounding.
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 2097152, totalBytes: 2097153, appSize: "2 MiB", totalSize: "2 MiB"}}
        verify(!totalSize.visible && !totalCaption.visible)
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 1900000000, totalBytes: 1900010000, appSize: "1.77 GiB", totalSize: "1.77 GiB"}}
        verify(!totalSize.visible && !totalCaption.visible)
        backend.installSizes = {"org.example.Size": {state: "ready", appSize: "1.77 GiB", totalSize: "1.78 GiB"}}
        verify(totalSize.visible && totalCaption.visible)
        backend.installSizes = {"org.example.Size": {state: "ready", appBytes: 0, totalBytes: 0, appSize: "0 bytes", totalSize: "0 bytes"}}
        verify(!totalSize.visible && !totalCaption.visible)
        verify(appSize.font.bold && totalSize.font.bold)
        compare(appSize.color, main.textColor)
        const website = findChild(page, "appWebsiteLink")
        compare(website.contentItem.horizontalAlignment, Text.AlignLeft)
        compare(website.leftPadding, 0)
        compare(website.rightPadding, 0)
        compare(website.topPadding, 0)
        compare(website.bottomPadding, 0)
        compare(website.background, null)
        compare(website.contentItem.text, app.homepage)
        verify(Math.abs(website.width - website.contentItem.implicitWidth) < 1,
               "Plain website link must fit its text without a button inset")
        const category = findChild(page, "appCategoryValue")
        const caption = findChild(page, "appWebsiteCaption")
        compare(website.mapToItem(page, 0, 0).x, category.mapToItem(page, 0, 0).x)
        verify(Math.abs(website.contentItem.mapToItem(page, 0, website.contentItem.baselineOffset).y
                        - caption.mapToItem(page, 0, caption.baselineOffset).y) < 1, "Website and its caption must share a baseline")
        compare(website.contentItem.font.weight, category.font.weight)
        verify(website.width < website.parent.width / 2)
        backend.installSizes = {"org.example.Size": {state: "unavailable"}}
        verify(totalSize.visible && totalCaption.visible)
        compare(totalSize.text, "Unavailable")
        verify(findChild(page, "installAppButton").enabled)
        backend.installSizes = {"org.example.Size": {state: "partial", appSize: "2 MiB"}}
        compare(appSize.text, "2 MiB")
        compare(totalSize.text, "Unavailable")
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installSizes = ({})
    }
    function test_long_website_fits_narrow_window() {
        const previousWidth = main.width
        main.width = 720
        const app = {id: "org.example.Website", name: "Website test", summary: "", description: "", category: "", license: "", developer: "", icon: "", screenshots: [],
                     homepage: "https://example.org/" + "long-path/".repeat(40)}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const website = findChild(stack.currentItem, "appWebsiteLink")
        verify(website.width > 0 && website.width <= website.parent.width)
        verify(website.width < website.contentItem.implicitWidth)
        const point = website.mapToItem(stack.currentItem, 0, 0)
        verify(point.x + website.width <= stack.currentItem.width)
        website.forceActiveFocus()
        verify(website.activeFocus)
        main.showCatalog(); tryCompare(stack, "busy", false)
        main.width = previousWidth
    }
    Component { id: linkFixture; AppCenter.WebsiteLink { x: 20; y: 20; text: "https://example.org/?a=1&b=2" } }
    Component { id: linkSpy; SignalSpy { signalName: "activated" } }
    function test_plain_website_link_activation_and_focus() {
        const link = createTemporaryObject(linkFixture, main.contentItem)
        const spy = createTemporaryObject(linkSpy, main, {target: link})
        verify(spy.valid)
        waitForRendering(link)
        mouseMove(main.contentItem, main.width - 20, 20)
        link.focus = false
        compare(link.background, null)
        verify(!link.contentItem.font.underline)
        mouseMove(link, link.width / 2, link.height / 2)
        tryCompare(link, "hovered", true)
        verify(link.contentItem.font.underline)
        mouseClick(link)
        compare(spy.count, 1)
        compare(spy.signalArguments[0][0], link.text)
        mouseMove(main.contentItem, main.width - 20, 20)
        main.contentItem.forceActiveFocus(Qt.OtherFocusReason)
        link.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(link, "visualFocus", true)
        verify(link.contentItem.font.underline)
        compare(link.background, null) // Keyboard focus must not bring back a box.
        keyClick(Qt.Key_Return)
        compare(spy.count, 2)
        keyClick(Qt.Key_Enter)
        compare(spy.count, 3)
        keyClick(Qt.Key_Space)
        compare(spy.count, 4)
        compare(link.Accessible.role, Accessible.Link)
        compare(link.contentItem.textFormat, Text.PlainText)
    }
    function test_installed_app_tracks_size_target_data() {
        return [{tag: "fresh-session", priorApp: false}, {tag: "different-app-viewed-first", priorApp: true}]
    }
    function test_installed_app_tracks_size_target(data) {
        const app = {id: "org.example.Installed", name: "Installed test", summary: "", description: "", icon: "", screenshots: [], category: "Games", license: "", homepage: "", developer: "",
                     installation: "user", installedBranch: "stable", installedArch: "x86_64", installedSize: "10 MiB", installedVersion: "1.0", version: "2.0"}
        const stack = findChild(main, "navigationStack")
        backend.installSizes = ({})
        backend.sizeRequested = ""
        backend.installedApps = [app]
        if (data.priorApp) {
            main.openApp(Object.assign({}, app, {id: "org.example.Prior"}))
            tryCompare(stack, "busy", false)
            compare(backend.sizeRequested, "org.example.Prior")
        }
        const before = backend.sizeRequestCount
        main.openApp(app)
        tryCompare(stack, "busy", false)
        compare(backend.sizeRequested, app.id)
        compare(backend.sizeRequestCount, before + 1)
        const page = stack.currentItem
        verify(findChild(page, "installSizeDetails").visible)
        compare(findChild(page, "appDownloadSize").text, "10 MiB")
        compare(findChild(page, "appAvailableVersion").text, "1.0")
        verify(!findChild(page, "totalDownloadSize").visible)
        // The manager refreshes the tracked app's sizes before it publishes
        // the new installed list. The same page must reveal those fresh values.
        backend.installSizes = {"org.example.Installed": {state: "ready", appSize: "2 MiB", totalSize: "2 MiB"}}
        backend.installedApps = []
        compare(stack.currentItem, page)
        verify(findChild(page, "appDownloadSize").visible)
        compare(findChild(page, "appDownloadSize").text, "2 MiB")
        compare(findChild(page, "appAvailableVersion").text, "2.0")
        verify(!findChild(page, "totalDownloadSize").visible)
        verify(findChild(page, "installAppButton").visible)
        // Icon/list notifications must not introduce additional size reads.
        ++backend.iconRevision
        backend.installedApps = []
        compare(backend.sizeRequestCount, before + 1)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.installSizes = ({})
    }
    function hasDownloadsText(item) {
        if (item.text === "Queue") return true
        const children = item.children || []
        for (let i = 0; i < children.length; ++i)
            if (hasDownloadsText(children[i])) return true
        return false
    }
    function test_downloads_stays_in_catalog_not_app_view() {
        const app = {id: "org.example.Download", name: "Download test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.5,
                         status: "Downloading", operations: [{name: "org.example.Runtime", progress: 0.5}]}]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        verify(!findChild(page, "downloadsButton"))
        verify(!hasDownloadsText(page))
        verify(findChild(page, "appInstallProgress").visible)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: false, progress: 1, status: "Complete", operations: []}]
        verify(!hasDownloadsText(page))
        verify(!findChild(page, "appJobStatus").visible)
        main.showCatalog()
        tryCompare(stack, "busy", false)
        verify(findChild(stack.currentItem, "downloadsButton").visible)
        backend.jobs = []
    }
    function test_cancelled_job_removed_from_app_and_downloads() {
        const app = {id: "org.example.Cancel", name: "Cancel test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.jobs = [{id: app.id, index: 5, name: app.name, active: true, progress: 0.4, status: "Downloading", operations: []}]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        mouseClick(findChild(page, "cancelAppButton"))
        compare(backend.requested, "cancel:5")
        // The backend removes a completed cancellation from its public list.
        backend.jobs = []
        verify(findChild(page, "installAppButton").visible)
        verify(!findChild(page, "appJobStatus").visible)
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!main.downloadQueue.buttonVisible)
        main.showDownloads(); tryCompare(stack, "busy", false)
        compare(findChild(stack.currentItem, "downloadJobs").count, 0)
        // Other completed/failed operations still remain in session history.
        backend.jobs = [{id: "org.example.Keep", index: 8, name: "Keep", active: false, failed: false, progress: 1, status: "Complete", operations: []}]
        compare(findChild(stack.currentItem, "downloadJobs").count, 1)
        verify(main.downloadQueue.buttonVisible)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
    }
    function test_downloads_title_centered_data() {
        return [{tag: "wide", width: 1180}, {tag: "narrow", width: 720}]
    }
    function test_downloads_title_centered(data) {
        const previousWidth = main.width
        main.width = data.width
        main.showDownloads()
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        waitForRendering(page)
        const title = findChild(page, "downloadsTitle")
        const back = findChild(page, "downloadsBackButton")
        compare(title.text, "Queue")
        compare(title.horizontalAlignment, Text.AlignHCenter)
        fuzzyCompare(title.mapToItem(page, title.width / 2, 0).x, page.width / 2, 1,
                     "Downloads must be centered on the whole page")
        verify(back.mapToItem(page, back.width, 0).x <= title.mapToItem(page, 0, 0).x)
        mouseClick(back)
        tryCompare(stack, "busy", false)
        compare(stack.depth, 1, "Back must still return to the catalog")
        main.width = previousWidth
    }
    function verifyProgressHeader(root) {
        const bar = findChild(root, "overallInstallProgress")
        const bytes = findChild(root, "downloadBytesLabel")
        const percentage = findChild(root, "overallPercentageLabel")
        waitForRendering(root)
        verify(percentage.visible)
        compare(percentage.horizontalAlignment, Text.AlignRight)
        const percentageTop = percentage.mapToItem(bar, 0, 0)
        verify(percentageTop.y + percentage.height <= 0, "Percentage belongs above the bar")
        fuzzyCompare(percentageTop.x + percentage.width, bar.width, 1,
                     "Percentage must align with the bar's right edge")
        if (bytes.visible) {
            const bytesTop = bytes.mapToItem(bar, 0, 0)
            compare(bytes.horizontalAlignment, Text.AlignLeft)
            fuzzyCompare(bytesTop.x, 0, 1, "Download info must align with the bar's left edge")
            fuzzyCompare(bytesTop.y, percentageTop.y, 1, "Both labels belong on the same top row")
            verify(bytesTop.y + bytes.height <= 0, "Wrapped download info must stay above the bar")
            verify(bytesTop.x + bytes.width + 11 <= percentageTop.x,
                   "Download info and percentage must not overlap")
        }
    }
    function test_pending_has_only_status_in_both_views_data() {
        return [{tag: "install-unplanned", action: "install", operations: []},
                {tag: "install-planned", action: "install", operations: [{name: "Runtime"}]},
                {tag: "source-unplanned", action: "source", operations: []},
                {tag: "source-planned", action: "source", operations: [{name: "Runtime"}]}]
    }
    function verifyPendingProgressHidden(root) {
        for (const name of ["overallInstallProgress", "downloadBytesLabel", "overallPercentageLabel"])
            verify(!findChild(root, name).visible, name + " must not appear while queued")
    }
    function test_pending_has_only_status_in_both_views(data) {
        const app = {id: "org.example.Pending", name: "Pending app", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        const queued = {id: app.id, name: app.name, index: 3, active: true, queued: true,
            action: data.action, status: "Queued", operations: data.operations, progress: 0.4,
            hasDownload: true, downloadComplete: false, downloadedSize: "128.00 MiB",
            downloadTotalSize: "512.00 MiB", downloadSpeed: "2.30 MiB/s"}
        const started = Object.assign({}, queued, {queued: false, status: "Preparing…"})
        backend.jobs = [queued]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        let page = stack.currentItem
        verifyPendingProgressHidden(page)
        verify(findChild(page, "appJobStatus").visible)
        compare(findChild(page, "appJobStatus").text, "Pending…")
        verify(findChild(page, "cancelAppButton").visible, "Queued installs remain cancellable")
        backend.jobs = [started]
        verify(findChild(page, "overallInstallProgress").visible, "Progress appears only once work starts")
        backend.jobs = [queued]
        main.showDownloads(); tryCompare(stack, "busy", false)
        page = stack.currentItem
        verifyPendingProgressHidden(page)
        verify(findChild(page, "downloadJobStatus").visible)
        compare(findChild(page, "downloadJobStatus").text, "Pending…")
        mouseClick(findChild(page, "cancelDownloadButton"))
        compare(backend.requested, "cancel:3")
        backend.jobs = [started]
        verify(findChild(page, "overallInstallProgress").visible)
        backend.jobs = [Object.assign({}, started, {active: false, status: "Complete"})]
        verifyPendingProgressHidden(page)
        verify(!findChild(page, "downloadJobStatus").visible)
        backend.jobs = []
        main.showCatalog(); tryCompare(stack, "busy", false)
    }
    function test_unified_download_and_install_progress() {
        const app = {id: "org.example.Stages", name: "Stages", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        const job = {id: app.id, name: app.name, index: 0, active: true, action: "install", progress: 0.5,
            hasDownload: true, downloadProgress: 0.5, installProgress: 0, installCompleted: 0, installTotal: 2,
            downloadedSize: "128.00 MiB", downloadTotalSize: "512.00 MiB", downloadSpeed: "2.30 MiB/s", downloadComplete: false,
            phase: "download", status: "Downloading…", operations: [{name: "Runtime", phase: "download", progress: 0.5, status: "Downloading…", downloadSize: "2 MiB"}]}
        backend.jobs = [job]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const bar = findChild(page, "overallInstallProgress")
        verify(bar.visible && !bar.indeterminate)
        compare(bar.value, 0.5)
        compare(findChild(page, "downloadPhaseProgress"), null)
        compare(findChild(page, "installPhaseProgress"), null)
        compare(findChild(page, "overallPercentageLabel").text, "50%")
        compare(findChild(page, "completedOperationsLabel"), null)
        compare(findChild(page, "downloadBytesLabel").color, main.textColor)
        compare(findChild(page, "overallPercentageLabel").color, main.textColor)
        compare(findChild(page, "downloadBytesLabel").text, "128.00 MiB / 512.00 MiB (2.30 MiB/s)")
        verify(findChild(page, "downloadBytesLabel").visible)
        verify(!findChild(page, "appJobStatus").visible)
        verifyProgressHeader(page)
        const deployment = Object.assign({}, job, {downloadProgress: 1, downloadComplete: true, progress: 0.95, downloadedSize: "128.00 MiB", downloadTotalSize: "128.00 MiB",
            phase: "install", installCompleted: 1, installProgress: 0.5})
        backend.jobs = [deployment]
        compare(bar.value, 0.95)
        verify(bar.activeStep && !bar.indeterminate)
        compare(findChild(page, "overallPercentageLabel").text, "95%")
        compare(findChild(page, "completedOperationsLabel"), null)
        verify(!findChild(page, "downloadBytesLabel").visible)
        verifyProgressHeader(page)
        // A dependency deploying before the next pull must not hide the total.
        backend.jobs = [Object.assign({}, job, {phase: "install", downloadSpeed: "0.00 MiB/s"})]
        verify(findChild(page, "downloadBytesLabel").visible)
        // Download info stays top-left and wraps without displacing the percentage.
        const previousWidth = main.width
        main.width = 720
        waitForRendering(page)
        verifyProgressHeader(page)
        captureTouchLayout(page, "progress-header-narrow")
        main.width = previousWidth
        backend.jobs = [deployment]
        main.showDownloads(); tryCompare(stack, "busy", false)
        let card = findChild(stack.currentItem, "downloadJobProgress")
        verify(card.visible)
        compare(findChild(card, "overallInstallProgress").value, 0.95)
        verify(!findChild(card, "downloadBytesLabel").visible)
        verify(!findChild(stack.currentItem, "downloadJobStatus").visible)
        verifyProgressHeader(card)
        backend.jobs = [Object.assign({}, job, {downloadEstimating: true})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(!findChild(card, "overallInstallProgress").indeterminate)
        compare(findChild(card, "overallPercentageLabel").text, "50%")
        verifyProgressHeader(card)
        captureTouchLayout(stack.currentItem, "downloads-progress-header")
        backend.jobs = [Object.assign({}, job, {hasDownload: false, phase: "install"})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(!findChild(card, "downloadBytesLabel").visible)
        verify(findChild(card, "overallInstallProgress").visible)
        verify(findChild(card, "overallInstallProgress").activeStep)
        compare(findChild(card, "completedOperationsLabel"), null)
        compare(findChild(card, "downloadBytesLabel").color, main.textColor)
        compare(findChild(card, "overallPercentageLabel").color, main.textColor)
        verifyProgressHeader(card)
        // Local bundle with an online dependency must show only network bytes.
        backend.jobs = [Object.assign({}, job, {action: "source"})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(findChild(card, "downloadBytesLabel").visible)
        compare(findChild(card, "downloadBytesLabel").text, "128.00 MiB / 512.00 MiB (2.30 MiB/s)")
        backend.jobs = [Object.assign({}, deployment, {action: "source"})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(!findChild(card, "downloadBytesLabel").visible)
        backend.jobs = [Object.assign({}, job, {active: false, progress: 1, status: "Complete"})]
        card = findChild(stack.currentItem, "downloadJobProgress")
        verify(!card.visible)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
    }
    function test_download_amount_format_data() {
        return [{tag: "mebibytes", received: "128.00 MiB", total: "512.00 MiB", speed: "2.30 MiB/s"},
                {tag: "mixed_units", received: "181.90 MiB", total: "1.77 GiB", speed: "2.11 MiB/s"},
                {tag: "gibibytes", received: "1.20 GiB", total: "1.77 GiB", speed: "0.90 MiB/s"},
                {tag: "localized", received: "181,90 MiB", total: "1,77 GiB", speed: "2,11 MiB/s"}]
    }
    function test_download_amount_format(data) {
        const app = {id: "org.example.Format", name: "Download formatting", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.installSizes = {"org.example.Format": {state: "ready", appSize: data.total, totalSize: data.total}}
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, action: "install", progress: 0.2,
            hasDownload: true, downloadComplete: false, downloadedSize: data.received, downloadTotalSize: data.total,
            downloadSpeed: data.speed, installCompleted: 1, installTotal: 2, phase: "download", operations: [{}]}]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const previousWidth = main.width
        main.width = 720
        waitForRendering(stack.currentItem)
        let label = findChild(stack.currentItem, "downloadBytesLabel")
        const expected = data.received + " / " + data.total + " (" + data.speed + ")"
        compare(label.text, expected)
        compare(findChild(stack.currentItem, "appDownloadSize").text, data.total)
        verify(!findChild(stack.currentItem, "totalDownloadSize").visible)
        compare(findChild(stack.currentItem, "completedOperationsLabel"), null)
        compare(label.color, main.textColor)
        verify(label.visible)
        verifyProgressHeader(stack.currentItem)
        verify(label.contentWidth <= label.width + 1)
        verify(!label.text.includes("·"))
        if (data.tag === "mixed_units") {
            let captured = false
            stack.currentItem.grabToImage(function(result) {
                captured = result.saveToFile(Qt.resolvedUrl("../../target/download-format-proof.png").toString().replace("file://", ""))
            })
            tryVerify(function() { return captured })
        }
        main.showDownloads(); tryCompare(stack, "busy", false)
        label = findChild(stack.currentItem, "downloadBytesLabel")
        compare(label.text, expected)
        main.width = previousWidth
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
    }
    function test_active_sizes_follow_transaction_total() {
        const app = {id: "org.example.ActualSize", name: "Actual sizes", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.installSizes = {"org.example.ActualSize": {state: "ready", appSize: "194.82 MiB", totalSize: "194.93 MiB"}}
        const job = {id: app.id, index: 0, active: true, action: "install", phase: "download", operations: [{}, {}],
            downloadTotalSize: "194.83 MiB", sizeInfo: {state: "ready", appSize: "194.82 MiB", totalSize: "194.83 MiB"}}
        backend.jobs = [job]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        compare(findChild(stack.currentItem, "totalDownloadSize").text, job.downloadTotalSize)
        compare(findChild(stack.currentItem, "appDownloadSize").text, "194.82 MiB")
        backend.jobs = [Object.assign({}, job, {downloadTotalSize: "194.82 MiB",
            sizeInfo: {state: "ready", appSize: "194.82 MiB", totalSize: "194.82 MiB"}})]
        verify(!findChild(stack.currentItem, "totalDownloadSize").visible)
        // Local bundle file sizes stay separate from network dependency bytes.
        backend.jobs = [Object.assign({}, job, {action: "source", sizeInfo: null, downloadTotalSize: "0.11 MiB"})]
        compare(findChild(stack.currentItem, "appDownloadSize").text, "194.82 MiB")
        compare(findChild(stack.currentItem, "totalDownloadSize").text, "194.93 MiB")
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
    }
    function test_progress_foreground_data() {
        return [{tag: "dark", background: "#202426", foreground: "#ffffff"},
                {tag: "light", background: "#ffffff", foreground: "#202426"}]
    }
    function test_progress_foreground(data) {
        const previousBackground = main.palette.window
        const previousForeground = main.palette.windowText
        const previousPlaceholder = main.palette.placeholderText
        main.palette.window = data.background
        main.palette.windowText = data.foreground
        main.palette.placeholderText = data.tag === "dark" ? "#a0a7ad" : "#757575"
        const app = {id: "org.example.Units", name: "Consistent download sizes", summary: "App and transfer totals use the same units", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.installSizes = {"org.example.Units": {state: "ready", appBytes: 1897842165, totalBytes: 1897842165, appSize: "1.77 GiB", totalSize: "1.77 GiB"}}
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, action: "install", progress: 0.1,
            hasDownload: true, downloadComplete: false, downloadedSize: "89.62 MiB", downloadTotalSize: "1.77 GiB",
            downloadSpeed: "0.99 MiB/s", installCompleted: 0, installTotal: 1, phase: "download", operations: [{}]}]
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const bytes = findChild(stack.currentItem, "downloadBytesLabel")
        const percentage = findChild(stack.currentItem, "overallPercentageLabel")
        compare(bytes.color.toString(), data.foreground)
        compare(percentage.color.toString(), data.foreground)
        compare(percentage.text, "10%")
        compare(findChild(stack.currentItem, "completedOperationsLabel"), null)
        compare(findChild(stack.currentItem, "appDownloadSize").text, backend.jobs[0].downloadTotalSize)
        verify(!findChild(stack.currentItem, "totalDownloadSize").visible)
        waitForRendering(stack.currentItem)
        let captured = false
        stack.currentItem.grabToImage(function(result) {
            captured = result.saveToFile(Qt.resolvedUrl("../../target/consistent-progress-" + data.tag + ".png").toString().replace("file://", ""))
        })
        tryVerify(function() { return captured })
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
        main.palette.window = previousBackground
        main.palette.windowText = previousForeground
        main.palette.placeholderText = previousPlaceholder
    }
    function test_removals_only_show_in_installed_and_app_view() {
        const app = {id: "org.example.Remove", name: "Remove test", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "",
                     installedSize: "10 MB", installedVersion: "1.0", installation: "user", installedBranch: "stable", installedArch: "x86_64"}
        const removal = {id: app.id, index: 4, action: "uninstall", name: app.name, active: true, removalConfirmed: true, progress: 0.3, status: "Removing…", operations: [{name: app.id, progress: 0.3}]}
        const download = {id: "org.example.Download", index: 7, action: "install", name: "Download", active: true, progress: 0.5, status: "Downloading", operations: []}
        backend.installedApps = [app]
        backend.jobs = [removal]
        main.showCatalog()
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        main.selectedCategory = "Installed"
        const list = findChild(stack.currentItem, "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const row = list.itemAtIndex(0)
        verify(findChild(row, "installedRemovalProgress").visible)
        compare(findChild(row, "installedRemovalProgress").value, 0.3)
        compare(findChild(row, "installedRemovalStatus").text, "Uninstalling…")
        verify(!findChild(row, "uninstallButton").enabled)
        verify(!main.downloadQueue.buttonVisible)
        compare(main.downloadQueue.activeCount, 0)
        backend.jobs = [removal, download]
        compare(main.downloadQueue.jobs.length, 1)
        compare(main.downloadQueue.activeCount, 1)
        compare(main.downloadQueue.progress, 0.5)
        main.openApp(app); tryCompare(stack, "busy", false)
        verify(findChild(stack.currentItem, "appInstallProgress").visible)
        compare(findChild(stack.currentItem, "appJobStatus").text, "Uninstalling…")
        backend.jobs = [Object.assign({}, removal, {active: false, failed: true, status: "Failed", error: "Removal failed"}), download]
        verify(findChild(stack.currentItem, "appJobStatus").visible)
        verify(!main.downloadQueue.hasError) // Removal errors stay with the app.
        backend.jobs = [Object.assign({}, removal, {active: false, failed: false, status: "Complete"}), download]
        verify(!findChild(stack.currentItem, "appJobStatus").visible)
        main.showDownloads(); tryCompare(stack, "busy", false)
        compare(findChild(stack.currentItem, "downloadJobs").count, 1)
        // A cancelled download must not create a badge alongside a removal.
        backend.jobs = [removal, Object.assign({}, download, {active: false, cancelled: true, status: "Cancelled"})]
        compare(findChild(stack.currentItem, "downloadJobs").count, 0)
        verify(!main.downloadQueue.buttonVisible)
        main.showCatalog(); tryCompare(stack, "busy", false)
        backend.jobs = []
        backend.installedApps = []
        main.selectedCategory = "All Apps"
    }
    function test_external_flatpak_opens_app_view_without_catalog_picker() {
        const app = {id: "org.example.External", name: "External app", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        backend.appOpened(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        compare(stack.currentItem.app.id, app.id)
        verify(findChild(stack.currentItem, "installAppButton").visible)
        compare(typeof main.openFlatpak, "undefined")
        main.showCatalog()
        tryCompare(stack, "busy", false)
    }
    function test_removal_progress_waits_for_yes_data() {
        return [{tag: "queued", status: "Queued", operations: []},
                {tag: "preparing", status: "Preparing…", operations: []},
                {tag: "review", status: "Waiting for confirmation", operations: [{name: "App", progress: 0}]}]
    }
    function test_removal_progress_waits_for_yes(data) {
        const app = {id: "org.example.Confirmation", name: "Confirmation", summary: "", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: "",
            installedSize: "10 MB", installedVersion: "1.0", installation: "user", installedBranch: "stable", installedArch: "x86_64"}
        const removal = {id: app.id, index: 0, action: "uninstall", name: app.name, active: true,
            removalConfirmed: false, progress: 0, status: data.status, operations: data.operations}
        backend.installedApps = [app]
        backend.jobs = [removal]
        main.showCatalog()
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        main.selectedCategory = "Installed"
        const list = findChild(stack.currentItem, "installedList")
        tryVerify(function() { return list.itemAtIndex(0) !== null })
        const row = list.itemAtIndex(0)
        verify(!findChild(row, "installedRemovalProgress").visible)
        compare(findChild(row, "installedRemovalStatus").text, "Waiting for confirmation")
        main.openApp(app); tryCompare(stack, "busy", false)
        const page = stack.currentItem
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!findChild(page, "cancelAppButton").visible)
        compare(findChild(page, "appJobStatus").text, "Waiting for confirmation")
        // No must not briefly display the bar while its worker exits.
        backend.jobs = [Object.assign({}, removal, {status: "Cancelling…"})]
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!findChild(page, "cancelAppButton").visible)
        backend.jobs = []
        verify(findChild(page, "uninstallAppButton").visible)
        verify(!findChild(page, "appJobStatus").visible)
        // Confirming a queued removal shows Pending, not a running animation.
        backend.jobs = [Object.assign({}, removal, {removalConfirmed: true, queued: true, status: "Pending…"})]
        verify(!findChild(page, "appInstallProgress").visible)
        verify(!findChild(page, "cancelAppButton").visible)
        compare(findChild(page, "appJobStatus").text, "Pending…")
        main.showCatalog(); tryCompare(stack, "busy", false)
        compare(findChild(row, "installedRemovalStatus").text, "Pending…")
        verify(!findChild(row, "installedRemovalProgress").visible)
        main.openApp(app); tryCompare(stack, "busy", false)
        const runningPage = stack.currentItem
        // A finished sub-step must not claim the whole removal is complete.
        backend.jobs = [Object.assign({}, removal, {removalConfirmed: true, queued: false, status: "Complete", progress: 0.99})]
        verify(findChild(runningPage, "appInstallProgress").visible)
        verify(!findChild(runningPage, "cancelAppButton").visible)
        compare(findChild(runningPage, "appJobStatus").text, "Uninstalling…")
        main.showCatalog(); tryCompare(stack, "busy", false)
        verify(findChild(row, "installedRemovalProgress").visible)
        verify(findChild(row, "installedRemovalProgress").indeterminate)
        compare(findChild(row, "installedRemovalStatus").text, "Uninstalling…")
        backend.jobs = []
        backend.installedApps = []
        main.selectedCategory = "All Apps"
    }
    function test_app_actions_review_progress_and_installed_refresh() {
        const app = {id: "org.example.Test", name: "Test", summary: "A test", description: "", icon: "", screenshots: [], category: "", license: "", homepage: "", developer: ""}
        main.openApp(app)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const page = stack.currentItem
        const install = findChild(page, "installAppButton")
        verify(install.visible)
        mouseClick(install)
        compare(backend.requested, "install:org.example.Test")
        verify(!findChild(main, "transactionReview").visible)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.35,
                         downloadProgress: 0.35, installProgress: 0, installTotal: 1, installCompleted: 0,
                         status: "Downloading", operations: [{name: "org.example.Runtime", progress: 0.35}]}]
        verify(findChild(page, "appInstallProgress").visible)
        compare(findChild(page, "overallInstallProgress").value, 0.35)
        verify(findChild(page, "overallPercentageLabel").visible)
        compare(findChild(page, "overallPercentageLabel").text, "35%")
        verify(!findChild(page, "appJobStatus").visible)
        verify(!install.visible)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.99,
                         downloadProgress: 1, installProgress: 0, phase: "install", installTotal: 1, installCompleted: 0,
                         status: "Installing…", operations: [{name: app.id, progress: 1}]}]
        verify(!findChild(page, "appJobStatus").visible)
        compare(findChild(page, "overallInstallProgress").value, 0.99)
        compare(findChild(page, "completedOperationsLabel"), null)
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: true, progress: 0.4,
                         status: "Downloading… 1.50 MiB received", operations: [{name: app.id, progress: 0.4}]}]
        verify(!findChild(page, "appJobStatus").visible)
        backend.jobs = [Object.assign({}, backend.jobs[0], {cancelling: true, status: "Cancelling…"})]
        verify(findChild(page, "appJobStatus").visible)
        compare(findChild(page, "appJobStatus").text, "Cancelling…")
        backend.jobs = [{id: app.id, name: app.name, index: 0, active: false, failed: true,
                         progress: 0.35, status: "Failed", error: "Connection lost", operations: []}]
        verify(findChild(page, "appJobStatus").visible)
        verify(findChild(page, "appJobStatus").text.indexOf("Connection lost") !== -1)
        backend.review = {token: 7, title: "Uninstall", kind: "transaction", removing: true, message: "Remove app and data",
                          operations: [], downloadSize: "10 MB"}
        const dialog = findChild(main, "transactionReview")
        tryCompare(dialog, "visible", true)
        tryCompare(dialog, "opened", true)
        waitForRendering(dialog.footer)
        mouseClick(findChild(dialog.footer, "confirmReviewButton"))
        compare(backend.acceptedToken, 7)
        tryCompare(dialog, "visible", false)
        wait(250) // Allow the modal dimmer's close transition to finish.
        backend.installedApps = [Object.assign({}, app, {installation: "user", installedSize: "20 MB", installedVersion: "1.2", installedBranch: "stable", installedArch: "x86_64"})]
        backend.jobs = [{id: app.id, index: 0, name: app.name, active: false, progress: 1, status: "Complete", operations: []}]
        verify(!install.visible)
        verify(!findChild(page, "appJobStatus").visible)
        verify(!findChild(page, "appInstallProgress").visible)
        compare(main.downloadQueue.jobs.length, 1)
        verify(!findChild(page, "overallPercentageLabel").visible)
        verify(findChild(page, "openAppButton").visible)
        verify(findChild(page, "installSizeDetails").visible)
        compare(findChild(page, "appDownloadSize").text, "20 MB")
        compare(findChild(page, "appAvailableVersion").text, "1.2")
        verify(!findChild(page, "totalDownloadSize").visible)
        compare(main.downloadQueue.jobs[0].status, "Complete")
        const uninstall = findChild(page, "uninstallAppButton")
        verify(uninstall.visible)
        waitForRendering(page)
        mouseClick(uninstall)
        compare(backend.requested, "uninstall:org.example.Test")
        backend.installedApps = []
        verify(install.visible)
        verify(!uninstall.visible)
        compare(main.detailsFor(app).installedSize, undefined)
    }
}
