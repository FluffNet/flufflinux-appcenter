import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: window
    width: 1180; height: 760
    minimumWidth: 720; minimumHeight: 520
    visible: true
    title: "App Center"
    color: "transparent"

    readonly property bool darkMode: palette.window.hslLightness < 0.5
    readonly property color accentColor: darkMode ? "#e05562" : "#820101"
    readonly property color textColor: palette.windowText
    readonly property color mutedTextColor: palette.placeholderText
    readonly property color surfaceColor: darkMode ? Qt.rgba(0.13, 0.15, 0.18, 0.94) : Qt.rgba(0.98, 0.985, 0.995, 0.95)
    readonly property color raisedSurfaceColor: darkMode ? Qt.rgba(0.18, 0.20, 0.23, 0.96) : Qt.rgba(1, 1, 1, 0.97)
    readonly property color sidebarColor: darkMode ? Qt.rgba(0.10, 0.115, 0.14, 0.96) : Qt.rgba(0.925, 0.94, 0.96, 0.96)
    readonly property color borderColor: darkMode ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0.08, 0.10, 0.14, 0.16)
    readonly property color hoverColor: darkMode ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(0.13, 0.15, 0.20, 0.065)
    readonly property url appIconUrl: fluffAppIconUrl

    property var catalog: fluffInitialCatalog
    property var selectedApp: null
    property string selectedCategory: "All Apps"
    property string searchText: ""
    readonly property bool catalogLoaded: true
    function openApp(app) { selectedApp = app; stack.replace(appPage) }
    function showCatalog() { selectedApp = null; stack.replace(catalogPage) }
    FluffBackground { anchors.fill: parent }
    StackView {
        id: stack
        anchors.fill: parent
        initialItem: catalogPage
        background: null
        pushEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        replaceEnter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
        replaceExit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 100 } }
    }
    Component { id: catalogPage; CatalogPage {} }
    Component { id: appPage; AppPage { app: window.selectedApp } }
}
