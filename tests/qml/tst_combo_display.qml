import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "ComboDisplay"
    when: main.visible
    AppCenter.Main { id: main; visible: true }
    Image { id: sampled; parent: main.contentItem; visible: false }
    Canvas { id: reader; parent: main.contentItem; x: -400; width: 320; height: 80 }
    function page() { return findChild(main, "navigationStack").currentItem }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop)/)
        main.requestActivate(); main.showCatalog()
        tryCompare(findChild(main, "navigationStack"), "busy", false)
        main.width = 1180; main.height = 760
        main.searchText = ""; main.selectedCategory = "Installed"
        page().installedSortIndex = 0
    }
    function assertPainted(control) {
        waitForPolish(main.contentItem); waitForRendering(control)
        verify(control.contentItem.visible)
        compare(control.contentItem.text, control.displayText)
        verify(control.contentItem.text.length > 0)
        let shot = null
        verify(control.grabToImage(result => shot = result))
        tryVerify(() => shot !== null)
        sampled.source = shot.url; tryCompare(sampled, "status", Image.Ready)
        tryCompare(reader, "available", true)
        const ctx = reader.getContext("2d")
        ctx.clearRect(0, 0, reader.width, reader.height)
        ctx.drawImage(sampled, 0, 0, control.width, control.height)
        function ink(x, y, width, height) {
            const data = ctx.getImageData(Math.floor(x), Math.floor(y), Math.floor(width), Math.floor(height)).data
            let pixels = 0
            const bg = control.background.color
            for (let i = 0; i < data.length; i += 4)
                if (Math.abs(data[i] / 255 - bg.r) + Math.abs(data[i + 1] / 255 - bg.g)
                    + Math.abs(data[i + 2] / 255 - bg.b) > 0.8) ++pixels
            return pixels
        }
        verify(ink(control.leftPadding, control.topPadding, control.availableWidth, control.availableHeight) > 25,
               "Selected text must actually be painted, not merely present in displayText")
        verify(ink(control.indicator.x, control.indicator.y, control.indicator.width, control.indicator.height) > 3,
               "Dropdown arrow must actually be painted")
        sampled.source = ""
    }
    function test_every_selected_label_data() { return [{tag:"dark",dark:true}, {tag:"light",dark:false}] }
    function test_every_selected_label(data) {
        main.palette.window = data.dark ? "#202326" : "#eff0f1"
        main.palette.windowText = data.dark ? "white" : "#202326"
        const sort = findChild(page(), "installedSort")
        compare(sort.currentIndex, 0); compare(sort.displayText, "Name: A-Z")
        for (let i = 0; i < sort.count; ++i) {
            page().installedSortIndex = i
            compare(sort.displayText, page().installedSortOptions[i]); assertPainted(sort)
        }
        main.selectedCategory = "All Apps"; main.searchText = "test"
        const filter = findChild(page(), "searchCategoryFilter")
        for (const category of page().categories) {
            main.searchCategoryFilter = category.name
            compare(filter.displayText, category.name === "All Apps" ? "Category: All" : "Category: " + category.name)
            assertPainted(filter)
        }
    }
    function test_mouse_and_keyboard_selection() {
        const sort = findChild(page(), "installedSort")
        mouseClick(sort); tryCompare(sort.popup, "opened", true)
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
        tryCompare(sort.popup, "visible", false)
        tryCompare(sort, "activeFocus", false)
        compare(page().installedSortIndex, 1); assertPainted(sort)
        sort.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space); tryCompare(sort.popup, "opened", true)
        keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
        tryCompare(sort.popup, "visible", false)
        verify(sort.activeFocus && sort.visualFocus)
        compare(page().installedSortIndex, 2)
        main.selectedCategory = "All Apps"; main.searchText = "test"
        main.searchCategoryFilter = "All Apps"
        const filter = findChild(page(), "searchCategoryFilter")
        mouseClick(filter); tryCompare(filter.popup, "opened", true)
        const list = filter.popup.contentItem
        tryVerify(() => list.itemAtIndex(2) !== null)
        waitForPolish(list); waitForRendering(list)
        mouseClick(list.itemAtIndex(2))
        tryCompare(filter.popup, "visible", false)
        tryCompare(filter, "activeFocus", false)
        compare(main.searchCategoryFilter, "Development"); assertPainted(filter)
    }
    function test_popup_contrast_data() {
        const rows = []
        for (const dark of [false, true])
            for (const kind of ["installed", "catalog", "filter"])
                rows.push({tag: kind + (dark ? "-dark" : "-light"), dark: dark, kind: kind})
        return rows
    }
    function test_popup_contrast(data) {
        main.palette.window = data.dark ? "#202326" : "#eff0f1"
        main.palette.windowText = data.dark ? "white" : "#202326"
        if (data.kind !== "installed") main.selectedCategory = "All Apps"
        if (data.kind === "filter") main.searchText = "test"
        const control = findChild(page(), data.kind === "installed" ? "installedSort"
            : data.kind === "catalog" ? "catalogSort" : "searchCategoryFilter")
        tryCompare(control, "visible", true)
        waitForPolish(main.contentItem); waitForRendering(control)
        mouseClick(control); tryCompare(control.popup, "opened", true)
        const list = control.popup.contentItem
        for (let index = 0; index < control.count; ++index) {
            list.positionViewAtIndex(index, ListView.Contain)
            tryVerify(() => list.itemAtIndex(index) !== null)
            const row = list.itemAtIndex(index)
            mouseMove(row, row.width / 2, row.height / 2)
            tryCompare(control, "highlightedIndex", index)
            waitForPolish(list); waitForRendering(row)
            // Verify both the rendered label color and real pixels. A white
            // label on a white hover surface used to be completely invisible.
            compare(row.contentItem.color, main.textColor)
            let shot = null
            verify(row.grabToImage(result => shot = result))
            tryVerify(() => shot !== null)
            sampled.source = shot.url; tryCompare(sampled, "status", Image.Ready)
            tryCompare(reader, "available", true)
            const ctx = reader.getContext("2d")
            ctx.clearRect(0, 0, reader.width, reader.height)
            ctx.drawImage(sampled, 0, 0, row.width, row.height)
            const pixels = ctx.getImageData(12, 8, Math.floor(row.width - 24), Math.floor(row.height - 16)).data
            let ink = 0
            const bg = row.background.color
            for (let i = 0; i < pixels.length; i += 4)
                if (Math.abs(pixels[i] / 255 - bg.r) + Math.abs(pixels[i + 1] / 255 - bg.g)
                    + Math.abs(pixels[i + 2] / 255 - bg.b) > 0.8) ++ink
            verify(ink > 25, data.tag + " invisible popup label: " + row.text)
        }
        if (data.kind === "installed") {
            let shot = null
            verify(list.parent.grabToImage(result => shot = result))
            tryVerify(() => shot !== null)
            verify(shot.saveToFile(Qt.resolvedUrl("../../target/sort-hover-" + (data.dark ? "dark" : "light") + ".png")))
        }
        keyClick(Qt.Key_Up)
        compare(list.itemAtIndex(control.highlightedIndex).contentItem.color, main.textColor)
        keyClick(Qt.Key_Escape); tryCompare(control.popup, "visible", false)
        sampled.source = ""
    }
}
