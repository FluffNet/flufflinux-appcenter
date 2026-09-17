// VM-only UI check. Opens an existing app's removal prompt, NEVER accepts it,
// then checks its website link. No application or app data is removed.
import QtQuick
import "../../qml" as AppCenter

AppCenter.Main {
    id: main
    width: 1240; height: 820
    property string testId: "com.anydesk.Anydesk"
    property string scope: "user"
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
                main.testApp = main.installedApps.find(app => String(app.id).replace(/\.desktop$/, "") === main.testId && app.installation === main.scope)
                if (!main.check(!!main.testApp, "Expected installed app missing: " + JSON.stringify(main.installedApps) + " " + main.installedError)) return
                main.selectedCategory = "Installed"
                main.backend.uninstallApp(main.testApp)
                main.phase = "review"
            } else if (main.phase === "review" && main.backend.review.removing) {
                const review = main.backend.review
                if (!main.check(review.title === "Uninstall " + main.testApp.name + "?", "Wrong short title")) return
                const expected = main.scope === "user"
                    ? "If you proceed, " + main.testApp.name + " and its app data will be removed."
                    : "If you proceed, " + main.testApp.name + " will be removed for all users, and its app data for this account will be deleted."
                if (!main.check(review.message === expected, "Wrong explanatory paragraph")) return
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
                }
                if (!main.check(Math.abs(link.width - link.contentItem.implicitWidth) < 1
                                && link.width < link.parent.width,
                                "Website control still stretches beyond the URL")) return
                const scroll = main.find(stack.currentItem, "detailsFlickable")
                scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
                link.forceActiveFocus(Qt.TabFocusReason)
                console.info("REVIEW_LAYOUT_ALL_PASS: removal declined; focused website width=" + link.width + ", column=" + link.parent.width)
                main.phase = "done" // Remain visible for the website screenshot.
            }
        }
    }
    Timer { interval: 60000; running: main.phase !== "done"; onTriggered: main.check(false, "Timeout at " + main.phase) }
}
