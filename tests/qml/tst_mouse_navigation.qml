import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "MouseNavigation"
    when: main.visible
    AppCenter.Main { id: main }
    ToolTip { id: tip; parent: main.contentItem; text: "Queue" }
    readonly property var app: ({id:"org.example.Mouse", name:"Mouse test", description:"Test", summary:"", icon:"", developer:"", category:"Utilities", screenshots:[], homepage:"", license:""})
    function stack() { return findChild(main, "navigationStack") }
    function settle() { tryCompare(stack(), "busy", false); waitForPolish(stack()); wait(30) }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        main.showCatalog(); settle(); main.requestActivate()
    }
    function test_mouse_back_matches_page_back_data() {
        return [{tag:"app", route:"openApp"}, {tag:"queue", route:"showDownloads"}, {tag:"settings", route:"showSettings"}]
    }
    function test_mouse_back_matches_page_back(data) {
        main[data.route](app); settle(); compare(stack().depth, 2)
        mouseClick(stack(), stack().width / 2, stack().height / 2, Qt.BackButton)
        settle(); compare(stack().depth, 1)
    }
    function test_back_through_child_controls_and_nested_pages() {
        main.showDownloads(); settle(); main.openApp(app); settle(); compare(stack().depth, 3)
        mouseClick(findChild(stack().currentItem, "backButton"), 10, 10, Qt.BackButton)
        settle(); compare(stack().depth, 2); compare(stack().currentItem.objectName, "downloadsPage")
        mouseClick(stack(), 20, 150, Qt.BackButton); settle(); compare(stack().depth, 1)
        mouseClick(stack(), 20, 150, Qt.BackButton); settle(); compare(stack().depth, 1)
    }
    function test_back_does_not_cross_dialog() {
        main.openApp(app); settle(); main.showAbout()
        const dialog = findChild(main, "aboutDialog")
        tryCompare(dialog, "opened", true)
        mouseClick(dialog.contentItem, 20, 20, Qt.BackButton)
        compare(stack().depth, 2); verify(dialog.visible)
        dialog.close(); tryCompare(dialog, "visible", false)
        mouseClick(stack(), 500, 200, Qt.BackButton); settle(); compare(stack().depth, 1)
    }
    function test_tooltip_does_not_block_back() {
        main.showDownloads(); settle(); tip.open(); tryCompare(tip, "opened", true)
        mouseClick(stack(), 500, 200, Qt.BackButton); settle(); tip.close()
        compare(stack().depth, 1)
    }
}
