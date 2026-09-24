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
        property color backgroundColor: "#202326"
        property int cornerRadius: 8
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
        property var downloadQueue: ({activeCount: 0, buttonVisible: false, progress: 0, completionSeen: true, hasError: false})
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
        }, {
            id: "net.supertuxkart.SuperTuxKart",
            name: "SuperTuxKart",
            summary: "A kart racing game",
            description: "Race with Tux and friends",
            icon: "",
            category: "Games",
            developer: "SuperTuxKart Team",
            searchName: "supertuxkart",
            searchSummary: "a kart racing game",
            searchDescription: "race with tux and friends",
            searchMetadata: "supertuxkart net.supertuxkart.supertuxkart games",
            searchHaystack: "supertuxkart a kart racing game race with tux and friends supertuxkart team net.supertuxkart.supertuxkart games"
        }, {
            id: "io.github.freeciv21.Freeciv21",
            name: "Freeciv21",
            summary: "Build a civilization",
            description: "A strategy game",
            icon: "",
            category: "Games",
            developer: "Freeciv21",
            searchName: "freeciv21",
            searchSummary: "build a civilization",
            searchDescription: "a strategy game",
            searchMetadata: "freeciv21 io.github.freeciv21.freeciv21 games",
            searchHaystack: "freeciv21 build a civilization a strategy game io.github.freeciv21.freeciv21 games"
        }, {
            id: "org.fluff.PenguinGuide",
            name: "Penguin Racing Guide",
            summary: "Track reference",
            description: "Learn every SuperTuxKart track",
            icon: "",
            category: "Games",
            developer: "FluffNet",
            searchName: "penguin racing guide",
            searchSummary: "track reference",
            searchDescription: "learn every supertuxkart track",
            searchMetadata: "fluffnet org.fluff.penguingguide games",
            searchHaystack: "penguin racing guide track reference learn every supertuxkart track fluffnet org.fluff.penguingguide games"
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
        window.darkMode = true
        window.textColor = "white"
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
        compare(catalogPage.visibleApps.length, 4)
        compare(catalogPage.categorySortIndex, 0)
        compare(catalogPage.visibleApps.map(app => app.name).join(","),
                "Freeciv21,Minecraft,Penguin Racing Guide,SuperTuxKart")
    }

    function test_title_search_ignores_spaces() {
        window.searchText = "tux kart"
        compare(catalogPage.visibleApps.length, 2)
        compare(catalogPage.visibleApps[0].name, "SuperTuxKart")
        compare(catalogPage.visibleApps[1].name, "Penguin Racing Guide")

        window.searchText = "free civ"
        compare(catalogPage.visibleApps.length, 1)
        compare(catalogPage.visibleApps[0].name, "Freeciv21")
    }

    function test_space_insensitive_match_uses_the_requested_rank() {
        const query = "tux kart"
        function result(name, summary, description) {
            return {
                searchName: name,
                searchSummary: summary,
                searchDescription: description,
                searchMetadata: ""
            }
        }

        const exactTitle = catalogPage.searchScore(
                    result("tux kart", "", ""), query)
        const includedTitle = catalogPage.searchScore(
                    result("ultimate tux kart racer", "", ""), query)
        const compactTitle = catalogPage.searchScore(
                    result("supertuxkart", "", ""), query)
        const normalDescription = catalogPage.searchScore(
                    result("racing guide", "", "play tux kart"), query)
        const compactDescription = catalogPage.searchScore(
                    result("track guide", "", "supertuxkart tracks"), query)

        verify(exactTitle < includedTitle)
        verify(includedTitle < compactTitle)
        verify(compactTitle < normalDescription)
        verify(normalDescription < compactDescription)
    }

    function test_clear_button_returns_to_home() {
        const searchField = findChild(catalogPage, "searchField")
        const clearButton = findChild(catalogPage, "searchClearButton")
        verify(searchField !== null)
        verify(clearButton !== null)
        compare(clearButton.visible, false)

        window.selectedCategory = "Games"
        window.searchCategoryFilter = "Games"
        searchField.text = "free civ"
        window.searchText = "free civ"
        compare(clearButton.visible, true)
        mouseClick(clearButton, clearButton.width / 2, clearButton.height / 2)

        compare(searchField.text, "")
        compare(window.searchText, "")
        compare(window.searchCategoryFilter, "All Apps")
        compare(window.selectedCategory, "All Apps")
        compare(catalogPage.visibleApps.length, window.catalog.length)
    }

    function test_home_label_keeps_all_apps_destination() {
        const homeButton = findChild(catalogPage, "categoryButton-All Apps")
        verify(homeButton !== null)
        compare(homeButton.text, "Home")
        compare(homeButton.icon.name, "go-home")

        catalogPage.openCategory("All Apps")
        compare(window.selectedCategory, "All Apps")
        compare(homeButton.highlighted, false)
        verify(homeButton.categorySelected)

        const searchField = findChild(catalogPage, "searchField")
        searchField.text = "minecraft"
        window.searchText = "minecraft"
        compare(homeButton.categorySelected, false)
    }

    function test_selected_home_is_dark_in_light_theme() {
        const homeButton = findChild(catalogPage, "categoryButton-All Apps")
        verify(homeButton !== null)
        window.darkMode = false
        // The selected icon must stay black even if a platform style exposes
        // an unexpected windowText value while Breeze Light is active.
        window.textColor = "white"
        window.selectedCategory = "All Apps"
        compare(homeButton.highlighted, false)
        verify(homeButton.categorySelected)
        compare(homeButton.foregroundColor, "#000000")
        compare(homeButton.palette.buttonText, "#000000")
        compare(homeButton.palette.highlightedText, "#000000")
        compare(homeButton.icon.color, "#000000")
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
        const categoryScroll = findChild(catalogPage, "categoryNaturalScroll")
        verify(catalogGrid !== null)
        verify(naturalScroll !== null)
        verify(categoryScroll !== null)
        compare(naturalScroll.wheelStep, 100)
        compare(naturalScroll.touchpadStep, 42)
        compare(naturalScroll.touchpadPixelScale, 2.15)
        compare(categoryScroll.touchpadPixelScale, 2.15)
        compare(categoryScroll.smoothScrolling, false)
    }

    function test_category_sidebar_grows_for_translated_labels() {
        const sidebar = findChild(catalogPage, "categorySidebar")
        const homeButton = findChild(catalogPage, "categoryButton-All Apps")
        verify(sidebar !== null)
        verify(homeButton !== null)
        compare(sidebar.width, catalogPage.categorySidebarWidth)
        verify(sidebar.width >= 240)
        compare(homeButton.height, sidebar.navigationRowHeight)
        compare(homeButton.icon.width, sidebar.navigationIconSize)
        compare(homeButton.icon.height, sidebar.navigationIconSize)
        compare(homeButton.font.pixelSize, sidebar.navigationFontSize)

        const shortWidth = catalogPage.categoryWidthForLabels(["Home"])
        const translatedWidth = catalogPage.categoryWidthForLabels([
            "A considerably longer translated category label"
        ])
        verify(translatedWidth > shortWidth)
    }
}
