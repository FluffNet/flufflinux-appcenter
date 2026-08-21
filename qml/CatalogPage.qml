import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    readonly property var categories: ["All Apps", "Audio & Video", "Development", "Education", "Games", "Graphics", "Internet", "Office", "Science", "System", "Utilities", "Other"]
    readonly property var visibleApps: {
        const query = window.searchText.trim().toLowerCase()
        return window.catalog.filter(function(app) {
            const categoryMatches = window.selectedCategory === "All Apps" || app.category === window.selectedCategory
            const haystack = (app.name + " " + app.summary + " " + app.description + " " + app.category).toLowerCase()
            return categoryMatches && (!query || haystack.indexOf(query) >= 0)
        })
    }
    header: ToolBar {
        height: 72
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 22; anchors.rightMargin: 22; spacing: 18
            Label { text: "App Center"; font.pixelSize: 24; font.weight: Font.Bold }
            Item { Layout.fillWidth: true }
            TextField {
                Layout.preferredWidth: Math.min(420, page.width * 0.42)
                placeholderText: "Search applications…"; text: window.searchText
                leftPadding: 16; rightPadding: 16
                onTextEdited: window.searchText = text
                Keys.onEscapePressed: clear()
            }
        }
    }
    RowLayout {
        anchors.fill: parent; spacing: 0
        Pane {
            Layout.fillHeight: true; Layout.preferredWidth: 220; padding: 12
            background: Rectangle { color: palette.alternateBase }
            ListView {
                anchors.fill: parent; spacing: 3; clip: true; model: page.categories
                delegate: ItemDelegate {
                    required property string modelData
                    width: ListView.view.width; height: 42; text: modelData
                    highlighted: window.selectedCategory === modelData
                    onClicked: window.selectedCategory = modelData
                }
            }
        }
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            ColumnLayout {
                width: parent.width; spacing: 18
                ColumnLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.topMargin: 26; spacing: 5
                    Label { text: window.searchText ? "Search results" : window.selectedCategory; font.pixelSize: 30; font.weight: Font.Bold }
                    Label { text: page.visibleApps.length + (page.visibleApps.length === 1 ? " application" : " applications"); color: palette.placeholderText }
                }
                GridLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.bottomMargin: 28
                    columns: Math.max(1, Math.floor(width / 285)); columnSpacing: 16; rowSpacing: 16
                    Repeater {
                        model: page.visibleApps
                        delegate: AppCard {
                            required property var modelData
                            Layout.fillWidth: true; app: modelData
                            onClicked: window.openApp(app)
                        }
                    }
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 80
                    visible: window.catalogLoaded && page.visibleApps.length === 0
                    text: window.catalog.length === 0 ? "No AppStream applications were found." : "No applications match this view."
                    color: palette.placeholderText; font.pixelSize: 17
                }
                BusyIndicator { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 80; visible: !window.catalogLoaded; running: visible }
            }
        }
    }
}
