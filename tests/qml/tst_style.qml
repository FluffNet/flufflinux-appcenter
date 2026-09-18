import QtQuick
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "Style"
    when: main.visible
    AppCenter.Main {
        id: main
        catalog: [{id: "org.example.Style", name: "Style", summary: "Style test", description: "", icon: "", category: "Utilities", developer: "", homepage: "", license: "", screenshots: []}]
    }
    function findVisual(item, name) {
        if (item.objectName === name) return item
        for (const child of (item.children || [])) {
            const result = findVisual(child, name)
            if (result) return result
        }
        return null
    }
    function cleanup() {
        main.showCatalog()
        tryCompare(findChild(main, "navigationStack"), "busy", false)
    }
    function test_surfaces_data() {
        return [{tag: "dark", background: "#202326", foreground: "#ffffff"},
                {tag: "light", background: "#eff0f1", foreground: "#202326"},
                {tag: "custom", background: "#302922", foreground: "#f2e7d9"}]
    }
    function test_surfaces(data) {
        main.palette.window = data.background
        main.palette.windowText = data.foreground
        compare(main.backgroundColor, main.palette.window)
        compare(main.color, main.backgroundColor)
        compare(main.sidebarColor, main.backgroundColor)
        compare(main.surfaceColor, main.raisedSurfaceColor)
        for (const color of [main.backgroundColor, main.surfaceColor, main.raisedSurfaceColor, main.sidebarColor, main.borderColor, main.hoverColor])
            compare(color.a, 1)
        verify(main.surfaceColor !== main.backgroundColor)
        const stack = findChild(main, "navigationStack")
        tryCompare(stack, "busy", false)
        const header = findChild(main, "catalogHeaderBackground")
        const sidebar = findChild(main, "sidebarBackground")
        compare(header.color, main.backgroundColor)
        compare(sidebar.color, main.backgroundColor)
        compare(header.border.width, 0)
        compare(sidebar.border.width, 0)
        const search = findChild(main, "searchField")
        compare(search.background.radius, main.cornerRadius)
        compare(search.background.color, main.surfaceColor)
        main.requestActivate()
        search.forceActiveFocus()
        tryCompare(search, "activeFocus", true)
        compare(search.background.border.width, 2)
        compare(search.background.border.color, main.accentColor)
        const grid = findChild(main, "catalogGrid")
        tryVerify(function() { return grid.itemAtIndex(0) !== null })
        compare(grid.itemAtIndex(0).background.radius, main.cornerRadius)
        tryVerify(function() { return findVisual(main.contentItem, "categoryButton-All Apps") !== null })
        compare(findVisual(main.contentItem, "categoryButton-All Apps").background.radius, main.cornerRadius)
    }
    function test_single_seams_and_scalable_count() {
        const header = findChild(main, "catalogHeaderBackground")
        const sidebar = findChild(main, "sidebarBackground")
        const horizontal = findChild(main, "catalogHeaderSeparator")
        const vertical = findChild(main, "sidebarSeparator")
        waitForRendering(main.contentItem)
        verify(!horizontal.vertical && vertical.vertical)
        compare(horizontal.height, horizontal.thickness)
        compare(vertical.width, horizontal.thickness)
        compare(horizontal.thickness * horizontal.pixelRatio, Math.max(1, Math.round(horizontal.pixelRatio)))
        verify(Math.abs(horizontal.y + horizontal.height - header.height) < 0.001)
        verify(Math.abs(vertical.x + vertical.width - sidebar.width) < 0.001)
        const bottom = horizontal.mapToItem(main.contentItem, 0, horizontal.height)
        const top = vertical.mapToItem(main.contentItem, 0, 0)
        verify(Math.abs(bottom.y - top.y) < 0.001) // Meet once, never two boxed outlines.
        const count = findChild(main, "catalogCountLabel")
        compare(count.renderType, Text.QtRendering)
        compare(count.text, "1 application")
        compare(count.font.family, main.font.family)
    }
    function test_navigation_hover_uses_shared_color() {
        main.requestActivate()
        const stack = findChild(main, "navigationStack")
        main.showCatalog(); tryCompare(stack, "busy", false)
        for (const name of ["categoryButton-All Apps", "categoryButton-Games", "installedButton"]) {
            const button = findVisual(main.contentItem, name)
            verify(button.hoverEnabled)
            mouseMove(button, button.width / 2, button.height / 2)
            tryCompare(button, "hovered", true)
            compare(button.background.color, main.hoverColor)
        }
        main.openApp(main.catalog[0]); tryCompare(stack, "busy", false)
        const back = findChild(stack.currentItem, "backButton")
        waitForRendering(back)
        verify(back.height >= 40)
        verify(findChild(back, "fluffButtonLabel").visible)
        mouseMove(main.contentItem, main.width - 10, main.height - 10)
        mouseMove(back, back.width / 2, back.height / 2)
        tryCompare(back, "hovered", true)
        compare(back.background.color, main.hoverColor)
        main.showDownloads(); tryCompare(stack, "busy", false)
        const downloadsBack = findChild(stack.currentItem, "downloadsBackButton")
        mouseMove(downloadsBack, downloadsBack.width / 2, downloadsBack.height / 2)
        tryCompare(downloadsBack, "hovered", true)
        compare(downloadsBack.background.color, main.hoverColor)
        main.showCatalog(); tryCompare(stack, "busy", false)
    }
}
