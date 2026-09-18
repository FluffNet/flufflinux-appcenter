import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "EmptySpaceFocus"
    when: main.visible
    AppCenter.Main { id: main }
    SignalSpy { id: menuClosed; signalName: "closed" }
    readonly property var app: ({id: "org.example.Focus", name: "Focus test", summary: "", description: "",
        icon: "", developer: "", category: "Utilities", license: "", homepage: "", screenshots: []})
    function stack() { return findChild(main, "navigationStack") }
    function settle() { tryCompare(stack(), "busy", false); waitForPolish(main.contentItem) }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop)/)
        main.requestActivate()
        main.showCatalog(); settle()
        main.catalog = []
        main.installedApps = []
        main.searchText = ""
        stack().currentItem.openCategory("All Apps")
    }
    function test_empty_space_data() {
        const cases = []
        for (const page of ["catalog", "installed", "app", "downloads"])
            for (const header of [true, false])
                for (const touch of [false, true])
                    cases.push({tag: page + (header ? "-header" : "-body") + (touch ? "-touch" : "-mouse"),
                                page: page, header: header, touch: touch})
        return cases
    }
    function test_empty_space(data) {
        let name = "installedButton"
        if (data.page === "app") { main.openApp(app); name = "backButton" }
        else if (data.page === "downloads") { main.showDownloads(); name = "downloadsBackButton" }
        else if (data.page === "installed") stack().currentItem.openCategory("Installed")
        settle()
        const button = findChild(stack().currentItem, name)
        button.forceActiveFocus(Qt.TabFocusReason)
        verify(button.activeFocus)
        if (data.page === "app" || data.page === "downloads")
            compare(button.background.border.color, main.accentColor)
        const x = main.width / 2
        const y = data.header ? 8 : 190
        if (data.touch) {
            const sequence = touchEvent(stack())
            sequence.press(0, stack(), x, y).commit()
            sequence.release(0, stack(), x, y).commit()
        } else mouseClick(stack(), x, y)
        tryCompare(button, "activeFocus", false)
        if (data.page === "app" || data.page === "downloads")
            verify(button.background.border.width !== 2)
        // Keyboard traversal still reaches a control after clearing focus.
        keyClick(Qt.Key_Tab)
        verify(main.activeFocusItem !== stack())
    }
    function test_search_and_clear_keep_focus() {
        const field = findChild(stack().currentItem, "searchField")
        mouseClick(field)
        verify(field.activeFocus)
        keyClick(Qt.Key_A)
        compare(field.text, "a")
        waitForPolish(main.contentItem); wait(20)
        mouseClick(findChild(stack().currentItem, "searchClearButton"))
        verify(field.activeFocus)
        compare(field.text, "")
    }
    function test_menu_pointer_dismissal_clears_opener_data() {
        const cases = []
        for (const keyboard of [false, true])
            for (const touch of [false, true])
                for (const target of ["header", "body", "search", "category"])
                    cases.push({tag:(keyboard ? "keyboard-open" : "pointer-open") + "-" + (touch ? "touch" : "mouse") + "-" + target,
                                keyboard:keyboard, touch:touch, target:target})
        return cases
    }
    function test_menu_pointer_dismissal_clears_opener(data) {
        const page = stack().currentItem
        const button = findChild(page, "applicationMenuButton")
        const menu = findChild(page, "applicationMenu")
        const search = findChild(page, "searchField")
        menuClosed.target = menu; menuClosed.clear()
        for (let attempt = 0; attempt < 2; ++attempt) {
            if (data.keyboard) { button.forceActiveFocus(Qt.TabFocusReason); keyClick(Qt.Key_Space) }
            else mouseClick(button)
            tryCompare(menu, "opened", true)
            let target = page, point = Qt.point(page.width - 20, page.height - 20)
            if (data.target === "header") { target = page.header; point = Qt.point(20, 8) }
            else if (data.target === "search") { target = search; point = Qt.point(search.width / 2, search.height / 2) }
            else if (data.target === "category") { target = findChild(page, "categoryButton-Games"); point = Qt.point(12, target.height / 2) }
            if (data.touch) {
                const seq = touchEvent(target)
                seq.press(0, target, point.x, point.y).commit()
                seq.release(0, target, point.x, point.y).commit()
            } else mouseClick(target, point.x, point.y)
            tryCompare(menu, "visible", false)
            tryCompare(menuClosed, "count", attempt + 1)
            tryCompare(button, "activeFocus", false)
            verify(button.background.border.width !== 2)
            if (data.target === "search") {
                mouseClick(search); keyClick(Qt.Key_A)
                verify(search.activeFocus); compare(search.text, "a")
                page.openCategory("All Apps")
            }
        }
    }
    function test_keyboard_menu_escape_preserves_navigation() {
        const button = findChild(stack().currentItem, "applicationMenuButton")
        const menu = findChild(stack().currentItem, "applicationMenu")
        button.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space); tryCompare(menu, "opened", true)
        keyClick(Qt.Key_Escape); tryCompare(menu, "visible", false)
        tryCompare(button, "activeFocus", true)
        keyClick(Qt.Key_Tab); verify(!button.activeFocus)
    }
    function test_clicking_a_control_keeps_its_focus_data() {
        return [{tag: "header", scroll: false}, {tag: "scroll", scroll: true}]
    }
    function test_clicking_a_control_keeps_its_focus(data) {
        if (data.scroll) { main.openApp(app); settle() }
        const host = data.scroll ? findChild(stack().currentItem, "detailsFlickable").contentItem
                                 : stack().currentItem.header
        const button = createTemporaryObject(buttonFixture, host)
        waitForPolish(main.contentItem); wait(20)
        button.forceActiveFocus(Qt.TabFocusReason)
        mouseClick(button)
        wait(20)
        compare(button.clicks, 1)
        verify(button.activeFocus)
        mouseClick(button)
        wait(20)
        verify(button.activeFocus)
        compare(button.clicks, 2)
    }
    function test_empty_space_does_not_grab_a_drag() {
        main.openApp(app); settle()
        const button = findChild(stack().currentItem, "backButton")
        button.forceActiveFocus(Qt.TabFocusReason)
        mousePress(stack(), 500, 500)
        mouseMove(stack(), 500, 400)
        mouseRelease(stack(), 500, 400)
        const view = findChild(stack().currentItem, "detailsFlickable")
        verify(!view.dragging)
        compare(stack().depth, 2)
    }
    function test_popup_focus_is_not_cleared_by_page() {
        // Modal controls outside the page stack keep their own focus handling.
        const popup = createTemporaryObject(popupFixture, main.contentItem)
        popup.open(); tryCompare(popup, "opened", true)
        const button = popup.contentItem.children[0]
        button.forceActiveFocus(Qt.TabFocusReason)
        mouseClick(popup.contentItem, 160, 90)
        verify(button.activeFocus)
        popup.close()
    }
    Component {
        id: buttonFixture
        AppCenter.FluffButton {
            property var window: main
            property int clicks: 0
            x: 300; y: 20; text: "Test action"
            onClicked: ++clicks
        }
    }
    Component {
        id: popupFixture
        Popup {
            width: 300; height: 180; modal: true; focus: true
            contentItem: Item { Button { text: "Fixture" } }
        }
    }
}
