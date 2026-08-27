import QtQuick
import QtQuick.Controls
import QtTest
import "../../qml" as AppCenter

TestCase {
    name: "SearchInput"
    when: window.visible

    ApplicationWindow {
        id: window
        width: 1180
        height: 760
        visible: true

        property color accentColor: "#e05562"
        property color textColor: "white"
        property color mutedTextColor: "#a0a0a0"
        property color surfaceColor: "#24282d"
        property color raisedSurfaceColor: "#30343a"
        property color sidebarColor: "#1d2024"
        property color borderColor: "#50545a"
        property color hoverColor: "#393d43"
        property bool darkMode: true
        property url appIconUrl: ""
        property string searchText: ""
        property string selectedCategory: "All Apps"
        property bool catalogLoaded: true
        property var selectedApp: null
        property var catalog: [{
            id: "com.mojang.Minecraft",
            name: "Minecraft",
            summary: "Create your own world",
            description: "A block-building game",
            icon: "",
            category: "Games",
            developer: "Mojang",
            searchName: "minecraft",
            searchSummary: "create your own world",
            searchDescription: "a block-building game",
            searchMetadata: "mojang com.mojang.minecraft games",
            searchHaystack: "minecraft create your own world a block-building game mojang com.mojang.minecraft games"
        }]

        function openApp(app) { selectedApp = app }

        AppCenter.CatalogPage {
            id: catalogPage
            anchors.fill: parent
        }
    }

    function init() {
        window.searchText = ""
        const searchField = findChild(catalogPage, "searchField")
        searchField.clear()
    }

    function test_keyboard_input_is_retained_and_applied() {
        const searchField = findChild(catalogPage, "searchField")
        verify(searchField !== null)

        window.requestActivate()
        tryCompare(window, "active", true)
        mouseClick(searchField, searchField.width / 2, searchField.height / 2)
        tryCompare(searchField, "activeFocus", true)
        keyClick(Qt.Key_M)
        keyClick(Qt.Key_I)
        keyClick(Qt.Key_N)
        keyClick(Qt.Key_E)
        keyClick(Qt.Key_C)
        keyClick(Qt.Key_R)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_F)
        keyClick(Qt.Key_T)

        compare(searchField.text, "minecraft")
        tryCompare(window, "searchText", "minecraft", 500)
        compare(catalogPage.visibleApps.length, 1)
        compare(catalogPage.visibleApps[0].name, "Minecraft")
    }
}
