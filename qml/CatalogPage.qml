import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    focusPolicy: Qt.ClickFocus
    id: page
    StackView.onActivated: searchField.forceActiveFocus()
    background: Control { focusPolicy: Qt.ClickFocus }
    readonly property bool installedView: window.selectedCategory === "Installed"
    property int installedSortIndex: 0
    readonly property var installedSortOptions: [
        qsTr("Name: A–Z"), qsTr("Name: Z–A"),
        qsTr("Installed: Newest first"), qsTr("Installed: Oldest first"),
        qsTr("Size: Largest first"), qsTr("Size: Smallest first")
    ]
    readonly property var installedMatches: {
        const query = window.searchText.trim().toLowerCase()
        const sortIndex = installedSortIndex
        return (window.installedApps || []).filter(function(app) {
            return !query || (app.name + " " + app.id).toLowerCase().indexOf(query) >= 0
        }).sort(function(a, b) {
            const byName = a.name.localeCompare(b.name)
            const tie = byName || (a.id + "/" + a.installation + "/" + a.installedBranch)
                .localeCompare(b.id + "/" + b.installation + "/" + b.installedBranch)
            if (sortIndex < 2) return sortIndex === 1 ? -tie : tie
            const byDate = sortIndex < 4
            const left = byDate ? Date.parse(a.installedAt || "") : a.installedBytes
            const right = byDate ? Date.parse(b.installedAt || "") : b.installedBytes
            const leftKnown = typeof left === "number" && isFinite(left) && (byDate || left >= 0)
            const rightKnown = typeof right === "number" && isFinite(right) && (byDate || right >= 0)
            // Missing dates/sizes always go last, in either direction. Sort the
            // original byte counts, never localized/rounded MiB or GiB labels.
            if (leftKnown !== rightKnown) return leftKnown ? -1 : 1
            if (!leftKnown) return tie
            const ascending = sortIndex === 3 || sortIndex === 5
            return (ascending ? left - right : right - left) || tie
        })
    }
    onInstalledSortIndexChanged: installedList.positionViewAtBeginning()
    readonly property var categories: [
        { name: "All Apps", label: qsTr("Home"), icon: "go-home" },
        { name: "Audio & Video", label: qsTr("Audio & Video"), icon: "applications-multimedia" },
        { name: "Development", label: qsTr("Development"), icon: "applications-development" },
        { name: "Education", label: qsTr("Education"), icon: "applications-education" },
        { name: "Games", label: qsTr("Games"), icon: "applications-games" },
        { name: "Graphics", label: qsTr("Graphics"), icon: "applications-graphics" },
        { name: "Internet", label: qsTr("Internet"), icon: "applications-internet" },
        { name: "Office", label: qsTr("Office"), icon: "applications-office" },
        { name: "Science", label: qsTr("Science"), icon: "applications-science" },
        { name: "System", label: qsTr("System"), icon: "applications-system" },
        { name: "Utilities", label: qsTr("Utilities"), icon: "applications-utilities" },
        { name: "Other", label: qsTr("Other"), icon: "applications-other" }
    ]
    readonly property real categorySidebarWidth: Math.min(page.width * 0.46,
                                                           categoryWidthForLabels([qsTr("Installed")].concat(categories.map(
                                                               function(category) {
                                                                   return category.label
                                                               }))))
    readonly property var visibleApps: {
        const query = window.searchText.trim().toLowerCase()
        const compactQuery = page.compactSearchText(query)
        const activeCategory = query ? window.searchCategoryFilter : window.selectedCategory
        const matches = window.catalog.filter(function(app) {
            const categoryMatches = activeCategory === "All Apps" || app.category === activeCategory
            const compactNameMatches = compactQuery.length > 0
                    && page.compactSearchText(app.searchName).indexOf(compactQuery) >= 0
            const compactDescriptionMatches = compactQuery.length > 0
                    && (page.compactSearchText(app.searchSummary).indexOf(compactQuery) >= 0
                        || page.compactSearchText(app.searchDescription).indexOf(compactQuery) >= 0)
            return categoryMatches
                    && (!query || app.searchHaystack.indexOf(query) >= 0
                        || compactNameMatches || compactDescriptionMatches)
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

    function categoryWidthForLabels(labels) {
        let widestLabel = 0
        for (let index = 0; index < labels.length; ++index)
            widestLabel = Math.max(widestLabel,
                                   categoryFontMetrics.advanceWidth(labels[index]))
        return Math.max(240, Math.ceil(widestLabel + 92))
    }

    FontMetrics {
        id: categoryFontMetrics
        font.family: window.font.family
        font.pixelSize: sidebar.navigationFontSize
        font.weight: Font.DemiBold
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

    function compactSearchText(text) {
        return String(text || "").toLowerCase().replace(/\s+/g, "")
    }

    function searchScore(app, query) {
        const name = app.searchName
        const compactName = compactSearchText(name)
        const compactQuery = compactSearchText(query)
        const summary = app.searchSummary
        const compactSummary = compactSearchText(summary)
        const description = app.searchDescription
        const compactDescription = compactSearchText(description)
        const metadata = app.searchMetadata
        if (name === query) return 0
        if (name.startsWith(query)) return 10
        if (containsWholeWord(name, query)) return 20
        if (name.indexOf(query) >= 0) return 30
        if (compactName === compactQuery) return 34
        if (compactName.startsWith(compactQuery)) return 35
        if (compactName.indexOf(compactQuery) >= 0) return 36
        if (summary === query) return 40
        if (summary.startsWith(query)) return 41
        if (containsWholeWord(summary, query)) return 50
        if (summary.indexOf(query) >= 0) return 60
        if (compactSummary === compactQuery) return 61
        if (compactSummary.startsWith(compactQuery)) return 62
        if (compactSummary.indexOf(compactQuery) >= 0) return 63
        if (description === query) return 70
        if (description.startsWith(query)) return 71
        if (containsWholeWord(description, query)) return 75
        if (description.indexOf(query) >= 0) return 80
        if (compactDescription === compactQuery) return 81
        if (compactDescription.startsWith(compactQuery)) return 82
        if (compactDescription.indexOf(compactQuery) >= 0) return 83
        if (metadata.indexOf(query) >= 0) return 90
        return 120
    }
    header: Control {
        focusPolicy: Qt.ClickFocus
        id: headerControl
        height: 88
        padding: 0
        background: Rectangle {
            objectName: "catalogHeaderBackground"
            color: window.backgroundColor
            border.width: 0
            FluffSeparator {
                objectName: "catalogHeaderSeparator"
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            }
        }
        contentItem: Item {
            Item {
                width: page.categorySidebarWidth
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
                    Label { text: qsTr("App Center"); color: window.textColor; font.pixelSize: 21; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignVCenter }
                }
            }

            DownloadsButton {
                id: downloadsControl
                x: page.categorySidebarWidth + 12
                anchors.verticalCenter: parent.verticalCenter
            }

            TextField {
                id: searchField
                objectName: "searchField"
                width: Math.min(420, Math.max(100, page.width - page.categorySidebarWidth
                                            - (downloadsControl.visible ? downloadsControl.width + 112 : 92)))
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: "Search applications…"
                color: window.textColor; placeholderTextColor: window.mutedTextColor
                leftPadding: 46; rightPadding: 48; implicitHeight: 44
                activeFocusOnPress: true
                Component.onCompleted: {
                    text = window.searchText
                    forceActiveFocus()
                }
                onTextEdited: {
                    if (text.length > 0 && !page.installedView)
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
                FluffToolButton {
                    id: clearSearchButton
                    objectName: "searchClearButton"
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 34
                    visible: searchField.text.length > 0
                    text: "×"
                    font.pixelSize: 20
                    focusPolicy: Qt.NoFocus
                    palette.buttonText: window.mutedTextColor
                    Accessible.name: qsTr("Clear search and return home")
                    onClicked: {
                        page.openCategory("All Apps")
                        searchField.forceActiveFocus()
                    }
                    background: Rectangle {
                        radius: width / 2
                        color: clearSearchButton.hovered
                               ? window.hoverColor : "transparent"
                    }
                }
                background: Rectangle {
                    radius: window.cornerRadius
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

            FluffToolButton {
                id: applicationMenuButton
                objectName: "applicationMenuButton"
                anchors.right: searchField.left; anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                text: "⋮"; font.pixelSize: 28
                Accessible.name: qsTr("Application menu")
                onClicked: {
                    applicationMenu.restoreKeyboardFocus = visualFocus
                    applicationMenu.open()
                }
                Menu {
                    id: applicationMenu
                    objectName: "applicationMenu"
                    property bool restoreKeyboardFocus: false
                    y: applicationMenuButton.height + 6
                    width: 210
                    Overlay.onPressed: restoreKeyboardFocus = false
                    onClosed: {
                        // Popup dismissal restores its opener's focus after
                        // swallowing an outside pointer click. Do not leave a
                        // focused menu button behind, or steal focus from the
                        // search field/new page. Keyboard Escape keeps its place.
                        if (!restoreKeyboardFocus) {
                            const wasActive = applicationMenuButton.activeFocus
                            applicationMenuButton.focus = false
                            if (wasActive && page.StackView.status === StackView.Active)
                                page.forceActiveFocus(Qt.OtherFocusReason)
                        }
                    }
                    MenuItem {
                        objectName: "settingsMenuItem"
                        text: qsTr("Settings"); icon.name: "settings-configure"
                        onTriggered: window.showSettings()
                    }
                    MenuItem {
                        objectName: "aboutMenuItem"
                        text: qsTr("About"); icon.name: "dialog-information"
                        onTriggered: window.showAbout()
                    }
                }
            }
        }
    }
    RowLayout {
        anchors.fill: parent; spacing: 0
        Pane {
            id: sidebar
            focusPolicy: Qt.ClickFocus
            objectName: "categorySidebar"
            Layout.fillHeight: true
            Layout.preferredWidth: page.categorySidebarWidth
            padding: Math.min(12, height / 30)
            // Fit every destination, not a clipped/scrolling subset. Re-layout
            // actual sizes (never scale an already-rendered text texture).
            readonly property real navigationGap: Math.min(4, availableHeight / 100)
            readonly property real sectionGap: Math.min(12, availableHeight / 40)
            readonly property real navigationRowHeight: Math.max(1, Math.min(52,
                (availableHeight - navigationSeparator.height - sectionGap * 2
                 - navigationGap * (page.categories.length - 1)) / (page.categories.length + 1)))
            readonly property int navigationFontSize: Math.max(1, Math.floor(Math.min(16, navigationRowHeight * 0.52)))
            readonly property int navigationIconSize: Math.max(1, Math.floor(Math.min(24, navigationRowHeight * 0.7)))
            readonly property real navigationPadding: Math.min(16, navigationRowHeight / 3)
            readonly property real navigationSpacing: Math.min(12, navigationRowHeight / 4)
            background: Rectangle {
                objectName: "sidebarBackground"
                color: window.sidebarColor
                border.width: 0
                FluffSeparator {
                    objectName: "sidebarSeparator"
                    vertical: true
                    anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
                }
            }
                Column {
                    id: installedNavigation
                    width: parent.width
                    spacing: sidebar.sectionGap
                    ItemDelegate {
                        id: installedButton
                        hoverEnabled: true
                        objectName: "installedButton"
                        width: parent.width
                        height: sidebar.navigationRowHeight
                        text: qsTr("Installed")
                        icon.name: "view-list-details"
                        icon.width: sidebar.navigationIconSize; icon.height: sidebar.navigationIconSize
                        icon.color: window.textColor
                        palette.buttonText: window.textColor
                        font.pixelSize: sidebar.navigationFontSize
                        font.weight: page.installedView ? Font.DemiBold : Font.Normal
                        leftPadding: sidebar.navigationPadding; rightPadding: sidebar.navigationPadding
                        topPadding: 0; bottomPadding: 0; spacing: sidebar.navigationSpacing
                        // KDE adds native list-item insets. Our custom shape
                        // should cover the entire clickable/hoverable button.
                        leftInset: 0; rightInset: 0; topInset: 0; bottomInset: 0
                        contentItem: RowLayout {
                            spacing: sidebar.navigationSpacing
                            Canvas {
                                id: installedIcon
                                Layout.preferredWidth: sidebar.navigationIconSize; Layout.preferredHeight: sidebar.navigationIconSize
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.clearRect(0, 0, width, height)
                                    ctx.save()
                                    ctx.scale(width / 24, height / 24)
                                    ctx.strokeStyle = window.textColor
                                    ctx.lineWidth = 1.6
                                    ctx.lineJoin = "round"
                                    ctx.strokeRect(3, 3, 18, 18)
                                    ctx.beginPath()
                                    ctx.moveTo(7, 12); ctx.lineTo(10.5, 15.5); ctx.lineTo(17, 8.5)
                                    ctx.stroke()
                                    ctx.restore()
                                }
                                Connections {
                                    target: window
                                    function onTextColorChanged() { installedIcon.requestPaint() }
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: installedButton.text
                                font: installedButton.font
                                color: window.textColor
                                fontSizeMode: Text.Fit; minimumPixelSize: 1
                            }
                        }
                        onClicked: page.openCategory("Installed")
                        background: Rectangle {
                            radius: window.cornerRadius
                            color: installedButton.hovered || installedButton.down ? window.hoverColor : page.installedView
                                   ? Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, 0.14)
                                   : "transparent"
                            border.color: page.installedView ? window.accentColor : "transparent"
                        }
                    }
                    FluffSeparator {
                        id: navigationSeparator
                        width: parent.width - 16; x: 8
                    }
                }
            ListView {
                id: categoryList
                objectName: "categoryList"
                anchors.fill: parent; anchors.topMargin: installedNavigation.height + sidebar.sectionGap
                spacing: sidebar.navigationGap; clip: true; model: page.categories
                interactive: false
                boundsBehavior: Flickable.StopAtBounds
                onHeightChanged: contentY = 0
                NaturalWheelScroll {
                    objectName: "categoryNaturalScroll"
                    scrollTarget: categoryList
                }
                delegate: ItemDelegate {
                    id: categoryButton
                    hoverEnabled: true
                    objectName: "categoryButton-" + modelData.name
                    required property var modelData
                    width: ListView.view.width
                    height: sidebar.navigationRowHeight
                    text: modelData.label
                    icon.name: modelData.icon
                    icon.width: sidebar.navigationIconSize
                    icon.height: sidebar.navigationIconSize
                    display: AbstractButton.TextBesideIcon
                    // Do not use the style's highlighted state here: Breeze
                    // deliberately substitutes highlightedText (usually
                    // white), which can override the explicit light-theme
                    // icon color. Selection is drawn by our own background.
                    highlighted: false
                    readonly property bool categorySelected:
                        searchField.text.trim().length === 0
                        && window.selectedCategory === modelData.name
                    onClicked: page.openCategory(modelData.name)
                    leftPadding: sidebar.navigationPadding
                    rightPadding: sidebar.navigationPadding
                    topPadding: 0; bottomPadding: 0
                    leftInset: 0; rightInset: 0; topInset: 0; bottomInset: 0
                    spacing: sidebar.navigationSpacing
                    readonly property color foregroundColor: categorySelected
                                                               ? (window.darkMode
                                                                  ? window.accentColor
                                                                  : "#000000")
                                                               : window.textColor
                    palette.buttonText: foregroundColor
                    palette.text: foregroundColor
                    palette.highlightedText: foregroundColor
                    icon.color: categorySelected ? foregroundColor : "transparent"
                    font.pixelSize: sidebar.navigationFontSize
                    font.weight: categorySelected ? Font.DemiBold : Font.Normal
                    contentItem: RowLayout {
                        spacing: sidebar.navigationSpacing
                        Image {
                            Layout.preferredWidth: sidebar.navigationIconSize
                            Layout.preferredHeight: sidebar.navigationIconSize
                            sourceSize: Qt.size(sidebar.navigationIconSize * 2, sidebar.navigationIconSize * 2)
                            source: window.iconSource(modelData.icon)
                            fillMode: Image.PreserveAspectFit
                        }
                        Label {
                            objectName: "categoryLabel"
                            Layout.fillWidth: true
                            text: categoryButton.text; font: categoryButton.font
                            color: categoryButton.categorySelected && !window.darkMode ? "#000000" : window.textColor
                            fontSizeMode: Text.Fit; minimumPixelSize: 1
                        }
                    }
                    background: Rectangle {
                        radius: window.cornerRadius
                        color: categoryButton.hovered || categoryButton.down ? window.hoverColor : categoryButton.categorySelected
                               ? Qt.rgba(window.accentColor.r, window.accentColor.g, window.accentColor.b, window.darkMode ? 0.16 : 0.10)
                               : "transparent"
                        border.color: categoryButton.categorySelected ? window.accentColor : "transparent"
                        border.width: categoryButton.categorySelected ? 1 : 0
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
                        Label { text: page.installedView ? qsTr("Installed") : window.searchText ? "Search results" : window.selectedCategory; color: window.textColor; font.pixelSize: 32; font.weight: Font.DemiBold }
                        Label {
                            objectName: "catalogCountLabel"
                            readonly property int count: page.installedView ? page.installedMatches.length : page.visibleApps.length
                            text: count + (count === 1 ? " application" : " applications")
                            color: window.mutedTextColor
                            // Static small text should use the desktop font's
                            // native rasterization, including at 150% scaling.
                            renderType: Text.NativeRendering
                        }
                    }
                    Item { Layout.fillWidth: true }
                    ComboBox {
                        id: installedSort
                        hoverEnabled: true
                        objectName: "installedSort"
                        visible: page.installedView
                        Layout.preferredWidth: 210
                        Layout.preferredHeight: 42
                        model: page.installedSortOptions
                        currentIndex: page.installedSortIndex
                        onActivated: page.installedSortIndex = index
                        Accessible.name: qsTr("Sort installed apps")
                        palette.button: window.raisedSurfaceColor
                        palette.buttonText: window.textColor
                        palette.window: window.raisedSurfaceColor
                        palette.text: window.textColor
                        palette.highlight: window.accentColor
                        palette.highlightedText: "white"
                        background: Rectangle {
                            radius: window.cornerRadius
                            color: installedSort.hovered || installedSort.down ? window.hoverColor : window.raisedSurfaceColor
                            border.color: installedSort.activeFocus ? window.accentColor : window.borderColor
                            border.width: installedSort.activeFocus ? 2 : 1
                        }
                    }
                    ComboBox {
                        id: searchCategoryFilter
                        hoverEnabled: true
                        visible: !page.installedView && window.searchText.length > 0
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
                            radius: window.cornerRadius
                            color: searchCategoryFilter.hovered || searchCategoryFilter.down ? window.hoverColor : window.raisedSurfaceColor
                            border.color: searchCategoryFilter.activeFocus
                                          ? window.accentColor
                                          : window.borderColor
                            border.width: searchCategoryFilter.activeFocus ? 2 : 1
                        }
                    }
                }
                GridView {
                    id: catalogGrid
                    EmptySpaceFocus { parent: catalogGrid }
                    objectName: "catalogGrid"
                    visible: !page.installedView
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.leftMargin: 20; Layout.rightMargin: 20; Layout.bottomMargin: 20
                    clip: true
                    model: page.visibleApps
                    readonly property int columnCount: Math.max(1, Math.floor(width / 285))
                    readonly property int rowCount: Math.max(1, Math.floor(height / 158))
                    cellWidth: width / columnCount
                    // Share spare viewport height between the rows. This only
                    // sizes the cards; scrolling and normal edge clipping stay unchanged.
                    cellHeight: Math.max(158, height / rowCount)
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: PageScrollBar {
                        objectName: "catalogPageScrollBar"
                        parent: page.contentItem
                        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                        visible: catalogGrid.visible && size < 1
                    }
                    NaturalWheelScroll {
                        objectName: "catalogNaturalScroll"
                        scrollTarget: catalogGrid
                    }
                    delegate: AppCard {
                        required property var modelData
                        width: GridView.view.cellWidth - 16
                        height: GridView.view.cellHeight - 16
                        x: 8
                        app: modelData
                        onClicked: window.openApp(app)
                    }
                }
                ListView {
                    id: installedList
                    EmptySpaceFocus { parent: installedList }
                    objectName: "installedList"
                    visible: page.installedView
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.bottomMargin: 20
                    clip: true; spacing: 12
                    model: page.installedMatches
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: PageScrollBar {
                        objectName: "installedPageScrollBar"
                        parent: page.contentItem
                        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
                        visible: installedList.visible && size < 1
                    }
                    NaturalWheelScroll { scrollTarget: installedList }
                    delegate: InstalledRow {
                        required property var modelData
                        width: ListView.view.width
                        app: modelData
                        onClicked: window.openApp(app)
                    }
                }
            }
            LoadingSpinner {
                anchors.centerIn: parent
                running: page.installedView && !!window.installedLoading
                color: window.textColor
            }
            Label {
                objectName: "catalogEmptyMessage"
                anchors.centerIn: parent
                width: parent.width - 48
                wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter
                visible: page.installedView ? !window.installedLoading && (window.installedError || page.installedMatches.length === 0)
                                            : window.catalogLoaded && page.visibleApps.length === 0
                text: page.installedView && window.installedError ? window.installedError
                      : !page.installedView && window.catalog.length === 0 && window.backend && window.backend.sourcesBusy
                      ? qsTr("Loading applications…") : qsTr("No results.")
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
