// VM-only UI check. Opens an existing app's removal prompt, NEVER accepts it,
// then checks its website link. No application or app data is removed.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1240; height: 820
    property string testId: "com.anydesk.Anydesk"
    property string scope: "user"
    property bool reviewOnAppPage: true
    property bool skipReview: false
    property bool useCatalog: false
    property string phase: "start"
    property var testApp: null
    property bool failed: false
    property double readyAt: 0
    function find(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const child of (item.children || [])) {
            const result = find(child, name)
            if (result) return result
        }
        return null
    }
    function check(condition, message) {
        if (condition) return true
        failed = true
        backend.cancelAll()
        console.error("REVIEW_LAYOUT_FAIL: " + message)
        Qt.exit(1)
        return false
    }
    Timer {
        interval: 30; repeat: true; running: !main.failed && main.phase !== "done"
        onTriggered: {
            if (main.installedLoading) return
            const stack = main.find(main.contentItem, "navigationStack")
            if (stack.busy) return
            if (main.phase === "start") {
                if (!main.check(!main.useCatalog || main.skipReview, "Catalog-only checks must not request removal")) return
                main.testApp = main.useCatalog ? main.catalog.find(app => String(app.id).replace(/\.desktop$/, "") === main.testId)
                    : main.installedApps.find(app => String(app.id).replace(/\.desktop$/, "") === main.testId && app.installation === main.scope)
                if (!main.check(!!main.testApp, "Expected installed app missing: " + JSON.stringify(main.installedApps) + " " + main.installedError)) return
                main.selectedCategory = "Installed"
                if (main.reviewOnAppPage || main.skipReview) main.openApp(main.testApp)
                main.phase = main.skipReview ? "website" : "openReview"
            } else if (main.phase === "openReview") {
                main.backend.uninstallApp(main.testApp)
                main.phase = "review"
            } else if (main.phase === "review" && main.backend.review.removing) {
                const review = main.backend.review
                if (!main.check(review.title === "Uninstall " + main.testApp.name + "?", "Wrong short title")) return
                const expected = main.scope === "user"
                    ? "If you proceed, " + main.testApp.name + " and its app data will be removed."
                    : "If you proceed, " + main.testApp.name + " will be removed for all users, and its app data for this account will be deleted."
                if (!main.check(review.message === expected, "Wrong explanatory paragraph")) return
                const job = main.jobForApp(main.testApp)
                if (!main.check(job && job.removalConfirmed === false, "Uninstall already confirmed")) return
                if (main.reviewOnAppPage) {
                    if (!main.check(!main.find(stack.currentItem, "appInstallProgress").visible
                                    && !main.find(stack.currentItem, "cancelAppButton").visible
                                    && main.find(stack.currentItem, "appJobStatus").text === "Waiting for confirmation",
                                    "Waiting state shows progress or Cancel")) return
                }
                console.info("REVIEW_LAYOUT_READY: " + review.title + " " + review.message)
                main.readyAt = Date.now()
                main.phase = "captureReview"
            } else if (main.phase === "captureReview" && Date.now() - main.readyAt > 30000) {
                // Deliberate pause for a real desktop screenshot. Always No.
                main.backend.answerReview(main.backend.review.token, false)
                main.phase = "declined"
            } else if (main.phase === "declined" && !main.backend.busy) {
                if (!main.check(!!main.findInstalled(main.testApp), "Declining changed the installed app")) return
                main.openApp(main.testApp)
                main.phase = "website"
            } else if (main.phase === "website") {
                const link = main.find(stack.currentItem, "appWebsiteLink")
                if (!main.check(!!link && link.visible, "Website missing")) return
                if (main.testApp.installedAt) {
                    const date = main.find(stack.currentItem, "appInstalledDateValue")
                    if (!main.check(!!date && date.visible && date.text === main.testApp.installedDate
                                    && date.text.includes(":"), "Installed date/time missing")) return
                    console.info("INSTALL_DATE_DISPLAY: " + date.text)
                } else {
                    if (!main.check(!main.find(stack.currentItem, "appInstalledDateValue").visible,
                                    "Unrecorded installation date must stay hidden")) return
                }
                const category = main.find(stack.currentItem, "appCategoryValue")
                const caption = main.find(stack.currentItem, "appWebsiteCaption")
                if (!main.check(Math.abs(link.width - link.contentItem.implicitWidth) < 1
                                && link.padding === 0 && link.background === null
                                && link.width < link.parent.width
                                && link.mapToItem(stack.currentItem, 0, 0).x === category.mapToItem(stack.currentItem, 0, 0).x
                                && Math.abs(link.contentItem.mapToItem(stack.currentItem, 0, link.contentItem.baselineOffset).y
                                            - caption.mapToItem(stack.currentItem, 0, caption.baselineOffset).y) < 1,
                                "Website must be plain text aligned with its caption and the other values")) return
                const scroll = main.find(stack.currentItem, "detailsFlickable")
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
                link.forceActiveFocus(Qt.TabFocusReason)
                if (!main.check(link.contentItem.font.underline && link.background === null,
                                "Keyboard focus must underline the link, not draw a box")) return
                console.info("REVIEW_LAYOUT_ALL_PASS: " + (main.skipReview ? "read-only app details" : "removal declined")
                             + "; focused website width=" + link.width + ", column=" + link.parent.width)
                main.phase = "done" // Remain visible for the website screenshot.
            }
        }
    }
    Timer { interval: 60000; running: main.phase !== "done"; onTriggered: main.check(false, "Timeout at " + main.phase) }
}
