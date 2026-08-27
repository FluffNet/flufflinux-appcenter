import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    background: null
    readonly property var categories: [
        { name: "All Apps", label: "Home", icon: "go-home" },
        { name: "Audio & Video", icon: "applications-multimedia" },
        { name: "Development", icon: "applications-development" },
        { name: "Education", icon: "applications-education" },
        { name: "Games", icon: "applications-games" },
        { name: "Graphics", icon: "applications-graphics" },
        { name: "Internet", icon: "applications-internet" },
        { name: "Office", icon: "applications-office" },
        { name: "Science", icon: "applications-science" },
        { name: "System", icon: "applications-system" },
        { name: "Utilities", icon: "applications-utilities" },
        { name: "Other", icon: "applications-other" }
    ]
    readonly property var visibleApps: {
        const query = window.searchText.trim().toLowerCase()
        const activeCategory = query ? window.searchCategoryFilter : window.selectedCategory
        const matches = window.catalog.filter(function(app) {
            const categoryMatches = activeCategory === "All Apps" || app.category === activeCategory
            return categoryMatches && (!query || app.searchHaystack.indexOf(query) >= 0)
        })
        if (!query)
            return matches
        const scoredMatches = matches.map(function(app) {
            return { app: app, score: page.searchScore(app, query) }
        })
        scoredMatches.sort(function(left, right) {
            const scoreDifference = left.score - right.score
            if (scoreDifference !== 0)
                return scoreDifference
            const lengthDifference = left.app.name.length - right.app.name.length
            return lengthDifference !== 0
                   ? lengthDifference
                   : left.app.name.localeCompare(right.app.name)
        })
        return scoredMatches.map(function(entry) { return entry.app })
    }

    function openCategory(category) {
        searchTimer.stop()
        searchField.clear()
        window.searchText = ""
        window.searchCategoryFilter = "All Apps"
        window.selectedCategory = category
    }

    function categoryIndex(category) {
        for (let index = 0; index < categories.length; ++index) {
            if (categories[index].name === category)
                return index
        }
        return 0
    }

    function containsWholeWord(text, query) {
        let index = text.indexOf(query)
        while (index >= 0) {
            const leftBoundary = index === 0 || !/[\p{L}\p{N}]/u.test(text.charAt(index - 1))
            const rightIndex = index + query.length
            const rightBoundary = rightIndex === text.length
                                  || !/[\p{L}\p{N}]/u.test(text.charAt(rightIndex))
            if (leftBoundary && rightBoundary)
                return true
            index = text.indexOf(query, index + 1)
        }
        return false
    }

    function searchScore(app, query) {
        const name = app.searchName
        const summary = app.searchSummary
        const description = app.searchDescription
        const metadata = app.searchMetadata
        if (name === query) return 0
        if (name.startsWith(query)) return 10
        if (containsWholeWord(name, query)) return 20
        if (name.indexOf(query) >= 0) return 30
        if (summary.startsWith(query)) return 40
        if (containsWholeWord(summary, query)) return 50
        if (summary.indexOf(query) >= 0) return 60
        if (containsWholeWord(description, query)) return 70
        if (description.indexOf(query) >= 0) return 80
        if (metadata.indexOf(query) >= 0) return 90
        return 120
    }
    header: Control {
        id: headerControl
        height: 88
        padding: 0
        background: Rectangle {
            color: window.surfaceColor
            border.color: window.borderColor
            border.width: 1
        }
        contentItem: Item {
            Item {
                width: 220
                height: parent.height

                RowLayout {
                    id: brandLockup
                    anchors.centerIn: parent
                    spacing: 12

                    Image {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        source: window.appIconUrl
                        sourceSize: Qt.size(88, 88)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    ColumnLayout {
                        spacing: 0
                        Label { text: "Fluff Linux"; color: window.accentColor; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.1 }
                        Label { text: "App Center"; color: window.textColor; font.pixelSize: 21; font.weight: Font.DemiBold }
                    }
                }
            }

            TextField {
                id: searchField
                objectName: "searchField"
                width: Math.min(420, page.width * 0.38)
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Search applications…"
                color: window.textColor; placeholderTextColor: window.mutedTextColor
                leftPadding: 46; rightPadding: 17; implicitHeight: 44
                activeFocusOnPress: true
                Component.onCompleted: text = window.searchText
                onTextEdited: {
                    if (text.length > 0)
                        window.selectedCategory = "All Apps"
                    else
                        window.searchCategoryFilter = "All Apps"
                    searchTimer.restart()
                }
                Keys.onEscapePressed: {
                    clear()
                    searchTimer.stop()
                    window.searchText = ""
                    window.searchCategoryFilter = "All Apps"
                }
                Canvas {
                    id: searchIcon
                    objectName: "searchIcon"
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    opacity: 0.78
                    antialiasing: true
                    onPaint: {
                        const context = getContext("2d")
                        context.clearRect(0, 0, width, height)
                        context.strokeStyle = window.mutedTextColor
                        context.lineWidth = 2
                        context.lineCap = "round"
                        context.beginPath()
                        context.arc(8, 8, 5.25, 0, Math.PI * 2, false)
                        context.moveTo(11.8, 11.8)
                        context.lineTo(17, 17)
                        context.stroke()
                    }
                    Connections {
                        target: window
                        function onMutedTextColorChanged() { searchIcon.requestPaint() }
                    }
                }
                background: Rectangle {
                    radius: 7
                    color: window.raisedSurfaceColor
                    border.color: parent.activeFocus ? window.accentColor : window.borderColor
                    border.width: parent.activeFocus ? 2 : 1
                }
            }
            Timer {
                id: searchTimer
                interval: 140
                repeat: false
                onTriggered: window.searchText = searchField.text
            }
        }
    }
    RowLayout {
        anchors.fill: parent; spacing: 0
        Pane {
            Layout.fillHeight: true; Layout.preferredWidth: 220; padding: 12
            background: Rectangle {
                color: window.sidebarColor
                border.color: window.borderColor
                border.width: 1
            }
            ListView {
                id: categoryList
                anchors.fill: parent; anchors.topMargin: 12; spacing: 4; clip: true; model: page.categories
                DirectWheelScroll { scrollTarget: categoryList; stepSize: 92 }
                delegate: ItemDelegate {
                    id: categoryButton
                    objectName: "categoryButton-" + modelData.name
                    required property var modelData
                    width: ListView.view.width; height: 42
                    text: modelData.label || modelData.name
                    icon.name: modelData.icon
                    icon.width: 20; icon.height: 20
                    display: AbstractButton.TextBesideIcon
                    highlighted: window.selectedCategory === modelData.name
                    onClicked: page.openCategory(modelData.name)
                    leftPadding: 15
                    palette.buttonText: highlighted ? window.accentColor : window.textColor
                    font.weight: highlighted ? Font.DemiBold : Font.Normal
                    background: Rectangle {
                        radius: 6
                        color: categoryButton.highlighted
                               ? Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, window.darkMode ? 0.16 : 0.10)
                               : categoryButton.hovered ? window.hoverColor : "transparent"
                        border.color: categoryButton.highlighted ? window.accentColor : "transparent"
                        border.width: categoryButton.highlighted ? 1 : 0
                    }
                }
            }
        }
        Item {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            ColumnLayout {
                anchors.fill: parent; spacing: 18
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 28
                    Layout.rightMargin: 28
                    Layout.topMargin: 26
                    spacing: 18

                    ColumnLayout {
                        spacing: 5
                        Label { text: window.searchText ? "Search results" : window.selectedCategory; color: window.textColor; font.pixelSize: 32; font.weight: Font.DemiBold }
                        Label { text: page.visibleApps.length + (page.visibleApps.length === 1 ? " application" : " applications"); color: window.mutedTextColor }
                    }
                    Item { Layout.fillWidth: true }
                    ComboBox {
                        id: searchCategoryFilter
                        visible: window.searchText.length > 0
                        Layout.preferredWidth: 210
                        Layout.preferredHeight: 42
                        model: page.categories
                        textRole: "name"
                        currentIndex: page.categoryIndex(window.searchCategoryFilter)
                        displayText: currentIndex === 0
                                     ? "Category: All"
                                     : "Category: " + currentText
                        onActivated: window.searchCategoryFilter = page.categories[index].name
                        palette.button: window.raisedSurfaceColor
                        palette.buttonText: window.textColor
                        palette.window: window.raisedSurfaceColor
                        palette.text: window.textColor
                        palette.highlight: window.accentColor
                        palette.highlightedText: "white"
                        background: Rectangle {
                            radius: 7
                            color: window.raisedSurfaceColor
                            border.color: searchCategoryFilter.activeFocus
                                          ? window.accentColor
                                          : window.borderColor
                            border.width: searchCategoryFilter.activeFocus ? 2 : 1
                        }
                    }
                }
                GridView {
                    id: catalogGrid
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.leftMargin: 20; Layout.rightMargin: 20; Layout.bottomMargin: 20
                    clip: true
                    model: page.visibleApps
                    readonly property int columnCount: Math.max(1, Math.floor(width / 285))
                    cellWidth: width / columnCount
                    cellHeight: 158
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    DirectWheelScroll { scrollTarget: catalogGrid; stepSize: catalogGrid.cellHeight }
                    delegate: AppCard {
                        required property var modelData
                        width: GridView.view.cellWidth - 16
                        height: 142
                        x: 8
                        app: modelData
                        onClicked: window.openApp(app)
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                visible: window.catalogLoaded && page.visibleApps.length === 0
                text: window.catalog.length === 0 ? "No Flatpak applications were found." : "No applications match this view."
                color: window.mutedTextColor; font.pixelSize: 17
            }
        }
    }

    Connections {
        target: window
        function onSearchTextChanged() { catalogGrid.positionViewAtBeginning() }
        function onSelectedCategoryChanged() { catalogGrid.positionViewAtBeginning() }
        function onSearchCategoryFilterChanged() { catalogGrid.positionViewAtBeginning() }
    }
}
