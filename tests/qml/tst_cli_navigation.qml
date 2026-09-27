import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "CliNavigation"
    when: main.visible
    AppCenter.Main { id: main; catalogStats: null; catalogPreferences: null }
    function page() { return findChild(main, "navigationStack").get(0) }
    function send(type, value) {
        main.handleCliAction({type:type, value:value})
        tryCompare(findChild(main, "navigationStack"), "busy", false)
    }
    function app(id, name, category, categories, mimeTypes) {
        return {id:id, name:name, category:category, categories:categories, mimeTypes:mimeTypes,
            summary:"Test", description:"Test", icon:"", developer:"Fixture", sources:[], screenshots:[],
            searchName:name.toLowerCase(), searchSummary:"test", searchDescription:"test",
            searchMetadata:id.toLowerCase(), searchHaystack:(name + " " + id).toLowerCase()}
    }
    function init() {
        failOnWarning(/(ReferenceError|TypeError|Binding loop|Cannot assign)/)
        send("mode", "Browsing")
        main.catalog = [app("org.example.Chat", "Telegram", "Internet", ["Network", "InstantMessaging"], ["x-scheme-handler/tg"]),
            app("org.example.Reader", "Reader", "Office", ["Office", "Viewer"], ["application/pdf", "image/png"]),
            app("org.example.PDF", "PDF in name only", "Office", ["Office"], []),
            app("org.example.Game", "Chess", "Games", ["Game", "BoardGame"], [])]
    }
    function test_search_returns_from_details_and_clears_category() {
        page().openCategory("Games")
        main.openApp(main.catalog[3])
        tryCompare(findChild(main, "navigationStack"), "busy", false)
        send("search", "Telegram")
        compare(main.searchText, "Telegram")
        compare(main.selectedCategory, "All Apps")
        compare(page().visibleApps.length, 1)
        compare(page().visibleApps[0].id, "org.example.Chat")
        compare(findChild(main, "navigationStack").depth, 1)
    }
    function test_mime_uses_declared_support_not_name() {
        send("mime", "APPLICATION/PDF")
        compare(page().visibleApps.length, 1)
        compare(page().visibleApps[0].name, "Reader")
        verify(!page().homeView)
        compare(findChild(page(), "catalogTitleLabel").text, "Apps for application/pdf")
        send("mime", "application/unknown")
        compare(page().visibleApps.length, 0)
        send("search", "pdf")
        compare(page().cliMimeType, "")
        compare(page().visibleApps[0].name, "PDF in name only")
    }
    function test_categories_data() {
        return [{tag:"sidebar", query:"games", expected:"Chess"},
            {tag:"appstream-main", query:"Network", expected:"Telegram"},
            {tag:"appstream-subcategory", query:"Viewer", expected:"Reader"},
            {tag:"appstream-case", query:"instantmessaging", expected:"Telegram"}]
    }
    function test_categories(data) {
        send("category", data.query)
        compare(page().visibleApps.length, 1)
        compare(page().visibleApps[0].name, data.expected)
        page().openCategory("All Apps")
        compare(page().cliCategory, "")
        compare(page().visibleApps.length, 4)
    }
    function test_modes() {
        send("mime", "application/pdf")
        send("mode", "Installed"); compare(main.selectedCategory, "Installed")
        send("mode", "Update"); compare(main.selectedCategory, "Updates")
        send("mode", "Search"); compare(main.selectedCategory, "All Apps"); compare(main.searchText, "")
        compare(page().cliMimeType, "")
        send("mode", "Sources"); compare(findChild(main, "navigationStack").currentItem.objectName, "settingsPage")
        send("mode", "About"); verify(findChild(main, "aboutDialog").visible)
        send("mode", "Browsing"); tryCompare(findChild(main, "aboutDialog"), "visible", false)
        compare(findChild(main, "navigationStack").depth, 1)
    }
}
