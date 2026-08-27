import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Page {
    id: page
    background: null
    readonly property var categories: ["All Apps", "Audio & Video", "Development", "Education", "Games", "Graphics", "Internet", "Office", "Science", "System", "Utilities", "Other"]
    readonly property var visibleApps: {
        const query = window.searchText.trim().toLowerCase()
        return window.catalog.filter(function(app) {
            const categoryMatches = window.selectedCategory === "All Apps" || app.category === window.selectedCategory
            const haystack = (app.name + " " + app.summary + " " + app.description + " " + app.category).toLowerCase()
            return categoryMatches && (!query || haystack.indexOf(query) >= 0)
        })
    }
    header: Control {
        height: 78
        padding: 0
        background: Rectangle {
            color: window.surfaceColor
            border.color: window.borderColor
            border.width: 1
        }
        contentItem: RowLayout {
            anchors.leftMargin: 26; anchors.rightMargin: 26; spacing: 18
            ColumnLayout {
                spacing: 0
                Label { text: "Fluff Linux"; color: window.accentColor; font.pixelSize: 12; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                Label { text: "App Center"; color: window.textColor; font.pixelSize: 24; font.weight: Font.DemiBold }
            }
            Item { Layout.fillWidth: true }
            TextField {
                Layout.preferredWidth: Math.min(420, page.width * 0.42)
                placeholderText: "Search applications…"; text: window.searchText
                color: window.textColor; placeholderTextColor: window.mutedTextColor
                leftPadding: 17; rightPadding: 17; implicitHeight: 44
                onTextEdited: window.searchText = text
                Keys.onEscapePressed: clear()
                background: Rectangle {
                    radius: 7
                    color: window.raisedSurfaceColor
                    border.color: parent.activeFocus ? window.accentColor : window.borderColor
                    border.width: parent.activeFocus ? 2 : 1
                }
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
                anchors.fill: parent; anchors.topMargin: 12; spacing: 4; clip: true; model: page.categories
                delegate: ItemDelegate {
                    id: categoryButton
                    required property string modelData
                    width: ListView.view.width; height: 42; text: modelData
                    highlighted: window.selectedCategory === modelData
                    onClicked: window.selectedCategory = modelData
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
        ScrollView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            ColumnLayout {
                width: parent.width; spacing: 18
                ColumnLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 28; Layout.rightMargin: 28; Layout.topMargin: 26; spacing: 5
                    Label { text: window.searchText ? "Search results" : window.selectedCategory; color: window.textColor; font.pixelSize: 32; font.weight: Font.DemiBold }
                    Label { text: page.visibleApps.length + (page.visibleApps.length === 1 ? " application" : " applications"); color: window.mutedTextColor }
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
                    color: window.mutedTextColor; font.pixelSize: 17
                }
                BusyIndicator { Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 80; visible: !window.catalogLoaded; running: visible }
            }
        }
    }
}
