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
        compare(sort.currentIndex, 0); compare(sort.displayText, "Name: A–Z")
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
        compare(page().installedSortIndex, 1); assertPainted(sort)
        main.selectedCategory = "All Apps"; main.searchText = "test"
        main.searchCategoryFilter = "All Apps"
        const filter = findChild(page(), "searchCategoryFilter")
        mouseClick(filter); tryCompare(filter.popup, "opened", true)
        const list = filter.popup.contentItem
        tryVerify(() => list.itemAtIndex(2) !== null)
        mouseClick(list.itemAtIndex(2))
        tryCompare(filter.popup, "visible", false)
        compare(main.searchCategoryFilter, "Development"); assertPainted(filter)
    }
}
