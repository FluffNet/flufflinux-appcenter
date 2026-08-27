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
        property string searchCategoryFilter: "All Apps"
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
        }, {
            id: "org.fluff.MinecraftTool",
            name: "Minecraft Tool",
            summary: "Edit Minecraft resources",
            description: "A developer utility",
            icon: "",
            category: "Development",
            developer: "FluffNet",
            searchName: "minecraft tool",
            searchSummary: "edit minecraft resources",
            searchDescription: "a developer utility",
            searchMetadata: "fluffnet org.fluff.minecrafttool development",
            searchHaystack: "minecraft tool edit minecraft resources a developer utility fluffnet org.fluff.minecrafttool development"
        }]

        function openApp(app) { selectedApp = app }

        AppCenter.CatalogPage {
            id: catalogPage
            anchors.fill: parent
        }
    }

    function init() {
        window.searchText = ""
        window.searchCategoryFilter = "All Apps"
        window.selectedCategory = "All Apps"
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
        compare(catalogPage.visibleApps.length, 2)
        compare(catalogPage.visibleApps[0].name, "Minecraft")
    }

    function test_search_filter_is_separate_from_sidebar_navigation() {
        const searchField = findChild(catalogPage, "searchField")
        searchField.text = "minecraft"
        window.searchText = "minecraft"
        window.searchCategoryFilter = "Development"
        compare(catalogPage.visibleApps.length, 1)
        compare(catalogPage.visibleApps[0].name, "Minecraft Tool")

        catalogPage.openCategory("Games")
        compare(searchField.text, "")
        compare(window.searchText, "")
        compare(window.searchCategoryFilter, "All Apps")
        compare(window.selectedCategory, "Games")
        compare(catalogPage.visibleApps.length, 1)
        compare(catalogPage.visibleApps[0].name, "Minecraft")
    }

    function test_home_label_keeps_all_apps_destination() {
        const homeButton = findChild(catalogPage, "categoryButton-All Apps")
        verify(homeButton !== null)
        compare(homeButton.text, "Home")
        compare(homeButton.icon.name, "go-home")

        catalogPage.openCategory("All Apps")
        compare(window.selectedCategory, "All Apps")
        verify(homeButton.highlighted)

        const searchField = findChild(catalogPage, "searchField")
        searchField.text = "minecraft"
        window.searchText = "minecraft"
        compare(homeButton.highlighted, false)
    }

    function test_search_icon_is_on_the_left() {
        const searchField = findChild(catalogPage, "searchField")
        const searchIcon = findChild(searchField, "searchIcon")
        verify(searchIcon !== null)
        compare(searchIcon.width, 20)
        compare(searchIcon.height, 20)
        verify(searchIcon.x < searchField.leftPadding)
    }

    function test_catalog_uses_natural_scrolling() {
        const catalogGrid = findChild(catalogPage, "catalogGrid")
        const naturalScroll = findChild(catalogPage, "catalogNaturalScroll")
        verify(catalogGrid !== null)
        verify(naturalScroll !== null)
        compare(naturalScroll.wheelStep, 100)
    }
}
